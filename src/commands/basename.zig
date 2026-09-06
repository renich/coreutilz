const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "basename";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, _: std.mem.Allocator) !u8 {
    var stdout_buffer: [4096]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_file_writer: std.Io.File.Writer = .init(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_file_writer.interface;
    const stderr = &stderr_file_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var multiple: bool = false;
    var suffix: ?[]const u8 = null;
    var zero: bool = false;
    var operands_start: usize = args.len;

    // Process options (POSIX style: stop at first non-option)
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--")) {
            operands_start = i + 1;
            break;
        } else if (std.mem.eql(u8, arg, "--help")) {
            printHelp(stdout) catch return 1;
            stdout.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            printVersion(stdout) catch return 1;
            stdout.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--multiple")) {
            multiple = true;
        } else if (std.mem.eql(u8, arg, "--zero")) {
            zero = true;
        } else if (std.mem.eql(u8, arg, "--suffix")) {
            multiple = true;
            if (i + 1 >= args.len) {
                try errors.printErrorWithHelp(stderr, name, "option '--suffix' requires an argument");
                return 1;
            }
            i += 1;
            suffix = args[i];
        } else if (std.mem.startsWith(u8, arg, "--suffix=")) {
            multiple = true;
            suffix = arg["--suffix=".len..];
        } else if (std.mem.startsWith(u8, arg, "--")) {
            try errors.printUnrecognizedOption(stderr, name, arg);
            return 1;
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            var j: usize = 1;
            while (j < arg.len) : (j += 1) {
                const c = arg[j];
                switch (c) {
                    'a' => multiple = true,
                    'z' => zero = true,
                    's' => {
                        multiple = true;
                        if (j + 1 < arg.len) {
                            suffix = arg[j + 1 ..];
                            break;
                        } else if (i + 1 < args.len) {
                            i += 1;
                            suffix = args[i];
                            break;
                        } else {
                            try errors.printErrorWithHelp(stderr, name, "option requires an argument -- 's'");
                            return 1;
                        }
                    },
                    else => {
                        try errors.printInvalidOption(stderr, name, c);
                        return 1;
                    },
                }
            }
        } else {
            operands_start = i;
            break;
        }
    }

    const num_operands = if (operands_start <= args.len) args.len - operands_start else 0;
    if (num_operands == 0) {
        try errors.printMissingOperand(stderr, name);
        return 1;
    }

    const terminator: u8 = if (zero) 0 else '\n';

    if (!multiple) {
        if (num_operands > 2) {
            try errors.printExtraOperand(stderr, name, args[operands_start + 2]);
            return 1;
        }
        const op_suffix = if (num_operands == 2) args[operands_start + 1] else null;
        const res = getBasename(args[operands_start], op_suffix);
        try stdout.print("{s}{c}", .{ res, terminator });
    } else {
        for (args[operands_start..]) |arg| {
            const res = getBasename(arg, suffix);
            try stdout.print("{s}{c}", .{ res, terminator });
        }
    }

    try stdout.flush();
    return 0;
}

fn getBasename(path: []const u8, suffix: ?[]const u8) []const u8 {
    if (path.len == 0) return "";

    // Remove trailing slashes
    var end = path.len;
    while (end > 0 and path[end - 1] == '/') {
        end -= 1;
    }

    if (end == 0) return "/";

    const last_slash = std.mem.lastIndexOfScalar(u8, path[0..end], '/');
    var base = if (last_slash) |i| path[i + 1 .. end] else path[0..end];

    if (suffix) |s| {
        if (std.mem.endsWith(u8, base, s) and base.len > s.len) {
            base = base[0 .. base.len - s.len];
        }
    }

    return base;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: basename NAME [SUFFIX]
        \\  or:  basename OPTION... NAME...
        \\Print NAME with any leading directory components removed.
        \\If specified, also remove a trailing SUFFIX.
        \\
        \\  -a, --multiple       support multiple arguments and treat each as a NAME
        \\  -s, --suffix=SUFFIX  remove a trailing SUFFIX; implies -a
        \\  -z, --zero           end each output line with NUL, not newline
        \\      --help           display this help and exit
        \\      --version        output version information and exit
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
