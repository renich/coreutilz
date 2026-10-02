const std = @import("std");
const common = @import("basenc/common.zig");
const base64_mod = @import("basenc/base64.zig");
const base32_mod = @import("basenc/base32.zig");
const base16_mod = @import("basenc/base16.zig");
const base2_mod = @import("basenc/base2.zig");
const z85_mod = @import("basenc/z85.zig");
const base58_mod = @import("basenc/base58.zig");
const WrapWriter = common.WrapWriter;
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "basenc";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    _ = c.signal(c.SIGPIPE, c.SIG_DFL);
    var stdout_buf: [16384]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var opts: common.Options = .{};
    if (try parseCliArgs(args, stdout, &opts)) |rc| return rc;

    if (opts.encoding == null) {
        emitMissingEncoding();
        return 1;
    }

    return execute(opts, stdout, allocator);
}

fn parseCliArgs(args: [][]const u8, stdout: *std.Io.Writer, opts: *common.Options) !?u8 {
    var operand_seen = false;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            while (i < args.len) : (i += 1) {
                if (operand_seen) {
                    common.emitExtraOperand(name, args[i]);
                    return 1;
                }
                opts.file_path = args[i];
                operand_seen = true;
            }
            break;
        }
        if (std.mem.startsWith(u8, arg, "--")) {
            if (try handleLong(arg, &i, args, stdout, opts)) |rc| return rc;
        } else if (arg.len > 1 and arg[0] == '-') {
            if (handleShort(arg, &i, args, opts)) |rc| return rc;
        } else {
            if (operand_seen) {
                common.emitExtraOperand(name, arg);
                return 1;
            }
            opts.file_path = arg;
            operand_seen = true;
        }
    }
    return null;
}

fn handleLong(
    arg: []const u8,
    i: *usize,
    args: [][]const u8,
    stdout: *std.Io.Writer,
    opts: *common.Options,
) !?u8 {
    if (std.mem.eql(u8, arg, "--help")) {
        try printHelp(stdout);
        stdout.flush() catch return 1;
        return 0;
    } else if (std.mem.eql(u8, arg, "--version")) {
        try printVersion(stdout);
        stdout.flush() catch return 1;
        return 0;
    } else if (std.mem.eql(u8, arg, "--decode")) {
        opts.decode = true;
    } else if (std.mem.eql(u8, arg, "--ignore-garbage")) {
        opts.ignore_garbage = true;
    } else if (std.mem.startsWith(u8, arg, "--wrap=")) {
        opts.wrap_column = common.parseWrapArg(name, arg[7..]) catch return 1;
    } else if (std.mem.eql(u8, arg, "--wrap")) {
        i.* += 1;
        if (i.* >= args.len) {
            common.emitOptionRequiresArgLong(name, "--wrap");
            return 1;
        }
        opts.wrap_column = common.parseWrapArg(name, args[i.*]) catch return 1;
    } else if (parseEncodingLong(arg)) |enc| {
        opts.encoding = enc;
    } else {
        emitUnknownOption(arg);
        return 1;
    }
    return null;
}

fn handleShort(arg: []const u8, i: *usize, args: [][]const u8, opts: *common.Options) ?u8 {
    var j: usize = 1;
    while (j < arg.len) : (j += 1) {
        switch (arg[j]) {
            'd' => opts.decode = true,
            'i' => opts.ignore_garbage = true,
            'w' => {
                const val = if (j + 1 < arg.len) arg[j + 1 ..] else blk: {
                    i.* += 1;
                    if (i.* >= args.len) {
                        emitOptionRequiresArg('w');
                        return 1;
                    }
                    break :blk args[i.*];
                };
                opts.wrap_column = common.parseWrapArg(name, val) catch return 1;
                break;
            },
            else => {
                emitInvalidOption(arg[j]);
                return 1;
            },
        }
    }
    return null;
}

fn parseEncodingLong(arg: []const u8) ?common.EncodingType {
    if (std.mem.eql(u8, arg, "--base64")) return .base64;
    if (std.mem.eql(u8, arg, "--base64url") or (std.mem.startsWith(u8, "--base64url", arg) and arg.len >= 9)) return .base64url;
    if (std.mem.eql(u8, arg, "--base32")) return .base32;
    if (std.mem.eql(u8, arg, "--base32hex") or (std.mem.startsWith(u8, "--base32hex", arg) and arg.len >= 9)) return .base32hex;
    if (std.mem.eql(u8, arg, "--base16") or std.mem.eql(u8, arg, "--hex")) return .base16;
    if (std.mem.eql(u8, arg, "--base2msbf") or (std.mem.startsWith(u8, "--base2msbf", arg) and arg.len >= 8)) return .base2msbf;
    if (std.mem.eql(u8, arg, "--base2lsbf") or (std.mem.startsWith(u8, "--base2lsbf", arg) and arg.len >= 8)) return .base2lsbf;
    if (std.mem.eql(u8, arg, "--z85")) return .z85;
    if (std.mem.eql(u8, arg, "--base58")) return .base58;
    return null;
}

fn execute(opts: common.Options, stdout: *std.Io.Writer, allocator: std.mem.Allocator) !u8 {
    const file = common.openInputFile(name, opts.file_path) catch return 1;
    defer if (opts.file_path != null and !std.mem.eql(u8, opts.file_path.?, "-")) {
        file.close(std.Options.debug_io);
    };

    const res = if (opts.decode)
        executeDecode(file, stdout, opts, allocator)
    else
        executeEncode(file, stdout, opts, allocator);

    res catch |err| {
        if (err == error.Z85InvalidLength) {
            common.emitZ85InvalidLength(name);
            return 1;
        } else if (err == error.InvalidInput) {
            common.emitInvalidInput(name);
            return 1;
        }
        return err;
    };
    try stdout.flush();
    return 0;
}

