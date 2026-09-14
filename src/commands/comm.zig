const std = @import("std");
const args_mod = @import("comm/args.zig");

pub const name: []const u8 = "comm";
pub const version: []const u8 = "0.1.0";
pub const Options = args_mod.Options;
pub const OrderCheck = args_mod.OrderCheck;

fn readFileLines(path: []const u8, opt: *const Options, allocator: std.mem.Allocator) ![][]const u8 {
    const is_stdin = std.mem.eql(u8, path, "-");
    const file = if (is_stdin)
        std.Io.File.stdin()
    else
        try std.Io.Dir.cwd().openFile(std.Options.debug_io, path, .{ .mode = .read_only });
    defer if (!is_stdin) file.close(std.Options.debug_io);

    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);

    var r_buf: [16384]u8 = undefined;
    var r = file.readerStreaming(std.Options.debug_io, &r_buf);
    const reader = &r.interface;

    var in_buf: [16384]u8 = undefined;
    while (true) {
        const n = try reader.readSliceShort(&in_buf);
        if (n == 0) break;
        try list.appendSlice(allocator, in_buf[0..n]);
    }

    var lines: std.ArrayList([]const u8) = .empty;
    if (list.items.len == 0) return lines.toOwnedSlice(allocator);
    const delim = if (opt.zero_terminated) @as(u8, 0) else @as(u8, '\n');
    const input = if (std.mem.endsWith(u8, list.items, &[_]u8{delim}))
        list.items[0 .. list.items.len - 1]
    else
        list.items;
    var it = std.mem.splitScalar(u8, input, delim);
    while (it.next()) |line| {
        try lines.append(allocator, try allocator.dupe(u8, line));
    }
    return lines.toOwnedSlice(allocator);
}

fn emitCol1(writer: anytype, line: []const u8, opt: *const Options) !void {
    if (opt.suppress_col1) return;
    const term = if (opt.zero_terminated) @as(u8, 0) else @as(u8, '\n');
    try writer.print("{s}{c}", .{ line, term });
}

fn emitCol2(writer: anytype, line: []const u8, opt: *const Options) !void {
    if (opt.suppress_col2) return;
    const term = if (opt.zero_terminated) @as(u8, 0) else @as(u8, '\n');
    if (!opt.suppress_col1) {
        try writer.print("{s}{s}{c}", .{ opt.delimiter, line, term });
    } else {
        try writer.print("{s}{c}", .{ line, term });
    }
}

fn emitCol3(writer: anytype, line: []const u8, opt: *const Options) !void {
    if (opt.suppress_col3) return;
    const term = if (opt.zero_terminated) @as(u8, 0) else @as(u8, '\n');
    var lead_count: usize = 0;
    if (!opt.suppress_col1) lead_count += 1;
    if (!opt.suppress_col2) lead_count += 1;
    var i: usize = 0;
    while (i < lead_count) : (i += 1) {
        try writer.writeAll(opt.delimiter);
    }
    try writer.print("{s}{c}", .{ line, term });
}

fn emitTotal(total: [3]u64, opt: *const Options, writer: anytype) !void {
    const term = if (opt.zero_terminated) @as(u8, 0) else @as(u8, '\n');
    try writer.print("{d}{s}{d}{s}{d}{s}total{c}", .{
        total[0], opt.delimiter,
        total[1], opt.delimiter,
        total[2], opt.delimiter,
        term,
    });
}

fn checkOrder(
    prev: ?[]const u8,
    curr: []const u8,
    whatfile: u8,
    opt: *const Options,
    seen_unpairable: bool,
    warned: *[2]bool,
    had_disorder: *bool,
    stderr: anytype,
) !bool {
    if (opt.order_check == .disabled) return false;
    if (prev == null) return false;
    if (std.mem.order(u8, prev.?, curr) != .gt) return false;

    if (opt.order_check == .enabled) {
        try stderr.print("comm: file {d} is not in sorted order\n", .{whatfile});
        return true;
    }
    if (seen_unpairable and !warned[whatfile - 1]) {
        try stderr.print("comm: file {d} is not in sorted order\n", .{whatfile});
        warned[whatfile - 1] = true;
        had_disorder.* = true;
    }
    return false;
}

