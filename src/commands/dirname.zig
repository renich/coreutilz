const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "dirname";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buffer: [4096]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_file_writer: std.Io.File.Writer = .init(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_file_writer.interface;
    const stderr = &stderr_file_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var zero: bool = false;
    var operands: std.ArrayList([]const u8) = .empty;
    defer operands.deinit(allocator);

    const posixly_correct = errors.isPosixlyCorrect();
    var stop_options = false;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (stop_options) {
            try operands.append(allocator, arg);
            continue;
        }

        if (std.mem.eql(u8, arg, "--")) {
            stop_options = true;
            continue;
        } else if (std.mem.eql(u8, arg, "--help")) {
            try printHelp(stdout);
            try stdout.flush();
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try printVersion(stdout);
            try stdout.flush();
            return 0;
        } else if (std.mem.eql(u8, arg, "--zero")) {
            zero = true;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            try errors.printUnrecognizedOption(stderr, name, arg);
            return 1;
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            for (arg[1..]) |c| {
                switch (c) {
                    'z' => zero = true,
                    else => {
                        try errors.printInvalidOption(stderr, name, c);
                        return 1;
                    },
                }
            }
        } else {
            try operands.append(allocator, arg);
            if (posixly_correct) {
                stop_options = true;
            }
        }
    }

    if (operands.items.len == 0) {
        try errors.printMissingOperand(stderr, name);
        return 1;
    }

    const terminator: u8 = if (zero) 0 else '\n';

    // Process all operands
    for (operands.items) |path| {
        const result = getDirname(path);
        try stdout.print("{s}{c}", .{ result, terminator });
    }

    try stdout.flush();
    return 0;
}

fn getDirname(path: []const u8) []const u8 {
    if (path.len == 0) return ".";

    // Remove trailing slashes (except if path is just slashes)
    var end = path.len;
    while (end > 0 and path[end - 1] == '/') {
        end -= 1;
    }

    if (end == 0) return "/"; // Path was all slashes

    // Find the last slash before the last component
    const last_slash = std.mem.lastIndexOfScalar(u8, path[0..end], '/');
    if (last_slash) |i| {
        if (i == 0) return "/";
        // Remove trailing slashes from the result
        var res_end = i;
        while (res_end > 0 and path[res_end - 1] == '/') {
            res_end -= 1;
        }
        if (res_end == 0) return "/";
        return path[0..res_end];
    } else {
        return ".";
    }
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: dirname [OPTION] NAME...
        \\Output each NAME with its last non-slash component and trailing slashes
        \\removed; if NAME contains no /'s, output '.' (meaning the current directory).
        \\
        \\  -z, --zero     end each output line with NUL, not newline
        \\      --help     display this help and exit
        \\      --version  output version information and exit
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