fn executeEncode(file: std.Io.File, stdout: *std.Io.Writer, opts: common.Options, allocator: std.mem.Allocator) !void {
    var wrap = WrapWriter.init(stdout, opts.wrap_column);
    switch (opts.encoding.?) {
        .base64 => try base64_mod.encodeStream(file, &wrap, false),
        .base64url => try base64_mod.encodeStream(file, &wrap, true),
        .base32 => try base32_mod.encodeStream(file, &wrap, false),
        .base32hex => try base32_mod.encodeStream(file, &wrap, true),
        .base16 => try base16_mod.encodeStream(file, &wrap),
        .base2msbf => try base2_mod.encodeStream(file, &wrap, true),
        .base2lsbf => try base2_mod.encodeStream(file, &wrap, false),
        .z85 => z85_mod.encodeStream(file, &wrap) catch |err| {
            if (err == error.InvalidInput) return error.Z85InvalidLength;
            return err;
        },
        .base58 => try base58_mod.encodeStream(file, &wrap, allocator),
    }
}

fn executeDecode(file: std.Io.File, stdout: *std.Io.Writer, opts: common.Options, allocator: std.mem.Allocator) !void {
    switch (opts.encoding.?) {
        .base64 => try base64_mod.decodeStream(file, stdout, false, opts.ignore_garbage),
        .base64url => try base64_mod.decodeStream(file, stdout, true, opts.ignore_garbage),
        .base32 => try base32_mod.decodeStream(file, stdout, false, opts.ignore_garbage),
        .base32hex => try base32_mod.decodeStream(file, stdout, true, opts.ignore_garbage),
        .base16 => try base16_mod.decodeStream(file, stdout, opts.ignore_garbage),
        .base2msbf => try base2_mod.decodeStream(file, stdout, true, opts.ignore_garbage),
        .base2lsbf => try base2_mod.decodeStream(file, stdout, false, opts.ignore_garbage),
        .z85 => try z85_mod.decodeStream(file, stdout, opts.ignore_garbage),
        .base58 => try base58_mod.decodeStream(file, stdout, opts.ignore_garbage, allocator),
    }
}

fn emitMissingEncoding() void {
    var stderr_buf: [256]u8 = undefined;
    var writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stderr = &writer.interface;
    stderr.print("{s}: missing encoding type\n", .{name}) catch {};
    writer.interface.flush() catch {};
    common.emitTryHelp(name);
}

fn printHelp(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        \\Usage: basenc [OPTION]... [FILE]
        \\basenc encode or decode FILE, or standard input, to standard output.
        \\
        \\With no FILE, or when FILE is -, read standard input.
        \\
        \\Mandatory arguments to long options are mandatory for short options too.
        \\      --base64          same as 'base64' program (RFC4648 section 4)
        \\      --base64url       file- and url-safe base64 (RFC4648 section 5)
        \\      --base58          visually unambiguous base58 encoding
        \\      --base32          same as 'base32' program (RFC4648 section 6)
        \\      --base32hex       extended hex alphabet base32 (RFC4648 section 7)
        \\      --base16          hex encoding (RFC4648 section 8)
        \\      --base2msbf       bit string with most significant bit (msb) first
        \\      --base2lsbf       bit string with least significant bit (lsb) first
        \\  -d, --decode          decode data
        \\  -i, --ignore-garbage  when decoding, ignore non-alphabet characters
        \\  -w, --wrap=COLS       wrap encoded lines after COLS character (default 76).
        \\                          Use 0 to disable line wrapping
        \\      --z85             ascii85-like encoding (ZeroMQ spec:32/Z85);
        \\                          when encoding, input length must be a multiple of 4;
        \\                          when decoding, input length must be a multiple of 5
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
        \\When decoding, the input may contain newlines in addition to the bytes of
        \\the formal alphabet.  Use --ignore-garbage to attempt to recover
        \\from any other non-alphabet bytes in the encoded stream.
        \\
    );
}

fn printVersion(writer: *std.Io.Writer) !void {
    try writer.writeAll("basenc (coreutilz) 0.1.0\n");
}

fn emitUnknownOption(opt: []const u8) void {
    var stderr_buf: [256]u8 = undefined;
    var writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stderr = &writer.interface;
    stderr.print("{s}: unrecognized option '{s}'\n", .{ name, opt }) catch {};
    writer.interface.flush() catch {};
    common.emitTryHelp(name);
}

fn emitInvalidOption(opt: u8) void {
    var stderr_buf: [256]u8 = undefined;
    var writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stderr = &writer.interface;
    stderr.print("{s}: invalid option -- '{c}'\n", .{ name, opt }) catch {};
    writer.interface.flush() catch {};
    common.emitTryHelp(name);
}

fn emitOptionRequiresArg(opt: u8) void {
    var stderr_buf: [256]u8 = undefined;
    var writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stderr = &writer.interface;
    stderr.print("{s}: option requires an argument -- '{c}'\n", .{ name, opt }) catch {};
    writer.interface.flush() catch {};
    common.emitTryHelp(name);
}
