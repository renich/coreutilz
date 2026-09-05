const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "tee";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buffer: [16384]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var append = false;
    var ignore_interrupts = false;
    var file_start: usize = args.len;

    var i: usize = 1;
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
            } else if (std.mem.eql(u8, arg, "--append")) {
                append = true;
            } else if (std.mem.eql(u8, arg, "--ignore-interrupts")) {
                ignore_interrupts = true;
            } else if (std.mem.startsWith(u8, arg, "--output-error")) {
                // Supported option; default is to continue on error
            } else {
                try stderr.print("tee: unrecognized option '{s}'\n", .{arg});
                return 1;
            }
        } else {
            // Short options
            var j: usize = 1;
            while (j < arg.len) : (j += 1) {
                const c = arg[j];
                switch (c) {
                    'a' => append = true,
                    'i' => ignore_interrupts = true,
                    'p' => {},
                    else => {
                        try stderr.print("tee: invalid option -- '{c}'\n", .{c});
                        return 1;
                    },
                }
            }
        }
    }

    if (ignore_interrupts) {
        var act = std.posix.Sigaction{
            .handler = .{ .handler = std.posix.SIG.IGN },
            .mask = std.mem.zeroes(std.posix.sigset_t),
            .flags = 0,
        };
        _ = std.posix.sigaction(std.posix.SIG.INT, &act, null);
    }

    var out_files: std.ArrayList(std.Io.File) = .empty;
    defer {
        for (out_files.items) |f| {
            f.close(std.Options.debug_io);
        }
        out_files.deinit(allocator);
    }

    var exit_status: u8 = 0;

    if (file_start < args.len) {
        for (args[file_start..]) |filename| {
            if (std.mem.eql(u8, filename, "-")) {
                // "-" is treated as stdout, but stdout is already written to unconditionally
                continue;
            }

            const file = if (append)
                std.Io.Dir.cwd().createFile(std.Options.debug_io, filename, .{ .truncate = false }) catch |err| {
                    try stderr.print("tee: {s}: {s}\n", .{ filename, @errorName(err) });
                    exit_status = 1;
                    continue;
                }
            else
                std.Io.Dir.cwd().createFile(std.Options.debug_io, filename, .{ .truncate = true }) catch |err| {
                    try stderr.print("tee: {s}: {s}\n", .{ filename, @errorName(err) });
                    exit_status = 1;
                    continue;
                };

            if (append) {
                _ = std.os.linux.lseek(file.handle, 0, 2); // SEEK_END
            }

            try out_files.append(allocator, file);
        }
    }

    var r_buf: [16384]u8 = undefined;
    var r = std.Io.File.stdin().readerStreaming(std.Options.debug_io, &r_buf);
    const reader = &r.interface;

    var buf: [16384]u8 = undefined;

    while (true) {
        const n = try reader.readSliceShort(&buf);
        if (n == 0) break;

        const slice = buf[0..n];
        try stdout.writeAll(slice);
        try stdout.flush();

        for (out_files.items) |file| {
            var w_buf: [16384]u8 = undefined;
            var w = std.Io.File.Writer.initStreaming(file, std.Options.debug_io, &w_buf);
            const writer = &w.interface;
            try writer.writeAll(slice);
            try writer.flush();
        }
    }

    return exit_status;
}

fn printHelp(writer: anytype) !void {
    try writer.print(
        \\Usage: {s} [OPTION]... [FILE]...
        \\Copy standard input to each FILE, and also to standard output.
        \\
        \\  -a, --append              append to the given FILEs, do not overwrite
        \\  -i, --ignore-interrupts   ignore interrupt signals
        \\  -p                        diagnose errors writing to non pipes
        \\      --output-error[=MODE]   set behavior on write error.  See MODE below
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
        \\MODE determines behavior with write errors on the outputs:
        \\  warn         diagnose errors writing to any output
        \\  warn-nopipe  diagnose errors writing to any output not a pipe
        \\  exit         exit on error writing to any output
        \\  exit-nopipe  exit on error writing to any output not a pipe
        \\The default MODE for the -p option is 'warn-nopipe'.
        \\
    , .{name});
}

fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
