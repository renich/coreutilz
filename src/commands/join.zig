const std = @import("std");
const c = @import("../compat/c.zig").c;
const types = @import("join/types.zig");
const eval = @import("join/eval.zig");

pub const name: []const u8 = "join";
pub const version: []const u8 = "0.1.0";

const JoinOptions = types.JoinOptions;
const OutField = types.OutField;

fn parseFieldNum(s: []const u8, stderr: anytype) ?usize {
    const val = std.fmt.parseInt(usize, s, 10) catch |err| {
        if (err == error.Overflow) return std.math.maxInt(usize);
        stderr.print("join: invalid field number: '{s}'\n", .{s}) catch {};
        return null;
    };
    if (val == 0) {
        stderr.print("join: invalid field number: '{s}'\n", .{s}) catch {};
        return null;
    }
    return val;
}

fn addOutSpec(s: []const u8, outlist: *std.ArrayListUnmanaged(OutField), alloc: std.mem.Allocator, stderr: anytype) bool {
    if (std.mem.eql(u8, s, "0")) {
        outlist.append(alloc, .{ .file = 0, .field = 0 }) catch return false;
        return true;
    }
    if (s.len < 3 or s[1] != '.') {
        stderr.print("join: invalid field specifier: '{s}'\n", .{s}) catch {};
        return false;
    }
    const file_id: u8 = if (s[0] == '1') 1 else if (s[0] == '2') 2 else {
        stderr.print("join: invalid file number in field spec: '{s}'\n", .{s}) catch {};
        return false;
    };
    const fnum = parseFieldNum(s[2..], stderr) orelse return false;
    outlist.append(alloc, .{ .file = file_id, .field = fnum }) catch return false;
    return true;
}

fn parseOutFormat(fmt: []const u8, opts: *JoinOptions, outlist: *std.ArrayListUnmanaged(OutField), alloc: std.mem.Allocator, stderr: anytype) bool {
    if (std.mem.eql(u8, fmt, "auto")) {
        opts.autoformat = true;
        return true;
    }
    var it = std.mem.tokenizeAny(u8, fmt, ", \t");
    while (it.next()) |item| {
        if (!addOutSpec(item, outlist, alloc, stderr)) return false;
    }
    return true;
}

fn getArgVal(arg: []const u8, prefix: []const u8, i: *usize, args: [][]const u8) ?[]const u8 {
    if (arg.len > prefix.len) return arg[prefix.len..];
    if (i.* + 1 < args.len) {
        i.* += 1;
        return args[i.*];
    }
    return null;
}

fn parseTab(arg: []const u8, i: *usize, args: [][]const u8, opts: *JoinOptions) void {
    const val = getArgVal(arg, "-t", i, args) orelse "";
    if (val.len == 0) {
        opts.separator = "";
    } else if (std.mem.eql(u8, val, "\\0")) {
        opts.separator = "\x00";
        opts.output_sep = "\x00";
    } else {
        opts.separator = val;
        opts.output_sep = val;
    }
}

fn parseOption(
    arg: []const u8,
    i: *usize,
    args: [][]const u8,
    opts: *JoinOptions,
    outlist: *std.ArrayListUnmanaged(OutField),
    alloc: std.mem.Allocator,
    stderr: anytype,
) !?bool {
    if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--ignore-case")) {
        opts.ignore_case = true;
    } else if (std.mem.eql(u8, arg, "-z") or std.mem.eql(u8, arg, "--zero-terminated")) {
        opts.zero_terminated = true;
    } else if (std.mem.eql(u8, arg, "--header")) {
        opts.header = true;
    } else if (std.mem.eql(u8, arg, "--check-order")) {
        opts.check_order = .enabled;
    } else if (std.mem.eql(u8, arg, "--nocheck-order")) {
        opts.check_order = .disabled;
    } else if (std.mem.startsWith(u8, arg, "-1")) {
        const val = getArgVal(arg, "-1", i, args) orelse return false;
        opts.field1 = parseFieldNum(val, stderr) orelse return false;
    } else if (std.mem.startsWith(u8, arg, "-2")) {
        const val = getArgVal(arg, "-2", i, args) orelse return false;
        opts.field2 = parseFieldNum(val, stderr) orelse return false;
    } else if (std.mem.startsWith(u8, arg, "-j")) {
        const val = getArgVal(arg, "-j", i, args) orelse return false;
        const num = parseFieldNum(val, stderr) orelse return false;
        opts.field1 = num;
        opts.field2 = num;
    } else if (std.mem.startsWith(u8, arg, "-t")) {
        parseTab(arg, i, args, opts);
    } else if (std.mem.startsWith(u8, arg, "-e")) {
        opts.empty_filler = getArgVal(arg, "-e", i, args) orelse "";
    } else if (std.mem.startsWith(u8, arg, "-o")) {
        const val = getArgVal(arg, "-o", i, args) orelse return false;
        if (!parseOutFormat(val, opts, outlist, alloc, stderr)) return false;
    } else if (std.mem.startsWith(u8, arg, "-a") or std.mem.startsWith(u8, arg, "-v")) {
        const is_v = std.mem.startsWith(u8, arg, "-v");
        if (is_v) opts.suppress_paired = true;
        const val = getArgVal(arg, if (is_v) "-v" else "-a", i, args) orelse "1";
        if (std.mem.eql(u8, val, "1")) opts.print_unpairable1 = true else if (std.mem.eql(u8, val, "2")) opts.print_unpairable2 = true;
    } else {
        try stderr.print("join: unrecognized option '{s}'\nTry 'join --help' for more information.\n", .{arg});
        return false;
    }
    return true;
}

