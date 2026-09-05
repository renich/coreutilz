const std = @import("std");
const errors = @import("../utils/errors.zig");
const c = @cImport({
    @cInclude("unistd.h");
    @cInclude("stdio.h");
});

pub const name: []const u8 = "tty";
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

    var silent = false;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            try printHelp(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try printVersion(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--silent") or std.mem.eql(u8, arg, "--quiet")) {
            silent = true;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            try errors.printError(stderr, name, try std.fmt.allocPrint(allocator, "unrecognized option '{s}'", .{arg}));
            return 2;
        } else {
            try errors.printError(stderr, name, try std.fmt.allocPrint(allocator, "extra operand '{s}'", .{arg}));
            return 2;
        }
    }

    var buf: [4096]u8 = undefined;
    const result = c.ttyname_r(0, &buf, buf.len);
    if (result != 0) {
        if (!silent) try stdout.writeAll("not a tty\n");
        return 1;
    }

    if (!silent) {
        const tty_str = std.mem.span(@as([*:0]u8, @ptrCast(&buf)));
        try stdout.print("{s}\n", .{tty_str});
    }
    return 0;
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
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
