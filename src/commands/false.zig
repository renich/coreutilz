const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "false";
pub const version: []const u8 = "0.1.0";

pub fn run(_: [][]const u8, _: std.mem.Allocator) !u8 {
    return 1;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: false [ignored command line arguments]
        \\  or:  false OPTION
        \\Exit with a status code indicating failure.
        \\These arguments are ignored.
        \\      --help     display this help and exit
        \\      --version  output version information and exit
        \\An exit status of 1 indicates failure.
        \\GNU coreutils online help: <https://www.gnu.org/software/coreutils/>
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
