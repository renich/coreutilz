const std = @import("std");
const errors = @import("../utils/errors.zig");
const c = @cImport({
    @cInclude("unistd.h");
    @cInclude("pwd.h");
});

pub const name: []const u8 = "whoami";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, _: std.mem.Allocator) !u8 {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), std.Options.debug_io, &stdout_buffer);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            try printHelp(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try printVersion(stdout);
            return 0;
        }
    }

    const uid = c.geteuid();
    const pw = c.getpwuid(uid);
    if (pw == null) {
        // Fallback to UID number
        try stdout.print("{d}\n", .{uid});
        return 0;
    }

    try stdout.print("{s}\n", .{std.mem.span(pw.*.pw_name)});
    return 0;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: whoami [OPTION]...
        \\Print the user name associated with the current effective user ID.
        \\
        \\      --help     display this help and exit
        \\      --version  output version information and exit
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
