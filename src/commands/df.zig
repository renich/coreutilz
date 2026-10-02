const std = @import("std");
const types = @import("df/types.zig");
const mounts = @import("df/mounts.zig");
const format = @import("df/format.zig");
const options_mod = @import("df/options.zig");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "df";
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

    var parsed = try options_mod.parseArgs(args, allocator, stdout, stderr);
    defer parsed.deinit(allocator);

    if (parsed.early_exit) |code| {
        stdout.flush() catch return 1;
        return code;
    }
    const rc = try dispatchDf(&parsed.cfg, parsed.operands.items, allocator, stdout, stderr);
    stdout.flush() catch return 1;
    return rc;
}

fn dispatchDf(
    cfg: *const types.DfConfig,
    operands: []const []const u8,
    allocator: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) !u8 {
    if (cfg.do_sync) c.sync();

    var raw_list = try mounts.readMountTable(allocator);
    defer {
        for (raw_list.items) |item| mounts.freeMountInfo(&item, allocator);
        raw_list.deinit(allocator);
    }

    if (raw_list.items.len == 0) {
        if (operands.len == 0 or cfg.all or cfg.local_only or cfg.include_types.items.len > 0 or cfg.exclude_types.items.len > 0) {
            try stderr.print("df: cannot read table of mounted file systems\n", .{});
            return 1;
        }
        try stderr.print("df: Warning: cannot read table of mounted file systems\n", .{});
    }

    if (operands.len == 0) {
        return processAllMounts(cfg, raw_list.items, allocator, stdout, stderr);
    }
    return processOperandFiles(cfg, operands, raw_list.items, allocator, stdout, stderr);
}

fn processAllMounts(
    cfg: *const types.DfConfig,
    raw_list: []const types.MountInfo,
    allocator: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) !u8 {
    var filtered = try mounts.filterAndDeduplicate(raw_list, cfg, allocator);
    defer {
        for (filtered.items) |item| mounts.freeMountInfo(&item, allocator);
        filtered.deinit(allocator);
    }

    if (filtered.items.len == 0) {
        try stderr.print("df: no file systems processed\n", .{});
        return 1;
    }

    var cols = try format.resolveColumns(cfg, allocator);
    defer cols.deinit(allocator);

    try format.printTable(filtered.items, cfg, cols.items, allocator, stdout);
    return 0;
}

fn processOperandFiles(
    cfg: *const types.DfConfig,
    operands: []const []const u8,
    raw_list: []const types.MountInfo,
    allocator: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) !u8 {
    var matched_list = std.ArrayList(types.MountInfo).empty;
    defer {
        for (matched_list.items) |item| mounts.freeMountInfo(&item, allocator);
        matched_list.deinit(allocator);
    }

    var any_file_error = false;
    for (operands) |operand| {
        const ok = try findAndFilterMount(cfg, raw_list, operand, allocator, &matched_list, stderr);
        if (!ok) any_file_error = true;
    }

    if (matched_list.items.len == 0) {
        if (!any_file_error) try stderr.print("df: no file systems processed\n", .{});
        return 1;
    }

    var cols = try format.resolveColumns(cfg, allocator);
    defer cols.deinit(allocator);

    try format.printTable(matched_list.items, cfg, cols.items, allocator, stdout);
    return if (any_file_error) 1 else 0;
}

fn findAndFilterMount(
    cfg: *const types.DfConfig,
    raw_list: []const types.MountInfo,
    operand: []const u8,
    allocator: std.mem.Allocator,
    matched_list: *std.ArrayList(types.MountInfo),
    stderr: anytype,
) !bool {
    var found = try mounts.findMountForOperand(raw_list, operand, allocator);
    if (found == null) {
        found = try mounts.findMountFallback(operand, allocator);
    }
    if (found) |m| {
        if (!mounts.shouldIncludeMount(&m, cfg)) {
            mounts.freeMountInfo(&m, allocator);
            return true;
        }
        try matched_list.append(allocator, m);
        return true;
    }
    const err_msg = std.mem.span(c.strerror(c.__errno_location().*));
    try stderr.print("df: {s}: {s}\n", .{ operand, err_msg });
    return false;
}
