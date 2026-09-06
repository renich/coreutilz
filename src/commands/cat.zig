const std = @import("std");
const errors = @import("../utils/errors.zig");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "cat";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    _ = c.signal(c.SIGPIPE, c.SIG_DFL);

    var stdout_buffer: [16384]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var show_ends = false;
    var show_tabs = false;
    var show_nonprinting = false;
    var number = false;
    var number_nonblank = false;
    var squeeze_blank = false;

    var file_start: usize = args.len;

    // Parse options
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (arg.len == 0 or arg[0] != '-' or std.mem.eql(u8, arg, "-")) {
            file_start = i;
            break;
        }
        if (std.mem.eql(u8, arg, "--")) {
            file_start = i + 1;
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
            } else if (std.mem.eql(u8, arg, "--show-all")) {
                show_nonprinting = true;
                show_ends = true;
                show_tabs = true;
            } else if (std.mem.eql(u8, arg, "--number-nonblank")) {
                number_nonblank = true;
            } else if (std.mem.eql(u8, arg, "--show-ends")) {
                show_ends = true;
            } else if (std.mem.eql(u8, arg, "--number")) {
                number = true;
            } else if (std.mem.eql(u8, arg, "--squeeze-blank")) {
                squeeze_blank = true;
            } else if (std.mem.eql(u8, arg, "--show-tabs")) {
                show_tabs = true;
            } else if (std.mem.eql(u8, arg, "--show-nonprinting")) {
                show_nonprinting = true;
            } else {
                const msg = try std.fmt.allocPrint(allocator, "unrecognized option '{s}'", .{arg});
                defer allocator.free(msg);
                try errors.printError(stderr, name, msg);
                return 1;
            }
        } else {
            // Short options
            for (arg[1..]) |ch| {
                switch (ch) {
                    'A' => {
                        show_nonprinting = true;
                        show_ends = true;
                        show_tabs = true;
                    },
                    'b' => number_nonblank = true,
                    'e' => {
                        show_nonprinting = true;
                        show_ends = true;
                    },
                    'E' => show_ends = true,
                    'n' => number = true,
                    's' => squeeze_blank = true,
                    't' => {
                        show_nonprinting = true;
                        show_tabs = true;
                    },
                    'T' => show_tabs = true,
                    'u' => {}, // Ignored
                    'v' => show_nonprinting = true,
                    else => {
                        try errors.printInvalidOption(stderr, name, ch);
                        return 1;
                    },
                }
            }
        }
    }

    if (number_nonblank) {
        number = false;
    }

    const any_options = show_ends or show_tabs or show_nonprinting or number or number_nonblank or squeeze_blank;

    var line_num: usize = 1;
    var consecutive_newlines: usize = 0;
    var at_line_start = true;
    var pending_cr = false;
    var exit_status: u8 = 0;

    if (file_start >= args.len) {
        if (isInputOutputFile(0)) {
            try stderr.print("{s}: -: input file is output file\n", .{name});
            return 1;
        }
        try processFile(std.Io.File.stdin(), stdout, any_options, number, number_nonblank, show_ends, show_tabs, show_nonprinting, squeeze_blank, &line_num, &consecutive_newlines, &at_line_start, &pending_cr);
    } else {
        for (args[file_start..]) |filename| {
            if (std.mem.eql(u8, filename, "-")) {
                if (isInputOutputFile(0)) {
                    try stderr.print("{s}: -: input file is output file\n", .{name});
                    exit_status = 1;
                    continue;
                }
                try processFile(std.Io.File.stdin(), stdout, any_options, number, number_nonblank, show_ends, show_tabs, show_nonprinting, squeeze_blank, &line_num, &consecutive_newlines, &at_line_start, &pending_cr);
                try stdout.flush();
            } else {
                const file = std.Io.Dir.cwd().openFile(std.Options.debug_io, filename, .{ .mode = .read_only }) catch |err| {
                    try errors.printErrorWithArg(stderr, name, filename, err);
                    exit_status = 1;
                    continue;
                };
                defer file.close(std.Options.debug_io);

                if (isInputOutputFile(file.handle)) {
                    try stderr.print("{s}: {s}: input file is output file\n", .{ name, filename });
                    exit_status = 1;
                    continue;
                }

                try processFile(file, stdout, any_options, number, number_nonblank, show_ends, show_tabs, show_nonprinting, squeeze_blank, &line_num, &consecutive_newlines, &at_line_start, &pending_cr);
                try stdout.flush();
            }
        }
    }

    if (pending_cr) {
        try stdout.writeByte('\r');
        pending_cr = false;
    }

    return exit_status;
}

