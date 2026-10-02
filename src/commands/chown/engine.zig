const std = @import("std");
const types = @import("types.zig");
const format = @import("format.zig");
const spec_mod = @import("spec.zig");
const traverse = @import("traverse.zig");
const c = @import("../../compat/c.zig").c;

pub fn execute(
    cfg: *types.ChownConfig,
    targets: []const []const u8,
    allocator: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) !u8 {
    if (cfg.preserve_root and cfg.recurse) {
        initRootDevIno(cfg);
    }

    var exit_status: u8 = 0;
    var visited = std.AutoHashMap(types.DevIno, void).init(allocator);
    defer visited.deinit();

    for (targets) |target| {
        const ok = try processOperand(cfg, target, &visited, allocator, stdout, stderr);
        if (!ok) exit_status = 1;
    }

    return exit_status;
}

fn initRootDevIno(cfg: *types.ChownConfig) void {
    var root_st: c.struct_stat = undefined;
    if (c.stat("/", &root_st) == 0) {
        cfg.root_dev = @intCast(root_st.st_dev);
        cfg.root_ino = @intCast(root_st.st_ino);
    }
}

fn checkRootCycle(cfg: *const types.ChownConfig, path: []const u8, st: *const c.struct_stat, stderr: anytype) !bool {
    if (!cfg.preserve_root or !cfg.recurse) return false;
    if (cfg.root_dev) |rdev| {
        if (cfg.root_ino) |rino| {
            if (@as(u64, @intCast(st.st_dev)) == rdev and @as(u64, @intCast(st.st_ino)) == rino) {
                if (std.mem.eql(u8, path, "/") or std.mem.eql(u8, path, "/.")) {
                    try stderr.print("{s}: it is dangerous to operate recursively on '/'\n{s}: use --no-preserve-root to override this failsafe\n", .{ cfg.cmd_name, cfg.cmd_name });
                } else {
                    try stderr.print("{s}: it is dangerous to operate recursively on '{s}' (same as '/')\n{s}: use --no-preserve-root to override this failsafe\n", .{ cfg.cmd_name, path, cfg.cmd_name });
                }
                return true;
            }
        }
    }
    return false;
}

fn processOperand(
    cfg: *const types.ChownConfig,
    target: []const u8,
    visited: *std.AutoHashMap(types.DevIno, void),
    allocator: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) !bool {
    const target_z = try allocator.dupeZ(u8, target);
    defer allocator.free(target_z);

    var lst: c.struct_stat = undefined;
    if (c.lstat(target_z.ptr, &lst) != 0) {
        return handleStatFailure(cfg, target, target_z, stderr);
    }

    var st = lst;
    const is_symlink = (lst.st_mode & c.S_IFMT) == c.S_IFLNK;
    const is_cmd_symlink_traversable = is_symlink and (cfg.traverse_mode == .command_line or cfg.traverse_mode == .logical);
    if (is_cmd_symlink_traversable) {
        if (c.stat(target_z.ptr, &st) != 0) st = lst;
    }

    if (try checkRootCycle(cfg, target, &st, stderr)) return false;

    const is_dir = (st.st_mode & c.S_IFMT) == c.S_IFDIR;
    if (cfg.recurse and is_dir) {
        try visited.put(.{ .dev = @intCast(st.st_dev), .ino = @intCast(st.st_ino) }, {});
    }
    var ok = try processSinglePath(cfg, target, true, allocator, stdout, stderr);
    if (cfg.recurse and is_dir) {
        const walk_ok = try traverse.walkDirectory(processEntryCallback, cfg, target, true, visited, allocator, stdout, stderr);
        if (!walk_ok) ok = false;
    }
    return ok;
}

fn processEntryCallback(
    cfg: *const types.ChownConfig,
    path: []const u8,
    is_cmd_arg: bool,
    allocator: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) anyerror!bool {
    if (cfg.preserve_root and cfg.traverse_mode == .logical) {
        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);
        var st: c.struct_stat = undefined;
        if (c.stat(path_z.ptr, &st) == 0) {
            if (try checkRootCycle(cfg, path, &st, stderr)) return false;
        }
    }
    return processSinglePath(cfg, path, is_cmd_arg, allocator, stdout, stderr);
}

