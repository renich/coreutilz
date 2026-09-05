const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "yes";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), std.Options.debug_io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    // Check for help/version
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            try printHelp(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try printVersion(stdout);
            return 0;
        }
    }

    // Build the string to output
    var output: []const u8 = "y";
    if (args.len > 1) {
        output = try std.mem.join(allocator, " ", args[1..]);
    }

    // Loop forever printing the string
    while (true) {
        try stdout.print("{s}\n", .{output});
    }
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: yes [STRING]...
        \\  or:  yes OPTION
        \\Repeatedly output a line with all specified STRING(s), or 'y'.
        \\
        \\      --help     display this help and exit
        \\      --version  output version information and exit
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
