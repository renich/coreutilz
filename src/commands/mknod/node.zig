const std = @import("std");
const c = @import("../../compat/c.zig").c;

pub fn parseDeviceNum(s: []const u8) !u32 {
    if (s.len == 0) return error.InvalidNumber;
    if (std.mem.startsWith(u8, s, "0x") or std.mem.startsWith(u8, s, "0X")) {
        return std.fmt.parseInt(u32, s[2..], 16);
    } else if (s.len > 1 and s[0] == '0') {
        return std.fmt.parseInt(u32, s[1..], 8);
    } else {
        return std.fmt.parseInt(u32, s, 10);
    }
}

pub fn makeDev(major: u32, minor: u32) c.dev_t {
    const maj: u64 = major;
    const min: u64 = minor;
    return @intCast(((maj & 0x00000fff) << 8) |
        ((maj & ~@as(u64, 0x00000fff)) << 32) |
        (min & 0x000000ff) |
        ((min & ~@as(u64, 0x000000ff)) << 12));
}

pub fn createSpecialNode(
    path: []const u8,
    node_type: c.mode_t,
    dev: c.dev_t,
    mode: u32,
    mode_provided: bool,
    allocator: std.mem.Allocator,
    stderr: anytype,
) !u8 {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    const create_mode: c.mode_t = node_type | (if (mode_provided) 0o666 else @as(c.mode_t, @intCast(mode)));
    const ret = if (node_type == c.S_IFIFO) c.mkfifo(path_z.ptr, create_mode) else c.mknod(path_z.ptr, create_mode, dev);

    if (ret != 0) {
        const err_str = std.mem.span(c.strerror(c.__errno_location().*));
        try stderr.print("mknod: '{s}': {s}\n", .{ path, err_str });
        return 1;
    }

    if (mode_provided) {
        if (c.chmod(path_z.ptr, @intCast(mode)) != 0) {
            const err_str = std.mem.span(c.strerror(c.__errno_location().*));
            try stderr.print("mknod: cannot set permissions of '{s}': {s}\n", .{ path, err_str });
            return 1;
        }
    }
    return 0;
}
