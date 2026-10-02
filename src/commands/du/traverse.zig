const std = @import("std");
const types = @import("types.zig");
const format = @import("format.zig");
const filter = @import("filter.zig");
const c = @import("../../compat/c.zig").c;

pub const TraverseState = struct {
    seen_hardlinks: *std.AutoHashMap(types.DevIno, void),
    active_ancestors: std.AutoHashMap(types.DevIno, void),
    cfg: *const types.DuConfig,
    hash_all: bool,
    allocator: std.mem.Allocator,
    had_error: bool = false,
    stop_early: bool = false,
    tot_stats: types.DuStats = .{},

    pub fn init(cfg: *const types.DuConfig, seen_links: *std.AutoHashMap(types.DevIno, void), hash_all: bool, allocator: std.mem.Allocator) TraverseState {
        return .{
            .seen_hardlinks = seen_links,
            .active_ancestors = std.AutoHashMap(types.DevIno, void).init(allocator),
            .cfg = cfg,
            .hash_all = hash_all,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *TraverseState) void {
        self.active_ancestors.deinit();
    }
};
pub fn traverseDir(
    state: *TraverseState,
    dir_path: []const u8,
    dir_p: *c.DIR,
    dir_st: *const c.struct_stat,
    level: usize,
    root_dev: u64,
    stdout: anytype,
    stderr: anytype,
) anyerror!types.DuStats {
    defer _ = c.closedir(dir_p);

    const dev_ino = types.DevIno{ .dev = @intCast(dir_st.st_dev), .ino = @intCast(dir_st.st_ino) };
    if (state.active_ancestors.contains(dev_ino)) {
        if (!state.cfg.dereference_all) {
            try stderr.print("du: WARNING: Circular directory structure.\nThis almost certainly means that you have a corrupted file system.\nNOTIFY YOUR SYSTEM MANAGER.\nThe following directory is part of the cycle:\n  '{s}'\n", .{dir_path});
            state.had_error = true;
        }
        return .{};
    }
    if (!state.cfg.count_links and state.hash_all) {
        if (state.seen_hardlinks.contains(dev_ino)) return .{};
        try state.seen_hardlinks.put(dev_ino, {});
    }

    try state.active_ancestors.put(dev_ino, {});
    defer _ = state.active_ancestors.remove(dev_ino);

    var dir_stats = filter.computeEntryStats(state.cfg, dir_st);
    state.tot_stats.add(dir_stats);

    try readAndProcessChildren(state, dir_p, dir_path, level, root_dev, &dir_stats, stdout, stderr);

    if (filter.shouldPrint(state.cfg, true, level, dir_stats)) {
        try format.printEntry(stdout, dir_path, dir_stats, state.cfg);
    }
    return dir_stats;
}

fn readAndProcessChildren(
    state: *TraverseState,
    dir_p: *c.DIR,
    dir_path: []const u8,
    level: usize,
    root_dev: u64,
    dir_stats: *types.DuStats,
    stdout: anytype,
    stderr: anytype,
) !void {
    var entries = std.ArrayList([]const u8).empty;
    defer {
        for (entries.items) |name| state.allocator.free(name);
        entries.deinit(state.allocator);
    }

    while (c.readdir(dir_p)) |ent| {
        const name = std.mem.span(@as([*:0]const u8, @ptrCast(&ent.*.d_name)));
        if (std.mem.eql(u8, name, ".") or std.mem.eql(u8, name, "..")) continue;
        try entries.append(state.allocator, try state.allocator.dupe(u8, name));
    }

    for (entries.items) |name| {
        try processChildEntry(state, dir_p, dir_path, name, level, root_dev, dir_stats, stdout, stderr);
        if (state.stop_early) return error.TraversalStopped;
    }
}

fn processChildEntry(
    state: *TraverseState,
    dir_p: *c.DIR,
    dir_path: []const u8,
    name: []const u8,
    level: usize,
    root_dev: u64,
    dir_stats: *types.DuStats,
    stdout: anytype,
    stderr: anytype,
) !void {
    if (state.stop_early) return;
    const sep: []const u8 = if (std.mem.endsWith(u8, dir_path, "/")) "" else "/";
    const child_path = try std.fmt.allocPrint(state.allocator, "{s}{s}{s}", .{ dir_path, sep, name });
    defer state.allocator.free(child_path);

    if (filter.isExcluded(state.cfg, child_path, name)) return;

    const name_z = try state.allocator.dupeZ(u8, name);
    defer state.allocator.free(name_z);

    const dir_fd = c.dirfd(dir_p);
    var child_st: c.struct_stat = undefined;
    if (statChild(state, dir_fd, name_z.ptr, child_path, &child_st) != 0) {
        try handleStatError(state, dir_path, child_path, stderr);
        return;
    }

    if (state.cfg.one_file_system and @as(u64, @intCast(child_st.st_dev)) != root_dev) return;

    const child_is_dir = (child_st.st_mode & c.S_IFMT) == c.S_IFDIR;
    if (child_is_dir) {
        try processChildDir(state, dir_fd, name_z.ptr, child_path, &child_st, level, root_dev, dir_stats, stdout, stderr);
    } else {
        try processChildFile(state, child_path, &child_st, level + 1, dir_stats, stdout);
    }
}

fn statChild(state: *TraverseState, dir_fd: c_int, name_z: [*:0]const u8, child_path: []const u8, st: *c.struct_stat) c_int {
    if (state.cfg.dereference_all) {
        const cp_z = state.allocator.dupeZ(u8, child_path) catch return -1;
        defer state.allocator.free(cp_z);
        return c.fstatat(c.AT_FDCWD, cp_z.ptr, st, 0);
    }
    return c.fstatat(dir_fd, name_z, st, c.AT_SYMLINK_NOFOLLOW);
}

fn handleStatError(state: *TraverseState, dir_path: []const u8, child_path: []const u8, stderr: anytype) !void {
    const dir_z = try state.allocator.dupeZ(u8, dir_path);
    defer state.allocator.free(dir_z);
    var parent_st: c.struct_stat = undefined;
    if (c.lstat(dir_z.ptr, &parent_st) != 0 and c.__errno_location().* == c.ENOENT) {
        try stderr.print("du: fts_read failed: {s}: No such file or directory\n", .{dir_path});
        state.had_error = true;
        state.stop_early = true;
        return error.TraversalStopped;
    }
    const err_str = std.mem.span(c.strerror(c.__errno_location().*));
    try stderr.print("du: cannot access '{s}': {s}\n", .{ child_path, err_str });
    state.had_error = true;
}

fn openSubDir(state: *TraverseState, parent_fd: c_int, name_z: [*:0]const u8, child_path: []const u8) ?c_int {
    if (state.cfg.dereference_all) {
        const cp_z = state.allocator.dupeZ(u8, child_path) catch return null;
        defer state.allocator.free(cp_z);
        const fd = c.openat(c.AT_FDCWD, cp_z.ptr, c.O_RDONLY | c.O_DIRECTORY | c.O_NOCTTY);
        return if (fd >= 0) fd else null;
    }
    const fd = c.openat(parent_fd, name_z, c.O_RDONLY | c.O_DIRECTORY | c.O_NOCTTY);
    return if (fd >= 0) fd else null;
}

fn handleSubDirOpenFail(
    state: *TraverseState,
    child_path: []const u8,
    child_st: *const c.struct_stat,
    level: usize,
    dir_stats: *types.DuStats,
    stdout: anytype,
    stderr: anytype,
) !void {
    const err_str = std.mem.span(c.strerror(c.__errno_location().*));
    try stderr.print("du: cannot read directory '{s}': {s}\n", .{ child_path, err_str });
    state.had_error = true;
    const sub_stats = filter.computeEntryStats(state.cfg, child_st);
    state.tot_stats.add(sub_stats);
    if (!state.cfg.separate_dirs) dir_stats.add(sub_stats);
    if (filter.shouldPrint(state.cfg, true, level + 1, sub_stats)) {
        try format.printEntry(stdout, child_path, sub_stats, state.cfg);
    }
}

fn processChildDir(
    state: *TraverseState,
    parent_fd: c_int,
    name_z: [*:0]const u8,
    child_path: []const u8,
    child_st: *const c.struct_stat,
    level: usize,
    root_dev: u64,
    dir_stats: *types.DuStats,
    stdout: anytype,
    stderr: anytype,
) !void {
    const sub_fd = openSubDir(state, parent_fd, name_z, child_path) orelse {
        return handleSubDirOpenFail(state, child_path, child_st, level, dir_stats, stdout, stderr);
    };
    const sub_dir_p = c.fdopendir(sub_fd) orelse {
        _ = c.close(sub_fd);
        return;
    };
    const sub_stats = try traverseDir(state, child_path, sub_dir_p, child_st, level + 1, root_dev, stdout, stderr);
    if (state.stop_early) return error.TraversalStopped;

    var verify_st: c.struct_stat = undefined;
    if (c.fstatat(parent_fd, name_z, &verify_st, c.AT_SYMLINK_NOFOLLOW) != 0 and c.__errno_location().* == c.ENOENT) {
        try stderr.print("du: fts_read failed: {s}: No such file or directory\n", .{child_path});
        state.had_error = true;
        state.stop_early = true;
        return error.TraversalStopped;
    }

    if (!state.cfg.separate_dirs) {
        dir_stats.add(sub_stats);
    } else if (sub_stats.tmax > dir_stats.tmax or (sub_stats.tmax == dir_stats.tmax and sub_stats.tmax_nsec > dir_stats.tmax_nsec)) {
        dir_stats.tmax = sub_stats.tmax;
        dir_stats.tmax_nsec = sub_stats.tmax_nsec;
    }
}

fn processChildFile(
    state: *TraverseState,
    child_path: []const u8,
    child_st: *const c.struct_stat,
    level: usize,
    dir_stats: *types.DuStats,
    stdout: anytype,
) !void {
    const child_stats = filter.computeEntryStats(state.cfg, child_st);
    if (!state.cfg.count_links and (state.hash_all or child_st.st_nlink > 1)) {
        const c_dev_ino = types.DevIno{ .dev = @intCast(child_st.st_dev), .ino = @intCast(child_st.st_ino) };
        if (state.seen_hardlinks.contains(c_dev_ino)) return;
        try state.seen_hardlinks.put(c_dev_ino, {});
    }
    dir_stats.add(child_stats);
    state.tot_stats.add(child_stats);
    if (filter.shouldPrint(state.cfg, false, level, child_stats)) {
        try format.printEntry(stdout, child_path, child_stats, state.cfg);
    }
}
