const std = @import("std");
const char_class = @import("char_class.zig");
const errors = @import("../../utils/errors.zig");

pub const ParsedChar = struct {
    val: u8,
    consumed: usize,
};

pub fn parseEscape(str: []const u8, stderr: anytype) ?ParsedChar {
    if (str.len == 0 or str[0] != '\\') return null;
    if (str.len == 1) {
        stderr.print("tr: warning: an unescaped backslash at end of string is not portable\n", .{}) catch {};
        return .{ .val = '\\', .consumed = 1 };
    }
    switch (str[1]) {
        'a' => return .{ .val = 0x07, .consumed = 2 },
        'b' => return .{ .val = 0x08, .consumed = 2 },
        'f' => return .{ .val = 0x0C, .consumed = 2 },
        'n' => return .{ .val = 0x0A, .consumed = 2 },
        'r' => return .{ .val = 0x0D, .consumed = 2 },
        't' => return .{ .val = 0x09, .consumed = 2 },
        'v' => return .{ .val = 0x0B, .consumed = 2 },
        '\\' => return .{ .val = '\\', .consumed = 2 },
        '0'...'7' => {
            var val: u8 = 0;
            var i: usize = 1;
            while (i < str.len and i <= 3) : (i += 1) {
                const d = str[i];
                if (d >= '0' and d <= '7') {
                    val = (val << 3) | (d - '0');
                } else break;
            }
            return .{ .val = val, .consumed = i };
        },
        else => return .{ .val = str[1], .consumed = 2 },
    }
}

fn countMinRemaining(str: []const u8) usize {
    var count: usize = 0;
    var i: usize = 0;
    while (i < str.len) {
        if (std.mem.startsWith(u8, str[i..], "[:")) {
            if (std.mem.indexOf(u8, str[i..], ":]")) |end| {
                const name = str[i + 2 .. i + end];
                var buf: [256]u8 = undefined;
                if (char_class.getClassChars(name, &buf)) |c| {
                    count += c;
                    i += end + 2;
                    continue;
                }
            }
        }
        if (str[i] == '\\' and i + 1 < str.len) {
            count += 1;
            i += 2;
            continue;
        }
        count += 1;
        i += 1;
    }
    return count;
}

const RepeatResult = struct {
    char: u8,
    count: usize,
    consumed: usize,
};

fn parseRepeat(
    str: []const u8,
    target_len: usize,
    current_len: usize,
    stderr: anytype,
) ?union(enum) { ok: RepeatResult, err } {
    if (str.len < 3 or str[0] != '[') return null;
    var char: u8 = str[1];
    var offset: usize = 2;
    if (str[1] == '\\') {
        if (parseEscape(str[1..], stderr)) |esc| {
            char = esc.val;
            offset = 1 + esc.consumed;
        }
    }
    if (offset >= str.len or str[offset] != '*') return null;
    const end = std.mem.indexOfScalar(u8, str[offset + 1 ..], ']') orelse return null;
    const num_str = str[offset + 1 .. offset + 1 + end];
    for (num_str) |ch| {
        if (!std.ascii.isDigit(ch)) return null;
    }
    var count: usize = 1;
    if (num_str.len > 0 and num_str[0] == '0') {
        for (num_str[1..]) |ch| {
            if (ch > '7') {
                stderr.print("tr: invalid repeat count '{s}' in [c*n] construct\n", .{num_str}) catch {};
                return .err;
            }
        }
    }
    if (num_str.len == 0 or std.mem.allEqual(u8, num_str, '0')) {
        const remaining = countMinRemaining(str[offset + 1 + end + 1 ..]);
        count = if (target_len > current_len + remaining) target_len - current_len - remaining else 0;
    } else if (num_str[0] == '0') {
        count = std.fmt.parseUnsigned(usize, num_str, 8) catch 1;
    } else {
        count = std.fmt.parseUnsigned(usize, num_str, 10) catch 1;
    }
    return .{ .ok = .{ .char = char, .count = count, .consumed = offset + 1 + end + 1 } };
}

fn parseEquivClass(str: []const u8, stderr: anytype) ?union(enum) { char: u8, err, consumed: usize } {
    if (std.mem.eql(u8, str, "[==]") or std.mem.startsWith(u8, str, "[==]")) {
        stderr.print("tr: missing equivalence class character '[==]'\n", .{}) catch {};
        return .err;
    }
    if (str.len >= 5 and str[0] == '[' and str[1] == '=') {
        if (std.mem.indexOf(u8, str[2..], "=]")) |end| {
            const inner = str[2 .. 2 + end];
            if (inner.len == 0) {
                stderr.print("tr: missing equivalence class character '[==]'\n", .{}) catch {};
                return .err;
            }
            return .{ .char = inner[0] };
        }
    }
    return null;
}

