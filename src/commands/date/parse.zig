const std = @import("std");
const c = @import("../../compat/c.zig").c;

fn stripComments(allocator: std.mem.Allocator, s: []const u8) ![]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(allocator);
    var depth: usize = 0;
    for (s) |ch| {
        if (ch == '(') {
            depth += 1;
        } else if (ch == ')') {
            if (depth > 0) depth -= 1;
        } else if (depth == 0) {
            try out.append(allocator, ch);
        }
    }
    return out.toOwnedSlice(allocator);
}

fn parseWeekday(s: []const u8) ?u3 {
    const days = [_][]const u8{ "sun", "mon", "tue", "wed", "thu", "fri", "sat" };
    for (days, 0..) |d, idx| {
        if (std.ascii.startsWithIgnoreCase(s, d)) return @intCast(idx);
    }
    return null;
}

fn parseWeekdayOrRel(s: []const u8, is_utc: bool) ?c.time_t {
    var is_next = false;
    var rem = s;
    if (std.ascii.startsWithIgnoreCase(rem, "next ")) {
        is_next = true;
        rem = rem[5..];
    }
    if (parseWeekday(rem)) |target_wday| {
        var tm: c.struct_tm = std.mem.zeroes(c.struct_tm);
        const now = c.time(null);
        _ = if (is_utc) c.gmtime_r(&now, &tm) else c.localtime_r(&now, &tm);
        var diff: i32 = @as(i32, target_wday) - @as(i32, @intCast(tm.tm_wday));
        if (diff < 0) diff += 7;
        if (is_next and diff == 0) diff = 7;
        tm.tm_mday += diff;
        tm.tm_sec = 0;
        tm.tm_min = 0;
        tm.tm_hour = 0;
        tm.tm_isdst = -1;
        return if (is_utc) c.timegm(&tm) else c.mktime(&tm);
    }
    return null;
}

const RelUnit = enum { year, month, day };

fn parseRelativeOffset(s: []const u8) ?struct { base: []const u8, num: i32, unit: RelUnit } {
    var unit: RelUnit = .day;
    var idx: usize = 0;
    if (std.mem.indexOf(u8, s, " year")) |i| {
        idx = i;
        unit = .year;
    } else if (std.mem.indexOf(u8, s, " month")) |i| {
        idx = i;
        unit = .month;
    } else if (std.mem.indexOf(u8, s, " day")) |i| {
        idx = i;
        unit = .day;
    } else return null;

    var p = idx;
    while (p > 0 and s[p - 1] == ' ') : (p -= 1) {}
    const end_num = p;
    while (p > 0 and std.ascii.isDigit(s[p - 1])) : (p -= 1) {}
    const digits = s[p..end_num];
    if (digits.len == 0) return null;
    var num = std.fmt.parseInt(i32, digits, 10) catch return null;
    while (p > 0 and s[p - 1] == ' ') : (p -= 1) {}
    if (p > 0 and s[p - 1] == '-') {
        num = -num;
        p -= 1;
    } else if (p > 0 and s[p - 1] == '+') {
        p -= 1;
    }
    while (p > 0 and s[p - 1] == ' ') : (p -= 1) {}
    return .{ .base = s[0..p], .num = num, .unit = unit };
}

fn militaryTzOffset(ch: u8) ?i32 {
    const up = std.ascii.toUpper(ch);
    if (up >= 'A' and up <= 'I') return (@as(i32, up - 'A') + 1) * 3600;
    if (up >= 'K' and up <= 'M') return @as(i32, up - 'A') * 3600;
    if (up >= 'N' and up <= 'Y') return -(@as(i32, up - 'N') + 1) * 3600;
    if (up == 'Z') return 0;
    return null;
}

