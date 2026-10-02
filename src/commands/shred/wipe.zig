const std = @import("std");
const c = @import("../../compat/c.zig").c;

const nameset = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_.";

fn incname(name: []u8) bool {
    var len = name.len;
    while (len > 0) {
        len -= 1;
        const p = std.mem.indexOfScalar(u8, nameset, name[len]) orelse return false;
        if (p + 1 < nameset.len) {
            name[len] = nameset[p + 1];
            return true;
        }
        name[len] = nameset[0];
    }
    return false;
}

fn tryRenameStep(curr_path: *[]u8, base_buf: []u8, dir_name: []const u8, verbose: bool, stderr: anytype, alloc: std.mem.Allocator) bool {
    while (true) {
        const new_path = if (std.mem.eql(u8, dir_name, "."))
            alloc.dupe(u8, base_buf) catch return false
        else
            std.fs.path.join(alloc, &[_][]const u8{ dir_name, base_buf }) catch return false;
        defer alloc.free(new_path);

        const curr_z = alloc.dupeZ(u8, curr_path.*) catch return false;
        defer alloc.free(curr_z);
        const new_z = alloc.dupeZ(u8, new_path) catch return false;
        defer alloc.free(new_z);

        if (c.renameat2(c.AT_FDCWD, curr_z.ptr, c.AT_FDCWD, new_z.ptr, 1) == 0) {
            if (verbose) stderr.print("shred: {s}: renamed to {s}\n", .{ curr_path.*, new_path }) catch {};
            alloc.free(curr_path.*);
            curr_path.* = alloc.dupe(u8, new_path) catch return false;
            return true;
        }
        if (c.__errno_location().* == c.EEXIST and incname(base_buf)) continue;
        return false;
    }
}

pub fn wipeFileName(path: []const u8, verbose: bool, stderr: anytype, alloc: std.mem.Allocator) bool {
    if (verbose) stderr.print("shred: {s}: removing\n", .{path}) catch {};
    const base_name = std.fs.path.basename(path);
    const dir_name = std.fs.path.dirname(path) orelse ".";
    var curr_path = alloc.dupe(u8, path) catch return false;
    defer alloc.free(curr_path);

    var len = base_name.len;
    while (len > 0) : (len -= 1) {
        const base_buf = alloc.alloc(u8, len) catch return false;
        defer alloc.free(base_buf);
        @memset(base_buf, nameset[0]);
        _ = tryRenameStep(&curr_path, base_buf, dir_name, verbose, stderr, alloc);
    }

    const final_z = alloc.dupeZ(u8, curr_path) catch return false;
    defer alloc.free(final_z);
    if (c.unlink(final_z.ptr) != 0) {
        stderr.print("shred: {s}: failed to remove\n", .{path}) catch {};
        return false;
    }
    if (verbose) {
        stderr.print("shred: {s}: removed\n", .{path}) catch {};
    }
    return true;
}
