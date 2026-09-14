const std = @import("std");
const c = @import("../../compat/c.zig").c;
const mode = @import("../../utils/mode.zig");
const types = @import("types.zig");
const quoting = @import("quoting.zig");

pub fn formatPermissions(st: *const c.struct_stat, buf: *[10]u8) []const u8 {
    const mode_val: u32 = @intCast(st.st_mode);
    buf[0] = switch (mode_val & c.S_IFMT) {
        c.S_IFDIR => 'd',
        c.S_IFLNK => 'l',
        c.S_IFCHR => 'c',
        c.S_IFBLK => 'b',
        c.S_IFIFO => 'p',
        c.S_IFSOCK => 's',
        else => '-',
    };
    var perm_buf: [9]u8 = undefined;
    const perms = mode.formatMode(mode_val, &perm_buf);
    @memcpy(buf[1..10], perms);
    return buf;
}

pub fn formatFileSize(size: c.off_t, human: bool, block_size: u64, buf: []u8) []const u8 {
    if (!human) {
        if (block_size > 1) {
            const blk: u64 = if (size <= 0) 0 else (@as(u64, @intCast(size)) + block_size - 1) / block_size;
            return std.fmt.bufPrint(buf, "{d}", .{blk}) catch "?";
        }
        return std.fmt.bufPrint(buf, "{d}", .{size}) catch "?";
    }
    const units = [_]u8{ 'B', 'K', 'M', 'G', 'T', 'P' };
    var f_size: f64 = @floatFromInt(size);
    var u_idx: usize = 0;
    while (f_size >= 1024.0 and u_idx + 1 < units.len) {
        f_size /= 1024.0;
        u_idx += 1;
    }
    if (u_idx == 0) return std.fmt.bufPrint(buf, "{d}", .{size}) catch "?";
    if (f_size < 10.0) return std.fmt.bufPrint(buf, "{d:.1}{c}", .{ f_size, units[u_idx] }) catch "?";
    const rounded: u64 = @intFromFloat(@round(f_size));
    return std.fmt.bufPrint(buf, "{d}{c}", .{ rounded, units[u_idx] }) catch "?";
}

fn resolveTimeFormat(custom_fmt: ?[]const u8) ?[]const u8 {
    const chosen_fmt = custom_fmt orelse if (c.getenv("TIME_STYLE")) |raw| std.mem.span(raw) else null;
    const ts = chosen_fmt orelse return null;
    if (ts.len > 1 and ts[0] == '+') return ts[1..];
    if (std.mem.eql(u8, ts, "long-iso") or std.mem.eql(u8, ts, "posix-long-iso")) return "%Y-%m-%d %H:%M";
    if (std.mem.eql(u8, ts, "iso") or std.mem.eql(u8, ts, "posix-iso")) return "%Y-%m-%d";
    return null;
}

fn formatFullTime(st: *const c.struct_stat, tm_val: *const c.struct_tm, buf: []u8) []const u8 {
    var base_buf: [64]u8 = undefined;
    const len1 = c.strftime(&base_buf, base_buf.len, "%Y-%m-%d %H:%M:%S", tm_val);
    var tz_buf: [16]u8 = undefined;
    const len2 = c.strftime(&tz_buf, tz_buf.len, "%z", tm_val);
    const nsec: u64 = @intCast(st.st_mtim.tv_nsec);
    return std.fmt.bufPrint(buf, "{s}.{d:0>9} {s}", .{ base_buf[0..len1], nsec, tz_buf[0..len2] }) catch "?";
}

fn formatRecentOrOldTime(st: *const c.struct_stat, tm_val: *const c.struct_tm, buf: []u8) []const u8 {
    const now = c.time(null);
    const six_months_sec: i64 = 6 * 30 * 24 * 3600;
    const is_recent = (st.st_mtim.tv_sec <= now + 3600) and (st.st_mtim.tv_sec >= now - six_months_sec);
    const fmt: [*:0]const u8 = if (is_recent) "%b %e %H:%M" else "%b %e  %Y";
    const len = c.strftime(buf.ptr, buf.len, fmt, tm_val);
    return if (len > 0) buf[0..len] else "?";
}

pub fn formatTimestamp(st: *const c.struct_stat, full_time: bool, custom_fmt: ?[]const u8, buf: []u8) []const u8 {
    var tm_val: c.struct_tm = undefined;
    const time_val: c.time_t = @intCast(st.st_mtim.tv_sec);
    _ = c.localtime_r(&time_val, &tm_val);

    if (resolveTimeFormat(custom_fmt)) |fmt_str| {
        var fmt_z: [64]u8 = undefined;
        if (fmt_str.len < fmt_z.len) {
            @memcpy(fmt_z[0..fmt_str.len], fmt_str);
            fmt_z[fmt_str.len] = 0;
            const len = c.strftime(buf.ptr, buf.len, &fmt_z, &tm_val);
            if (len > 0) return buf[0..len];
        }
    }

    if (full_time) return formatFullTime(st, &tm_val, buf);
    return formatRecentOrOldTime(st, &tm_val, buf);
}

pub fn getOwner(uid: c.uid_t, numeric: bool, buf: *[32]u8) []const u8 {
    if (!numeric) {
        const pw = c.getpwuid(uid);
        if (pw != null and pw.*.pw_name != null) return std.mem.span(pw.*.pw_name);
    }
    return std.fmt.bufPrint(buf, "{d}", .{uid}) catch "?";
}

pub fn getGroup(gid: c.gid_t, numeric: bool, buf: *[32]u8) []const u8 {
    if (!numeric) {
        const gr = c.getgrgid(gid);
        if (gr != null and gr.*.gr_name != null) return std.mem.span(gr.*.gr_name);
    }
    return std.fmt.bufPrint(buf, "{d}", .{gid}) catch "?";
}

pub fn getVisibleLen(entry: *const types.FileEntry, options: *const types.Options) usize {
    var name_buf: [1024]u8 = undefined;
    const quoted = quoting.formatQuotedName(entry.name, options.quoting_style, options.hide_control_chars, &name_buf);
    var len = quoted.len;
    if (options.inode) len += 20;
    if (options.size_blocks) len += 12;
    if (quoting.getIndicatorChar(entry, options) != null) len += 1;
    return len;
}

pub fn printPrefix(writer: anytype, entry: *const types.FileEntry, options: *const types.Options) !void {
    if (options.inode) {
        if (entry.has_stat_error) {
            try writer.writeAll("? ");
        } else {
            try writer.print("{d} ", .{entry.stat.st_ino});
        }
    }
    if (options.size_blocks) {
        if (entry.has_stat_error) {
            try writer.writeAll("? ");
        } else {
            const blk = (@as(u64, @intCast(entry.stat.st_blocks)) * 512 + options.disk_block_size - 1) / options.disk_block_size;
            try writer.print("{d} ", .{blk});
        }
    }
}
