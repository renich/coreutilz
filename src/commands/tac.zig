const std = @import("std");
const errors = @import("../utils/errors.zig");
const c = @cImport({
    @cInclude("regex.h");
});

pub const name: []const u8 = "tac";
pub const version: []const u8 = "0.1.0";

pub const Options = struct {
    before: bool = false,
    regex: bool = false,
    separator: []const u8 = "\n",
};

const Match = struct {
    start: usize,
    end: usize,
};

fn printUsage(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: tac [OPTION]... [FILE]...
        \\Write each FILE to standard output, last line first.
        \\
        \\With no FILE, or when FILE is -, read standard input.
        \\
        \\  -b, --before             attach the separator before instead of after
        \\  -r, --regex              interpret the separator as a regular expression
        \\  -s, --separator=STRING   use STRING as the separator instead of newline
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
    );
}

fn parseSeparator(arg: []const u8, args: [][]const u8, i: *usize, opt: *Options) void {
    if (std.mem.startsWith(u8, arg, "--separator=")) {
        const sep = arg["--separator=".len..];
        opt.separator = if (sep.len == 0) "\x00" else sep;
    } else if (arg.len > 2) {
        const sep = arg[2..];
        opt.separator = if (sep.len == 0) "\x00" else sep;
    } else if (i.* + 1 < args.len) {
        i.* += 1;
        const sep = args[i.*];
        opt.separator = if (sep.len == 0) "\x00" else sep;
    }
}

fn parseArgs(
    args: [][]const u8,
    opt: *Options,
    files: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) !?u8 {
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            try printUsage(stdout);
            stdout.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try errors.printVersion(stdout, name, version);
            stdout.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "-b") or std.mem.eql(u8, arg, "--before")) {
            opt.before = true;
        } else if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "--regex")) {
            opt.regex = true;
        } else if (std.mem.startsWith(u8, arg, "--separator=") or std.mem.startsWith(u8, arg, "-s")) {
            parseSeparator(arg, args, &i, opt);
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1 and !std.mem.eql(u8, arg, "-")) {
            try stderr.print("tac: unrecognized option '{s}'\n", .{arg});
            return 1;
        } else {
            try files.append(allocator, arg);
        }
    }
    return null;
}

fn findRegexMatches(allocator: std.mem.Allocator, content: []const u8, pattern: []const u8) ![]Match {
    const pattern_z = try allocator.dupeZ(u8, pattern);
    defer allocator.free(pattern_z);

    var buf: [128]u8 align(8) = undefined;
    const preg: *c.regex_t = @ptrCast(&buf);
    if (c.regcomp(preg, pattern_z.ptr, c.REG_EXTENDED | c.REG_NEWLINE) != 0) return error.RegexCompileFailed;
    defer c.regfree(preg);

    var matches: std.ArrayList(Match) = .empty;
    defer matches.deinit(allocator);

    const content_z = try allocator.dupeZ(u8, content);
    defer allocator.free(content_z);

    var offset: usize = 0;
    while (offset <= content.len) {
        var pmatch: [1]c.regmatch_t = undefined;
        const eflags: c_int = if (offset > 0 and content[offset - 1] != '\n') c.REG_NOTBOL else 0;
        if (c.regexec(preg, content_z[offset..].ptr, 1, &pmatch, eflags) != 0) break;
        const s = offset + @as(usize, @intCast(pmatch[0].rm_so));
        const e = offset + @as(usize, @intCast(pmatch[0].rm_eo));
        try matches.append(allocator, .{ .start = s, .end = e });
        offset = if (e == s) s + 1 else e;
    }
    return matches.toOwnedSlice(allocator);
}

fn reverseRegexBefore(content: []const u8, matches: []const Match, writer: anytype) !void {
    if (matches.len == 0) {
        try writer.writeAll(content);
        return;
    }
    var end = content.len;
    var i = matches.len;
    while (i > 0) : (i -= 1) {
        const m = matches[i - 1];
        try writer.writeAll(content[m.start..end]);
        end = m.start;
    }
    if (end > 0) try writer.writeAll(content[0..end]);
}

