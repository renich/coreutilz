const std = @import("std");
const errors = @import("../utils/errors.zig");

const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "unlink";
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

    // 1. Check for help/version anywhere before --
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--")) {
            break;
        } else if (std.mem.eql(u8, arg, "--help")) {
            try printHelp(stdout);
            stdout.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try printVersion(stdout);
            stdout.flush() catch return 1;
            return 0;
        }
    }

    // 2. Separate options and operands
    var operands: std.ArrayList([]const u8) = .empty;
    defer operands.deinit(allocator);

    var parsing_options = true;
    for (args[1..]) |arg| {
        if (parsing_options) {
            if (std.mem.eql(u8, arg, "--")) {
                parsing_options = false;
                continue;
            }
            if (std.mem.startsWith(u8, arg, "--") and arg.len > 2) {
                try stderr.print("unlink: unrecognized option '{s}'\nTry 'unlink --help' for more information.\n", .{arg});
                return 1;
            }
            if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
                try stderr.print("unlink: invalid option -- '{c}'\nTry 'unlink --help' for more information.\n", .{arg[1]});
                return 1;
            }
        }
        try operands.append(allocator, arg);
    }

    if (operands.items.len < 1) {
        try stderr.print("unlink: missing operand\nTry 'unlink --help' for more information.\n", .{});
        return 1;
    }

    if (operands.items.len > 1) {
        try stderr.print("unlink: extra operand '{s}'\nTry 'unlink --help' for more information.\n", .{operands.items[1]});
        return 1;
    }

    const path = operands.items[0];
    const path_z = try allocator.dupeZ(u8, path);
    defer allocator.free(path_z);

    if (c.unlink(path_z.ptr) != 0) {
        const err_str = std.mem.span(c.strerror(c.__errno_location().*));
        try stderr.print("unlink: cannot unlink '{s}': {s}\n", .{ path, err_str });
        return 1;
    }

    return 0;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: unlink FILE
        \\  or:  unlink OPTION
        \\Call the unlink function to remove the specified FILE.
        \\
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