fn compareBothFiles(
    lines1: []const []const u8,
    lines2: []const []const u8,
    opt: *const Options,
    writer: anytype,
    stderr: anytype,
) !u8 {
    var total: [3]u64 = .{ 0, 0, 0 };
    var warned: [2]bool = .{ false, false };
    var had_disorder = false;
    var seen_unpairable = false;
    var idx1: usize = 0;
    var idx2: usize = 0;
    var prev1: ?[]const u8 = null;
    var prev2: ?[]const u8 = null;

    while (idx1 < lines1.len or idx2 < lines2.len) {
        if (idx1 < lines1.len and idx2 < lines2.len) {
            const ord = std.mem.order(u8, lines1[idx1], lines2[idx2]);
            switch (ord) {
                .lt => {
                    seen_unpairable = true;
                    if (try checkOrder(prev1, lines1[idx1], 1, opt, seen_unpairable, &warned, &had_disorder, stderr)) return 1;
                    prev1 = lines1[idx1];
                    total[0] += 1;
                    try emitCol1(writer, lines1[idx1], opt);
                    idx1 += 1;
                },
                .gt => {
                    seen_unpairable = true;
                    if (try checkOrder(prev2, lines2[idx2], 2, opt, seen_unpairable, &warned, &had_disorder, stderr)) return 1;
                    prev2 = lines2[idx2];
                    total[1] += 1;
                    try emitCol2(writer, lines2[idx2], opt);
                    idx2 += 1;
                },
                .eq => {
                    if (try checkOrder(prev1, lines1[idx1], 1, opt, seen_unpairable, &warned, &had_disorder, stderr)) return 1;
                    if (try checkOrder(prev2, lines2[idx2], 2, opt, seen_unpairable, &warned, &had_disorder, stderr)) return 1;
                    prev1 = lines1[idx1];
                    prev2 = lines2[idx2];
                    total[2] += 1;
                    try emitCol3(writer, lines1[idx1], opt);
                    idx1 += 1;
                    idx2 += 1;
                },
            }
        } else if (idx1 < lines1.len) {
            seen_unpairable = true;
            if (try checkOrder(prev1, lines1[idx1], 1, opt, seen_unpairable, &warned, &had_disorder, stderr)) return 1;
            prev1 = lines1[idx1];
            total[0] += 1;
            try emitCol1(writer, lines1[idx1], opt);
            idx1 += 1;
        } else {
            seen_unpairable = true;
            if (try checkOrder(prev2, lines2[idx2], 2, opt, seen_unpairable, &warned, &had_disorder, stderr)) return 1;
            prev2 = lines2[idx2];
            total[1] += 1;
            try emitCol2(writer, lines2[idx2], opt);
            idx2 += 1;
        }
    }

    if (opt.total) try emitTotal(total, opt, writer);
    if (had_disorder) {
        try stderr.writeAll("comm: input is not in sorted order\n");
        return 1;
    }
    return 0;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buffer: [16384]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var opt = Options{};
    if (try args_mod.parseArgs(args, &opt, stdout, stderr)) |code| return code;

    const lines1 = readFileLines(opt.file1.?, &opt, allocator) catch |err| {
        try stderr.print("comm: {s}: {s}\n", .{ opt.file1.?, @errorName(err) });
        return 1;
    };
    defer {
        for (lines1) |l| allocator.free(l);
        allocator.free(lines1);
    }

    const lines2 = readFileLines(opt.file2.?, &opt, allocator) catch |err| {
        try stderr.print("comm: {s}: {s}\n", .{ opt.file2.?, @errorName(err) });
        return 1;
    };
    defer {
        for (lines2) |l| allocator.free(l);
        allocator.free(lines2);
    }

    const rc = try compareBothFiles(lines1, lines2, &opt, stdout, stderr);
    stdout.flush() catch return 1;
    return rc;
}
