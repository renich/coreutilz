const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "pwd";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buffer: [4096]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .init(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var physical = false;

    // Check for options
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            try printHelp(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try printVersion(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "-L") or std.mem.eql(u8, arg, "--logical")) {
            physical = false;
        } else if (std.mem.eql(u8, arg, "-P") or std.mem.eql(u8, arg, "--physical")) {
            physical = true;
        } else if (std.mem.eql(u8, arg, "--")) {
            break;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            try errors.printError(stderr, name, try std.fmt.allocPrint(allocator, "unrecognized option '{s}'", .{arg}));
            return 2;
        }
    }

    if (physical) {
        var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const len = try std.process.currentPath(std.Options.debug_io, &buf);
        try stdout.print("{s}\n", .{buf[0..len]});
    } else {
        // Logical: try PWD env var first
        if (std.c.getenv("PWD")) |pwd_ptr| {
            const pwd = std.mem.span(pwd_ptr);
            if (pwd.len > 0 and pwd[0] == '/') {
                try stdout.print("{s}\n", .{pwd});
                return 0;
            }
        }

        // Fallback to physical
        var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const len = try std.process.currentPath(std.Options.debug_io, &buf);
        try stdout.print("{s}\n", .{buf[0..len]});
    }

    return 0;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: pwd [OPTION]...
        \\Print the full filename of the current working directory.
        \\
        \\  -L, --logical   use PWD from environment, even if it contains symlinks
        \\  -P, --physical  avoid all symlinks
        \\      --help     display this help and exit
        \\      --version  output version information and exit
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
