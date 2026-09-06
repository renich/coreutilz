const std = @import("std");
const errors = @import("../utils/errors.zig");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "pwd";
pub const version: []const u8 = "0.1.0";

fn logicalGetcwd() ?[:0]const u8 {
    const wd_c = c.getenv("PWD") orelse return null;
    const wd: [:0]const u8 = std.mem.span(wd_c);

    // Textual validation
    if (wd.len == 0 or wd[0] != '/') return null;

    // Check for "/." followed by '/' or '.' or end
    var i: usize = 0;
    while (i < wd.len) : (i += 1) {
        if (wd[i] == '/' and i + 1 < wd.len and wd[i + 1] == '.') {
            const next1 = if (i + 2 < wd.len) wd[i + 2] else 0;
            if (next1 == 0 or next1 == '/') return null;
            if (next1 == '.') {
                const next2 = if (i + 3 < wd.len) wd[i + 3] else 0;
                if (next2 == 0 or next2 == '/') return null;
            }
        }
    }

    // System call validation: stat(wd) and stat(".") must match inode and dev
    var st1: c.struct_stat = undefined;
    var st2: c.struct_stat = undefined;
    if (c.stat(wd.ptr, &st1) != 0) return null;
    if (c.stat(".", &st2) != 0) return null;

    if (st1.st_ino == st2.st_ino and st1.st_dev == st2.st_dev) {
        return wd;
    }
    return null;
}

fn physicalGetcwd() ?[:0]const u8 {
    const ptr = c.getcwd(null, 0) orelse return null;
    return std.mem.span(ptr);
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    _ = allocator;
    _ = c.signal(c.SIGPIPE, c.SIG_DFL);

    var stdout_buffer: [4096]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var logical = errors.isPosixlyCorrect();

    var i: usize = 1;
    var has_operands = false;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--")) {
            if (i + 1 < args.len) has_operands = true;
            break;
        }

        if (std.mem.startsWith(u8, arg, "--")) {
            if (std.mem.eql(u8, arg, "--help")) {
                printHelp(stdout) catch return 1;
                stdout.flush() catch return 1;
                return 0;
            } else if (std.mem.eql(u8, arg, "--version")) {
                printVersion(stdout) catch return 1;
                stdout.flush() catch return 1;
                return 0;
            } else if (std.mem.eql(u8, arg, "--logical")) {
                logical = true;
            } else if (std.mem.eql(u8, arg, "--physical")) {
                logical = false;
            } else {
                try errors.printUnrecognizedOption(stderr, name, arg);
                return 1;
            }
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            for (arg[1..]) |ch| {
                switch (ch) {
                    'L' => logical = true,
                    'P' => logical = false,
                    else => {
                        try errors.printInvalidOption(stderr, name, ch);
                        return 1;
                    },
                }
            }
        } else {
            has_operands = true;
            break;
        }
    }

    if (has_operands) {
        try stderr.print("{s}: ignoring non-option arguments\n", .{name});
    }

    if (logical) {
        if (logicalGetcwd()) |wd| {
            stdout.print("{s}\n", .{wd}) catch return 1;
            stdout.flush() catch return 1;
            return 0;
        }
    }

    if (physicalGetcwd()) |pwd_str| {
        defer c.free(@constCast(pwd_str.ptr));
        stdout.print("{s}\n", .{pwd_str}) catch return 1;
        stdout.flush() catch return 1;
        return 0;
    } else {
        const err = c.__errno_location().*;
        const msg = std.mem.span(c.strerror(err));
        try stderr.print("{s}: error getting current directory: {s}\n", .{ name, msg });
        return 1;
    }
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: pwd [OPTION]...
        \\Print the full filename of the current working directory.
        \\
        \\  -L, --logical   use PWD from environment, even if it contains symlinks
        \\  -P, --physical  avoid all symlinks
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
        \\If no option is specified, -P is assumed.
        \\
        \\GNU coreutils online help: <https://www.gnu.org/software/coreutils/>
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
