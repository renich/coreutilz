const std = @import("std");
const errors = @import("../utils/errors.zig");

const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "tty";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    _ = allocator;
    var stdout_buffer: [4096]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var silent = false;
    var parse_options = true;

    if (args.len > 1) {
        for (args[1..]) |arg| {
            if (parse_options and std.mem.eql(u8, arg, "--")) {
                parse_options = false;
                continue;
            }

            if (parse_options and std.mem.startsWith(u8, arg, "--") and arg.len > 2) {
                if (std.mem.eql(u8, arg, "--silent") or std.mem.eql(u8, arg, "--quiet")) {
                    silent = true;
                } else if (std.mem.eql(u8, arg, "--help")) {
                    try printHelp(stdout);
                    stdout.flush() catch return 3;
                    return 0;
                } else if (std.mem.eql(u8, arg, "--version")) {
                    try printVersion(stdout);
                    stdout.flush() catch return 3;
                    return 0;
                } else {
                    try errors.printUnrecognizedOption(stderr, name, arg);
                    return 2;
                }
            } else if (parse_options and std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
                for (arg[1..]) |ch| {
                    switch (ch) {
                        's' => silent = true,
                        else => {
                            try errors.printInvalidOption(stderr, name, ch);
                            return 2;
                        },
                    }
                }
            } else {
                try errors.printExtraOperand(stderr, name, arg);
                return 2;
            }
        }
    }

    if (silent) {
        return if (c.isatty(c.STDIN_FILENO) != 0) 0 else 1;
    }

    var status: u8 = 0;
    const tty_ptr = c.ttyname(c.STDIN_FILENO);
    const msg = if (tty_ptr != null)
        std.mem.span(tty_ptr)
    else blk: {
        const ttyname_err = c.__errno_location().*;
        if (c.isatty(c.STDIN_FILENO) != 0) {
            const err_str = std.mem.span(c.strerror(ttyname_err));
            try stderr.print("tty: ttyname error: {s}\n", .{err_str});
            return 4;
        }
        status = 1;
        break :blk "not a tty";
    };

    stdout.print("{s}\n", .{msg}) catch {
        try stderr.print("tty: write error: No space left on device\n", .{});
        return 3;
    };
    stdout.flush() catch {
        try stderr.print("tty: write error: No space left on device\n", .{});
        return 3;
    };

    return status;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: tty [OPTION]...
        \\Print the file name of the terminal connected to standard input.
        \\
        \\  -s, --silent, --quiet   print nothing, only return an exit status
        \\      --help     display this help and exit
        \\      --version  output version information and exit
        \\
        \\GNU coreutils online help: <https://www.gnu.org/software/coreutils/>
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
