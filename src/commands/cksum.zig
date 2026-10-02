const std = @import("std");
const algo_mod = @import("cksum/algorithm.zig");
const Algorithm = algo_mod.Algorithm;
const check_mod = @import("cksum/check.zig");
const engine_mod = @import("cksum/engine.zig");
const opt_mod = @import("cksum/options.zig");
const ParsedArgs = opt_mod.ParsedArgs;
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "cksum";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    _ = c.signal(c.SIGPIPE, c.SIG_DFL);
    var stdout_buf: [16384]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    var p = ParsedArgs{ .files = .empty };
    defer p.files.deinit(allocator);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            while (i < args.len) : (i += 1) try p.files.append(allocator, args[i]);
            break;
        }
        if (std.mem.startsWith(u8, arg, "--")) {
            const rc = try opt_mod.handleLongOption(name, arg, &i, args, &p, stdout);
            if (rc) |code| return code;
        } else if (arg.len > 1 and arg[0] == '-') {
            const rc = try opt_mod.handleShortOptions(name, arg, &i, args, &p);
            if (rc) |code| return code;
        } else {
            try p.files.append(allocator, arg);
        }
    }

    return execute(p, stdout, allocator);
}

fn validateCheckOrDigestOptions(p: *const ParsedArgs) u8 {
    if (!p.check) {
        return validateDigestOnlyOptions(p);
    } else {
        return validateCheckOnlyOptions(p);
    }
}

fn validateDigestOnlyOptions(p: *const ParsedArgs) u8 {
    if (p.ignore_missing) {
        opt_mod.emitVerifyOnly(name, "ignore-missing");
        return 1;
    }
    if (p.status_only) {
        opt_mod.emitVerifyOnly(name, "status");
        return 1;
    }
    if (p.warn) {
        opt_mod.emitVerifyOnly(name, "warn");
        return 1;
    }
    if (p.quiet) {
        opt_mod.emitVerifyOnly(name, "quiet");
        return 1;
    }
    if (p.strict) {
        opt_mod.emitVerifyOnly(name, "strict");
        return 1;
    }
    if (p.base64 and p.raw) {
        opt_mod.emitError(name, "--base64 and --raw are mutually exclusive", .{});
        opt_mod.emitTryHelp(name);
        return 1;
    }
    if (p.raw and p.files.items.len > 1) {
        opt_mod.emitError(name, "the --raw option is not supported with multiple files", .{});
        return 1;
    }
    return 0;
}

fn validateCheckOnlyOptions(p: *const ParsedArgs) u8 {
    if (p.zero) {
        opt_mod.emitError(name, "the --zero option is not supported when verifying checksums", .{});
        opt_mod.emitTryHelp(name);
        return 1;
    }
    if (p.tag_opt_seen and p.tagged) {
        opt_mod.emitError(name, "the --tag option is meaningless when verifying checksums", .{});
        opt_mod.emitTryHelp(name);
        return 1;
    }
    if (p.binary_seen or p.text_seen) {
        opt_mod.emitError(name, "the --binary and --text options are meaningless when verifying checksums", .{});
        opt_mod.emitTryHelp(name);
        return 1;
    }
    return 0;
}

fn resolveAlgorithmAndLength(p: *ParsedArgs) u8 {
    if (p.algo_name) |aname| {
        p.algo = Algorithm.fromName(aname) orelse {
            opt_mod.emitError(name, "invalid digest type '{s}'", .{aname});
            return 1;
        };
    }
    if (p.length_str) |lstr| {
        for (lstr) |ch| {
            if (!std.ascii.isDigit(ch)) {
                opt_mod.emitError(name, "invalid length: '{s}'", .{lstr});
                return 1;
            }
        }
        const a = p.algo orelse .crc;
        if (a != .blake2b and a != .sha2 and a != .sha3 and a != .sha3_224 and a != .sha3_256 and a != .sha3_384 and a != .sha3_512) {
            opt_mod.emitError(name, "--length is only supported with --algorithm blake2b, sha2, or sha3", .{});
            return 1;
        }
        const bits = std.fmt.parseInt(usize, lstr, 10) catch std.math.maxInt(usize);
        const rc = validateLength(a, bits, lstr);
        if (rc != 0) return rc;
        p.length_bits = if (bits == 0 and a == .blake2b) 512 else bits;
    }
    if (!p.check) {
        if (p.algo) |a| {
            if ((a == .sha2 or a == .sha3) and p.length_bits == null) {
                opt_mod.emitError(name, "--algorithm={s} requires specifying --length 224, 256, 384, or 512", .{@tagName(a)});
                return 1;
            }
        }
        if (p.text_seen and (p.tagged or (!p.untagged and p.algo != null and !p.algo.?.isNumeric()))) {
            opt_mod.emitError(name, "--text mode is only supported with --untagged", .{});
            opt_mod.emitTryHelp(name);
            return 1;
        }
    }
    return 0;
}

