const std = @import("std");
const args_mod = @import("shuf/args.zig");

pub const name: []const u8 = "shuf";
pub const version: []const u8 = "0.1.0";
pub const Options = args_mod.Options;

fn randpermSparse(allocator: std.mem.Allocator, h: usize, n: u64, rand: std.Random) ![]u64 {
    var map = std.AutoHashMap(u64, u64).init(allocator);
    defer map.deinit();

    var v = try allocator.alloc(u64, h);
    var i: usize = 0;
    while (i < h) : (i += 1) {
        const remaining = n - @as(u64, i);
        const offset = rand.uintLessThan(u64, remaining);
        const j = @as(u64, i) + offset;

        const val_i = map.get(@as(u64, i)) orelse @as(u64, i);
        const val_j = map.get(j) orelse j;

        try map.put(j, val_i);
        v[i] = val_j;
    }
    return v;
}

fn emitRangeOutput(range: [2]u64, opt: *const Options, rand: std.Random, allocator: std.mem.Allocator, writer: anytype) !void {
    const lo = range[0];
    const hi = range[1];
    const range_len = hi - lo + 1;
    const delim = if (opt.zero_terminated) @as(u8, 0) else @as(u8, '\n');

    if (opt.repeat) {
        var count: usize = 0;
        while (opt.head_count == null or count < opt.head_count.?) : (count += 1) {
            const val = lo + rand.uintLessThan(u64, range_len);
            try writer.print("{d}{c}", .{ val, delim });
        }
        return;
    }

    const k = if (opt.head_count) |h| @min(@as(u64, h), range_len) else range_len;
    if (k == 0) return;

    if (range_len <= 100_000 and range_len <= k * 4) {
        var nums = try allocator.alloc(u64, @as(usize, @intCast(range_len)));
        defer allocator.free(nums);
        for (nums, 0..) |*item, idx| item.* = lo + @as(u64, idx);
        rand.shuffle(u64, nums);
        const take = @min(@as(usize, @intCast(k)), nums.len);
        for (nums[0..take]) |val| try writer.print("{d}{c}", .{ val, delim });
    } else {
        const perm = try randpermSparse(allocator, @as(usize, @intCast(k)), range_len, rand);
        defer allocator.free(perm);
        for (perm) |idx| try writer.print("{d}{c}", .{ lo + idx, delim });
    }
}

fn emitRepeatedLines(lines: []const []const u8, head_count: ?usize, delim: u8, rand: std.Random, writer: anytype) !void {
    var count: usize = 0;
    while (head_count == null or count < head_count.?) : (count += 1) {
        const idx = rand.uintLessThan(usize, lines.len);
        try writer.print("{s}{c}", .{ lines[idx], delim });
    }
}

fn emitShuffledLines(lines: [][]const u8, opt: *const Options, rand: std.Random, writer: anytype, stderr: anytype) !u8 {
    const delim = if (opt.zero_terminated) @as(u8, 0) else @as(u8, '\n');
    if (lines.len == 0) {
        if (opt.repeat) {
            try stderr.writeAll("shuf: no lines to repeat\n");
            return 1;
        }
        return 0;
    }

    if (opt.repeat) {
        try emitRepeatedLines(lines, opt.head_count, delim, rand, writer);
        return 0;
    }

    rand.shuffle([]const u8, lines);
    const limit = if (opt.head_count) |h| @min(h, lines.len) else lines.len;
    for (lines[0..limit]) |line| try writer.print("{s}{c}", .{ line, delim });
    return 0;
}

fn readLinesFromFile(path: ?[]const u8, zero_terminated: bool, allocator: std.mem.Allocator) ![][]const u8 {
    const is_stdin = (path == null) or std.mem.eql(u8, path.?, "-");
    const file = if (is_stdin)
        std.Io.File.stdin()
    else
        try std.Io.Dir.cwd().openFile(std.Options.debug_io, path.?, .{ .mode = .read_only });
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
    const delim = if (zero_terminated) @as(u8, 0) else @as(u8, '\n');
    const input = if (std.mem.endsWith(u8, list.items, &[_]u8{delim}))
        list.items[0 .. list.items.len - 1]
    else
        list.items;
    var it = std.mem.splitScalar(u8, input, delim);
    while (it.next()) |line| try lines.append(allocator, try allocator.dupe(u8, line));
    return lines.toOwnedSlice(allocator);
}

fn executeShuffle(
    opt: *const Options,
    operands: []const []const u8,
    rand: std.Random,
    allocator: std.mem.Allocator,
    writer: anytype,
    stderr: anytype,
) !u8 {
    if (opt.head_count) |h| {
        if (h == 0) return 0;
    }
    if (opt.input_range) |range| {
        try emitRangeOutput(range, opt, rand, allocator, writer);
        return 0;
    }
    if (opt.echo) {
        const lines = try allocator.alloc([]const u8, operands.len);
        defer allocator.free(lines);
        @memcpy(lines, operands);
        return try emitShuffledLines(lines, opt, rand, writer, stderr);
    }
    const file_arg = if (operands.len > 0) operands[0] else null;
    const lines = readLinesFromFile(file_arg, opt.zero_terminated, allocator) catch |err| {
        try stderr.print("shuf: {s}: {s}\n", .{ file_arg orelse "-", @errorName(err) });
        return 1;
    };
    defer {
        for (lines) |l| allocator.free(l);
        allocator.free(lines);
    }
    return try emitShuffledLines(lines, opt, rand, writer, stderr);
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
    var operands: std.ArrayList([]const u8) = .empty;
    defer operands.deinit(allocator);

    if (try args_mod.parseArgs(args, &opt, &operands, allocator, stdout, stderr)) |code| return code;

    var io_source: std.Random.IoSource = .{ .io = std.Options.debug_io };
    const rand = io_source.interface();

    if (opt.output_file) |out_path| {
        const out_file = std.Io.Dir.cwd().createFile(std.Options.debug_io, out_path, .{}) catch |err| {
            try stderr.print("shuf: {s}: {s}\n", .{ out_path, @errorName(err) });
            return 1;
        };
        defer out_file.close(std.Options.debug_io);
        var out_buf: [16384]u8 = undefined;
        var out_w: std.Io.File.Writer = .initStreaming(out_file, std.Options.debug_io, &out_buf);
        const w = &out_w.interface;
        const res = try executeShuffle(&opt, operands.items, rand, allocator, w, stderr);
        try w.flush();
        return res;
    }
    const res = try executeShuffle(&opt, operands.items, rand, allocator, stdout, stderr);
    stdout.flush() catch return 1;
    return res;
}
