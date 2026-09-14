const std = @import("std");
const args_mod = @import("uniq/args.zig");

pub const name: []const u8 = "uniq";
pub const version: []const u8 = "0.1.0";
pub const Options = args_mod.Options;
pub const GroupingMethod = args_mod.GroupingMethod;
pub const AllRepeatedMethod = args_mod.AllRepeatedMethod;

fn extractKey(line: []const u8, opt: *const Options) []const u8 {
    var slice = line;
    var f: usize = 0;
    while (f < opt.skip_fields and slice.len > 0) : (f += 1) {
        var idx: usize = 0;
        while (idx < slice.len and (slice[idx] == ' ' or slice[idx] == '\t')) : (idx += 1) {}
        while (idx < slice.len and slice[idx] != ' ' and slice[idx] != '\t') : (idx += 1) {}
        slice = slice[idx..];
    }
    if (opt.skip_chars > 0) {
        const skip = @min(opt.skip_chars, slice.len);
        slice = slice[skip..];
    }
    if (opt.check_chars) |w| {
        const take = @min(w, slice.len);
        slice = slice[0..take];
    }
    return slice;
}

fn keysEqual(k1: []const u8, k2: []const u8, ignore_case: bool) bool {
    if (k1.len != k2.len) return false;
    if (ignore_case) return std.ascii.eqlIgnoreCase(k1, k2);
    return std.mem.eql(u8, k1, k2);
}

fn emitGroup(writer: anytype, prev_line: []const u8, count: u64, opt: *const Options) !void {
    if (count == 0 or (opt.repeated and opt.unique_only)) return;
    const term = if (opt.zero_terminated) @as(u8, 0) else @as(u8, '\n');
    if (opt.unique_only) {
        if (count == 1) try writer.print("{s}{c}", .{ prev_line, term });
        return;
    }
    if (opt.repeated) {
        if (count > 1) try writer.print("{s}{c}", .{ prev_line, term });
        return;
    }
    if (opt.count) {
        try writer.print("{d:7} {s}{c}", .{ count, prev_line, term });
        return;
    }
    try writer.print("{s}{c}", .{ prev_line, term });
}

fn readStream(allocator: std.mem.Allocator, input_file: ?[]const u8) ![]const u8 {
    const is_stdin = (input_file == null) or std.mem.eql(u8, input_file.?, "-");
    const file = if (is_stdin)
        std.Io.File.stdin()
    else
        try std.Io.Dir.cwd().openFile(std.Options.debug_io, input_file.?, .{ .mode = .read_only });
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
    return list.toOwnedSlice(allocator);
}

fn processGrouping(content: []const u8, opt: *const Options, writer: anytype) !void {
    if (content.len == 0) return;
    const delim = if (opt.zero_terminated) @as(u8, 0) else @as(u8, '\n');
    const input = if (std.mem.endsWith(u8, content, &[_]u8{delim}))
        content[0 .. content.len - 1]
    else
        content;
    var it = std.mem.splitScalar(u8, input, delim);
    var prev_key: ?[]const u8 = null;
    var first_group_printed = false;

    while (it.next()) |line| {
        const cur_key = extractKey(line, opt);
        const new_group = if (prev_key) |pk| !keysEqual(pk, cur_key, opt.ignore_case) else true;
        if (new_group) {
            const should_delimit = switch (opt.grouping) {
                .prepend, .both => true,
                .append, .separate => first_group_printed,
                .none => false,
            };
            if (should_delimit) try writer.print("{c}", .{delim});
        }
        try writer.print("{s}{c}", .{ line, delim });
        prev_key = cur_key;
        first_group_printed = true;
    }
    if ((opt.grouping == .both or opt.grouping == .append) and first_group_printed) {
        try writer.print("{c}", .{delim});
    }
}

fn processAllRepeated(content: []const u8, opt: *const Options, writer: anytype) !void {
    if (content.len == 0) return;
    const delim = if (opt.zero_terminated) @as(u8, 0) else @as(u8, '\n');
    const input = if (std.mem.endsWith(u8, content, &[_]u8{delim}))
        content[0 .. content.len - 1]
    else
        content;
    var it = std.mem.splitScalar(u8, input, delim);
    var cand_line: ?[]const u8 = null;
    var cand_key: ?[]const u8 = null;
    var in_dup = false;
    var first_dup = false;

    while (it.next()) |line| {
        const cur_key = extractKey(line, opt);
        if (cand_key) |ck| {
            if (keysEqual(ck, cur_key, opt.ignore_case)) {
                if (!in_dup) {
                    const should_delimit = switch (opt.all_repeated_method) {
                        .prepend => true,
                        .separate => first_dup,
                        .none => false,
                    };
                    if (should_delimit) try writer.print("{c}", .{delim});
                    first_dup = true;
                    try writer.print("{s}{c}", .{ cand_line.?, delim });
                    in_dup = true;
                }
                try writer.print("{s}{c}", .{ line, delim });
                continue;
            }
        }
        cand_line = line;
        cand_key = cur_key;
        in_dup = false;
    }
}

fn processUniq(content: []const u8, opt: *const Options, writer: anytype) !void {
    if (content.len == 0 or (opt.repeated and opt.unique_only)) return;
    if (opt.grouping != .none) return try processGrouping(content, opt, writer);
    if (opt.all_repeated) return try processAllRepeated(content, opt, writer);

    const delim = if (opt.zero_terminated) @as(u8, 0) else @as(u8, '\n');
    const input = if (std.mem.endsWith(u8, content, &[_]u8{delim}))
        content[0 .. content.len - 1]
    else
        content;
    var it = std.mem.splitScalar(u8, input, delim);
    var prev_line: ?[]const u8 = null;
    var prev_key: ?[]const u8 = null;
    var count: u64 = 0;

    while (it.next()) |line| {
        const cur_key = extractKey(line, opt);
        if (prev_key) |pk| {
            if (keysEqual(pk, cur_key, opt.ignore_case)) {
                count += 1;
                continue;
            }
            try emitGroup(writer, prev_line.?, count, opt);
        }
        prev_line = line;
        prev_key = cur_key;
        count = 1;
    }
    if (prev_line) |pl| try emitGroup(writer, pl, count, opt);
}

fn executeOutputFile(content: []const u8, opt: *const Options, out_path: []const u8, stderr: anytype) !u8 {
    const out_file = std.Io.Dir.cwd().createFile(std.Options.debug_io, out_path, .{}) catch |err| {
        try stderr.print("uniq: {s}: {s}\n", .{ out_path, @errorName(err) });
        return 1;
    };
    defer out_file.close(std.Options.debug_io);
    var out_buf: [16384]u8 = undefined;
    var out_w: std.Io.File.Writer = .initStreaming(out_file, std.Options.debug_io, &out_buf);
    const w = &out_w.interface;
    try processUniq(content, opt, w);
    try w.flush();
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

    const content = readStream(allocator, opt.input_file) catch |err| {
        try stderr.print("uniq: {s}: {s}\n", .{ opt.input_file orelse "-", @errorName(err) });
        return 1;
    };
    defer allocator.free(content);

    if (opt.output_file) |out_path| {
        return try executeOutputFile(content, &opt, out_path, stderr);
    }
    try processUniq(content, &opt, stdout);
    stdout.flush() catch return 1;
    return 0;
}
