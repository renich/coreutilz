const std = @import("std");
const types = @import("types.zig");
const numcmp = @import("numcmp.zig");
const version_sort = @import("../ls/version_sort.zig");

const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("locale.h");
    @cInclude("langinfo.h");
});

pub inline fn isBlank(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\n';
}

pub fn compareGeneralNumeric(sa_slice: []const u8, sb_slice: []const u8) std.math.Order {
    const sa_z = std.mem.trim(u8, sa_slice, " \t\n");
    const sb_z = std.mem.trim(u8, sb_slice, " \t\n");
    if (sa_z.len == 0 and sb_z.len == 0) return .eq;
    if (sa_z.len == 0) return .lt;
    if (sb_z.len == 0) return .gt;

    var buf_a: [512]u8 = undefined;
    var buf_b: [512]u8 = undefined;
    const ca = if (sa_z.len < 511) blk: {
        @memcpy(buf_a[0..sa_z.len], sa_z);
        buf_a[sa_z.len] = 0;
        break :blk buf_a[0..sa_z.len :0];
    } else sa_z;
    const cb = if (sb_z.len < 511) blk: {
        @memcpy(buf_b[0..sb_z.len], sb_z);
        buf_b[sb_z.len] = 0;
        break :blk buf_b[0..sb_z.len :0];
    } else sb_z;

    var end_a: [*c]u8 = null;
    var end_b: [*c]u8 = null;
    const val_a = c.strtold(ca.ptr, &end_a);
    const val_b = c.strtold(cb.ptr, &end_b);

    const conv_err_a = (end_a == ca.ptr);
    const conv_err_b = (end_b == cb.ptr);
    if (conv_err_a and conv_err_b) return .eq;
    if (conv_err_a) return .lt;
    if (conv_err_b) return .gt;

    if (val_a < val_b) return .lt;
    if (val_a > val_b) return .gt;
    if (val_a == val_b) return .eq;

    const a_nan = (val_a != val_a);
    const b_nan = (val_b != val_b);
    if (a_nan and !b_nan) return .lt;
    if (!a_nan and b_nan) return .gt;
    return .eq;
}

pub fn parseMonth(str: []const u8) u8 {
    const s = std.mem.trimStart(u8, str, " \t\n");
    if (s.len < 1) return 0;
    const months = [_][]const u8{ "JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC" };
    if (s.len >= 3) {
        for (months, 1..) |m, idx| {
            if (std.ascii.eqlIgnoreCase(s[0..3], m)) return @intCast(idx);
        }
    }
    for (0..12) |i| {
        const item = c.nl_langinfo(@intCast(c.ABMON_1 + i));
        if (item != null) {
            const span = std.mem.span(item);
            const trimmed = std.mem.trim(u8, span, " \t\n");
            if (trimmed.len > 0 and std.ascii.startsWithIgnoreCase(s, trimmed)) return @intCast(i + 1);
        }
    }
    return 0;
}

fn begfield(line: []const u8, key: *const types.KeySpec, delim: ?u8) usize {
    var idx: usize = 0;
    var sword: usize = if (key.field_start > 0) key.field_start - 1 else 0;
    if (delim) |d| {
        while (idx < line.len and sword > 0) : (sword -= 1) {
            while (idx < line.len and line[idx] != d) idx += 1;
            if (idx < line.len) idx += 1;
        }
    } else {
        while (idx < line.len and sword > 0) : (sword -= 1) {
            while (idx < line.len and isBlank(line[idx])) idx += 1;
            while (idx < line.len and !isBlank(line[idx])) idx += 1;
        }
    }
    if (key.skipsblanks) {
        while (idx < line.len and isBlank(line[idx])) idx += 1;
    }
    const schar = if (key.char_start > 0) key.char_start - 1 else 0;
    return @min(idx +| schar, line.len);
}

fn limfield(line: []const u8, key: *const types.KeySpec, delim: ?u8) usize {
    if (key.field_end == null) return line.len;
    var idx: usize = 0;
    var eword: usize = if (key.field_end.? > 0) key.field_end.? - 1 else 0;
    const echar: usize = key.char_end orelse 0;
    if (echar == 0) eword +|= 1;
    if (delim) |d| {
        while (idx < line.len and eword > 0) : (eword -= 1) {
            while (idx < line.len and line[idx] != d) idx += 1;
            if (idx < line.len and (eword > 1 or echar > 0)) idx += 1;
        }
    } else {
        while (idx < line.len and eword > 0) : (eword -= 1) {
            while (idx < line.len and isBlank(line[idx])) idx += 1;
            while (idx < line.len and !isBlank(line[idx])) idx += 1;
        }
    }
    if (echar > 0) {
        if (key.skipeblanks) {
            while (idx < line.len and isBlank(line[idx])) idx += 1;
        }
        idx = @min(idx +| echar, line.len);
    }
    return idx;
}

