const std = @import("std");
const errors = @import("../utils/errors.zig");

const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "yes";
pub const version: []const u8 = "0.1.0";

fn fullWrite(fd: c_int, bytes: []const u8) bool {
    var written: usize = 0;
    while (written < bytes.len) {
        const count = bytes.len - written;
        const res = c.write(fd, bytes[written..].ptr, count);
        if (res <= 0) {
            return false;
        }
        written += @intCast(res);
    }
    return true;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.Writer.init(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.Writer.init(.stdout(), std.Options.debug_io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var operands: std.ArrayList([]const u8) = .empty;
    defer operands.deinit(allocator);

    var parsing_options = true;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (parsing_options and arg.len > 0 and arg[0] == '-') {
            if (std.mem.eql(u8, arg, "--")) {
                parsing_options = false;
                continue;
            } else if (std.mem.eql(u8, arg, "--help")) {
                try printHelp(stdout);
                try stdout.flush();
                return 0;
            } else if (std.mem.eql(u8, arg, "--version")) {
                try printVersion(stdout);
                try stdout.flush();
                return 0;
            } else if (std.mem.startsWith(u8, arg, "--")) {
                try errors.printUnrecognizedOption(stderr, name, arg);
                try stderr.flush();
                return 1;
            } else if (arg.len > 1) {
                try errors.printInvalidOption(stderr, name, arg[1]);
                try stderr.flush();
                return 1;
            }
        }
        try operands.append(allocator, arg);
    }

    // Measure size of one repetition
    var line_len: usize = 0;
    if (operands.items.len == 0) {
        line_len = 2; // "y\n"
    } else {
        for (operands.items, 0..) |op, idx| {
            line_len += op.len;
            if (idx + 1 < operands.items.len) {
                line_len += 1; // space
            }
        }
        line_len += 1; // newline
    }

    // Allocate buffer: at least 8192 bytes (BUFSIZ)
    var bufalloc: usize = 8192;
    if (line_len > bufalloc / 2) {
        bufalloc = line_len;
    }
    const copies = @max(1, bufalloc / line_len);
    const total_buf_len = copies * line_len;

    const buf = try allocator.alloc(u8, total_buf_len);
    defer allocator.free(buf);

    // Build the first repetition
    var pos: usize = 0;
    if (operands.items.len == 0) {
        buf[0] = 'y';
        buf[1] = '\n';
        pos = 2;
    } else {
        for (operands.items, 0..) |op, idx| {
            @memcpy(buf[pos .. pos + op.len], op);
            pos += op.len;
            if (idx + 1 < operands.items.len) {
                buf[pos] = ' ';
                pos += 1;
            }
        }
        buf[pos] = '\n';
        pos += 1;
    }

    // Replicate across the remainder of the buffer
    const copysize = pos;
    while (pos + copysize <= total_buf_len) {
        @memcpy(buf[pos .. pos + copysize], buf[0..copysize]);
        pos += copysize;
    }

    // Output loop
    while (fullWrite(1, buf[0..pos])) {}

    const err = c.__errno_location().*;
    const msg = std.mem.span(c.strerror(err));
    try stderr.print("{s}: standard output: {s}\n", .{ name, msg });
    try stderr.flush();
    return 1;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: yes [STRING]...
        \\  or:  yes OPTION
        \\Repeatedly output a line with all specified STRING(s), or 'y'.
        \\
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