fn readFileLines(path: []const u8, alloc: std.mem.Allocator, delim: u8, stderr: anytype) ![][]const u8 {
    var fd: c_int = c.STDIN_FILENO;
    var should_close = false;
    if (!std.mem.eql(u8, path, "-")) {
        const path_z = try alloc.dupeZ(u8, path);
        defer alloc.free(path_z);
        fd = c.open(path_z.ptr, c.O_RDONLY);
        if (fd < 0) {
            stderr.print("join: {s}: No such file or directory\n", .{path}) catch {};
            return error.FileNotFound;
        }
        should_close = true;
    }
    defer if (should_close) {
        _ = c.close(fd);
    };

    var list_bytes: std.ArrayListUnmanaged(u8) = .empty;
    defer list_bytes.deinit(alloc);
    var buf: [16384]u8 = undefined;
    while (true) {
        const n = c.read(fd, &buf, buf.len);
        if (n < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            return error.ReadError;
        }
        if (n == 0) break;
        try list_bytes.appendSlice(alloc, buf[0..@intCast(n)]);
    }

    const data = try list_bytes.toOwnedSlice(alloc);
    var list: std.ArrayListUnmanaged([]const u8) = .empty;
    var it = std.mem.splitScalar(u8, data, delim);
    while (it.next()) |line| {
        if (line.len > 0 or it.peek() != null) try list.append(alloc, line);
    }
    return list.toOwnedSlice(alloc);
}

fn parseArgs(
    args: [][]const u8,
    opts: *JoinOptions,
    outlist: *std.ArrayListUnmanaged(OutField),
    files: *std.ArrayListUnmanaged([]const u8),
    alloc: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) !?u8 {
    var i: usize = 1;
    var past = false;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (past or !std.mem.startsWith(u8, arg, "-") or std.mem.eql(u8, arg, "-")) {
            try files.append(alloc, arg);
        } else if (std.mem.eql(u8, arg, "--")) {
            past = true;
        } else if (std.mem.eql(u8, arg, "--help")) {
            try stdout.print("Usage: join [OPTION]... FILE1 FILE2\nFor each pair of input lines with identical join fields, write a line to\nstandard output. The default join field is the first, delimited by blanks.\n", .{});
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try stdout.print("join (coreutilz) {s}\n", .{version});
            return 0;
        } else if (try parseOption(arg, &i, args, opts, outlist, alloc, stderr)) |valid| {
            if (!valid) return 1;
        }
    }
    return null;
}

fn validateFiles(files: []const []const u8, stderr: anytype) bool {
    if (files.len < 2) {
        stderr.print("join: missing operand\nTry 'join --help' for more information.\n", .{}) catch {};
        return false;
    }
    if (std.mem.eql(u8, files[0], "-") and std.mem.eql(u8, files[1], "-")) {
        stderr.print("join: both files cannot be standard input\n", .{}) catch {};
        return false;
    }
    return true;
}

fn runJoin(files: []const []const u8, opts: *JoinOptions, alloc: std.mem.Allocator, stdout: anytype, stderr: anytype) !u8 {
    opts.file1_name = files[0];
    opts.file2_name = files[1];
    const delim: u8 = if (opts.zero_terminated) 0 else '\n';
    const lines1 = readFileLines(files[0], alloc, delim, stderr) catch return 1;
    defer alloc.free(lines1);
    const lines2 = readFileLines(files[1], alloc, delim, stderr) catch return 1;
    defer alloc.free(lines2);
    return eval.executeJoin(lines1, lines2, opts, alloc, stdout, stderr);
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &out_w.interface;
    const stderr = &err_w.interface;

    var opts = JoinOptions{};
    var outlist: std.ArrayListUnmanaged(OutField) = .empty;
    defer outlist.deinit(allocator);
    var files: std.ArrayListUnmanaged([]const u8) = .empty;
    defer files.deinit(allocator);

    if (try parseArgs(args, &opts, &outlist, &files, allocator, stdout, stderr)) |rc| {
        stdout.flush() catch return 1;
        stderr.flush() catch {};
        return rc;
    }
    if (!validateFiles(files.items, stderr)) {
        stderr.flush() catch {};
        return 1;
    }

    if (outlist.items.len > 0) opts.outlist = outlist.items;
    const rc = try runJoin(files.items, &opts, allocator, stdout, stderr);
    stdout.flush() catch return 1;
    stderr.flush() catch {};
    return rc;
}
