const std = @import("std");
const c = @import("../../compat/c.zig").c;
const types = @import("types.zig");
const colors_mod = @import("colors.zig");
const dired_mod = @import("dired.zig");
const hyperlink_mod = @import("hyperlink.zig");
const collector = @import("collector.zig");
const formatter = @import("formatter.zig");

pub const DevIno = struct { dev: c.dev_t, ino: c.ino_t };
pub const DirOp = struct { path: []const u8, stat: c.struct_stat };

fn checkAncestorCycle(
    dir_path: []const u8,
    st_opt: ?c.struct_stat,
    recursive: bool,
    visited: *std.ArrayList(DevIno),
    prog_name: []const u8,
    arena: std.mem.Allocator,
    stderr: anytype,
) !?u8 {
    if (!recursive) return null;
    const st = st_opt orelse return null;
    const item = DevIno{ .dev = st.st_dev, .ino = st.st_ino };
    for (visited.items) |v| {
        if (v.dev == item.dev and v.ino == item.ino) {
            try stderr.print("{s}: {s}: not listing already-listed directory\n", .{ prog_name, dir_path });
            return 2;
        }
    }
    try visited.append(arena, item);
    return null;
}

fn printDirectoryHeader(
    dir_path: []const u8,
    options: *const types.Options,
    dired_ctx: *dired_mod.DiredContext,
    arena: std.mem.Allocator,
    stdout: anytype,
) !void {
    var dir_buf: [1024]u8 = undefined;
    const quoted_dir = formatter.formatQuotedName(dir_path, options.quoting_style, options.hide_control_chars, &dir_buf);
    if (dired_ctx.enabled) {
        try dired_ctx.indent(stdout);
        try dired_ctx.pushSubdired(arena);
        try dired_ctx.writeBytes(stdout, quoted_dir);
        try dired_ctx.pushSubdired(arena);
        try dired_ctx.writeBytes(stdout, ":\n");
    } else if (options.hyperlink) {
        const uri = try hyperlink_mod.getAbsoluteUri(arena, dir_path);
        try hyperlink_mod.printHyperlinkStart(stdout, uri);
        try stdout.writeAll(quoted_dir);
        try hyperlink_mod.printHyperlinkEnd(stdout);
        try stdout.writeAll(":\n");
    } else {
        try stdout.print("{s}:\n", .{quoted_dir});
    }
}

fn recurseSubdirectories(
    entries: []const types.FileEntry,
    dir_path: []const u8,
    options: *const types.Options,
    prog_name: []const u8,
    visited: *std.ArrayList(DevIno),
    need_newline: *bool,
    colors: *const colors_mod.Colors,
    use_color: bool,
    used_color: *bool,
    dired_ctx: *dired_mod.DiredContext,
    arena: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) anyerror!u8 {
    var exit_status: u8 = 0;
    for (entries) |*entry| {
        const is_dir_target = entry.is_dir or (options.dereference and entry.is_dir_or_link_to_dir);
        if (!is_dir_target or std.mem.eql(u8, entry.name, ".") or std.mem.eql(u8, entry.name, "..")) continue;
        const sub_path = if (std.mem.eql(u8, dir_path, "."))
            try std.fmt.allocPrint(arena, "./{s}", .{entry.name})
        else
            try std.fmt.allocPrint(arena, "{s}/{s}", .{ dir_path, entry.name });
        const sub_exit = try processDirectory(sub_path, null, options, true, prog_name, visited, need_newline, colors, use_color, used_color, dired_ctx, arena, stdout, stderr);
        if (sub_exit != 0 and exit_status == 0) exit_status = sub_exit;
    }
    return exit_status;
}

fn getDirectoryStat(dir_path: []const u8, dir_stat: ?c.struct_stat, dereference: bool, arena: std.mem.Allocator) !?c.struct_stat {
    if (dir_stat) |s| return s;
    var temp_st: c.struct_stat = undefined;
    const dir_path_z = try arena.dupeZ(u8, dir_path);
    const stat_res = if (dereference) c.stat(dir_path_z.ptr, &temp_st) else c.lstat(dir_path_z.ptr, &temp_st);
    if (stat_res != 0) return null;
    return temp_st;
}

fn reportStatErrors(entries: []const types.FileEntry, prog_name: []const u8, stderr: anytype) !u8 {
    var exit_status: u8 = 0;
    for (entries) |*entry| {
        if (entry.has_stat_error) {
            try stderr.print("{s}: cannot access '{s}': No such file or directory\n", .{ prog_name, entry.full_path });
            if (exit_status == 0) exit_status = 1;
        }
    }
    return exit_status;
}

pub fn processDirectory(
    dir_path: []const u8,
    dir_stat: ?c.struct_stat,
    options: *const types.Options,
    show_header: bool,
    prog_name: []const u8,
    visited: *std.ArrayList(DevIno),
    need_newline: *bool,
    colors: *const colors_mod.Colors,
    use_color: bool,
    used_color: *bool,
    dired_ctx: *dired_mod.DiredContext,
    arena: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) anyerror!u8 {
    const st_opt = try getDirectoryStat(dir_path, dir_stat, options.dereference, arena);
    if (try checkAncestorCycle(dir_path, st_opt, options.recursive, visited, prog_name, arena, stderr)) |cycle_exit| return cycle_exit;
    defer if (options.recursive and st_opt != null) {
        _ = visited.pop();
    };

    if (need_newline.*) try stdout.writeByte('\n');
    need_newline.* = true;
    if (show_header) try printDirectoryHeader(dir_path, options, dired_ctx, arena, stdout);

    const entries = collector.readDirEntries(dir_path, options, colors, use_color, arena) catch {
        try stderr.print("{s}: cannot open directory '{s}': Permission denied\n", .{ prog_name, dir_path });
        return 1;
    };

    var exit_status = try reportStatErrors(entries, prog_name, stderr);
    const print_total = (options.format == .long) or options.size_blocks;
    try formatter.renderEntries(stdout, entries, options, print_total, colors, use_color, used_color, dired_ctx, arena);
    if (options.recursive) {
        const sub_exit = try recurseSubdirectories(entries, dir_path, options, prog_name, visited, need_newline, colors, use_color, used_color, dired_ctx, arena, stdout, stderr);
        if (sub_exit != 0 and exit_status == 0) exit_status = sub_exit;
    }
    return exit_status;
}