fn handleStatFailure(cfg: *const types.ChownConfig, target: []const u8, target_z: [:0]const u8, stderr: anytype) !bool {
    _ = target_z;
    if (!cfg.silent) {
        const err_str = std.mem.span(c.strerror(c.__errno_location().*));
        try stderr.print("{s}: cannot access '{s}': {s}\n", .{ cfg.cmd_name, target, err_str });
    }
    if (cfg.verbosity == .high) {
        const new_spec = if (cfg.is_chgrp) cfg.target_group_str orelse "" else cfg.target_user_str orelse "";
        if (cfg.is_chgrp) {
            try stderr.print("failed to change group of '{s}' to {s}\n", .{ target, new_spec });
        } else {
            try stderr.print("failed to change ownership of '{s}' to {s}\n", .{ target, new_spec });
        }
    }
    return false;
}

pub fn processSinglePath(
    cfg: *const types.ChownConfig,
    path: []const u8,
    is_cmd_arg: bool,
    allocator: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) !bool {
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    const use_deref = cfg.affect_symlink_referent;
    var st: c.struct_stat = undefined;
    const stat_res = if (use_deref) c.stat(path_z.ptr, &st) else c.lstat(path_z.ptr, &st);

    if (stat_res != 0) {
        return handlePathStatError(cfg, path, path_z, use_deref, is_cmd_arg, stderr);
    }

    const cur_u = try spec_mod.uidToName(st.st_uid, allocator);
    defer allocator.free(cur_u);
    const cur_g = try spec_mod.gidToName(st.st_gid, allocator);
    defer allocator.free(cur_g);

    if (isFilteredOut(cfg, st.st_uid, st.st_gid)) {
        const old_spec = try format.formatUserGroup(cfg.is_chgrp, cur_u, cur_g, allocator);
        defer allocator.free(old_spec);
        try format.describeChange(cfg, path, .retained, old_spec, old_spec, stdout);
        return true;
    }

    const new_uid: c.uid_t = if (cfg.uid) |u| @intCast(u) else @as(c.uid_t, @bitCast(@as(c_int, -1)));
    const new_gid: c.gid_t = if (cfg.gid) |g| @intCast(g) else @as(c.gid_t, @bitCast(@as(c_int, -1)));

    const rc = if (use_deref) c.chown(path_z.ptr, new_uid, new_gid) else c.lchown(path_z.ptr, new_uid, new_gid);
    return handleChownResult(cfg, path, rc, cur_u, cur_g, allocator, stdout, stderr);
}

fn handlePathStatError(
    cfg: *const types.ChownConfig,
    path: []const u8,
    path_z: [:0]const u8,
    use_deref: bool,
    is_cmd_arg: bool,
    stderr: anytype,
) !bool {
    _ = is_cmd_arg;
    if (use_deref and c.__errno_location().* == c.ENOENT) {
        var lst: c.struct_stat = undefined;
        if (c.lstat(path_z.ptr, &lst) == 0) {
            try stderr.print("{s}: cannot dereference '{s}': No such file or directory\n", .{ cfg.cmd_name, path });
            return false;
        }
    }
    if (!cfg.silent) {
        const err_str = std.mem.span(c.strerror(c.__errno_location().*));
        try stderr.print("{s}: cannot access '{s}': {s}\n", .{ cfg.cmd_name, path, err_str });
    }
    return false;
}

fn isFilteredOut(cfg: *const types.ChownConfig, uid: u32, gid: u32) bool {
    if (cfg.req_uid) |ru| {
        if (uid != ru) return true;
    }
    if (cfg.req_gid) |rg| {
        if (gid != rg) return true;
    }
    return false;
}

fn handleChownResult(
    cfg: *const types.ChownConfig,
    path: []const u8,
    rc: c_int,
    cur_u: []const u8,
    cur_g: []const u8,
    allocator: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) !bool {
    const old_spec = try format.formatUserGroup(cfg.is_chgrp, cur_u, cur_g, allocator);
    defer allocator.free(old_spec);
    const new_spec = try format.formatUserGroup(cfg.is_chgrp, cfg.target_user_str, cfg.target_group_str, allocator);
    defer allocator.free(new_spec);

    if (rc != 0) {
        if (!cfg.silent) {
            const err_str = std.mem.span(c.strerror(c.__errno_location().*));
            try stderr.print("{s}: changing ownership of '{s}': {s}\n", .{ cfg.cmd_name, path, err_str });
        }
        try format.describeChange(cfg, path, .failed, old_spec, new_spec, stdout);
        return false;
    }

    const actually_changed = (cfg.uid != null and cfg.uid.? != std.fmt.parseInt(u32, cur_u, 10) catch null) or
        (cfg.gid != null and cfg.gid.? != std.fmt.parseInt(u32, cur_g, 10) catch null) or
        !std.mem.eql(u8, old_spec, new_spec);

    const status: format.ChangeStatus = if (actually_changed) .changed else .retained;
    try format.describeChange(cfg, path, status, old_spec, new_spec, stdout);
    return true;
}
