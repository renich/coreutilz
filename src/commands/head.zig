const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "head";
pub const version: []const u8 = "0.1.0";

const HeaderMode = enum {
    multiple,
    always,
    never,
};

fn parseNumber(str: []const u8) !usize {
    if (str.len == 0) return error.InvalidNumber;
    var multiplier: usize = 1;
    var num_part = str;

    if (std.mem.endsWith(u8, str, "KiB")) {
        multiplier = 1024;
        num_part = str[0 .. str.len - 3];
    } else if (std.mem.endsWith(u8, str, "MiB")) {
        multiplier = 1024 * 1024;
        num_part = str[0 .. str.len - 3];
    } else if (std.mem.endsWith(u8, str, "GiB")) {
        multiplier = 1024 * 1024 * 1024;
        num_part = str[0 .. str.len - 3];
    } else if (std.mem.endsWith(u8, str, "TiB")) {
        multiplier = 1024 * 1024 * 1024 * 1024;
        num_part = str[0 .. str.len - 3];
    } else if (std.mem.endsWith(u8, str, "kB")) {
        multiplier = 1000;
        num_part = str[0 .. str.len - 2];
    } else if (std.mem.endsWith(u8, str, "MB")) {
        multiplier = 1000 * 1000;
        num_part = str[0 .. str.len - 2];
    } else if (std.mem.endsWith(u8, str, "GB")) {
        multiplier = 1000 * 1000 * 1000;
        num_part = str[0 .. str.len - 2];
    } else if (std.mem.endsWith(u8, str, "TB")) {
        multiplier = 1000 * 1000 * 1000 * 1000;
        num_part = str[0 .. str.len - 2];
    } else if (str.len > 0) {
        const last = str[str.len - 1];
        switch (last) {
            'b' => {
                multiplier = 512;
                num_part = str[0 .. str.len - 1];
            },
            'k', 'K' => {
                multiplier = 1024;
                num_part = str[0 .. str.len - 1];
            },
            'm', 'M' => {
                multiplier = 1024 * 1024;
                num_part = str[0 .. str.len - 1];
            },
            'g', 'G' => {
                multiplier = 1024 * 1024 * 1024;
                num_part = str[0 .. str.len - 1];
            },
            't', 'T' => {
                multiplier = 1024 * 1024 * 1024 * 1024;
                num_part = str[0 .. str.len - 1];
            },
            '0'...'9' => {},
            else => return error.InvalidNumber,
        }
    }

    if (num_part.len == 0) return error.InvalidNumber;
    const val = std.fmt.parseInt(usize, num_part, 10) catch return error.InvalidNumber;
    return val * multiplier;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buffer: [16384]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var count_lines = true;
    var n_units: usize = 10;
    var elide_from_end = false;
    var header_mode: HeaderMode = .multiple;
    var line_delim: u8 = '\n';

    var file_start: usize = args.len;
    var i: usize = 1;

    // Check for obsolete syntax like -5 or -100
    if (args.len > 1 and args[1].len > 1 and args[1][0] == '-' and std.ascii.isDigit(args[1][1])) {
        const opt = args[1][1..];
        var end_idx: usize = 0;
        while (end_idx < opt.len and std.ascii.isDigit(opt[end_idx])) : (end_idx += 1) {}
        n_units = std.fmt.parseInt(usize, opt[0..end_idx], 10) catch 10;
        count_lines = true;
        elide_from_end = false;

        var suffix = opt[end_idx..];
        while (suffix.len > 0) {
            switch (suffix[0]) {
                'c' => count_lines = false,
                'q' => header_mode = .never,
                'v' => header_mode = .always,
                'z' => line_delim = 0,
                else => {},
            }
            suffix = suffix[1..];
        }
        i = 2;
    }

    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-")) {
            file_start = i;
            break;
        }
        if (std.mem.eql(u8, arg, "--")) {
            file_start = i + 1;
            break;
        }
        if (!std.mem.startsWith(u8, arg, "-") or arg.len == 1) {
            file_start = i;
            break;
        }

        if (std.mem.startsWith(u8, arg, "--")) {
            if (std.mem.eql(u8, arg, "--help")) {
                try printHelp(stdout);
                return 0;
            } else if (std.mem.eql(u8, arg, "--version")) {
                try printVersion(stdout);
                return 0;
            } else if (std.mem.startsWith(u8, arg, "--lines=")) {
                var val_str = arg["--lines=".len..];
                elide_from_end = false;
                if (val_str.len > 0 and val_str[0] == '-') {
                    elide_from_end = true;
                    val_str = val_str[1..];
                } else if (val_str.len > 0 and val_str[0] == '+') {
                    val_str = val_str[1..];
                }
                count_lines = true;
                n_units = parseNumber(val_str) catch {
                    try stderr.print("head: invalid number of lines: '{s}'\n", .{arg["--lines=".len..]});
                    return 1;
                };
            } else if (std.mem.eql(u8, arg, "--lines")) {
                i += 1;
                if (i >= args.len) {
                    try stderr.print("head: option '--lines' requires an argument\n", .{});
                    return 1;
                }
                var val_str = args[i];
                elide_from_end = false;
                if (val_str.len > 0 and val_str[0] == '-') {
                    elide_from_end = true;
                    val_str = val_str[1..];
                } else if (val_str.len > 0 and val_str[0] == '+') {
                    val_str = val_str[1..];
                }
                count_lines = true;
                n_units = parseNumber(val_str) catch {
                    try stderr.print("head: invalid number of lines: '{s}'\n", .{args[i]});
                    return 1;
                };
            } else if (std.mem.startsWith(u8, arg, "--bytes=")) {
                var val_str = arg["--bytes=".len..];
                elide_from_end = false;
                if (val_str.len > 0 and val_str[0] == '-') {
                    elide_from_end = true;
                    val_str = val_str[1..];
                } else if (val_str.len > 0 and val_str[0] == '+') {
                    val_str = val_str[1..];
                }
                count_lines = false;
                n_units = parseNumber(val_str) catch {
                    try stderr.print("head: invalid number of bytes: '{s}'\n", .{arg["--bytes=".len..]});
                    return 1;
                };
            } else if (std.mem.eql(u8, arg, "--bytes")) {
                i += 1;
                if (i >= args.len) {
                    try stderr.print("head: option '--bytes' requires an argument\n", .{});
                    return 1;
                }
                var val_str = args[i];
                elide_from_end = false;
                if (val_str.len > 0 and val_str[0] == '-') {
                    elide_from_end = true;
                    val_str = val_str[1..];
                } else if (val_str.len > 0 and val_str[0] == '+') {
                    val_str = val_str[1..];
                }
                count_lines = false;
                n_units = parseNumber(val_str) catch {
                    try stderr.print("head: invalid number of bytes: '{s}'\n", .{args[i]});
                    return 1;
                };
            } else if (std.mem.eql(u8, arg, "--quiet") or std.mem.eql(u8, arg, "--silent")) {
                header_mode = .never;
            } else if (std.mem.eql(u8, arg, "--verbose")) {
                header_mode = .always;
            } else if (std.mem.eql(u8, arg, "--zero-terminated")) {
                line_delim = 0;
            } else {
                try stderr.print("head: unrecognized option '{s}'\n", .{arg});
                return 1;
            }
        } else {
            // Short options
            var j: usize = 1;
            while (j < arg.len) : (j += 1) {
                const c = arg[j];
                switch (c) {
                    'n' => {
                        count_lines = true;
                        var val_str: []const u8 = undefined;
                        if (j + 1 < arg.len) {
                            val_str = arg[j + 1 ..];
                            j = arg.len;
                        } else {
                            i += 1;
                            if (i >= args.len) {
                                try stderr.print("head: option requires an argument -- 'n'\n", .{});
                                return 1;
                            }
                            val_str = args[i];
                        }
                        const orig_val = val_str;
                        elide_from_end = false;
                        if (val_str.len > 0 and val_str[0] == '-') {
                            elide_from_end = true;
                            val_str = val_str[1..];
                        } else if (val_str.len > 0 and val_str[0] == '+') {
                            val_str = val_str[1..];
                        }
                        n_units = parseNumber(val_str) catch {
                            try stderr.print("head: invalid number of lines: '{s}'\n", .{orig_val});
                            return 1;
                        };
                    },
                    'c' => {
                        count_lines = false;
                        var val_str: []const u8 = undefined;
                        if (j + 1 < arg.len) {
                            val_str = arg[j + 1 ..];
                            j = arg.len;
                        } else {
                            i += 1;
                            if (i >= args.len) {
                                try stderr.print("head: option requires an argument -- 'c'\n", .{});
                                return 1;
                            }
                            val_str = args[i];
                        }
                        const orig_val = val_str;
                        elide_from_end = false;
                        if (val_str.len > 0 and val_str[0] == '-') {
                            elide_from_end = true;
                            val_str = val_str[1..];
                        } else if (val_str.len > 0 and val_str[0] == '+') {
                            val_str = val_str[1..];
                        }
                        n_units = parseNumber(val_str) catch {
                            try stderr.print("head: invalid number of bytes: '{s}'\n", .{orig_val});
                            return 1;
                        };
                    },
                    'q' => header_mode = .never,
                    'v' => header_mode = .always,
                    'z' => line_delim = 0,
                    else => {
                        try stderr.print("head: invalid option -- '{c}'\n", .{c});
                        return 1;
                    },
                }
            }
        }
    }

    var files: [][]const u8 = undefined;
    const default_files = [_][]const u8{"-"};
    if (file_start < args.len) {
        files = @constCast(args[file_start..]);
    } else {
        files = @constCast(&default_files);
    }

    const print_headers = switch (header_mode) {
        .always => true,
        .never => false,
        .multiple => files.len > 1,
    };

    var first_header = true;
    var exit_status: u8 = 0;

    for (files) |filename| {
        const is_stdin = std.mem.eql(u8, filename, "-");
        const display_name = if (is_stdin) "standard input" else filename;

        var file: std.Io.File = undefined;
        var is_regular = false;
        var file_size: u64 = 0;

        if (is_stdin) {
            file = std.Io.File.stdin();
        } else {
            file = std.Io.Dir.cwd().openFile(std.Options.debug_io, filename, .{ .mode = .read_only }) catch |err| {
                const err_desc = switch (err) {
                    error.FileNotFound => "No such file or directory",
                    error.AccessDenied => "Permission denied",
                    error.IsDir => "Is a directory",
                    else => "Cannot open file",
                };
                try stderr.print("head: cannot open '{s}' for reading: {s}\n", .{ filename, err_desc });
                exit_status = 1;
                continue;
            };
        }
        defer if (!is_stdin) file.close(std.Options.debug_io);

        if (file.stat(std.Options.debug_io)) |st| {
            if (st.kind == .file) {
                is_regular = true;
                file_size = st.size;
            }
        } else |_| {}

        if (print_headers) {
            if (!first_header) {
                try stdout.writeByte('\n');
            }
            try stdout.print("==> {s} <==\n", .{display_name});
            try stdout.flush();
            first_header = false;
        }

        if (count_lines) {
            if (elide_from_end) {
                try processLinesElide(file, is_regular, is_stdin, n_units, line_delim, stdout, allocator);
            } else {
                try processLinesHead(file, n_units, line_delim, stdout);
            }
        } else {
            if (elide_from_end) {
                try processBytesElide(file, is_regular, file_size, n_units, stdout, allocator);
            } else {
                try processBytesHead(file, n_units, stdout);
            }
        }
        try stdout.flush();
    }

    return exit_status;
}

