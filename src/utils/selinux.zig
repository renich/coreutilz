const std = @import("std");
const c = @import("../compat/c.zig").c;

/// Set the default file creation context via /proc/self/attr/fscreate.
/// Emits standard GNU Coreutils diagnostic on failure and returns false.
pub fn setFsCreateCon(cmd_name: []const u8, ctx: []const u8, stderr: anytype) bool {
    const fd = c.open("/proc/self/attr/fscreate", c.O_WRONLY | c.O_CLOEXEC);
    if (fd < 0) {
        const err_ptr = c.strerror(c.__errno_location().*);
        const err_msg = if (err_ptr != null) std.mem.span(err_ptr) else "Invalid argument";
        stderr.print("{s}: failed to set default file creation context to '{s}': {s}\n", .{ cmd_name, ctx, err_msg }) catch {};
        return false;
    }
    defer _ = c.close(fd);

    const n = c.write(fd, ctx.ptr, ctx.len);
    if (n < 0) {
        const err_ptr = c.strerror(c.__errno_location().*);
        const err_msg = if (err_ptr != null) std.mem.span(err_ptr) else "Invalid argument";
        stderr.print("{s}: failed to set default file creation context to '{s}': {s}\n", .{ cmd_name, ctx, err_msg }) catch {};
        return false;
    }
    return true;
}