pub fn extractKeySlice(line: []const u8, key: *const types.KeySpec, delim: ?u8) []const u8 {
    const start = begfield(line, key, delim);
    const end = limfield(line, key, delim);
    if (start >= end or start >= line.len) return "";
    return line[start..@min(end, line.len)];
}

pub fn transformKey(key_slice: []const u8, key: *const types.KeySpec, out_buf: []u8) []const u8 {
    const ic = key.ignore_case;
    const dict = key.dictionary_order;
    const nonprint = key.ignore_nonprinting;
    if (!ic and !dict and !nonprint) return key_slice;

    var len: usize = 0;
    for (key_slice) |b| {
        if (len >= out_buf.len) break;
        if (dict and !std.ascii.isAlphanumeric(b) and !isBlank(b)) continue;
        if (nonprint and !std.ascii.isPrint(b)) continue;
        out_buf[len] = if (ic) std.ascii.toUpper(b) else b;
        len += 1;
    }
    return out_buf[0..len];
}

fn getLocaleSeparators() struct { dec: u8, sep: ?u8 } {
    const lconv = c.localeconv();
    var sep: ?u8 = null;
    var dec: u8 = '.';
    if (lconv) |lc| {
        if (lc.*.thousands_sep != null and lc.*.thousands_sep[0] != 0 and lc.*.thousands_sep[1] == 0) {
            sep = @bitCast(lc.*.thousands_sep[0]);
        }
        if (lc.*.decimal_point != null and lc.*.decimal_point[0] != 0 and lc.*.decimal_point[1] == 0) {
            dec = @bitCast(lc.*.decimal_point[0]);
        }
    }
    return .{ .dec = dec, .sep = sep };
}

pub fn compareKeyValues(raw1: []const u8, raw2: []const u8, key: *const types.KeySpec, opt: *const types.Options) std.math.Order {
    var b1: [1024]u8 = undefined;
    var b2: [1024]u8 = undefined;
    const k1 = transformKey(raw1, key, &b1);
    const k2 = transformKey(raw2, key, &b2);

    if (key.numeric) {
        const loc = getLocaleSeparators();
        const diff = numcmp.numcompare(k1, k2, loc.dec, loc.sep);
        return if (diff < 0) .lt else if (diff > 0) .gt else .eq;
    }
    if (key.general_numeric) {
        return compareGeneralNumeric(k1, k2);
    }
    if (key.human_numeric) {
        const loc = getLocaleSeparators();
        const diff = numcmp.findUnitOrder(k1, loc.dec, loc.sep) - numcmp.findUnitOrder(k2, loc.dec, loc.sep);
        if (diff != 0) return if (diff < 0) .lt else .gt;
        const ndiff = numcmp.numcompare(k1, k2, loc.dec, loc.sep);
        return if (ndiff < 0) .lt else if (ndiff > 0) .gt else .eq;
    }
    if (key.month) {
        return std.math.order(parseMonth(k1), parseMonth(k2));
    }
    if (key.version) {
        return version_sort.versionCompare(k1, k2);
    }
    if (key.random) {
        const h1 = std.hash.Wyhash.hash(opt.random_seed, k1);
        const h2 = std.hash.Wyhash.hash(opt.random_seed, k2);
        return std.math.order(h1, h2);
    }
    return std.mem.order(u8, k1, k2);
}

pub fn compareLines(a: []const u8, b: []const u8, opt: *const types.Options) std.math.Order {
    if (opt.keys.len > 0) {
        for (opt.keys) |*key| {
            const k1 = extractKeySlice(a, key, opt.delimiter);
            const k2 = extractKeySlice(b, key, opt.delimiter);
            var ord = compareKeyValues(k1, k2, key, opt);
            if (ord != .eq) {
                if (key.reverse) ord = ord.invert();
                return ord;
            }
        }
        if (opt.stable or opt.unique) return .eq;
    }
    var ord = std.mem.order(u8, a, b);
    if (ord != .eq and opt.reverse) ord = ord.invert();
    return ord;
}
