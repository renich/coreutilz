const std = @import("std");
const algo_mod = @import("algorithm.zig");
const Algorithm = algo_mod.Algorithm;
const AnyHasher = algo_mod.AnyHasher;
const parser = @import("parser.zig");
const format = @import("format.zig");
const c = @import("../../compat/c.zig").c;

pub const CheckOptions = struct {
    quiet: bool = false,
    status_only: bool = false,
    strict: bool = false,
    warn: bool = false,
    ignore_missing: bool = false,
    expected_algo: ?Algorithm = null,
    expected_length: ?usize = null,
};

pub const CheckCounters = struct {
    valid_lines: usize = 0,
    verified_files: usize = 0,
    improper_lines: usize = 0,
    unreadable_files: usize = 0,
    mismatched_files: usize = 0,
};

const CheckCtx = struct {
    cmd_name: []const u8,
    check_name: []const u8,
    opts: CheckOptions,
    stdout: *std.Io.Writer,
    allocator: std.mem.Allocator,
    ctr: CheckCounters = .{},
    tag: []const u8,
    bsd_reversed: ?bool = null,
};

pub fn verifyFile(cmd_name: []const u8, check_path: []const u8, opts: CheckOptions, stdout: *std.Io.Writer, allocator: std.mem.Allocator) !u8 {
    const is_stdin = std.mem.eql(u8, check_path, "-");
    const file = if (is_stdin) std.Io.File.stdin() else std.Io.Dir.cwd().openFile(std.Options.debug_io, check_path, .{ .mode = .read_only }) catch |err| {
        emitOpenFileError(cmd_name, check_path, err);
        return 1;
    };
    defer if (!is_stdin) file.close(std.Options.debug_io);

    var ctx = CheckCtx{
        .cmd_name = cmd_name,
        .check_name = check_path,
        .opts = opts,
        .stdout = stdout,
        .allocator = allocator,
        .tag = defaultTag(opts.expected_algo),
    };
    return processStream(&ctx, file);
}

fn emitOpenFileError(cmd_name: []const u8, path: []const u8, err: anyerror) void {
    var buf: [256]u8 = undefined;
    var writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &buf);
    const errno_val = c.__errno_location().*;
    const msg = if (errno_val != 0) std.mem.span(c.strerror(errno_val)) else @errorName(err);
    writer.interface.print("{s}: {s}: {s}\n", .{ cmd_name, path, msg }) catch {};
    writer.interface.flush() catch {};
}

fn processStream(ctx: *CheckCtx, file: std.Io.File) !u8 {
    var line_buf: std.ArrayList(u8) = .empty;
    defer line_buf.deinit(ctx.allocator);

    var line_num: usize = 0;
    var read_buf: [8192]u8 = undefined;
    while (true) {
        const n = c.read(file.handle, &read_buf, read_buf.len);
        if (n < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            return 1;
        }
        if (n == 0) break;
        try feedChunk(ctx, read_buf[0..@intCast(n)], &line_buf, &line_num);
    }
    if (line_buf.items.len > 0) {
        line_num += 1;
        try handleLine(ctx, line_buf.items, line_num);
    }
    return finalizeVerification(ctx);
}

fn feedChunk(
    ctx: *CheckCtx,
    chunk: []const u8,
    buf: *std.ArrayList(u8),
    line_num: *usize,
) !void {
    var i: usize = 0;
    while (i < chunk.len) {
        const start = i;
        while (i < chunk.len and chunk[i] != '\n') : (i += 1) {}
        try buf.appendSlice(ctx.allocator, chunk[start..i]);
        if (i < chunk.len and chunk[i] == '\n') {
            i += 1;
            line_num.* += 1;
            try handleLine(ctx, buf.items, line_num.*);
            buf.clearRetainingCapacity();
        }
    }
}