fn processFile(
    file: std.Io.File,
    writer: anytype,
    any_options: bool,
    number: bool,
    number_nonblank: bool,
    show_ends: bool,
    show_tabs: bool,
    show_nonprinting: bool,
    squeeze_blank: bool,
    line_num: *usize,
    consecutive_newlines: *usize,
    at_line_start: *bool,
    pending_cr: *bool,
) !void {
    var inbuf: [16384]u8 = undefined;

    if (!any_options) {
        while (true) {
            var n_to_read: c_int = 0;
            const input_pending = if (c.ioctl(file.handle, c.FIONREAD, &n_to_read) == 0) (n_to_read > 0) else true;
            if (!input_pending) {
                try writer.flush();
            }

            const n_read = c.read(file.handle, &inbuf, inbuf.len);
            if (n_read < 0) {
                if (c.__errno_location().* == c.EINTR) continue;
                return error.ReadError;
            }
            if (n_read == 0) break;
            try writer.writeAll(inbuf[0..@intCast(n_read)]);
        }
        return;
    }

    while (true) {
        var n_to_read: c_int = 0;
        const input_pending = if (c.ioctl(file.handle, c.FIONREAD, &n_to_read) == 0) (n_to_read > 0) else true;
        if (!input_pending) {
            try writer.flush();
        }

        const n_read = c.read(file.handle, &inbuf, inbuf.len);
        if (n_read < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            return error.ReadError;
        }
        if (n_read == 0) break;

        for (inbuf[0..@intCast(n_read)]) |byte| {
            if (show_ends and byte == '\r') {
                if (pending_cr.*) {
                    try writer.writeByte('\r');
                }
                pending_cr.* = true;
                continue;
            }

            if (pending_cr.*) {
                if (byte == '\n') {
                    try writer.writeAll("^M");
                } else {
                    try writer.writeByte('\r');
                }
                pending_cr.* = false;
            }

            if (at_line_start.*) {
                if (byte == '\n') {
                    consecutive_newlines.* += 1;
                    if (squeeze_blank and consecutive_newlines.* > 1) {
                        continue;
                    }
                } else {
                    consecutive_newlines.* = 0;
                }

                if (number_nonblank) {
                    if (byte != '\n') {
                        try writer.print("{d:>6}\t", .{line_num.*});
                        line_num.* += 1;
                    }
                } else if (number) {
                    try writer.print("{d:>6}\t", .{line_num.*});
                    line_num.* += 1;
                }
                at_line_start.* = false;
            }

            if (byte == '\n') {
                if (show_ends) try writer.writeByte('$');
                try writer.writeByte('\n');
                at_line_start.* = true;
            } else if (byte == '\t' and !show_tabs) {
                try writer.writeByte('\t');
            } else if (byte == '\t' and show_tabs) {
                try writer.writeAll("^I");
            } else {
                if (show_nonprinting) {
                    if (byte < 32) {
                        try writer.print("^{c}", .{@as(u8, byte + 64)});
                    } else if (byte == 127) {
                        try writer.writeAll("^?");
                    } else if (byte >= 128) {
                        try writer.writeAll("M-");
                        const next = byte - 128;
                        if (next < 32) {
                            try writer.print("^{c}", .{@as(u8, next + 64)});
                        } else if (next == 127) {
                            try writer.writeAll("^?");
                        } else {
                            try writer.writeByte(next);
                        }
                    } else {
                        try writer.writeByte(byte);
                    }
                } else {
                    try writer.writeByte(byte);
                }
            }
        }
    }
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: cat [OPTION]... [FILE]...
        \\Concatenate FILE(s) to standard output.
        \\
        \\With no FILE, or when FILE is -, read standard input.
        \\
        \\  -A, --show-all           equivalent to -vET
        \\  -b, --number-nonblank    number nonempty output lines, overrides -n
        \\  -e                       equivalent to -vE
        \\  -E, --show-ends          display $ at end of each line
        \\  -n, --number             number all output lines
        \\  -s, --squeeze-blank      suppress repeated empty output lines
        \\  -t                       equivalent to -vT
        \\  -T, --show-tabs          display TAB characters as ^I
        \\  -u                       (ignored)
        \\  -v, --show-nonprinting   use ^ and M- notation, except for LFD and TAB
        \\      --help     display this help and exit
        \\      --version  output version information and exit
        \\
        \\Examples:
        \\  cat f - g  Output f's contents, then standard input, then g's contents.
        \\  cat        Copy standard input to standard output.
        \\
        \\GNU coreutils online help: <https://www.gnu.org/software/coreutils/>
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}

fn isInputOutputFile(in_fd: i32) bool {
    var istat: c.struct_stat = undefined;
    var ostat: c.struct_stat = undefined;
    if (c.fstat(in_fd, &istat) != 0) return false;
    if (c.fstat(1, &ostat) != 0) return false;

    // Must be same inode and device
    if (istat.st_ino != ostat.st_ino or istat.st_dev != ostat.st_dev) {
        return false;
    }

    // Check file types (not pipes/sockets)
    if (c.S_ISFIFO(istat.st_mode) or c.S_ISSOCK(istat.st_mode)) return false;

    const in_pos = c.lseek(in_fd, 0, c.SEEK_CUR);
    if (in_pos < 0) return false;

    const out_flags = c.fcntl(1, c.F_GETFL);
    const whence: c_int = if (out_flags >= 0 and (out_flags & c.O_APPEND) != 0) c.SEEK_END else c.SEEK_CUR;
    const out_pos = c.lseek(1, 0, whence);
    if (out_pos < 0) return false;

    return in_pos < out_pos;
}
