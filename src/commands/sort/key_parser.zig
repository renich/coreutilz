const std = @import("std");
const types = @import("types.zig");

pub fn applyKeyFlag(key: *types.KeySpec, ch: u8, is_end: bool) bool {
    switch (ch) {
        'n' => key.numeric = true,
        'g' => key.general_numeric = true,
        'h' => key.human_numeric = true,
        'M' => key.month = true,
        'V' => key.version = true,
        'R' => key.random = true,
        'r' => key.reverse = true,
        'b' => if (is_end) {
            key.skipeblanks = true;
        } else {
            key.skipsblanks = true;
        },
        'f' => key.ignore_case = true,
        'd' => key.dictionary_order = true,
        'i' => key.ignore_nonprinting = true,
        else => return false,
    }
    return true;
}

pub fn parseCount(str: []const u8, idx: *usize) ?usize {
    const start = idx.*;
    while (idx.* < str.len and std.ascii.isDigit(str[idx.*])) : (idx.* += 1) {}
    if (idx.* == start) return null;
    return std.fmt.parseInt(usize, str[start..idx.*], 10) catch std.math.maxInt(usize);
}

fn parsePos1(str: []const u8, idx: *usize, key: *types.KeySpec, stderr: anytype) !bool {
    const f_start = parseCount(str, idx) orelse {
        try stderr.print("sort: invalid field specification '{s}'\n", .{str});
        return false;
    };
    if (f_start == 0) {
        try stderr.print("sort: field number is zero: invalid field specification '{s}'\n", .{str});
        return false;
    }
    key.field_start = f_start;
    if (idx.* < str.len and str[idx.*] == '.') {
        idx.* += 1;
        const rest = str[idx.*..];
        const c_start = parseCount(str, idx) orelse {
            try stderr.print("sort: invalid number after '.': invalid count at start of '{s}'\n", .{rest});
            return false;
        };
        if (c_start == 0) {
            try stderr.print("sort: character offset is zero: invalid field specification '{s}'\n", .{str});
            return false;
        }
        key.char_start = c_start;
    }
    while (idx.* < str.len and str[idx.*] != ',') : (idx.* += 1) {
        _ = applyKeyFlag(key, str[idx.*], false);
    }
    return true;
}

fn parsePos2(str: []const u8, idx: *usize, key: *types.KeySpec, stderr: anytype) !bool {
    if (idx.* >= str.len or str[idx.*] != ',') return true;
    idx.* += 1;
    const rest = str[idx.*..];
    const f_end = parseCount(str, idx) orelse {
        try stderr.print("sort: invalid number after ',': invalid count at start of '{s}'\n", .{rest});
        return false;
    };
    key.field_end = f_end;
    if (idx.* < str.len and str[idx.*] == '.') {
        idx.* += 1;
        const dot_rest = str[idx.*..];
        const c_end = parseCount(str, idx) orelse {
            try stderr.print("sort: invalid number after '.': invalid count at start of '{s}'\n", .{dot_rest});
            return false;
        };
        key.char_end = c_end;
    }
    while (idx.* < str.len) : (idx.* += 1) {
        _ = applyKeyFlag(key, str[idx.*], true);
    }
    return true;
}

pub fn parseKeySpec(str: []const u8, stderr: anytype) !?types.KeySpec {
    var key = types.KeySpec{};
    var idx: usize = 0;
    if (!try parsePos1(str, &idx, &key, stderr)) return null;
    if (!try parsePos2(str, &idx, &key, stderr)) return null;
    return key;
}

pub fn parseObsoleteKey(arg1: []const u8, arg2: ?[]const u8, consumed_arg2: *bool) ?types.KeySpec {
    if (arg1.len <= 1 or arg1[0] != '+' or !std.ascii.isDigit(arg1[1])) return null;
    var idx1: usize = 1;
    const f1 = parseCount(arg1, &idx1) orelse return null;
    var c1: ?usize = null;
    if (idx1 < arg1.len and arg1[idx1] == '.') {
        idx1 += 1;
        c1 = parseCount(arg1, &idx1);
    }
    var key = types.KeySpec{
        .field_start = f1 +| 1,
        .char_start = if (c1) |c| c +| 1 else 1,
    };
    while (idx1 < arg1.len) : (idx1 += 1) {
        if (!applyKeyFlag(&key, arg1[idx1], false)) return null;
    }

    if (arg2) |a2| {
        if (a2.len > 1 and a2[0] == '-' and std.ascii.isDigit(a2[1])) {
            var idx2: usize = 1;
            if (parseCount(a2, &idx2)) |f2| {
                var c2: ?usize = null;
                if (idx2 < a2.len and a2[idx2] == '.') {
                    idx2 += 1;
                    c2 = parseCount(a2, &idx2);
                }
                var eword = f2;
                const echar = c2 orelse 0;
                if (echar == 0 and eword > 0) eword -= 1;
                key.field_end = eword +| 1;
                key.char_end = echar;
                while (idx2 < a2.len) : (idx2 += 1) {
                    if (!applyKeyFlag(&key, a2[idx2], true)) return null;
                }
                consumed_arg2.* = true;
            }
        }
    }
    return key;
}