fn reverseRegexAfter(content: []const u8, matches: []const Match, writer: anytype) !void {
    if (matches.len == 0) {
        try writer.writeAll(content);
        return;
    }
    const last = matches[matches.len - 1];
    if (last.end < content.len) {
        try writer.writeAll(content[last.end..content.len]);
    }
    var i = matches.len;
    while (i > 0) : (i -= 1) {
        const m = matches[i - 1];
        const prev_end = if (i > 1) matches[i - 2].end else 0;
        try writer.writeAll(content[prev_end..m.end]);
    }
}

fn reverseRecordsAfter(content: []const u8, sep: []const u8, writer: anytype) !void {
    if (content.len == 0 or sep.len == 0) return;
    var end = content.len;
    while (end > 0) {
        const search_slice = content[0..end];
        if (std.mem.lastIndexOf(u8, search_slice, sep)) |sep_idx| {
            if (sep_idx + sep.len == end) {
                const prev_search = content[0..sep_idx];
                if (std.mem.lastIndexOf(u8, prev_search, sep)) |p_idx| {
                    try writer.writeAll(content[p_idx + sep.len .. end]);
                    end = p_idx + sep.len;
                } else {
                    try writer.writeAll(content[0..end]);
                    break;
                }
            } else {
                try writer.writeAll(content[sep_idx + sep.len .. end]);
                end = sep_idx + sep.len;
            }
        } else {
            try writer.writeAll(content[0..end]);
            break;
        }
    }
}

fn reverseRecordsBefore(content: []const u8, sep: []const u8, writer: anytype) !void {
    if (content.len == 0 or sep.len == 0) return;
    var end = content.len;
    while (end > 0) {
        const search_slice = content[0..end];
        if (std.mem.lastIndexOf(u8, search_slice, sep)) |sep_idx| {
            try writer.writeAll(content[sep_idx..end]);
            end = sep_idx;
        } else {
            try writer.writeAll(content[0..end]);
            break;
        }
    }
}

fn processTacStream(content: []const u8, opt: *const Options, allocator: std.mem.Allocator, writer: anytype, stderr: anytype) !u8 {
    if (opt.regex) {
        const matches = findRegexMatches(allocator, content, opt.separator) catch |err| {
            try stderr.print("tac: {s}\n", .{@errorName(err)});
            return 1;
        };
        defer allocator.free(matches);
        if (opt.before) {
            try reverseRegexBefore(content, matches, writer);
        } else {
            try reverseRegexAfter(content, matches, writer);
        }
        return 0;
    }
    if (opt.before) {
        try reverseRecordsBefore(content, opt.separator, writer);
    } else {
        try reverseRecordsAfter(content, opt.separator, writer);
    }
    return 0;
}

fn processFile(path: []const u8, opt: *const Options, allocator: std.mem.Allocator, writer: anytype, stderr: anytype) !u8 {
    const is_stdin = std.mem.eql(u8, path, "-");
    const file = if (is_stdin)
        std.Io.File.stdin()
    else
        std.Io.Dir.cwd().openFile(std.Options.debug_io, path, .{ .mode = .read_only }) catch |err| {
            try stderr.print("tac: {s}: {s}\n", .{ path, @errorName(err) });
            return 1;
        };
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

    return try processTacStream(list.items, opt, allocator, writer, stderr);
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
    var files: std.ArrayList([]const u8) = .empty;
    defer files.deinit(allocator);

    if (try parseArgs(args, &opt, &files, allocator, stdout, stderr)) |code| return code;

    var status: u8 = 0;
    if (files.items.len == 0) {
        status = try processFile("-", &opt, allocator, stdout, stderr);
    } else {
        for (files.items) |file_path| {
            const res = try processFile(file_path, &opt, allocator, stdout, stderr);
            if (res != 0 and status == 0) status = res;
        }
    }
    stdout.flush() catch return 1;
    return status;
}