fn defaultTag(algo: ?Algorithm) []const u8 {
    const a = algo orelse return "CRC";
    return switch (a) {
        .md5 => "MD5",
        .sha1 => "SHA1",
        .sha224 => "SHA224",
        .sha256 => "SHA256",
        .sha384 => "SHA384",
        .sha512 => "SHA512",
        .blake2b => "BLAKE2b",
        .sm3 => "SM3",
        .sha2 => "SHA2",
        .sha3, .sha3_224, .sha3_256, .sha3_384, .sha3_512 => "SHA3",
        .sysv => "SYSV",
        .bsd => "BSD",
        else => "CRC",
    };
}

fn formatCheckName(check_name: []const u8) []const u8 {
    return if (std.mem.eql(u8, check_name, "-")) "'standard input'" else check_name;
}

fn isSha2Tag(tag: []const u8) bool {
    return std.mem.startsWith(u8, tag, "SHA2") or
        std.mem.eql(u8, tag, "SHA384") or
        std.mem.eql(u8, tag, "SHA512");
}

fn handleLine(ctx: *CheckCtx, line: []const u8, line_num: usize) !void {
    if (ctx.opts.expected_algo == null or ctx.opts.expected_algo == .sha2) {
        if (parser.parseLeadingTag(line)) |tag| {
            if (ctx.opts.expected_algo == null or isSha2Tag(tag)) ctx.tag = tag;
        }
    }
    const res = parser.parseLine(line, ctx.opts.expected_algo, ctx.opts.expected_length, &ctx.bsd_reversed);
    switch (res) {
        .ignored => {},
        .invalid => {
            ctx.ctr.improper_lines += 1;
            if (ctx.opts.warn and !ctx.opts.status_only) {
                emitWarnLine(ctx.cmd_name, ctx.check_name, line_num, ctx.tag);
            }
        },
        .parsed => |p| {
            ctx.ctr.valid_lines += 1;
            if (ctx.opts.expected_algo == null or ctx.opts.expected_algo == .sha2) {
                ctx.tag = defaultTag(p.algo);
            }
            try verifyParsedEntry(ctx, p);
        },
    }
}

fn verifyParsedEntry(ctx: *CheckCtx, p: parser.ParsedLine) !void {
    const target_path = if (p.escaped)
        try format.unescapeFilename(ctx.allocator, p.filename)
    else
        p.filename;
    defer if (p.escaped) ctx.allocator.free(target_path);

    const is_stdin = std.mem.eql(u8, target_path, "-");
    const file = if (is_stdin)
        std.Io.File.stdin()
    else
        std.Io.Dir.cwd().openFile(std.Options.debug_io, target_path, .{ .mode = .read_only }) catch {
            if (ctx.opts.ignore_missing and c.__errno_location().* == c.ENOENT) return;
            ctx.ctr.unreadable_files += 1;
            if (!ctx.opts.status_only) {
                try printStatus(ctx.stdout, p, "FAILED open or read");
                emitOpenFileError(ctx.cmd_name, target_path, error.OpenFailed);
            }
            return;
        };
    defer if (!is_stdin) file.close(std.Options.debug_io);

    try hashAndCheck(ctx, p, target_path, file);
}

fn hashAndCheck(
    ctx: *CheckCtx,
    p: parser.ParsedLine,
    target_path: []const u8,
    file: std.Io.File,
) !void {
    var hasher = AnyHasher.init(p.algo, p.length_bits);
    var buf: [16384]u8 = undefined;
    while (true) {
        const n = c.read(file.handle, &buf, buf.len);
        if (n < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            ctx.ctr.unreadable_files += 1;
            if (!ctx.opts.status_only) {
                try printStatus(ctx.stdout, p, "FAILED open or read");
                emitOpenFileError(ctx.cmd_name, target_path, error.ReadFailed);
            }
            return;
        }
        if (n == 0) break;
        hasher.update(buf[0..@intCast(n)]);
    }

    ctx.ctr.verified_files += 1;
    var computed: [64]u8 = undefined;
    const comp_len = hasher.final(&computed);

    if (digestMatches(p, computed[0..comp_len])) {
        if (!ctx.opts.quiet and !ctx.opts.status_only) try printStatus(ctx.stdout, p, "OK");
    } else {
        ctx.ctr.mismatched_files += 1;
        if (!ctx.opts.status_only) try printStatus(ctx.stdout, p, "FAILED");
    }
}

