const std = @import("std");
const algo_mod = @import("algorithm.zig");
const Algorithm = algo_mod.Algorithm;
const AnyHasher = algo_mod.AnyHasher;
const format = @import("format.zig");
const c = @import("../../compat/c.zig").c;

pub const DigestOptions = struct {
    algo: Algorithm,
    length_bits: ?usize = null,
    tagged: bool = false,
    binary: bool = false,
    raw: bool = false,
    base64: bool = false,
    zero: bool = false,
    files: []const []const u8 = &.{},
};

pub fn digestFiles(
    cmd_name: []const u8,
    opts: DigestOptions,
    stdout: *std.Io.Writer,
    allocator: std.mem.Allocator,
) !u8 {
    _ = allocator;
    if (opts.raw and opts.base64) {
        emitError(cmd_name, "the --base64 and --raw options are mutually exclusive");
        return 1;
    }
    if (opts.raw and opts.files.len > 1) {
        emitError(cmd_name, "the --raw option is not supported with multiple files");
        return 1;
    }

    var exit_code: u8 = 0;
    if (opts.files.len == 0) {
        const rc = try processFile(cmd_name, "-", null, opts, stdout);
        if (rc != 0) exit_code = rc;
    } else {
        for (opts.files) |filepath| {
            const rc = try processFile(cmd_name, filepath, filepath, opts, stdout);
            if (rc != 0) exit_code = rc;
        }
    }
    return exit_code;
}

fn processFile(
    cmd_name: []const u8,
    filepath: []const u8,
    display_name: ?[]const u8,
    opts: DigestOptions,
    stdout: *std.Io.Writer,
) !u8 {
    const is_stdin = std.mem.eql(u8, filepath, "-");
    const file = if (is_stdin)
        std.Io.File.stdin()
    else
        std.Io.Dir.cwd().openFile(std.Options.debug_io, filepath, .{ .mode = .read_only }) catch |err| {
            emitOpenFileError(cmd_name, filepath, err);
            return 1;
        };
    defer if (!is_stdin) file.close(std.Options.debug_io);

    var hasher = AnyHasher.init(opts.algo, opts.length_bits);
    var buf: [16384]u8 = undefined;
    while (true) {
        const n_read = c.read(file.handle, &buf, buf.len);
        if (n_read < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            emitOpenFileError(cmd_name, filepath, error.ReadFailed);
            return 1;
        }
        if (n_read == 0) break;
        hasher.update(buf[0..@intCast(n_read)]);
    }

    if (opts.algo.isNumeric()) {
        try outputNumeric(hasher, display_name, opts, stdout);
    } else {
        try outputCrypto(hasher, display_name orelse "-", opts, stdout);
    }
    stdout.flush() catch return error.WriteError;
    return 0;
}

fn outputNumeric(
    hasher: AnyHasher,
    display_name: ?[]const u8,
    opts: DigestOptions,
    stdout: *std.Io.Writer,
) !void {
    if (opts.raw) {
        try outputNumericRaw(hasher, stdout);
        return;
    }
    switch (hasher) {
        .crc => |h| {
            var m = h;
            const val = m.final();
            try format.printCrc(stdout, val, m.total_bytes, display_name, opts.zero);
        },
        .crc32b => |h| {
            var m = h;
            const val = m.final();
            try format.printCrc(stdout, val, m.total_bytes, display_name, opts.zero);
        },
        .bsd => |h| {
            const res = h.final();
            try format.printBsd(stdout, res.checksum, res.blocks, display_name, opts.zero);
        },
        .sysv => |h| {
            const res = h.final();
            try format.printSysv(stdout, res.checksum, res.blocks, display_name, opts.zero);
        },
        else => unreachable,
    }
}

