const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "true";
pub const version: []const u8 = "0.1.0";

pub fn run(_: [][]const u8, _: std.mem.Allocator) !u8 {
    return 0;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: true [ignored command line arguments]
        \\  or:  true OPTION
        \\\n        \\Exit with a status code indicating success.
        \\These arguments are ignored.
        \\      --help     display this help and exit
        \\      --version  output version information and exit
        \\An exit status of 0 indicates success.
        \\GNU coreutils online help: <https://www.gnu.org/software/coreutils/>
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}

test "true returns 0" {
    const allocator = std.testing.allocator;
    const args = &[_][]const u8{"true"};
    const result = try run(args, allocator);
    try std.testing.expectEqual(@as(u8, 0), result);
}

test "true ignores arguments" {
    const allocator = std.testing.allocator;
    const args = &[_][]const u8{ "true", "--help", "--version", "ignored" };
    const result = try run(args, allocator);
    try std.testing.expectEqual(@as(u8, 0), result);
}