fn digestMatches(p: parser.ParsedLine, computed: []const u8) bool {
    const raw_target = p.digest_str[0..p.digest_str_len];
    if (p.is_base64) {
        var b64_buf: [128]u8 = undefined;
        const b64_len = format.toBase64(computed, &b64_buf);
        return std.mem.eql(u8, b64_buf[0..b64_len], raw_target);
    }
    const hex_chars = "0123456789abcdef";
    if (computed.len * 2 != raw_target.len) return false;
    var hex_buf: [128]u8 = undefined;
    for (computed, 0..) |b, i| {
        hex_buf[i * 2] = hex_chars[b >> 4];
        hex_buf[i * 2 + 1] = hex_chars[b & 0x0f];
    }
    return std.ascii.eqlIgnoreCase(hex_buf[0 .. computed.len * 2], raw_target);
}

fn printStatus(writer: *std.Io.Writer, p: parser.ParsedLine, status_text: []const u8) !void {
    if (p.escaped) try writer.writeByte('\\');
    try writer.print("{s}: {s}\n", .{ p.filename, status_text });
    try writer.flush();
}

fn emitWarnLine(cmd_name: []const u8, check_name: []const u8, line_num: usize, tag: []const u8) void {
    var buf: [256]u8 = undefined;
    var writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &buf);
    writer.interface.print("{s}: {s}: {d}: improperly formatted {s} checksum line\n", .{
        cmd_name, formatCheckName(check_name), line_num, tag,
    }) catch {};
    writer.interface.flush() catch {};
}

fn finalizeVerification(ctx: *const CheckCtx) u8 {
    var buf: [512]u8 = undefined;
    var writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &buf);
    const stderr = &writer.interface;

    if (ctx.ctr.valid_lines == 0) {
        if (!ctx.opts.status_only) {
            stderr.print("{s}: {s}: no properly formatted checksum lines found\n", .{
                ctx.cmd_name, formatCheckName(ctx.check_name),
            }) catch {};
            writer.interface.flush() catch {};
        }
        return 1;
    }
    if (ctx.opts.ignore_missing and ctx.ctr.verified_files == 0) {
        if (!ctx.opts.status_only) {
            stderr.print("{s}: {s}: no file was verified\n", .{ ctx.cmd_name, formatCheckName(ctx.check_name) }) catch {};
            writer.interface.flush() catch {};
        }
        return 1;
    }
    if (!ctx.opts.status_only) {
        emitWarning(stderr, ctx.cmd_name, ctx.ctr.improper_lines, "line is improperly formatted", "lines are improperly formatted");
        emitWarning(stderr, ctx.cmd_name, ctx.ctr.unreadable_files, "listed file could not be read", "listed files could not be read");
        emitWarning(stderr, ctx.cmd_name, ctx.ctr.mismatched_files, "computed checksum did NOT match", "computed checksums did NOT match");
        writer.interface.flush() catch {};
    }
    if (ctx.ctr.mismatched_files > 0 or ctx.ctr.unreadable_files > 0) return 1;
    if (ctx.opts.strict and ctx.ctr.improper_lines > 0) return 1;
    return 0;
}

fn emitWarning(stderr: *std.Io.Writer, cmd_name: []const u8, count: usize, sing: []const u8, plur: []const u8) void {
    if (count == 0) return;
    const desc = if (count == 1) sing else plur;
    stderr.print("{s}: WARNING: {d} {s}\n", .{ cmd_name, count, desc }) catch {};
}