fn shouldDerefDirArg(deref: bool, options: *const types.Options, st: c.struct_stat, path_z: [:0]const u8) bool {
    if (deref or options.directory or options.format == .long or options.indicator == .classify) return false;
    if ((st.st_mode & c.S_IFMT) != c.S_IFLNK) return false;
    var target_st: c.struct_stat = undefined;
    return (c.stat(path_z.ptr, &target_st) == 0 and (target_st.st_mode & c.S_IFMT) == c.S_IFDIR);
}

fn classifyOperand(
    path: []const u8,
    options: *const types.Options,
    colors: *const colors_mod.Colors,
    use_color: bool,
    prog_name: []const u8,
    file_operands: *std.ArrayList(types.FileEntry),
    dir_operands: *std.ArrayList(DirOp),
    arena: std.mem.Allocator,
    stderr: anytype,
) !u8 {
    const path_z = try arena.dupeZ(u8, path);
    var st: c.struct_stat = undefined;
    const deref = options.dereference or options.dereference_args or (path.len > 1 and std.mem.endsWith(u8, path, "/"));
    const stat_res = if (deref) c.stat(path_z.ptr, &st) else c.lstat(path_z.ptr, &st);
    if (stat_res != 0) {
        const err_msg = std.mem.span(c.strerror(c.__errno_location().*));
        try stderr.print("{s}: cannot access '{s}': {s}\n", .{ prog_name, path, err_msg });
        return 2;
    }

    var is_dir = (st.st_mode & c.S_IFMT) == c.S_IFDIR;
    var deref_this_arg = deref;
    if (shouldDerefDirArg(deref, options, st, path_z)) {
        is_dir = true;
        deref_this_arg = true;
    }

    if (is_dir and !options.directory) {
        try dir_operands.append(arena, .{ .path = path, .stat = st });
    } else {
        const entry = try collector.createFileEntryFromStat(".", path, st, deref_this_arg, false, colors, use_color, options, arena);
        try file_operands.append(arena, entry);
    }
    return 0;
}

fn renderFileOperands(
    file_operands: []types.FileEntry,
    options: *const types.Options,
    colors: *const colors_mod.Colors,
    use_color: bool,
    used_color: *bool,
    dired_ctx: *dired_mod.DiredContext,
    arena: std.mem.Allocator,
    stdout: anytype,
) !void {
    collector.sortEntries(file_operands, options);
    try formatter.renderEntries(stdout, file_operands, options, false, colors, use_color, used_color, dired_ctx, arena);
}

fn quotingStyleName(style: types.QuotingStyle) []const u8 {
    return switch (style) {
        .literal => "literal",
        .shell, .shell_escape => "shell-escape",
        .shell_always => "shell-always",
        .c_style, .clocale => "c",
        .escape => "escape",
        .locale => "locale",
    };
}

pub fn executeListing(
    paths: []const []const u8,
    options: *const types.Options,
    prog_name: []const u8,
    allocator: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) !u8 {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const arena_alloc = arena.allocator();

    const colors = colors_mod.parseLsColors(arena_alloc);
    const use_color = colors_mod.shouldUseColor(options);
    var used_color = false;
    var dired_ctx = dired_mod.DiredContext.init(arena_alloc, options.dired);

    var exit_status: u8 = 0;
    var file_operands: std.ArrayList(types.FileEntry) = .empty;
    defer file_operands.deinit(arena_alloc);
    var dir_operands: std.ArrayList(DirOp) = .empty;
    defer dir_operands.deinit(arena_alloc);

    for (paths) |path| {
        const op_exit = try classifyOperand(path, options, &colors, use_color, prog_name, &file_operands, &dir_operands, arena_alloc, stderr);
        if (op_exit != 0 and exit_status == 0) exit_status = op_exit;
    }

    var need_newline = false;
    if (file_operands.items.len > 0) {
        try renderFileOperands(file_operands.items, options, &colors, use_color, &used_color, &dired_ctx, arena_alloc, stdout);
        need_newline = true;
    }

    var visited_dirs: std.ArrayList(DevIno) = .empty;
    defer visited_dirs.deinit(arena_alloc);
    const show_header = (paths.len > 1) or options.recursive;
    for (dir_operands.items) |dir_op| {
        const dir_exit = try processDirectory(dir_op.path, dir_op.stat, options, show_header, prog_name, &visited_dirs, &need_newline, &colors, use_color, &used_color, &dired_ctx, arena_alloc, stdout, stderr);
        if (dir_exit != 0 and exit_status == 0) exit_status = dir_exit;
    }

    try dired_ctx.finish(stdout, quotingStyleName(options.quoting_style));
    return exit_status;
}
