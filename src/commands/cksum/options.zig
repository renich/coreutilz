const std = @import("std");
const algo_mod = @import("algorithm.zig");
const Algorithm = algo_mod.Algorithm;

pub const ParsedArgs = struct {
    algo: ?Algorithm = null,
    algo_name: ?[]const u8 = null,
    length_str: ?[]const u8 = null,
    length_bits: ?usize = null,
    check: bool = false,
    check_opt_seen: bool = false,
    tag_opt_seen: bool = false,
    binary_seen: bool = false,
    text_seen: bool = false,
    zero_seen: bool = false,
    tagged: bool = false,
    untagged: bool = false,
    binary: bool = false,
    text: bool = false,
    raw: bool = false,
    base64: bool = false,
    zero: bool = false,
    quiet: bool = false,
    status_only: bool = false,
    strict: bool = false,
    warn: bool = false,
    ignore_missing: bool = false,
    files: std.ArrayList([]const u8),
};

fn handleAlgorithmOrLength(
    cmd_name: []const u8,
    arg: []const u8,
    i: *usize,
    args: [][]const u8,
    p: *ParsedArgs,
) ?u8 {
    if (std.mem.startsWith(u8, arg, "--algorithm=")) {
        p.algo_name = arg[12..];
    } else if (std.mem.eql(u8, arg, "--algorithm")) {
        i.* += 1;
        if (i.* >= args.len) {
            emitError(cmd_name, "option '--algorithm' requires an argument", .{});
            emitTryHelp(cmd_name);
            return 1;
        }
        p.algo_name = args[i.*];
    } else if (std.mem.startsWith(u8, arg, "--length=")) {
        p.length_str = arg[9..];
    } else if (std.mem.eql(u8, arg, "--length")) {
        i.* += 1;
        if (i.* >= args.len) {
            emitError(cmd_name, "option '--length' requires an argument", .{});
            emitTryHelp(cmd_name);
            return 1;
        }
        p.length_str = args[i.*];
    } else return null;
    return 0;
}

fn handleLongModeOptions(arg: []const u8, p: *ParsedArgs) bool {
    if (std.mem.eql(u8, arg, "--tag")) {
        p.tagged = true;
        p.tag_opt_seen = true;
    } else if (std.mem.eql(u8, arg, "--untagged")) {
        p.tagged = false;
        p.untagged = true;
    } else if (std.mem.eql(u8, arg, "--binary")) {
        p.binary = true;
        p.binary_seen = true;
    } else if (std.mem.eql(u8, arg, "--text")) {
        p.text = true;
        p.text_seen = true;
        p.binary = false;
    } else if (std.mem.eql(u8, arg, "--raw")) {
        p.raw = true;
    } else if (std.mem.eql(u8, arg, "--base64")) {
        p.base64 = true;
    } else if (std.mem.eql(u8, arg, "--zero")) {
        p.zero = true;
        p.zero_seen = true;
    } else return false;
    return true;
}

fn handleLongCheckOptions(arg: []const u8, p: *ParsedArgs) bool {
    if (std.mem.eql(u8, arg, "--quiet")) {
        p.status_only = false;
        p.warn = false;
        p.quiet = true;
    } else if (std.mem.eql(u8, arg, "--status")) {
        p.status_only = true;
        p.warn = false;
        p.quiet = false;
    } else if (std.mem.eql(u8, arg, "--strict")) {
        p.strict = true;
    } else if (std.mem.eql(u8, arg, "--warn")) {
        p.status_only = false;
        p.warn = true;
        p.quiet = false;
    } else if (std.mem.eql(u8, arg, "--ignore-missing")) {
        p.ignore_missing = true;
    } else if (std.mem.eql(u8, arg, "--debug")) {
        // Ignored
    } else return false;
    return true;
}

pub fn handleLongOption(
    cmd_name: []const u8,
    arg: []const u8,
    i: *usize,
    args: [][]const u8,
    p: *ParsedArgs,
    stdout: *std.Io.Writer,
) !?u8 {
    if (std.mem.eql(u8, arg, "--help")) {
        try printHelp(stdout);
        stdout.flush() catch return 1;
        return 0;
    } else if (std.mem.eql(u8, arg, "--version")) {
        try printVersion(stdout);
        stdout.flush() catch return 1;
        return 0;
    } else if (std.mem.eql(u8, arg, "--check")) {
        p.check = true;
        p.check_opt_seen = true;
    } else if (handleAlgorithmOrLength(cmd_name, arg, i, args, p)) |rc| {
        if (rc != 0) return rc;
    } else if (handleLongModeOptions(arg, p) or handleLongCheckOptions(arg, p)) {} else {
        emitError(cmd_name, "unrecognized option '{s}'", .{arg});
        emitTryHelp(cmd_name);
        return 1;
    }
    return null;
}