fn parseCharClass(str: []const u8, out: *std.ArrayList(u8), allocator: std.mem.Allocator, stderr: anytype) ?union(enum) { consumed: usize, err } {
    if (std.mem.eql(u8, str, "[::]") or std.mem.startsWith(u8, str, "[::]")) {
        stderr.print("tr: missing character class name '[::]'\n", .{}) catch {};
        return .err;
    }
    if (str.len < 5 or !std.mem.startsWith(u8, str, "[:")) return null;
    const end = std.mem.indexOf(u8, str, ":]") orelse return null;
    const class_name = str[2..end];
    var buf: [256]u8 = undefined;
    if (char_class.getClassChars(class_name, &buf)) |count| {
        out.appendSlice(allocator, buf[0..count]) catch return null;
        return .{ .consumed = end + 2 };
    }
    return null;
}

fn nextChar(str: []const u8, stderr: anytype) ParsedChar {
    if (parseEscape(str, stderr)) |pc| return pc;
    return .{ .val = str[0], .consumed = 1 };
}

pub fn hasCharClass(str: []const u8) bool {
    var i: usize = 0;
    while (i < str.len) {
        if (std.mem.startsWith(u8, str[i..], "[:")) {
            if (std.mem.indexOf(u8, str[i..], ":]")) |_| return true;
        }
        i += 1;
    }
    return false;
}

pub const CaseSpan = struct {
    start: usize,
    len: usize,
};

fn validateSet2Class(class_name: []const u8, start_off: usize, spans: []const CaseSpan, stderr: anytype) bool {
    if (!std.mem.eql(u8, class_name, "upper") and !std.mem.eql(u8, class_name, "lower")) {
        stderr.print("tr: when translating, the only character classes that may appear in\nstring2 are 'upper' and 'lower'\n", .{}) catch {};
        return false;
    }
    for (spans) |span| {
        if (span.start == start_off and span.len == 26) return true;
    }
    stderr.print("tr: misaligned [:upper:] and/or [:lower:] construct\n", .{}) catch {};
    return false;
}

pub fn expandSet(
    str: []const u8,
    target_len: usize,
    case_spans_in: ?[]const CaseSpan,
    case_spans_out: ?*std.ArrayList(CaseSpan),
    allocator: std.mem.Allocator,
    stderr: anytype,
) ?[]u8 {
    var list = std.ArrayList(u8).empty;
    errdefer list.deinit(allocator);

    var i: usize = 0;
    while (i < str.len) {
        if (parseRepeat(str[i..], target_len, list.items.len, stderr)) |r_res| {
            switch (r_res) {
                .ok => |rep| {
                    list.appendNTimes(allocator, rep.char, rep.count) catch return null;
                    i += rep.consumed;
                    continue;
                },
                .err => return null,
            }
        }
        if (parseEquivClass(str[i..], stderr)) |eq_res| {
            switch (eq_res) {
                .char => |ch| {
                    list.append(allocator, ch) catch return null;
                    const end = std.mem.indexOf(u8, str[i + 2 ..], "=]").?;
                    i += 2 + end + 2;
                    continue;
                },
                .err => return null,
                .consumed => {},
            }
        }
        if (std.mem.startsWith(u8, str[i..], "[:")) {
            if (case_spans_in) |spans| {
                if (std.mem.indexOf(u8, str[i..], ":]")) |end| {
                    const class_name = str[i + 2 .. i + end];
                    if (!validateSet2Class(class_name, list.items.len, spans, stderr)) {
                        return null;
                    }
                }
            }
        }
        if (parseCharClass(str[i..], &list, allocator, stderr)) |cc_res| {
            switch (cc_res) {
                .consumed => |c_len| {
                    const end = std.mem.indexOf(u8, str[i + 2 ..], ":]").?;
                    const class_name = str[i + 2 .. i + 2 + end];
                    if (case_spans_out != null and (std.mem.eql(u8, class_name, "upper") or std.mem.eql(u8, class_name, "lower"))) {
                        case_spans_out.?.append(allocator, .{ .start = list.items.len - 26, .len = 26 }) catch return null;
                    }
                    i += c_len;
                    continue;
                },
                .err => return null,
            }
        }
        const c1 = nextChar(str[i..], stderr);
        i += c1.consumed;
        if (i < str.len and str[i] == '-' and i + 1 < str.len) {
            i += 1;
            const c2 = nextChar(str[i..], stderr);
            i += c2.consumed;
            if (c1.val > c2.val) {
                stderr.print("tr: range-endpoints of '{c}-{c}' are in reverse order\n", .{ c1.val, c2.val }) catch {};
                return null;
            }
            var b: usize = c1.val;
            while (b <= c2.val) : (b += 1) {
                list.append(allocator, @intCast(b)) catch return null;
            }
        } else {
            list.append(allocator, c1.val) catch return null;
        }
    }
    return list.toOwnedSlice(allocator) catch null;
}

pub fn complementSet(set: []const u8, allocator: std.mem.Allocator) ?[]u8 {
    var present = [_]bool{false} ** 256;
    for (set) |b| present[b] = true;
    var list = std.ArrayList(u8).empty;
    errdefer list.deinit(allocator);
    for (0..256) |b| {
        if (!present[b]) {
            list.append(allocator, @intCast(b)) catch return null;
        }
    }
    return list.toOwnedSlice(allocator) catch null;
}
