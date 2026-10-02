const std = @import("std");
const types = @import("types.zig");
const format = @import("format.zig");
const filter = @import("filter.zig");
const traverse = @import("traverse.zig");
const c = @import("../../compat/c.zig").c;

pub fn processOperand(state: *traverse.TraverseState, op: []const u8, stdout: anytype, stderr: anytype) !void {
    if (state.stop_early) return;
    const operand_z = try state.allocator.dupeZ(u8, op);
    defer state.allocator.free(operand_z);

    const has_slash = op.len > 1 and op[op.len - 1] == '/';
    var st: c.struct_stat = undefined;
    const stat_res = if (state.cfg.dereference_all or state.cfg.dereference_args or has_slash)
        c.stat(operand_z.ptr, &st)
    else
        c.lstat(operand_z.ptr, &st);

    if (stat_res != 0) {
        const err_str = std.mem.span(c.strerror(c.__errno_location().*));
        try stderr.print("du: cannot access '{s}': {s}\n", .{ op, err_str });
        state.had_error = true;
        return;
    }

    if (filter.isExcluded(state.cfg, op, op)) return;

    const is_dir = (st.st_mode & c.S_IFMT) == c.S_IFDIR;
    if (!is_dir) {
        try processNonDirOperand(state, op, &st, stdout);
        return;
    }

    return processDirOperand(state, op, operand_z, &st, stdout, stderr);
}

fn processDirOperand(
    state: *traverse.TraverseState,
    op: []const u8,
    operand_z: [:0]const u8,
    st: *const c.struct_stat,
    stdout: anytype,
    stderr: anytype,
) !void {
    const dir_p = c.opendir(operand_z.ptr) orelse {
        const err_str = std.mem.span(c.strerror(c.__errno_location().*));
        try stderr.print("du: cannot read directory '{s}': {s}\n", .{ op, err_str });
        state.had_error = true;
        const dir_stats = filter.computeEntryStats(state.cfg, st);
        if (filter.shouldPrint(state.cfg, true, 0, dir_stats)) {
            try format.printEntry(stdout, op, dir_stats, state.cfg);
        }
        return;
    };

    const root_dev = @as(u64, @intCast(st.st_dev));
    _ = traverse.traverseDir(state, op, dir_p, st, 0, root_dev, stdout, stderr) catch |err| {
        if (err == error.TraversalStopped) return;
        return err;
    };
}

fn processNonDirOperand(state: *traverse.TraverseState, op: []const u8, st: *const c.struct_stat, stdout: anytype) !void {
    const stats = filter.computeEntryStats(state.cfg, st);
    if (!state.cfg.count_links and (state.hash_all or st.st_nlink > 1)) {
        const dev_ino = types.DevIno{ .dev = @intCast(st.st_dev), .ino = @intCast(st.st_ino) };
        if (state.seen_hardlinks.contains(dev_ino)) return;
        try state.seen_hardlinks.put(dev_ino, {});
    }
    state.tot_stats.add(stats);
    if (filter.shouldPrint(state.cfg, false, 0, stats)) {
        try format.printEntry(stdout, op, stats, state.cfg);
    }
}