fn execute(p_in: ParsedArgs, stdout: *std.Io.Writer, allocator: std.mem.Allocator) !u8 {
    var p = p_in;
    const v_rc = validateCheckOrDigestOptions(&p);
    if (v_rc != 0) return v_rc;
    const r_rc = resolveAlgorithmAndLength(&p);
    if (r_rc != 0) return r_rc;

    if (p.check) {
        return executeCheck(p, stdout, allocator);
    } else {
        return executeDigest(p, stdout, allocator);
    }
}

fn validateLength(algo: Algorithm, bits: usize, lstr: []const u8) u8 {
    switch (algo) {
        .blake2b => {
            if (bits > 512) {
                opt_mod.emitError(name, "invalid length: '{s}'\n{s}: maximum digest length for 'BLAKE2b' is 512 bits", .{ lstr, name });
                return 1;
            }
            if (bits % 8 != 0) {
                opt_mod.emitError(name, "invalid length: '{s}'\n{s}: length is not a multiple of 8", .{ lstr, name });
                return 1;
            }
        },
        .sha2 => {
            if (bits != 224 and bits != 256 and bits != 384 and bits != 512) {
                opt_mod.emitError(name, "invalid length: '{s}'\n{s}: digest length for 'SHA2' must be 224, 256, 384, or 512", .{ lstr, name });
                return 1;
            }
        },
        .sha3, .sha3_224, .sha3_256, .sha3_384, .sha3_512 => {
            if (bits != 224 and bits != 256 and bits != 384 and bits != 512) {
                opt_mod.emitError(name, "invalid length: '{s}'\n{s}: digest length for 'SHA3' must be 224, 256, 384, or 512", .{ lstr, name });
                return 1;
            }
        },
        else => {},
    }
    return 0;
}

fn executeCheck(p: ParsedArgs, stdout: *std.Io.Writer, allocator: std.mem.Allocator) !u8 {
    if (p.algo) |a| {
        if (a.isNumeric()) {
            opt_mod.emitError(name, "--check is not supported with --algorithm={s}", .{@tagName(a)});
            return 1;
        }
    }
    const check_opts = check_mod.CheckOptions{
        .quiet = p.quiet,
        .status_only = p.status_only,
        .strict = p.strict,
        .warn = p.warn,
        .ignore_missing = p.ignore_missing,
        .expected_algo = p.algo,
        .expected_length = p.length_bits,
    };
    var exit_code: u8 = 0;
    if (p.files.items.len == 0) {
        exit_code = try check_mod.verifyFile(name, "-", check_opts, stdout, allocator);
    } else {
        for (p.files.items) |f| {
            const rc = try check_mod.verifyFile(name, f, check_opts, stdout, allocator);
            if (rc != 0) exit_code = rc;
        }
    }
    try stdout.flush();
    return exit_code;
}

fn executeDigest(p: ParsedArgs, stdout: *std.Io.Writer, allocator: std.mem.Allocator) !u8 {
    const final_algo = determineFinalAlgo(p);
    const is_tagged = if (p.untagged) false else if (p.tagged) true else if (p.algo != null and !final_algo.isNumeric()) true else false;

    const digest_opts = engine_mod.DigestOptions{
        .algo = final_algo,
        .length_bits = p.length_bits,
        .tagged = is_tagged,
        .binary = p.binary,
        .raw = p.raw,
        .base64 = p.base64,
        .zero = p.zero,
        .files = p.files.items,
    };
    const rc = try engine_mod.digestFiles(name, digest_opts, stdout, allocator);
    try stdout.flush();
    return rc;
}

fn determineFinalAlgo(p: ParsedArgs) Algorithm {
    const a = p.algo orelse return .crc;
    if (a == .sha2) {
        return switch (p.length_bits orelse 256) {
            224 => .sha224,
            256 => .sha256,
            384 => .sha384,
            512 => .sha512,
            else => .sha256,
        };
    } else if (a == .sha3) {
        return switch (p.length_bits orelse 256) {
            224 => .sha3_224,
            256 => .sha3_256,
            384 => .sha3_384,
            512 => .sha3_512,
            else => .sha3_256,
        };
    }
    return a;
}
