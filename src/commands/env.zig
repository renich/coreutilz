const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "env";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buffer: [65536]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .init(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var ignore_environment = false;
    var null_terminator = false;
    var unset_vars: std.ArrayList([]const u8) = .empty;
    defer unset_vars.deinit(allocator);
    var assignments: std.ArrayList([2][]const u8) = .empty;
    defer assignments.deinit(allocator);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            try printHelp(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try printVersion(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            break;
        } else if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--ignore-environment") or std.mem.eql(u8, arg, "-")) {
            ignore_environment = true;
        } else if (std.mem.eql(u8, arg, "-0") or std.mem.eql(u8, arg, "--null")) {
            null_terminator = true;
        } else if (std.mem.eql(u8, arg, "-u")) {
            i += 1;
            if (i >= args.len) {
                try errors.printError(stderr, name, "option requires an argument -- '-u'");
                return 125;
            }
            try unset_vars.append(allocator, args[i]);
        } else if (std.mem.startsWith(u8, arg, "--unset=")) {
            try unset_vars.append(allocator, arg[8..]);
        } else if (std.mem.eql(u8, arg, "-C") or std.mem.eql(u8, arg, "--chdir")) {
            i += 1;
        } else if (std.mem.startsWith(u8, arg, "--chdir=")) {} else if (std.mem.eql(u8, arg, "-S") or std.mem.eql(u8, arg, "--split-string")) {
            i += 1;
        } else if (std.mem.startsWith(u8, arg, "--split-string=")) {} else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            const msg = try std.fmt.allocPrint(allocator, "invalid option -- '{s}'", .{arg});
            defer allocator.free(msg);
            try errors.printError(stderr, name, msg);
            return 125;
        } else if (std.mem.indexOf(u8, arg, "=") != null) {
            const eq = std.mem.indexOf(u8, arg, "=").?;
            try assignments.append(allocator, .{ arg[0..eq], arg[eq + 1 ..] });
        } else {
            break;
        }
    }

    const terminator: u8 = if (null_terminator) 0 else '\n';

    if (ignore_environment) {
        for (assignments.items) |pair| {
            var skip = false;
            for (unset_vars.items) |uvar| {
                if (std.mem.eql(u8, pair[0], uvar)) {
                    skip = true;
                    break;
                }
            }
            if (!skip) {
                try stdout.print("{s}={s}", .{ pair[0], pair[1] });
                try stdout.writeByte(terminator);
            }
        }
    } else {
        const c_environ = std.c.environ;
        var ei: usize = 0;
        while (c_environ[ei]) |entry_ptr| : (ei += 1) {
            const entry = std.mem.span(entry_ptr);
            const eq = std.mem.indexOf(u8, entry, "=") orelse continue;
            const entry_name = entry[0..eq];
            var skip = false;
            for (unset_vars.items) |uvar| {
                if (std.mem.eql(u8, entry_name, uvar)) {
                    skip = true;
                    break;
                }
            }
            if (!skip) {
                try stdout.writeAll(entry);
                try stdout.writeByte(terminator);
            }
        }
        for (assignments.items) |pair| {
            try stdout.print("{s}={s}", .{ pair[0], pair[1] });
            try stdout.writeByte(terminator);
        }
    }

    return 0;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: env [OPTION]... [-] [NAME=VALUE]... [COMMAND [ARG]...]
        \\Set each NAME to VALUE in the environment and run COMMAND.
        \\
        \\  -i, --ignore-environment  start with an empty environment
        \\  -0, --null           end each output line with 0 byte rather than newline
        \\  -u, --unset=NAME     remove variable from the environment
        \\  -C, --chdir=DIR      change working directory to DIR
        \\  -S, --split-string=S  process and split S into separate arguments
        \\      --help     display this help and exit
        \\      --version  output version information and exit
        \\
        \\A mere - implies -i.  If no COMMAND, print the resulting environment.
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
