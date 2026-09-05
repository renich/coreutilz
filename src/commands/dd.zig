const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "dd";
pub const version: []const u8 = "0.1.0";

fn parseSize(str: []const u8) !usize {
    if (str.len == 0) return error.InvalidNumber;

    var num_part = str;
    var multiplier: usize = 1;

    if (std.mem.endsWith(u8, str, "KiB") or std.mem.endsWith(u8, str, "kib")) {
        multiplier = 1024;
        num_part = str[0 .. str.len - 3];
    } else if (std.mem.endsWith(u8, str, "MiB") or std.mem.endsWith(u8, str, "mib")) {
        multiplier = 1024 * 1024;
        num_part = str[0 .. str.len - 3];
    } else if (std.mem.endsWith(u8, str, "GiB") or std.mem.endsWith(u8, str, "gib")) {
        multiplier = 1024 * 1024 * 1024;
        num_part = str[0 .. str.len - 3];
    } else if (std.mem.endsWith(u8, str, "KB") or std.mem.endsWith(u8, str, "kb")) {
        multiplier = 1000;
        num_part = str[0 .. str.len - 2];
    } else if (std.mem.endsWith(u8, str, "MB") or std.mem.endsWith(u8, str, "mb")) {
        multiplier = 1000 * 1000;
        num_part = str[0 .. str.len - 2];
    } else if (std.mem.endsWith(u8, str, "GB") or std.mem.endsWith(u8, str, "gb")) {
        multiplier = 1000 * 1000 * 1000;
        num_part = str[0 .. str.len - 2];
    } else if (str.len > 0) {
        const last = str[str.len - 1];
        switch (last) {
            'c' => {
                multiplier = 1;
                num_part = str[0 .. str.len - 1];
            },
            'w' => {
                multiplier = 2;
                num_part = str[0 .. str.len - 1];
            },
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

    const val = try std.fmt.parseInt(usize, num_part, 10);
    return val * multiplier;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), std.Options.debug_io, &stdout_buf);
    var stderr_writer: std.Io.File.Writer = .init(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var if_path: ?[]const u8 = null;
    var of_path: ?[]const u8 = null;
    var ibs: usize = 512;
    var obs: usize = 512;
    var count: ?usize = null;
    var skip: usize = 0;
    var seek: usize = 0;

    var conv_ucase = false;
    var conv_lcase = false;
    var conv_sync = false;
    var conv_noerror = false;
    var conv_notrunc = false;

    var status_progress = false;
    var status_noxfer = false;
    var status_none = false;

    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            try printHelp(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try printVersion(stdout);
            return 0;
        } else if (std.mem.startsWith(u8, arg, "if=")) {
            if_path = arg["if=".len..];
        } else if (std.mem.startsWith(u8, arg, "of=")) {
            of_path = arg["of=".len..];
        } else if (std.mem.startsWith(u8, arg, "bs=")) {
            const size = parseSize(arg["bs=".len..]) catch {
                try errors.printError(stderr, name, "invalid number");
                return 1;
            };
            ibs = size;
            obs = size;
        } else if (std.mem.startsWith(u8, arg, "ibs=")) {
            ibs = parseSize(arg["ibs=".len..]) catch {
                try errors.printError(stderr, name, "invalid number");
                return 1;
            };
        } else if (std.mem.startsWith(u8, arg, "obs=")) {
            obs = parseSize(arg["obs=".len..]) catch {
                try errors.printError(stderr, name, "invalid number");
                return 1;
            };
        } else if (std.mem.startsWith(u8, arg, "count=")) {
            count = parseSize(arg["count=".len..]) catch {
                try errors.printError(stderr, name, "invalid number");
                return 1;
            };
        } else if (std.mem.startsWith(u8, arg, "skip=")) {
            skip = parseSize(arg["skip=".len..]) catch {
                try errors.printError(stderr, name, "invalid number");
                return 1;
            };
        } else if (std.mem.startsWith(u8, arg, "seek=")) {
            seek = parseSize(arg["seek=".len..]) catch {
                try errors.printError(stderr, name, "invalid number");
                return 1;
            };
        } else if (std.mem.startsWith(u8, arg, "conv=")) {
            var it = std.mem.splitScalar(u8, arg["conv=".len..], ',');
            while (it.next()) |opt| {
                if (std.mem.eql(u8, opt, "ucase")) {
                    conv_ucase = true;
                } else if (std.mem.eql(u8, opt, "lcase")) {
                    conv_lcase = true;
                } else if (std.mem.eql(u8, opt, "sync")) {
                    conv_sync = true;
                } else if (std.mem.eql(u8, opt, "noerror")) {
                    conv_noerror = true;
                } else if (std.mem.eql(u8, opt, "notrunc")) {
                    conv_notrunc = true;
                }
            }
        } else if (std.mem.startsWith(u8, arg, "status=")) {
            const s = arg["status=".len..];
            if (std.mem.eql(u8, s, "progress")) {
                status_progress = true;
            } else if (std.mem.eql(u8, s, "noxfer")) {
                status_noxfer = true;
            } else if (std.mem.eql(u8, s, "none")) {
                status_none = true;
            }
        } else if (std.mem.startsWith(u8, arg, "iflag=") or std.mem.startsWith(u8, arg, "oflag=")) {
            // Options accepted
        } else {
            const msg = try std.fmt.allocPrint(allocator, "unrecognized operand '{s}'", .{arg});
            defer allocator.free(msg);
            try errors.printError(stderr, name, msg);
            return 1;
        }
    }

    var if_file: std.Io.File = undefined;
    var if_needs_close = false;

    if (if_path) |path| {
        if_file = std.Io.Dir.cwd().openFile(std.Options.debug_io, path, .{ .mode = .read_only }) catch |err| {
            try errors.printErrorWithArg(stderr, name, path, err);
            return 1;
        };
        if_needs_close = true;
    } else {
        if_file = std.Io.File.stdin();
    }
    defer if (if_needs_close) if_file.close(std.Options.debug_io);

    var of_file: std.Io.File = undefined;
    var of_needs_close = false;

    if (of_path) |path| {
        if (seek > 0 or conv_notrunc) {
            of_file = std.Io.Dir.cwd().openFile(std.Options.debug_io, path, .{ .mode = .read_write }) catch |err| switch (err) {
                error.FileNotFound => std.Io.Dir.cwd().createFile(std.Options.debug_io, path, .{}) catch |e2| {
                    try errors.printErrorWithArg(stderr, name, path, e2);
                    return 1;
                },
                else => {
                    try errors.printErrorWithArg(stderr, name, path, err);
                    return 1;
                },
            };
        } else {
            of_file = std.Io.Dir.cwd().createFile(std.Options.debug_io, path, .{}) catch |err| {
                try errors.printErrorWithArg(stderr, name, path, err);
                return 1;
            };
        }
        of_needs_close = true;
    } else {
        of_file = std.Io.File.stdout();
    }
    defer if (of_needs_close) of_file.close(std.Options.debug_io);

    var if_r_buf: [64 * 1024]u8 = undefined;
    var if_r = if_file.readerStreaming(std.Options.debug_io, &if_r_buf);
    const if_reader = &if_r.interface;

    var of_w_buf: [64 * 1024]u8 = undefined;
    var of_w: std.Io.File.Writer = .initStreaming(of_file, std.Options.debug_io, &of_w_buf);
    const of_writer = &of_w.interface;
    defer of_writer.flush() catch {};

    // Skip input blocks
    var skip_left = skip * ibs;
    while (skip_left > 0) {
        var discard_buf: [8192]u8 = undefined;
        const to_read = @min(skip_left, discard_buf.len);
        const n = if_reader.readSliceShort(discard_buf[0..to_read]) catch |err| {
            if (conv_noerror) break;
            try errors.printErrorWithArg(stderr, name, if_path orelse "standard input", err);
            return 1;
        };
        if (n == 0) break;
        skip_left -= n;
    }

    // Seek output
    if (seek > 0) {
        _ = std.os.linux.lseek(of_file.handle, @intCast(seek * obs), 0);
    }

    const buf_size = @max(ibs, obs);
    const buffer = try allocator.alloc(u8, buf_size);
    defer allocator.free(buffer);

    var records_in_full: usize = 0;
    var records_in_partial: usize = 0;
    var records_out_full: usize = 0;
    var records_out_partial: usize = 0;
    var total_bytes_copied: usize = 0;

    var in_block_count: usize = 0;

    while (true) {
        if (count) |c| {
            if (in_block_count >= c) break;
        }

        var bytes_read: usize = 0;
        while (bytes_read < ibs) {
            const n = if_reader.readSliceShort(buffer[bytes_read..ibs]) catch |err| {
                if (conv_noerror) {
                    break;
                } else {
                    try errors.printErrorWithArg(stderr, name, if_path orelse "standard input", err);
                    return 1;
                }
            };
            if (n == 0) break;
            bytes_read += n;
        }

        if (bytes_read == 0) break;

        in_block_count += 1;
        if (bytes_read == ibs) {
            records_in_full += 1;
        } else {
            records_in_partial += 1;
        }

        if (conv_sync and bytes_read < ibs) {
            @memset(buffer[bytes_read..ibs], 0);
            bytes_read = ibs;
        }

        if (conv_ucase) {
            for (buffer[0..bytes_read]) |*b| {
                b.* = std.ascii.toUpper(b.*);
            }
        }
        if (conv_lcase) {
            for (buffer[0..bytes_read]) |*b| {
                b.* = std.ascii.toLower(b.*);
            }
        }

        of_writer.writeAll(buffer[0..bytes_read]) catch |err| {
            try errors.printErrorWithArg(stderr, name, of_path orelse "standard output", err);
            return 1;
        };

        total_bytes_copied += bytes_read;

        if (bytes_read == obs) {
            records_out_full += 1;
        } else {
            records_out_partial += 1;
        }

        if (status_progress) {
            try stderr.print("{d} bytes ({d} B) copied\r", .{ total_bytes_copied, total_bytes_copied });
            try stderr.flush();
        }
    }

    try of_writer.flush();

    if (!status_none) {
        if (status_progress) {
            try stderr.print("\n", .{});
        }
        try stderr.print("{d}+{d} records in\n", .{ records_in_full, records_in_partial });
        try stderr.print("{d}+{d} records out\n", .{ records_out_full, records_out_partial });
        if (!status_noxfer) {
            try stderr.print("{d} bytes copied\n", .{total_bytes_copied});
        }
        try stderr.flush();
    }

    return 0;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: dd [OPERAND]...
        \\  or:  dd OPTION
        \\Copy a file, converting and formatting according to the operands.
        \\
        \\  bs=BYTES        read and write up to BYTES bytes at a time
        \\  cbs=BYTES       convert BYTES bytes at a time
        \\  conv=CONVS      convert the file as per the comma separated symbol list
        \\  count=N         copy only N input blocks
        \\  ibs=BYTES       read up to BYTES bytes at a time (default: 512)
        \\  if=FILE         read from FILE instead of stdin
        \\  iflag=FLAGS     read as per the comma separated symbol list
        \\  obs=BYTES       write BYTES bytes at a time (default: 512)
        \\  of=FILE         write to FILE instead of stdout
        \\  oflag=FLAGS     write as per the comma separated symbol list
        \\  seek=N          (or oseek=N) skip N obs-sized blocks at start of output
        \\  skip=N          (or iseek=N) skip N ibs-sized blocks at start of input
        \\  status=LEVEL    The LEVEL of information to print to stderr;
        \\                  'none' suppresses everything but error messages,
        \\                  'noxfer' suppresses the final transfer statistics,
        \\                  'progress' shows periodic transfer statistics
        \\      --help      display this help and exit
        \\      --version   output version information and exit
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
