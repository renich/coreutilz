const std = @import("std");
const types = @import("du/types.zig");
const options = @import("du/options.zig");
const traverse = @import("du/traverse.zig");
const operand = @import("du/operand.zig");
const format = @import("du/format.zig");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "du";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buffer: [8192]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    return runWithIo(args, allocator, stdout, stderr);
}

pub fn runWithIo(args: []const []const u8, allocator: std.mem.Allocator, stdout: anytype, stderr: anytype) !u8 {
    var cfg = types.DuConfig{ .excludes = std.ArrayList(types.ExcludeRule).empty };
    defer cfg.deinit(allocator);

    var operands = std.ArrayList([]const u8).empty;
    defer operands.deinit(allocator);

    if (try options.parseOptions(allocator, args, &cfg, &operands, stdout, stderr)) |code| {
        stdout.flush() catch return 1;
        return code;
    }

    var files0_alloc = std.ArrayList([]const u8).empty;
    defer {
        for (files0_alloc.items) |op| allocator.free(op);
        files0_alloc.deinit(allocator);
    }

    var had_files0_error = false;
    if (cfg.files0_from) |f0_path| {
        if (operands.items.len > 0) {
            try stderr.print("du: extra operand '{s}'\nfile operands cannot be combined with --files0-from\nTry 'du --help' for more information.\n", .{operands.items[0]});
            return 1;
        }
        const ok = try readFiles0From(allocator, f0_path, &files0_alloc, &had_files0_error, stderr);
        if (!ok) return 1;
    } else if (operands.items.len == 0) {
        try operands.append(allocator, ".");
    }

    const op_list = if (cfg.files0_from != null) files0_alloc.items else operands.items;
    const had_err = try processOperandsList(&cfg, op_list, allocator, stdout, stderr);
    stdout.flush() catch return 1;
    return if (had_err or had_files0_error) 1 else 0;
}

fn processOperandsList(
    cfg: *const types.DuConfig,
    op_list: []const []const u8,
    allocator: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) !bool {
    var seen_hardlinks = std.AutoHashMap(types.DevIno, void).init(allocator);
    defer seen_hardlinks.deinit();

    const hash_all = (op_list.len > 1 or cfg.dereference_all or cfg.files0_from != null);
    var state = traverse.TraverseState.init(cfg, &seen_hardlinks, hash_all, allocator);
    defer state.deinit();

    for (op_list) |op| {
        try operand.processOperand(&state, op, stdout, stderr);
        if (state.stop_early) break;
    }

    if (cfg.total) {
        try format.printEntry(stdout, "total", state.tot_stats, cfg);
    }
    return state.had_error;
}

fn openFile0(allocator: std.mem.Allocator, f0_path: []const u8, is_stdin: bool, stderr: anytype) ?c_int {
    if (is_stdin) return 0;
    const path_z = allocator.dupeZ(u8, f0_path) catch return null;
    defer allocator.free(path_z);
    const fd = c.open(path_z.ptr, c.O_RDONLY);
    if (fd < 0) {
        const err_str = std.mem.span(c.strerror(c.__errno_location().*));
        stderr.print("du: cannot open '{s}' for reading: {s}\n", .{ f0_path, err_str }) catch {};
        return null;
    }
    return fd;
}

fn processFile0Chunk(
    allocator: std.mem.Allocator,
    chunk: []const u8,
    f0_path: []const u8,
    is_stdin: bool,
    item_buf: *std.ArrayList(u8),
    count: *usize,
    operands: *std.ArrayList([]const u8),
    had_error: *bool,
    stderr: anytype,
) !void {
    for (chunk) |b| {
        if (b == 0) {
            count.* += 1;
            try handleFile0Item(allocator, f0_path, is_stdin, item_buf.items, count.*, operands, had_error, stderr);
            item_buf.clearRetainingCapacity();
        } else {
            try item_buf.append(allocator, b);
        }
    }
}

fn readFiles0From(
    allocator: std.mem.Allocator,
    f0_path: []const u8,
    operands: *std.ArrayList([]const u8),
    had_error: *bool,
    stderr: anytype,
) !bool {
    const is_stdin = std.mem.eql(u8, f0_path, "-");
    const fd = openFile0(allocator, f0_path, is_stdin, stderr) orelse return false;
    defer {
        if (!is_stdin) _ = c.close(fd);
    }

    var item_buf = std.ArrayList(u8).empty;
    defer item_buf.deinit(allocator);

    var count: usize = 0;
    var buf: [16384]u8 = undefined;
    while (true) {
        const nr = c.read(fd, &buf, buf.len);
        if (nr < 0) {
            const err_str = std.mem.span(c.strerror(c.__errno_location().*));
            try stderr.print("du: {s}: read error: {s}\n", .{ f0_path, err_str });
            return false;
        }
        if (nr == 0) break;
        try processFile0Chunk(allocator, buf[0..@intCast(nr)], f0_path, is_stdin, &item_buf, &count, operands, had_error, stderr);
    }

    if (item_buf.items.len > 0) {
        count += 1;
        try handleFile0Item(allocator, f0_path, is_stdin, item_buf.items, count, operands, had_error, stderr);
    }
    return true;
}

fn handleFile0Item(
    allocator: std.mem.Allocator,
    f0_path: []const u8,
    is_stdin: bool,
    item: []const u8,
    count: usize,
    operands: *std.ArrayList([]const u8),
    had_error: *bool,
    stderr: anytype,
) !void {
    if (item.len == 0) {
        try stderr.print("du: {s}:{d}: invalid zero-length file name\n", .{ f0_path, count });
        had_error.* = true;
        return;
    }
    if (is_stdin and std.mem.eql(u8, item, "-")) {
        try stderr.print("du: when reading file names from standard input, no file name of '-' allowed\n", .{});
        had_error.* = true;
        return;
    }
    try operands.append(allocator, try allocator.dupe(u8, item));
}
