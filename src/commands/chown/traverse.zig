const std = @import("std");
const types = @import("types.zig");
const c = @import("../../compat/c.zig").c;

pub fn walkDirectory(
    comptime processEntryFn: anytype,
    cfg: *const types.ChownConfig,
    dir_path: []const u8,
    is_cmd_arg: bool,
    visited: *std.AutoHashMap(types.DevIno, void),
    allocator: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) anyerror!bool {
    _ = is_cmd_arg;
    const dir_z = try allocator.dupeZ(u8, dir_path);
    defer allocator.free(dir_z);

    const dir = c.opendir(dir_z.ptr) orelse {
        if (!cfg.silent) {
            const err_str = std.mem.span(c.strerror(c.__errno_location().*));
            try stderr.print("{s}: cannot read directory '{s}': {s}\n", .{ cfg.cmd_name, dir_path, err_str });
        }
        return false;
    };
    defer _ = c.closedir(dir);

    var all_ok = true;
    while (c.readdir(dir)) |entry| {
        const name = std.mem.span(@as([*:0]const u8, @ptrCast(&entry.*.d_name)));
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;

        const sub_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, name });
        defer allocator.free(sub_path);

        const ok = try processChild(processEntryFn, cfg, sub_path, visited, allocator, stdout, stderr);
        if (!ok) all_ok = false;
    }

    return all_ok;
}

fn processChild(
    comptime processEntryFn: anytype,
    cfg: *const types.ChownConfig,
    sub_path: []const u8,
    visited: *std.AutoHashMap(types.DevIno, void),
    allocator: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) anyerror!bool {
    const sub_z = try allocator.dupeZ(u8, sub_path);
    defer allocator.free(sub_z);

    var lst: c.struct_stat = undefined;
    if (c.lstat(sub_z.ptr, &lst) != 0) {
        if (!cfg.silent) {
            const err_str = std.mem.span(c.strerror(c.__errno_location().*));
            try stderr.print("{s}: cannot access '{s}': {s}\n", .{ cfg.cmd_name, sub_path, err_str });
        }
        return false;
    }

    const should_descend = checkDescend(cfg, sub_z, &lst);

    var ok = try processEntryFn(cfg, sub_path, false, allocator, stdout, stderr);
    if (!ok) return false;
    if (should_descend) {
        const key = types.DevIno{ .dev = @intCast(lst.st_dev), .ino = @intCast(lst.st_ino) };
        if (visited.contains(key)) {
            return ok;
        }
        try visited.put(key, {});
        const sub_ok = try walkDirectory(processEntryFn, cfg, sub_path, false, visited, allocator, stdout, stderr);
        if (!sub_ok) ok = false;
    }

    return ok;
}

fn checkDescend(cfg: *const types.ChownConfig, sub_z: [:0]const u8, lst: *c.struct_stat) bool {
    const is_symlink = (lst.st_mode & c.S_IFMT) == c.S_IFLNK;
    const is_dir = (lst.st_mode & c.S_IFMT) == c.S_IFDIR;
    if (is_dir) return true;
    if (is_symlink and cfg.traverse_mode == .logical) {
        var st: c.struct_stat = undefined;
        if (c.stat(sub_z.ptr, &st) == 0 and (st.st_mode & c.S_IFMT) == c.S_IFDIR) {
            lst.* = st;
            return true;
        }
    }
    return false;
}
