const std = @import("std");
const c = @import("../compat/c.zig").c;
const sum_alg = @import("cksum/sum.zig");

pub const name: []const u8 = "sum";
pub const version: []const u8 = "0.1.0";

const SumMode = enum {
    bsd,
    sysv,
};

fn printHelp(stdout: anytype) !void {
    try stdout.print(
        \\Usage: {s} [OPTION]... [FILE]...
        \\Print or verify checksums and block counts.
        \\
        \\  -r              use BSD sum algorithm, use 1K blocks (default)
        \\  -s, --sysv      use System V sum algorithm, use 512-byte blocks
        \\      --help      display this help and exit
        \\      --version   output version information and exit
        \\
        \\With no FILE, or when FILE is -, read standard input.
        \\
    , .{name});
}

const SumResult = struct {
    checksum: u16,
    blocks: u64,
};

fn processBsd(fd: std.posix.fd_t) !SumResult {
    var hasher = sum_alg.BsdSum.init();
    var buf: [16384]u8 = undefined;
    while (true) {
        const n = try std.posix.read(fd, &buf);
        if (n == 0) break;
        hasher.update(buf[0..n]);
    }
    const res = hasher.final();
    return .{ .checksum = res.checksum, .blocks = res.blocks };
}

fn processSysv(fd: std.posix.fd_t) !SumResult {
    var hasher = sum_alg.SysvSum.init();
    var buf: [16384]u8 = undefined;
    while (true) {
        const n = try std.posix.read(fd, &buf);
        if (n == 0) break;
        hasher.update(buf[0..n]);
    }
    const res = hasher.final();
    return .{ .checksum = res.checksum, .blocks = res.blocks };
}

fn processFile(
    file_arg: ?[]const u8,
    mode: SumMode,
    stdout: anytype,
    stderr: anytype,
) !bool {
    const is_stdin = file_arg == null or std.mem.eql(u8, file_arg.?, "-");
    const fd: std.posix.fd_t = if (is_stdin) std.posix.STDIN_FILENO else blk: {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        const fname = file_arg.?;
        if (fname.len >= path_buf.len) {
            try stderr.print("{s}: {s}: File name too long\n", .{ name, fname });
            return false;
        }
        @memcpy(path_buf[0..fname.len], fname);
        path_buf[fname.len] = 0;
        const file_z = c.open(&path_buf, c.O_RDONLY | c.O_CLOEXEC, @as(c_uint, 0));
        if (file_z < 0) {
            const err_str = std.mem.span(c.strerror(c.__errno_location().*));
            try stderr.print("{s}: {s}: {s}\n", .{ name, fname, err_str });
            return false;
        }
        break :blk file_z;
    };

    defer {
        if (!is_stdin) _ = c.close(fd);
    }

    const res = switch (mode) {
        .bsd => processBsd(fd) catch |err| {
            try stderr.print("{s}: {s}: {s}\n", .{ name, if (is_stdin) "-" else file_arg.?, @errorName(err) });
            return false;
        },
        .sysv => processSysv(fd) catch |err| {
            try stderr.print("{s}: {s}: {s}\n", .{ name, if (is_stdin) "-" else file_arg.?, @errorName(err) });
            return false;
        },
    };

    if (mode == .bsd) {
        if (file_arg) |f| {
            try stdout.print("{d:0>5} {d:>5} {s}\n", .{ res.checksum, res.blocks, f });
        } else {
            try stdout.print("{d:0>5} {d:>5}\n", .{ res.checksum, res.blocks });
        }
    } else {
        if (file_arg) |f| {
            try stdout.print("{d} {d} {s}\n", .{ res.checksum, res.blocks, f });
        } else {
            try stdout.print("{d} {d}\n", .{ res.checksum, res.blocks });
        }
    }
    return true;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &out_w.interface;
    const stderr = &err_w.interface;

    var mode: SumMode = .bsd;
    var files: std.ArrayListUnmanaged([]const u8) = .empty;
    defer files.deinit(allocator);

    var options_done = false;
    for (args[1..]) |arg| {
        if (!options_done and std.mem.eql(u8, arg, "--")) {
            options_done = true;
        } else if (!options_done and (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h"))) {
            try printHelp(stdout);
            stdout.flush() catch return 1;
            return 0;
        } else if (!options_done and (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v"))) {
            try stdout.print("{s} (coreutilz) {s}\n", .{ name, version });
            stdout.flush() catch return 1;
            return 0;
        } else if (!options_done and (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--sysv"))) {
            mode = .sysv;
        } else if (!options_done and std.mem.eql(u8, arg, "-r")) {
            mode = .bsd;
        } else if (!options_done and std.mem.startsWith(u8, arg, "-") and !std.mem.eql(u8, arg, "-")) {
            try stderr.print("{s}: unrecognized option '{s}'\nTry '{s} --help' for more information.\n", .{ name, arg, name });
            stderr.flush() catch {};
            return 1;
        } else {
            try files.append(allocator, arg);
        }
    }

    var success = true;
    if (files.items.len == 0) {
        success = try processFile(null, mode, stdout, stderr);
    } else {
        for (files.items) |f| {
            if (!try processFile(f, mode, stdout, stderr)) {
                success = false;
            }
        }
    }

    stdout.flush() catch return 1;
    stderr.flush() catch {};
    return if (success) 0 else 1;
}