fn parseShortVal(cmd_name: []const u8, opt: u8, j: usize, arg: []const u8, i: *usize, args: [][]const u8) ?[]const u8 {
    if (j + 1 < arg.len) return arg[j + 1 ..];
    i.* += 1;
    if (i.* >= args.len) {
        emitError(cmd_name, "option requires an argument -- '{c}'", .{opt});
        emitTryHelp(cmd_name);
        return null;
    }
    return args[i.*];
}

fn handleShortFlag(opt: u8, p: *ParsedArgs) bool {
    switch (opt) {
        'c' => {
            p.check = true;
            p.check_opt_seen = true;
        },
        'b' => {
            p.binary = true;
            p.binary_seen = true;
        },
        't' => {
            p.text = true;
            p.text_seen = true;
            p.binary = false;
        },
        'z' => {
            p.zero = true;
            p.zero_seen = true;
        },
        'w' => {
            p.status_only = false;
            p.warn = true;
            p.quiet = false;
        },
        else => return false,
    }
    return true;
}

pub fn handleShortOptions(
    cmd_name: []const u8,
    arg: []const u8,
    i: *usize,
    args: [][]const u8,
    p: *ParsedArgs,
) !?u8 {
    var j: usize = 1;
    while (j < arg.len) : (j += 1) {
        if (handleShortFlag(arg[j], p)) continue;
        switch (arg[j]) {
            'a' => {
                p.algo_name = parseShortVal(cmd_name, 'a', j, arg, i, args) orelse return 1;
                break;
            },
            'l' => {
                p.length_str = parseShortVal(cmd_name, 'l', j, arg, i, args) orelse return 1;
                break;
            },
            else => {
                emitError(cmd_name, "invalid option -- '{c}'", .{arg[j]});
                emitTryHelp(cmd_name);
                return 1;
            },
        }
    }
    return null;
}

pub fn emitVerifyOnly(cmd_name: []const u8, opt_name: []const u8) void {
    emitError(cmd_name, "the --{s} option is meaningful only when verifying checksums", .{opt_name});
    emitTryHelp(cmd_name);
}

pub fn emitError(cmd_name: []const u8, comptime fmt: []const u8, args: anytype) void {
    var stderr_buf: [256]u8 = undefined;
    var writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stderr = &writer.interface;
    stderr.print("{s}: ", .{cmd_name}) catch {};
    stderr.print(fmt, args) catch {};
    stderr.writeByte('\n') catch {};
    writer.interface.flush() catch {};
}

pub fn emitTryHelp(cmd_name: []const u8) void {
    var stderr_buf: [256]u8 = undefined;
    var writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stderr = &writer.interface;
    stderr.print("Try '{s} --help' for more information.\n", .{cmd_name}) catch {};
    writer.interface.flush() catch {};
}

fn printHelpDigests(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        \\DIGEST determines the digest algorithm and default output format:
        \\  sysv      (equivalent to sum -s)
        \\  bsd       (equivalent to sum -r)
        \\  crc       (equivalent to cksum)
        \\  crc32b    (only available through cksum)
        \\  md5       (equivalent to md5sum)
        \\  sha1      (equivalent to sha1sum)
        \\  sha2      (equivalent to sha{224,256,384,512}sum)
        \\  sha3      (only available through cksum)
        \\  blake2b   (equivalent to b2sum)
        \\  sm3       (only available through cksum)
        \\
    );
}

fn printHelp(writer: *std.Io.Writer) !void {
    try writer.writeAll(
        \\Usage: cksum [OPTION]... [FILE]...
        \\Print or verify checksums.
        \\By default use the 32 bit CRC algorithm.
        \\
        \\With no FILE, or when FILE is -, read standard input.
        \\
        \\Mandatory arguments to long options are mandatory for short options too.
        \\  -a, --algorithm=TYPE   select the digest type to use. See DIGEST below
        \\      --base64           emit base64-encoded digests, not hexadecimal
        \\  -c, --check            read checksums from the FILEs and check them
        \\  -l, --length=BITS      digest length in bits; must not exceed the max size
        \\                           and must be a multiple of 8 for blake2b;
        \\                           must be 224, 256, 384, or 512 for sha2 or sha3
        \\      --raw              emit a raw binary digest, not hexadecimal
        \\      --tag              create a BSD-style checksum (the default)
        \\      --untagged         create a reversed style checksum, without digest type
        \\  -z, --zero             end each output line with NUL, not newline,
        \\                           and disable file name escaping
        \\
        \\The following five options are useful only when verifying checksums:
        \\      --ignore-missing   don't fail or report status for missing files
        \\      --quiet            don't print OK for each successfully verified file
        \\      --status           don't output anything, status code shows success
        \\      --strict           exit non-zero for improperly formatted checksum lines
        \\  -w, --warn             warn about improperly formatted checksum lines
        \\      --debug            indicate which implementation used
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
    );
    try printHelpDigests(writer);
}

fn printVersion(writer: *std.Io.Writer) !void {
    try writer.writeAll("cksum (coreutilz) 0.1.0\n");
}
