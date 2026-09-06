const std = @import("std");
const errors = @import("../utils/errors.zig");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "logname";
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

    // 1. Scan for --help and --version anywhere before --
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
                try stderr.print("logname: unrecognized option '{s}'\nTry 'logname --help' for more information.\n", .{arg});
                return 1;
            }
            if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
                try stderr.print("logname: invalid option -- '{c}'\nTry 'logname --help' for more information.\n", .{arg[1]});
                return 1;
            }
        }
        try operands.append(allocator, arg);
    }

    if (operands.items.len > 0) {
        try stderr.print("logname: extra operand '{s}'\nTry 'logname --help' for more information.\n", .{operands.items[0]});
        return 1;
    }

    const login = c.getlogin();
    if (login == null) {
        try stderr.print("logname: no login name\n", .{});
        return 1;
    }

    stdout.print("{s}\n", .{std.mem.span(login)}) catch return 1;
    stdout.flush() catch return 1;
    return 0;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: logname [OPTION]
        \\Print the user's login name.
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