fn processBytesHead(file: std.Io.File, count: usize, stdout: anytype) !void {
    if (count == 0) return;
    var r_buf: [16384]u8 = undefined;
    var r = file.readerStreaming(std.Options.debug_io, &r_buf);
    const reader = &r.interface;

    var remaining = count;
    var buf: [16384]u8 = undefined;

    while (remaining > 0) {
        const to_read = @min(remaining, buf.len);
        const bytes_read = try reader.readSliceShort(buf[0..to_read]);
        if (bytes_read == 0) break;
        try stdout.writeAll(buf[0..bytes_read]);
        remaining -= bytes_read;
    }
}

fn processBytesElide(file: std.Io.File, is_regular: bool, file_size: u64, elide_count: usize, stdout: anytype, allocator: std.mem.Allocator) !void {
    if (elide_count == 0) {
        // Output entire file
        var r_buf: [16384]u8 = undefined;
        var r = file.readerStreaming(std.Options.debug_io, &r_buf);
        const reader = &r.interface;
        var buf: [16384]u8 = undefined;
        while (true) {
            const bytes_read = try reader.readSliceShort(&buf);
            if (bytes_read == 0) break;
            try stdout.writeAll(buf[0..bytes_read]);
        }
        return;
    }

    if (is_regular) {
        if (file_size <= elide_count) return;
        const to_output = file_size - elide_count;
        var r_buf: [16384]u8 = undefined;
        var r = file.readerStreaming(std.Options.debug_io, &r_buf);
        const reader = &r.interface;
        var remaining = to_output;
        var buf: [16384]u8 = undefined;
        while (remaining > 0) {
            const to_read = @min(remaining, buf.len);
            const bytes_read = try reader.readSliceShort(buf[0..to_read]);
            if (bytes_read == 0) break;
            try stdout.writeAll(buf[0..bytes_read]);
            remaining -= bytes_read;
        }
    } else {
        // Non-seekable stream: FIFO buffer of size elide_count
        var fifo = try std.ArrayList(u8).initCapacity(allocator, elide_count);
        defer fifo.deinit(allocator);

        var r_buf: [16384]u8 = undefined;
        var r = file.readerStreaming(std.Options.debug_io, &r_buf);
        const reader = &r.interface;
        var buf: [16384]u8 = undefined;

        while (true) {
            const bytes_read = try reader.readSliceShort(&buf);
            if (bytes_read == 0) break;

            for (buf[0..bytes_read]) |byte| {
                if (fifo.items.len == elide_count) {
                    try stdout.writeByte(fifo.items[0]);
                    _ = fifo.orderedRemove(0);
                }
                try fifo.append(allocator, byte);
            }
        }
    }
}

