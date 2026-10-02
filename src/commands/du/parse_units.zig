const std = @import("std");
const types = @import("types.zig");
const c = @import("../../compat/c.zig").c;

fn getMultiplier(suffix: []const u8) ?u64 {
    if (suffix.len == 0) return 1;
    if (std.mem.eql(u8, suffix, "c")) return 1;
    if (std.mem.eql(u8, suffix, "w")) return 2;
    if (std.mem.eql(u8, suffix, "b")) return 512;
    if (std.mem.eql(u8, suffix, "k") or std.mem.eql(u8, suffix, "K") or std.mem.eql(u8, suffix, "KiB")) return 1024;
    if (std.mem.eql(u8, suffix, "KB")) return 1000;
    if (std.mem.eql(u8, suffix, "M") or std.mem.eql(u8, suffix, "MiB")) return 1024 * 1024;
    if (std.mem.eql(u8, suffix, "MB")) return 1000 * 1000;
    if (std.mem.eql(u8, suffix, "G") or std.mem.eql(u8, suffix, "GiB")) return 1024 * 1024 * 1024;
    if (std.mem.eql(u8, suffix, "GB")) return 1000 * 1000 * 1000;
    if (std.mem.eql(u8, suffix, "T") or std.mem.eql(u8, suffix, "TiB")) return 1024 * 1024 * 1024 * 1024;
    if (std.mem.eql(u8, suffix, "TB")) return 1000 * 1000 * 1000 * 1000;
    if (std.mem.eql(u8, suffix, "P") or std.mem.eql(u8, suffix, "PiB")) return 1024 * 1024 * 1024 * 1024 * 1024;
    if (std.mem.eql(u8, suffix, "PB")) return 1000 * 1000 * 1000 * 1000 * 1000;
    if (std.mem.eql(u8, suffix, "E") or std.mem.eql(u8, suffix, "EiB")) return 1024 * 1024 * 1024 * 1024 * 1024 * 1024;
    if (std.mem.eql(u8, suffix, "EB")) return 1000 * 1000 * 1000 * 1000 * 1000 * 1000;
    return null;
}

pub fn parseSizeUnit(str: []const u8) ?u64 {
    if (str.len == 0) return null;
    var num_end: usize = 0;
    while (num_end < str.len and std.ascii.isDigit(str[num_end])) : (num_end += 1) {}
    if (num_end == 0) return null;
    const base_num = std.fmt.parseInt(u64, str[0..num_end], 10) catch return null;
    const mult = getMultiplier(str[num_end..]) orelse return null;
    return std.math.mul(u64, base_num, mult) catch null;
}

pub fn parseThreshold(str: []const u8, opt_name: []const u8, stderr: anytype) ?i64 {
    if (str.len == 0 or std.mem.eql(u8, str, "-0")) {
        stderr.print("du: invalid {s} argument '{s}'\n", .{ opt_name, str }) catch {};
        return null;
    }
    const is_neg = str[0] == '-';
    const is_pos = str[0] == '+';
    const num_str = if (is_neg or is_pos) str[1..] else str;
    const raw_val = parseSizeUnit(num_str) orelse {
        stderr.print("du: invalid {s} argument '{s}'\n", .{ opt_name, str }) catch {};
        return null;
    };
    if (is_neg) {
        return -@as(i64, @intCast(raw_val));
    }
    return @as(i64, @intCast(raw_val));
}

pub fn addExcludePattern(allocator: std.mem.Allocator, pat: []const u8, cfg: *types.DuConfig) !void {
    const pattern_copy = try allocator.dupe(u8, pat);
    const has_slash = std.mem.indexOfScalar(u8, pat, '/') != null;
    try cfg.excludes.append(allocator, .{ .pattern = pattern_copy, .has_slash = has_slash });
}

pub fn loadExcludeFile(allocator: std.mem.Allocator, file_path: []const u8, cfg: *types.DuConfig, stderr: anytype) !bool {
    const path_z = try allocator.dupeZ(u8, file_path);
    defer allocator.free(path_z);

    const fd = c.open(path_z.ptr, c.O_RDONLY);
    if (fd < 0) {
        try stderr.print("du: {s}: No such file or directory\n", .{file_path});
        return false;
    }
    defer _ = c.close(fd);

    var buf: [4096]u8 = undefined;
    var line_buf = std.ArrayList(u8).empty;
    defer line_buf.deinit(allocator);

    while (true) {
        const nr = c.read(fd, &buf, buf.len);
        if (nr <= 0) break;
        const n: usize = @intCast(nr);
        for (buf[0..n]) |byte| {
            if (byte == '\n') {
                var line = line_buf.items;
                if (line.len > 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];
                if (line.len > 0) try addExcludePattern(allocator, line, cfg);
                line_buf.clearRetainingCapacity();
            } else {
                try line_buf.append(allocator, byte);
            }
        }
    }
    if (line_buf.items.len > 0) {
        var line = line_buf.items;
        if (line.len > 0 and line[line.len - 1] == '\r') line = line[0 .. line.len - 1];
        if (line.len > 0) try addExcludePattern(allocator, line, cfg);
    }
    return true;
}
