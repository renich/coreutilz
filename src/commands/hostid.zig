const std = @import("std");
const errors = @import("../utils/errors.zig");
const c = @cImport({
    @cInclude("unistd.h");
    @cInclude("stdio.h");
});

pub const name: []const u8 = "hostid";
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

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            try printHelp(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try printVersion(stdout);
            return 0;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            try errors.printError(stderr, name, try std.fmt.allocPrint(allocator, "unrecognized option '{s}'", .{arg}));
            return 1;
        } else {
            try errors.printError(stderr, name, try std.fmt.allocPrint(allocator, "extra operand '{s}'", .{arg}));
            return 1;
        }
    }

    const hostid = c.gethostid();
    try stdout.print("{x:0>8}\n", .{@as(u32, @truncate(@as(u64, @bitCast(hostid))))});
    return 0;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: hostid [OPTION]
        \\Print the numeric identifier for the current host.
        \\
        \\      --help     display this help and exit
        \\      --version  output version information and exit
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