fn processLinesHead(file: std.Io.File, count: usize, delim: u8, stdout: anytype) !void {
    if (count == 0) return;
    var r_buf: [16384]u8 = undefined;
    var r = file.readerStreaming(std.Options.debug_io, &r_buf);
    const reader = &r.interface;

    var lines_done: usize = 0;
    var buf: [16384]u8 = undefined;

    while (lines_done < count) {
        const bytes_read = try reader.readSliceShort(&buf);
        if (bytes_read == 0) break;

        const start: usize = 0;
        for (buf[0..bytes_read], 0..) |b, idx| {
            if (b == delim) {
                lines_done += 1;
                if (lines_done == count) {
                    try stdout.writeAll(buf[start .. idx + 1]);
                    return;
                }
            }
        }
        try stdout.writeAll(buf[start..bytes_read]);
    }
}

fn processLinesElide(file: std.Io.File, is_regular: bool, is_stdin: bool, elide_count: usize, delim: u8, stdout: anytype, allocator: std.mem.Allocator) !void {
    if (elide_count == 0) {
        // Output entire file
        var r_buf: [16384]u8 = undefined;
        var r = file.readerStreaming(std.Options.debug_io, &r_buf);
        const reader = &r.interface;
        var buf: [16384]u8 = undefined;
        while (true) {
            const bytes_read = try reader.readSliceShort(&buf);
            if (bytes_read == 0) break;
            try stdout.writeAll(buf[0..bytes_read]);
        }
        return;
    }

    if (is_regular and !is_stdin) {
        // Pass 1: count lines
        var total_lines: usize = 0;
        var r_buf: [16384]u8 = undefined;
        var r = file.readerStreaming(std.Options.debug_io, &r_buf);
        var reader = &r.interface;
        var buf: [16384]u8 = undefined;
        var last_byte: ?u8 = null;

        while (true) {
            const bytes_read = try reader.readSliceShort(&buf);
            if (bytes_read == 0) break;
            for (buf[0..bytes_read]) |b| {
                if (b == delim) {
                    total_lines += 1;
                }
                last_byte = b;
            }
        }
        if (last_byte != null and last_byte.? != delim) {
            total_lines += 1;
        }

        if (total_lines <= elide_count) return;
        const to_output = total_lines - elide_count;

        // Pass 2: seek to 0 and output to_output lines
        _ = std.os.linux.lseek(file.handle, 0, 0);
        var r2 = file.readerStreaming(std.Options.debug_io, &r_buf);
        reader = &r2.interface;

        var lines_done: usize = 0;
        while (lines_done < to_output) {
            const bytes_read = try reader.readSliceShort(&buf);
            if (bytes_read == 0) break;

            const start: usize = 0;
            for (buf[0..bytes_read], 0..) |b, idx| {
                if (b == delim) {
                    lines_done += 1;
                    if (lines_done == to_output) {
                        try stdout.writeAll(buf[start .. idx + 1]);
                        return;
                    }
                }
            }
            try stdout.writeAll(buf[start..bytes_read]);
        }
    } else {
        // Stream / pipe: hold lines in circular list
        var line_list = try std.ArrayList(std.ArrayList(u8)).initCapacity(allocator, elide_count + 1);
        defer {
            for (line_list.items) |*item| item.deinit(allocator);
            line_list.deinit(allocator);
        }

        var current_line: std.ArrayList(u8) = .empty;
        defer current_line.deinit(allocator);

        var r_buf: [16384]u8 = undefined;
        var r = file.readerStreaming(std.Options.debug_io, &r_buf);
        const reader = &r.interface;
        var buf: [16384]u8 = undefined;

        while (true) {
            const bytes_read = try reader.readSliceShort(&buf);
            if (bytes_read == 0) break;

            for (buf[0..bytes_read]) |b| {
                try current_line.append(allocator, b);
                if (b == delim) {
                    var stored_line: std.ArrayList(u8) = .empty;
                    try stored_line.appendSlice(allocator, current_line.items);
                    current_line.clearRetainingCapacity();

                    if (line_list.items.len >= elide_count) {
                        var oldest = line_list.orderedRemove(0);
                        try stdout.writeAll(oldest.items);
                        oldest.deinit(allocator);
                    }
                    try line_list.append(allocator, stored_line);
                }
            }
        }

        if (current_line.items.len > 0) {
            var stored_line: std.ArrayList(u8) = .empty;
            try stored_line.appendSlice(allocator, current_line.items);
            if (line_list.items.len >= elide_count) {
                var oldest = line_list.orderedRemove(0);
                try stdout.writeAll(oldest.items);
                oldest.deinit(allocator);
            }
            try line_list.append(allocator, stored_line);
        }
    }
}

fn printHelp(writer: anytype) !void {
    try writer.print(
        \\Usage: {s} [OPTION]... [FILE]...
        \\Print the first 10 lines of each FILE to standard output.
        \\With more than one FILE, precede each with a header giving the file name.
        \\
        \\With no FILE, or when FILE is -, read standard input.
        \\
        \\Mandatory arguments to long options are mandatory for short options too.
        \\  -c, --bytes=[-]NUM       print the first NUM bytes of each file;
        \\                             with the leading '-', print all but the last
        \\                             NUM bytes of each file
        \\  -n, --lines=[-]NUM       print the first NUM lines instead of the first 10;
        \\                             with the leading '-', print all but the last
        \\                             NUM lines of each file
        \\  -q, --quiet, --silent    never print headers giving file names
        \\  -v, --verbose            always print headers giving file names
        \\  -z, --zero-terminated    line delimiter is NUL, not newline
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
        \\NUM may have a multiplier suffix:
        \\b 512, kB 1000, K 1024, MB 1000*1000, M 1024*1024,
        \\GB 1000*1000*1000, G 1024*1024*1024, and so on for T, P, E, Z, Y.
        \\
    , .{name});
}

fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