fn parseWithStrptime(s: []const u8, is_utc: bool, allocator: std.mem.Allocator) ?c.time_t {
    var base_tm: c.struct_tm = std.mem.zeroes(c.struct_tm);
    const now = c.time(null);
    _ = if (is_utc) c.gmtime_r(&now, &base_tm) else c.localtime_r(&now, &base_tm);
    base_tm.tm_sec = 0;
    base_tm.tm_min = 0;
    base_tm.tm_hour = 0;
    base_tm.tm_isdst = -1;

    const s_z = allocator.dupeZ(u8, s) catch return null;
    defer allocator.free(s_z);

    const fmts = [_][:0]const u8{
        "%Y-%m-%d %H:%M:%S %z", "%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S%z",
        "%Y-%m-%dT%H:%M:%S",    "%Y-%m-%dT%H:%M",    "%Y-%m-%d %H:%M",
        "%Y-%m-%d",             "%Y%m%d",            "%H:%M:%S %z",
        "%H:%M:%S",             "%H:%M %z",          "%H:%M",
        "%d %b %Y %H:%M:%S %z", "%b %d %H:%M:%S %Y", "%m/%d/%Y %H:%M:%S",
        "%m/%d/%Y",
    };
    for (fmts) |fmt| {
        var tm = base_tm;
        if (c.strptime(s_z.ptr, fmt.ptr, &tm) != null) {
            if (std.mem.endsWith(u8, fmt, "%z")) return c.timegm(&tm) - tm.tm_gmtoff;
            return if (is_utc) c.timegm(&tm) else c.mktime(&tm);
        }
    }
    return null;
}

pub fn parseDateStr(raw_s: []const u8, is_utc: bool, allocator: std.mem.Allocator) ?c.time_t {
    const stripped = stripComments(allocator, raw_s) catch return null;
    defer allocator.free(stripped);
    const s = std.mem.trim(u8, stripped, " \t\r\n");

    if (s.len == 0) {
        var tm: c.struct_tm = std.mem.zeroes(c.struct_tm);
        const now = c.time(null);
        _ = if (is_utc) c.gmtime_r(&now, &tm) else c.localtime_r(&now, &tm);
        tm.tm_sec = 0;
        tm.tm_min = 0;
        tm.tm_hour = 0;
        tm.tm_isdst = -1;
        return if (is_utc) c.timegm(&tm) else c.mktime(&tm);
    }
    if (s.len <= 2 and std.ascii.isDigit(s[0]) and (s.len == 1 or std.ascii.isDigit(s[1]))) {
        const hour = std.fmt.parseInt(c_int, s, 10) catch return null;
        var tm: c.struct_tm = std.mem.zeroes(c.struct_tm);
        const now = c.time(null);
        _ = if (is_utc) c.gmtime_r(&now, &tm) else c.localtime_r(&now, &tm);
        tm.tm_sec = 0;
        tm.tm_min = 0;
        tm.tm_hour = hour;
        tm.tm_isdst = -1;
        return if (is_utc) c.timegm(&tm) else c.mktime(&tm);
    }
    if (s[0] == '@') return std.fmt.parseInt(c.time_t, s[1..], 10) catch null;
    if (std.mem.eql(u8, s, "now") or std.mem.eql(u8, s, "today")) return c.time(null);
    if (std.mem.eql(u8, s, "yesterday")) return c.time(null) - 86400;
    if (std.mem.eql(u8, s, "tomorrow")) return c.time(null) + 86400;

    if (parseWeekdayOrRel(s, is_utc)) |w_time| return w_time;

    if (parseRelativeOffset(s)) |rel| {
        const base_t = if (rel.base.len == 0) c.time(null) else parseDateStr(rel.base, is_utc, allocator) orelse return null;
        var tm: c.struct_tm = undefined;
        _ = if (is_utc) c.gmtime_r(&base_t, &tm) else c.localtime_r(&base_t, &tm);
        switch (rel.unit) {
            .year => tm.tm_year += rel.num,
            .month => tm.tm_mon += rel.num,
            .day => tm.tm_mday += rel.num,
        }
        tm.tm_isdst = -1;
        return if (is_utc) c.timegm(&tm) else c.mktime(&tm);
    }

    if (s.len >= 3 and std.ascii.isDigit(s[s.len - 2])) {
        if (militaryTzOffset(s[s.len - 1])) |off| {
            if (parseWithStrptime(s[0 .. s.len - 1], true, allocator)) |base_t| {
                var tm: c.struct_tm = undefined;
                _ = c.gmtime_r(&base_t, &tm);
                return c.timegm(&tm) - off;
            }
        }
    }

    return parseWithStrptime(s, is_utc, allocator);
}
