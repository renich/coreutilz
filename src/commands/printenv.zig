const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "printenv";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buffer: [8192]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .init(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var line_terminator: u8 = '\n';
    var var_start: usize = 1;

    // Parse options
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (arg.len < 2 or arg[0] != '-') {
            var_start = i;
            break;
        }
        if (std.mem.eql(u8, arg, "--")) {
            var_start = i + 1;
            break;
        }

        if (std.mem.startsWith(u8, arg, "--")) {
            if (std.mem.eql(u8, arg, "--help")) {
                printHelp(stdout) catch return 2;
                stdout.flush() catch return 2;
                return 0;
            } else if (std.mem.eql(u8, arg, "--version")) {
                printVersion(stdout) catch return 2;
                stdout.flush() catch return 2;
                return 0;
            } else if (std.mem.eql(u8, arg, "--null")) {
                line_terminator = 0;
            } else {
                try errors.printError(stderr, name, try std.fmt.allocPrint(allocator, "unrecognized option '{s}'", .{arg}));
                return 2;
            }
        } else {
            // Short options
            for (arg[1..]) |c| {
                switch (c) {
                    '0' => line_terminator = 0,
                    else => {
                        try errors.printError(stderr, name, try std.fmt.allocPrint(allocator, "invalid option -- '{c}'", .{c}));
                        return 2;
                    },
                }
            }
        }
        var_start = i + 1;
    }

    const c_environ = std.c.environ;
    if (var_start >= args.len) {
        // Print all environment variables
        var ei: usize = 0;
        while (c_environ[ei]) |entry_ptr| : (ei += 1) {
            const env_var = std.mem.span(entry_ptr);
            try stdout.writeAll(env_var);
            try stdout.writeByte(line_terminator);
        }
    } else {
        // Print specific variables
        var exit_status: u8 = 0;
        for (args[var_start..]) |var_name| {
            var found_val: ?[]const u8 = null;
            var ei: usize = 0;
            while (c_environ[ei]) |entry_ptr| : (ei += 1) {
                const entry = std.mem.span(entry_ptr);
                const eq = std.mem.indexOf(u8, entry, "=") orelse continue;
                if (std.mem.eql(u8, entry[0..eq], var_name)) {
                    found_val = entry[eq + 1 ..];
                    break;
                }
            }
            if (found_val) |val| {
                try stdout.writeAll(val);
                try stdout.writeByte(line_terminator);
            } else {
                exit_status = 1;
            }
        }
        stdout.flush() catch return 2;
        return exit_status;
    }

    stdout.flush() catch return 2;
    return 0;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: printenv [OPTION]... [VARIABLE]...
        \\Print the values of the specified environment VARIABLE(s).
        \\If no VARIABLE is specified, print name and value pairs for them all.
        \\
        \\  -0, --null     end each output line with 0 byte rather than newline
        \\      --help     display this help and exit
        \\      --version  output version information and exit
        \\
        \\NOTE: your shell may have its own version of printenv, which usually supersedes
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
