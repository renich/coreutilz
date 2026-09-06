const std = @import("std");
const errors = @import("../utils/errors.zig");

const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "echo";
pub const version: []const u8 = "0.1.0";

fn hextobin(ch: u8) u8 {
    return switch (ch) {
        '0'...'9' => ch - '0',
        'a'...'f' => ch - 'a' + 10,
        'A'...'F' => ch - 'A' + 10,
        else => 0,
    };
}

pub fn run(args: [][]const u8, _: std.mem.Allocator) !u8 {
    var stdout_buffer: [65536]u8 = undefined;
    var stdout_file_writer: std.Io.File.Writer = .init(.stdout(), std.Options.debug_io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var display_return = true;
    const posixly_correct = c.getenv("POSIXLY_CORRECT") != null;
    const allow_options = (!posixly_correct or (args.len > 1 and std.mem.eql(u8, args[1], "-n")));
    var do_v9 = false;

    if (allow_options and args.len == 2) {
        if (std.mem.eql(u8, args[1], "--help")) {
            printHelp(stdout) catch return 1;
            stdout.flush() catch return 1;
            return 0;
        }
        if (std.mem.eql(u8, args[1], "--version")) {
            printVersion(stdout) catch return 1;
            stdout.flush() catch return 1;
            return 0;
        }
    }

    var arg_idx: usize = 1;

    if (allow_options) {
        while (arg_idx < args.len and args[arg_idx].len > 1 and args[arg_idx][0] == '-') {
            const temp = args[arg_idx][1..];
            var all_valid = true;
            for (temp) |opt| {
                if (opt != 'e' and opt != 'E' and opt != 'n') {
                    all_valid = false;
                    break;
                }
            }
            if (!all_valid) break;

            for (temp) |opt| {
                switch (opt) {
                    'e' => do_v9 = true,
                    'E' => do_v9 = false,
                    'n' => display_return = false,
                    else => {},
                }
            }
            arg_idx += 1;
        }
    }

    if (do_v9 or posixly_correct) {
        while (arg_idx < args.len) {
            const s = args[arg_idx];
            var si: usize = 0;
            while (si < s.len) {
                var ch = s[si];
                si += 1;
                if (ch == '\\' and si < s.len) {
                    const next = s[si];
                    si += 1;
                    switch (next) {
                        'a' => ch = 0x07,
                        'b' => ch = 0x08,
                        'c' => return flushStdout(stdout),
                        'e' => ch = 0x1B,
                        'f' => ch = 0x0C,
                        'n' => ch = '\n',
                        'r' => ch = '\r',
                        't' => ch = '\t',
                        'v' => ch = 0x0B,
                        'x' => {
                            if (si < s.len and std.ascii.isHex(s[si])) {
                                const h1 = s[si];
                                si += 1;
                                var val = hextobin(h1);
                                if (si < s.len and std.ascii.isHex(s[si])) {
                                    val = val * 16 + hextobin(s[si]);
                                    si += 1;
                                }
                                ch = val;
                            } else {
                                try stdout.writeByte('\\');
                                ch = 'x';
                            }
                        },
                        '0' => {
                            var val: u8 = 0;
                            if (si < s.len and s[si] >= '0' and s[si] <= '7') {
                                val = s[si] - '0';
                                si += 1;
                                if (si < s.len and s[si] >= '0' and s[si] <= '7') {
                                    val = val * 8 + (s[si] - '0');
                                    si += 1;
                                }
                                if (si < s.len and s[si] >= '0' and s[si] <= '7') {
                                    val = val * 8 + (s[si] - '0');
                                    si += 1;
                                }
                            }
                            ch = val;
                        },
                        '1'...'7' => {
                            var val: u8 = next - '0';
                            if (si < s.len and s[si] >= '0' and s[si] <= '7') {
                                val = val * 8 + (s[si] - '0');
                                si += 1;
                            }
                            if (si < s.len and s[si] >= '0' and s[si] <= '7') {
                                val = val * 8 + (s[si] - '0');
                                si += 1;
                            }
                            ch = val;
                        },
                        '\\' => ch = '\\',
                        else => {
                            try stdout.writeByte('\\');
                            ch = next;
                        },
                    }
                }
                try stdout.writeByte(ch);
            }
            arg_idx += 1;
            if (arg_idx < args.len) {
                try stdout.writeByte(' ');
            }
        }
    } else {
        while (arg_idx < args.len) {
            try stdout.writeAll(args[arg_idx]);
            arg_idx += 1;
            if (arg_idx < args.len) {
                try stdout.writeByte(' ');
            }
        }
    }

    if (display_return) {
        try stdout.writeByte('\n');
    }
    return flushStdout(stdout);
}

fn flushStdout(stdout: anytype) u8 {
    stdout.flush() catch |err| {
        var stderr_buf: [256]u8 = undefined;
        var stderr_writer = std.Io.File.Writer.init(.stderr(), std.Options.debug_io, &stderr_buf);
        const stderr = &stderr_writer.interface;
        const err_desc = blk: {
            const errno = c.__errno_location().*;
            if (errno != 0) {
                break :blk std.mem.span(c.strerror(errno));
            }
            break :blk errors.errorDescription(err);
        };
        stderr.print("{s}: write error: {s}\n", .{ name, err_desc }) catch {};
        stderr.flush() catch {};
        return 1;
    };
    return 0;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: echo [SHORT-OPTION]... [STRING]...
        \\  or:  echo LONG-OPTION
        \\Echo the STRING(s) to standard output.
        \\
        \\  -n     do not output the trailing newline
        \\  -e     enable interpretation of backslash escapes
        \\  -E     disable interpretation of backslash escapes (default)
        \\      --help        display this help and exit
        \\      --version     output version information and exit
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
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
