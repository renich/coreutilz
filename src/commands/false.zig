const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "false";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, _: std.mem.Allocator) !u8 {
    if (args.len == 2) {
        if (std.mem.eql(u8, args[1], "--help")) {
            var stdout_buffer: [4096]u8 = undefined;
            var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), std.Options.debug_io, &stdout_buffer);
            const stdout = &stdout_file_writer.interface;
            printHelp(stdout) catch {};
            stdout.flush() catch {};
            return 1;
        } else if (std.mem.eql(u8, args[1], "--version")) {
            var stdout_buffer: [4096]u8 = undefined;
            var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), std.Options.debug_io, &stdout_buffer);
            const stdout = &stdout_file_writer.interface;
            printVersion(stdout) catch {};
            stdout.flush() catch {};
            return 1;
        }
    }
    return 1;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: false [ignored command line arguments]
        \\  or:  false OPTION
        \\Exit with a status code indicating failure.
        \\
        \\These arguments are ignored.
        \\      --help     display this help and exit
        \\      --version  output version information and exit
        \\
        \\Your shell may have its own version of false, which usually supersedes
        \\the version described here.  Please refer to your shell's documentation
        \\for details about the options it supports.
        \\
        \\GNU coreutils online help: <https://www.gnu.org/software/coreutils/>
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}

test "false returns 1" {
    const allocator = std.testing.allocator;
    const args = &[_][]const u8{"false"};
    const result = try run(args, allocator);
    try std.testing.expectEqual(@as(u8, 1), result);
}

test "false ignores arguments" {
    const allocator = std.testing.allocator;
    const args = &[_][]const u8{ "false", "--help", "--version", "ignored" };
    const result = try run(args, allocator);
    try std.testing.expectEqual(@as(u8, 1), result);
}
