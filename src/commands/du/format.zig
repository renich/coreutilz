const std = @import("std");
const types = @import("types.zig");
const c = @import("../../compat/c.zig").c;

const units_1024 = [_][]const u8{ "", "K", "M", "G", "T", "P", "E", "Z", "Y" };
const units_1000 = [_][]const u8{ "", "k", "M", "G", "T", "P", "E", "Z", "Y" };

pub fn formatSize(stats: types.DuStats, cfg: *const types.DuConfig, buf: []u8) []const u8 {
    if (cfg.inodes_mode) {
        return switch (cfg.display_mode) {
            .human_1024 => formatHumanCeiling(stats.inodes, 1024, &units_1024, buf),
            .human_1000 => formatHumanCeiling(stats.inodes, 1000, &units_1000, buf),
            .block_size => std.fmt.bufPrint(buf, "{d}", .{stats.inodes}) catch "?",
        };
    }

    return switch (cfg.display_mode) {
        .human_1024 => formatHumanCeiling(stats.size, 1024, &units_1024, buf),
        .human_1000 => formatHumanCeiling(stats.size, 1000, &units_1000, buf),
        .block_size => |bs| {
            if (stats.size == 0) return "0";
            const count = (stats.size + bs - 1) / bs;
            return std.fmt.bufPrint(buf, "{d}", .{count}) catch "?";
        },
    };
}

pub fn formatHumanCeiling(val: u64, divisor: u64, units: []const []const u8, buf: []u8) []const u8 {
    if (val == 0) return "0";
    if (val < divisor) return std.fmt.bufPrint(buf, "{d}", .{val}) catch "?";

    var k: usize = 0;
    var p: u64 = 1;
    while (k + 1 < units.len and val >= p * divisor) {
        k += 1;
        p *= divisor;
    }

    const whole = (val + p - 1) / p;
    if (whole >= divisor and k + 1 < units.len) {
        k += 1;
        p *= divisor;
    }

    const val128: u128 = @intCast(val);
    const p128: u128 = @intCast(p);
    const tenths = (val128 * 10 + p128 - 1) / p128;
    if (tenths < 100) {
        const d1: u64 = @intCast(tenths / 10);
        const d2: u64 = @intCast(tenths % 10);
        return std.fmt.bufPrint(buf, "{d}.{d}{s}", .{ d1, d2, units[k] }) catch "?";
    }

    const w = (val + p - 1) / p;
    return std.fmt.bufPrint(buf, "{d}{s}", .{ w, units[k] }) catch "?";
}

pub fn formatTime(stats: types.DuStats, cfg: *const types.DuConfig, buf: []u8) []const u8 {
    var sec: c.time_t = @intCast(stats.tmax);
    var tm_buf: c.struct_tm = undefined;
    const tm_ptr = c.localtime_r(&sec, &tm_buf);
    if (tm_ptr == null) {
        return std.fmt.bufPrint(buf, "{d}", .{stats.tmax}) catch "?";
    }

    const fmt_str = switch (cfg.time_style) {
        .iso => "%Y-%m-%d",
        .long_iso => "%Y-%m-%d %H:%M",
        .full_iso => "%Y-%m-%d %H:%M:%S",
        .custom => |s| s,
    };

    var fmt_buf: [128]u8 = undefined;
    if (fmt_str.len >= fmt_buf.len) return std.fmt.bufPrint(buf, "{d}", .{stats.tmax}) catch "?";
    @memcpy(fmt_buf[0..fmt_str.len], fmt_str);
    fmt_buf[fmt_str.len] = 0;

    var out_buf: [128]u8 = undefined;
    const len = c.strftime(&out_buf, out_buf.len, &fmt_buf, tm_ptr);
    if (len == 0) {
        return std.fmt.bufPrint(buf, "{d}", .{stats.tmax}) catch "?";
    }

    const str = out_buf[0..len];
    if (str.len > buf.len) return "?";
    @memcpy(buf[0..str.len], str);
    return buf[0..str.len];
}

pub fn printEntry(writer: anytype, path: []const u8, stats: types.DuStats, cfg: *const types.DuConfig) !void {
    var sz_buf: [64]u8 = undefined;
    const sz_str = formatSize(stats, cfg, &sz_buf);
    try writer.writeAll(sz_str);

    if (cfg.time_type != .none) {
        try writer.writeByte('\t');
        var tm_buf: [128]u8 = undefined;
        const tm_str = formatTime(stats, cfg, &tm_buf);
        try writer.writeAll(tm_str);
    }

    try writer.writeByte('\t');
    try writer.writeAll(path);
    if (cfg.null_terminate) {
        try writer.writeByte(0);
    } else {
        try writer.writeByte('\n');
    }
}
