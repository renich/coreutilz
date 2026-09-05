const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "cat";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buffer: [16384]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .init(.stderr(), std.Options.debug_io, &stderr_buffer);
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
                try printHelp(stdout);
                return 0;
            } else if (std.mem.eql(u8, arg, "--version")) {
                try printVersion(stdout);
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
            for (arg[1..]) |c| {
                switch (c) {
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
                        const msg = try std.fmt.allocPrint(allocator, "invalid option -- '{c}'", .{c});
                        defer allocator.free(msg);
                        try errors.printError(stderr, name, msg);
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

    const stdout_file = std.Io.File.stdout();
    const stdout_stat = stdout_file.stat(std.Options.debug_io) catch null;

    if (file_start >= args.len) {
        try processFile(std.Io.File.stdin(), stdout, any_options, number, number_nonblank, show_ends, show_tabs, show_nonprinting, squeeze_blank, &line_num, &consecutive_newlines, &at_line_start, &pending_cr);
    } else {
        for (args[file_start..]) |filename| {
            if (std.mem.eql(u8, filename, "-")) {
                try processFile(std.Io.File.stdin(), stdout, any_options, number, number_nonblank, show_ends, show_tabs, show_nonprinting, squeeze_blank, &line_num, &consecutive_newlines, &at_line_start, &pending_cr);
            } else {
                const file = std.Io.Dir.cwd().openFile(std.Options.debug_io, filename, .{ .mode = .read_only }) catch |err| {
                    try errors.printErrorWithArg(stderr, name, filename, err);
                    exit_status = 1;
                    continue;
                };
                defer file.close(std.Options.debug_io);

                if (stdout_stat) |out_st| {
                    if (out_st.kind == .file and out_st.inode != 0) {
                        if (file.stat(std.Options.debug_io)) |in_st| {
                            if (in_st.kind == .file and in_st.inode == out_st.inode) {
                                const msg = try std.fmt.allocPrint(allocator, "{s}: input file is output file", .{filename});
                                defer allocator.free(msg);
                                try errors.printError(stderr, name, msg);
                                exit_status = 1;
                                continue;
                            }
                        } else |_| {}
                    }
                }

                try processFile(file, stdout, any_options, number, number_nonblank, show_ends, show_tabs, show_nonprinting, squeeze_blank, &line_num, &consecutive_newlines, &at_line_start, &pending_cr);
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
    var r_buf: [16384]u8 = undefined;
    var r = file.readerStreaming(std.Options.debug_io, &r_buf);
    const reader = &r.interface;

    if (!any_options) {
        var buffer: [16384]u8 = undefined;
        while (true) {
            const bytes_read = try reader.readSliceShort(&buffer);
            if (bytes_read == 0) break;
            try writer.writeAll(buffer[0..bytes_read]);
        }
        return;
    }

    while (true) {
        const byte = reader.takeByte() catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };

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
