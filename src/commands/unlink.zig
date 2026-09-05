const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "unlink";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, _: std.mem.Allocator) !u8 {
    var stdout_buffer: [4096]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .init(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    // Check for help/version first
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            try printHelp(stdout);
            try stdout.flush();
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try printVersion(stdout);
            try stdout.flush();
            return 0;
        }
    }

    if (args.len < 2) {
        try errors.printError(stderr, name, "missing operand");
        return 1;
    }

    if (args.len > 2) {
        try errors.printError(stderr, name, "extra operand");
        return 1;
    }

    const path = args[1];
    std.Io.Dir.cwd().deleteFile(std.Options.debug_io, path) catch |err| {
        try errors.printErrorWithArg(stderr, name, path, err);
        return 1;
    };

    return 0;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: unlink FILE
        \\Call the unlink function to remove the specified FILE.
        \\
        \\      --help     display this help and exit
        \\      --version  output version information and exit
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
