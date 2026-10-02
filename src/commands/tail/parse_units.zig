const std = @import("std");

fn parseSuffixMult(suffix: []const u8) ?usize {
    if (suffix.len == 0) return 1;
    if (std.mem.eql(u8, suffix, "b")) return 512;
    if (std.mem.eql(u8, suffix, "c")) return 1;
    if (std.mem.eql(u8, suffix, "w")) return 2;
    if (std.mem.eql(u8, suffix, "k") or std.mem.eql(u8, suffix, "K") or std.mem.eql(u8, suffix, "KiB")) return 1024;
    if (std.mem.eql(u8, suffix, "m") or std.mem.eql(u8, suffix, "M") or std.mem.eql(u8, suffix, "MiB")) return 1024 * 1024;
    if (std.mem.eql(u8, suffix, "g") or std.mem.eql(u8, suffix, "G") or std.mem.eql(u8, suffix, "GiB")) return 1024 * 1024 * 1024;
    if (std.mem.eql(u8, suffix, "KB")) return 1000;
    if (std.mem.eql(u8, suffix, "MB")) return 1000 * 1000;
    if (std.mem.eql(u8, suffix, "GB")) return 1000 * 1000 * 1000;
    return null;
}

pub fn parseMultiplier(str: []const u8) ?usize {
    if (str.len == 0) return null;
    var end: usize = 0;
    while (end < str.len and std.ascii.isDigit(str[end])) : (end += 1) {}
    if (end == 0) return null;
    const base = std.fmt.parseUnsigned(usize, str[0..end], 10) catch |err| switch (err) {
        error.Overflow => std.math.maxInt(usize),
        else => return null,
    };
    const mult = parseSuffixMult(str[end..]) orelse return null;
    return std.math.mul(usize, base, mult) catch std.math.maxInt(usize);
}

pub fn parseOffset(str: []const u8, from_start: *bool, invalid_raw: *[]const u8) ?usize {
    if (str.len == 0) {
        invalid_raw.* = str;
        return null;
    }
    var slice = str;
    if (slice[0] == '+') {
        from_start.* = true;
        slice = slice[1..];
    } else if (slice[0] == '-') {
        from_start.* = false;
        slice = slice[1..];
    }
    invalid_raw.* = slice;
    return parseMultiplier(slice);
}