fn outputNumericRaw(hasher: AnyHasher, stdout: *std.Io.Writer) !void {
    switch (hasher) {
        .crc => |h| {
            var m = h;
            const val = m.final();
            var b: [4]u8 = undefined;
            std.mem.writeInt(u32, &b, val, .big);
            try stdout.writeAll(&b);
        },
        .crc32b => |h| {
            var m = h;
            const val = m.final();
            var b: [4]u8 = undefined;
            std.mem.writeInt(u32, &b, val, .big);
            try stdout.writeAll(&b);
        },
        .bsd => |h| {
            const res = h.final();
            var b: [2]u8 = undefined;
            std.mem.writeInt(u16, &b, res.checksum, .big);
            try stdout.writeAll(&b);
        },
        .sysv => |h| {
            const res = h.final();
            var b: [2]u8 = undefined;
            std.mem.writeInt(u16, &b, res.checksum, .big);
            try stdout.writeAll(&b);
        },
        else => unreachable,
    }
}

fn outputCrypto(
    hasher_in: AnyHasher,
    name_str: []const u8,
    opts: DigestOptions,
    stdout: *std.Io.Writer,
) !void {
    var hasher = hasher_in;
    var digest: [64]u8 = undefined;
    const len = hasher.final(&digest);

    if (opts.raw) {
        try stdout.writeAll(digest[0..len]);
        return;
    }

    var str_buf: [128]u8 = undefined;
    const str = if (opts.base64) blk: {
        const b64_len = format.toBase64(digest[0..len], &str_buf);
        break :blk str_buf[0..b64_len];
    } else blk: {
        const hex_chars = "0123456789abcdef";
        for (digest[0..len], 0..) |b, i| {
            str_buf[i * 2] = hex_chars[b >> 4];
            str_buf[i * 2 + 1] = hex_chars[b & 0x0f];
        }
        break :blk str_buf[0 .. len * 2];
    };

    if (opts.tagged) {
        var tag_buf: [32]u8 = undefined;
        const tag = getTagName(opts.algo, opts.length_bits, &tag_buf);
        try format.printTagged(stdout, tag, str, name_str, opts.zero);
    } else {
        try format.printUntagged(stdout, str, name_str, opts.binary, opts.zero);
    }
}

fn getTagName(algo: Algorithm, len_bits: ?usize, buf: *[32]u8) []const u8 {
    return switch (algo) {
        .md5 => "MD5",
        .sha1 => "SHA1",
        .sha224 => "SHA224",
        .sha256 => "SHA256",
        .sha384 => "SHA384",
        .sha512 => "SHA512",
        .sm3 => "SM3",
        .sha3_224 => "SHA3-224",
        .sha3_256 => "SHA3-256",
        .sha3_384 => "SHA3-384",
        .sha3_512 => "SHA3-512",
        .blake2b => blk: {
            if (len_bits) |bits| {
                if (bits != 0 and bits != 512) {
                    const s = std.fmt.bufPrint(buf, "BLAKE2b-{d}", .{bits}) catch "BLAKE2b";
                    break :blk s;
                }
            }
            break :blk "BLAKE2b";
        },
        else => "UNKNOWN",
    };
}

fn emitError(cmd_name: []const u8, msg: []const u8) void {
    var stderr_buf: [256]u8 = undefined;
    var writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stderr = &writer.interface;
    stderr.print("{s}: {s}\n", .{ cmd_name, msg }) catch {};
    writer.interface.flush() catch {};
}

fn emitOpenFileError(cmd_name: []const u8, path: []const u8, err: anyerror) void {
    var stderr_buf: [256]u8 = undefined;
    var writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stderr = &writer.interface;
    const errno_val = c.__errno_location().*;
    if (errno_val != 0) {
        const err_str = std.mem.span(c.strerror(errno_val));
        stderr.print("{s}: {s}: {s}\n", .{ cmd_name, path, err_str }) catch {};
    } else {
        stderr.print("{s}: {s}: {s}\n", .{ cmd_name, path, @errorName(err) }) catch {};
    }
    writer.interface.flush() catch {};
}
