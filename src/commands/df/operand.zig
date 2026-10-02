const std = @import("std");
const types = @import("types.zig");
const mounts = @import("mounts.zig");
const c = @import("../../compat/c.zig").c;

pub fn findMountForOperand(
    raw_list: []const types.MountInfo,
    operand: []const u8,
    allocator: std.mem.Allocator,
) !?types.MountInfo {
    const op_z = try allocator.dupeZ(u8, operand);
    defer allocator.free(op_z);

    var st: c.struct_stat = undefined;
    if (c.stat(op_z.ptr, &st) != 0) return null;

    const is_blk = (st.st_mode & c.S_IFMT) == c.S_IFBLK;
    if (is_blk) {
        if (try matchBlockDevice(raw_list, operand, st.st_rdev, allocator)) |res| return res;
    }

    var best_idx: ?usize = null;
    var best_len: usize = 0;
    for (raw_list, 0..) |*m, i| {
        if (m.dev != 0 and m.dev == @as(u64, @intCast(st.st_dev))) {
            if (best_idx == null or m.dir.len > best_len) {
                best_idx = i;
                best_len = m.dir.len;
            }
        }
    }
    if (best_idx) |idx| {
        var res = try mounts.cloneMountInfo(&raw_list[idx], allocator);
        res.file_operand = operand;
        return res;
    }
    return null;
}

fn matchBlockDevice(
    raw_list: []const types.MountInfo,
    operand: []const u8,
    rdev: c.dev_t,
    allocator: std.mem.Allocator,
) !?types.MountInfo {
    for (raw_list) |*m| {
        if (std.mem.eql(u8, m.fsname, operand)) {
            var res = try mounts.cloneMountInfo(m, allocator);
            res.file_operand = operand;
            return res;
        }
        const m_z = allocator.dupeZ(u8, m.fsname) catch continue;
        defer allocator.free(m_z);
        var m_st: c.struct_stat = undefined;
        if (c.stat(m_z.ptr, &m_st) == 0 and (m_st.st_mode & c.S_IFMT) == c.S_IFBLK) {
            if (m_st.st_rdev == rdev) {
                var res = try mounts.cloneMountInfo(m, allocator);
                res.file_operand = operand;
                return res;
            }
        }
    }
    return null;
}

pub fn findMountFallback(operand: []const u8, allocator: std.mem.Allocator) !?types.MountInfo {
    const op_z = try allocator.dupeZ(u8, operand);
    defer allocator.free(op_z);

    var vfs: c.struct_statvfs = undefined;
    if (c.statvfs(op_z.ptr, &vfs) != 0) return null;

    var st: c.struct_stat = undefined;
    const dev: u64 = if (c.stat(op_z.ptr, &st) == 0) @intCast(st.st_dev) else 0;
    const frsize: u64 = if (vfs.f_frsize != 0) @intCast(vfs.f_frsize) else if (vfs.f_bsize != 0) @intCast(vfs.f_bsize) else 1024;

    const mp = findMountPoint(operand, allocator) catch try allocator.dupe(u8, "/");
    return types.MountInfo{
        .fsname = try allocator.dupe(u8, "-"),
        .dir = mp,
        .fstype = try allocator.dupe(u8, "-"),
        .dev = dev,
        .is_dummy = false,
        .is_remote = false,
        .stat_ok = true,
        .f_frsize = frsize,
        .f_blocks = @intCast(vfs.f_blocks),
        .f_bfree = @intCast(vfs.f_bfree),
        .f_bavail = @intCast(vfs.f_bavail),
        .f_files = @intCast(vfs.f_files),
        .f_ffree = @intCast(vfs.f_ffree),
        .f_favail = @intCast(vfs.f_favail),
        .file_operand = operand,
    };
}

fn findMountPoint(operand: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    const op_z = try allocator.dupeZ(u8, operand);
    defer allocator.free(op_z);

    var resolved_buf: [c.PATH_MAX]u8 = undefined;
    const res_ptr = c.realpath(op_z.ptr, &resolved_buf);
    var cur_path: []const u8 = if (res_ptr != null) std.mem.span(res_ptr) else "/";

    var st: c.struct_stat = undefined;
    if (c.stat(op_z.ptr, &st) != 0) return try allocator.dupe(u8, "/");
    const target_dev = st.st_dev;

    while (!std.mem.eql(u8, cur_path, "/") and cur_path.len > 0) {
        const parent = std.fs.path.dirname(cur_path) orelse "/";
        const parent_z = try allocator.dupeZ(u8, parent);
        defer allocator.free(parent_z);
        var p_st: c.struct_stat = undefined;
        if (c.stat(parent_z.ptr, &p_st) == 0 and p_st.st_dev != target_dev) {
            return try allocator.dupe(u8, cur_path);
        }
        cur_path = parent;
    }
    return try allocator.dupe(u8, "/");
}
