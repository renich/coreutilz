const std = @import("std");
const errors = @import("../utils/errors.zig");

const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "hostname";
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

    var short_mode = false;
    var parsing_options = true;
    for (args[1..]) |arg| {
        if (parsing_options) {
            if (std.mem.eql(u8, arg, "--")) {
                parsing_options = false;
                continue;
            }
            if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--short")) {
                short_mode = true;
                continue;
            }
            if (std.mem.startsWith(u8, arg, "--") and arg.len > 2) {
                try stderr.print("hostname: unrecognized option '{s}'\nTry 'hostname --help' for more information.\n", .{arg});
                return 1;
            }
            if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
                try stderr.print("hostname: invalid option -- '{c}'\nTry 'hostname --help' for more information.\n", .{arg[1]});
                return 1;
            }
        }
        try operands.append(allocator, arg);
    }

    if (operands.items.len > 1) {
        try stderr.print("hostname: extra operand '{s}'\nTry 'hostname --help' for more information.\n", .{operands.items[1]});
        return 1;
    }

    if (operands.items.len == 1) {
        const new_name = operands.items[0];
        const new_name_z = try allocator.dupeZ(u8, new_name);
        defer allocator.free(new_name_z);

        if (c.sethostname(new_name_z.ptr, new_name.len) != 0) {
            const err_str = std.mem.span(c.strerror(c.__errno_location().*));
            try stderr.print("hostname: cannot set name to '{s}': {s}\n", .{ new_name, err_str });
            return 1;
        }
        return 0;
    }

    var hostname_buffer: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostname_slice = std.posix.gethostname(&hostname_buffer) catch {
        try stderr.print("hostname: cannot determine hostname\n", .{});
        return 1;
    };
    const out_slice = if (short_mode)
        (if (std.mem.indexOfScalar(u8, hostname_slice, '.')) |dot| hostname_slice[0..dot] else hostname_slice)
    else
        hostname_slice;

    stdout.print("{s}\n", .{out_slice}) catch return 1;
    stdout.flush() catch return 1;
    return 0;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: hostname [NAME]
        \\  or:  hostname OPTION
        \\Print or set the hostname of the current system.
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
