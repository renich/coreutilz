const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "echo";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, _: std.mem.Allocator) !u8 {
    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), std.Options.debug_io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;
    defer stdout.flush() catch {};

    var newline = true;
    var interpret_escapes = false;
    var arg_start: usize = 1;

    // GNU echo: If the first argument is exactly "--help" or "--version",
    // and no other arguments are present, handle them.
    if (args.len == 2) {
        if (std.mem.eql(u8, args[1], "--help")) {
            try printHelp(stdout);
            return 0;
        } else if (std.mem.eql(u8, args[1], "--version")) {
            try printVersion(stdout);
            return 0;
        }
    }

    // Parse options: -n, -e, -E
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (arg.len < 2 or arg[0] != '-') {
            break;
        }

        // Check for -n, -e, -E combined or separate
        var j: usize = 1;
        var valid_opts = true;
        while (j < arg.len) : (j += 1) {
            switch (arg[j]) {
                'n' => {},
                'e' => {},
                'E' => {},
                else => {
                    valid_opts = false;
                    break;
                },
            }
        }

        if (!valid_opts) break;

        // Apply options
        for (arg[1..]) |c| {
            switch (c) {
                'n' => newline = false,
                'e' => interpret_escapes = true,
                'E' => interpret_escapes = false,
                else => unreachable,
            }
        }
        arg_start = i + 1;
    }

    // Print arguments
    for (args[arg_start..], 0..) |arg, idx| {
        if (idx > 0) {
            try stdout.writeByte(' ');
        }
        if (interpret_escapes) {
            if (try printEscaped(stdout, arg)) {
                return 0;
            }
        } else {
            try stdout.writeAll(arg);
        }
    }

    if (newline) {
        try stdout.writeByte('\n');
    }

    return 0;
}

/// Returns true if \c was encountered
fn printEscaped(writer: anytype, s: []const u8) !bool {
    var i: usize = 0;
    while (i < s.len) : (i += 1) {
        if (s[i] == '\\' and i + 1 < s.len) {
            i += 1;
            const c = s[i];
            switch (c) {
                '\\' => try writer.writeByte('\\'),
                'a' => try writer.writeByte(0x07),
                'b' => try writer.writeByte(0x08),
                'c' => return true, // Stop output
                'e' => try writer.writeByte(0x1B),
                'f' => try writer.writeByte(0x0C),
                'n' => try writer.writeByte('\n'),
                'r' => try writer.writeByte('\r'),
                't' => try writer.writeByte('\t'),
                'v' => try writer.writeByte(0x0B),
                '0' => {
                    // Octal escape: \0 followed by up to 3 octal digits
                    var val: u8 = 0;
                    if (i + 1 < s.len and s[i + 1] >= '0' and s[i + 1] <= '7') {
                        i += 1;
                        val = s[i] - '0';
                        if (i + 1 < s.len and s[i + 1] >= '0' and s[i + 1] <= '7') {
                            i += 1;
                            val = (val << 3) | (s[i] - '0');
                            if (i + 1 < s.len and s[i + 1] >= '0' and s[i + 1] <= '7') {
                                i += 1;
                                val = (val << 3) | (s[i] - '0');
                            }
                        }
                    }
                    try writer.writeByte(val);
                },
                '1'...'7' => {
                    // Octal escape: \1..7 followed by up to 2 octal digits
                    var val: u8 = c - '0';
                    if (i + 1 < s.len and s[i + 1] >= '0' and s[i + 1] <= '7') {
                        i += 1;
                        val = (val << 3) | (s[i] - '0');
                        if (i + 1 < s.len and s[i + 1] >= '0' and s[i + 1] <= '7') {
                            i += 1;
                            val = (val << 3) | (s[i] - '0');
                        }
                    }
                    try writer.writeByte(val);
                },
                'x' => {
                    // Hex escape: \xHH (1 to 2 digits)
                    i += 1;
                    var val: u8 = 0;
                    var count: usize = 0;
                    while (count < 2 and i < s.len) : ({
                        i += 1;
                        count += 1;
                    }) {
                        const digit = std.fmt.charToDigit(s[i], 16) catch break;
                        val = (val << 4) | @as(u8, @truncate(digit));
                    }
                    if (count > 0) {
                        try writer.writeByte(val);
                    } else {
                        try writer.writeAll("\\x");
                    }
                    i -= 1; // Adjust for outer loop increment
                },
                else => {
                    try writer.writeByte('\\');
                    try writer.writeByte(c);
                },
            }
        } else {
            try writer.writeByte(s[i]);
        }
    }
    return false;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: echo [SHORT-OPTION]... [STRING]...
        \\  or:  echo LONG-OPTION
        \\Print the STRING(s) to standard output.
        \\
        \\  -n             do not output the trailing newline
        \\  -e             enable interpretation of backslash escapes
        \\  -E             disable interpretation of backslash escapes (default)
        \\      --help     display this help and exit
        \\      --version  output version information and exit
        \\
        \\If -e is in effect, the following sequences are recognized:
        \\
        \\  \\      backslash
        \\  \a      alert (BEL)
        \\  \b      backspace
        \\  \c      produce no further output
        \\  \e      escape
        \\  \f      form feed
        \\  \n      new line
        \\  \r      carriage return
        \\  \t      horizontal tab
        \\  \v      vertical tab
        \\  \0NNN   byte with octal value NNN (1 to 3 digits)
        \\  \xHH    byte with hexadecimal value HH (1 to 2 digits)
        \\
        \\NOTE: your shell may have its own version of echo, which usually supersedes
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
