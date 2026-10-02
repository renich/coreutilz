const std = @import("std");
const algo_mod = @import("algorithm.zig");
const Algorithm = algo_mod.Algorithm;
const check_mod = @import("check.zig");
const engine_mod = @import("engine.zig");
const legacy_opt = @import("legacy_options.zig");
const opt_mod = @import("options.zig");
const c = @import("../../compat/c.zig").c;

pub fn runLegacy(
    cmd_name: []const u8,
    algo: Algorithm,
    accepts_length: bool,
    args: [][]const u8,
    allocator: std.mem.Allocator,
) !u8 {
    _ = c.signal(c.SIGPIPE, c.SIG_DFL);
    var stdout_buf: [16384]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    const stdout = &stdout_writer.interface;
    defer stdout.flush() catch {};

    const parse_res = try legacy_opt.parseLegacyArgs(cmd_name, accepts_length, args, allocator);
    switch (parse_res) {
        .help => {
            try printHelp(stdout, cmd_name, accepts_length);
            stdout.flush() catch return 1;
            return 0;
        },
        .version => {
            try printVersion(stdout, cmd_name);
            stdout.flush() catch return 1;
            return 0;
        },
        .err => return 1,
        .parsed => |p| {
            var pl = p;
            defer pl.files.deinit(allocator);
            if (validateParsed(cmd_name, &pl) != 0) return 1;
            if (pl.check) {
                return executeCheck(cmd_name, algo, pl, stdout, allocator);
            } else {
                return executeDigest(cmd_name, algo, pl, stdout, allocator);
            }
        },
    }
}

fn executeCheck(
    cmd_name: []const u8,
    algo: Algorithm,
    p: legacy_opt.LegacyParsedArgs,
    stdout: *std.Io.Writer,
    allocator: std.mem.Allocator,
) !u8 {
    const check_opts = check_mod.CheckOptions{
        .quiet = p.quiet,
        .status_only = p.status_only,
        .strict = p.strict,
        .warn = p.warn,
        .ignore_missing = p.ignore_missing,
        .expected_algo = algo,
        .expected_length = p.length_bits,
    };
    var exit_code: u8 = 0;
    if (p.files.items.len == 0) {
        exit_code = try check_mod.verifyFile(cmd_name, "-", check_opts, stdout, allocator);
    } else {
        for (p.files.items) |f| {
            const rc = try check_mod.verifyFile(cmd_name, f, check_opts, stdout, allocator);
            if (rc != 0) exit_code = rc;
        }
    }
    try stdout.flush();
    return exit_code;
}

fn executeDigest(
    cmd_name: []const u8,
    algo: Algorithm,
    p: legacy_opt.LegacyParsedArgs,
    stdout: *std.Io.Writer,
    allocator: std.mem.Allocator,
) !u8 {
    const digest_opts = engine_mod.DigestOptions{
        .algo = algo,
        .length_bits = p.length_bits,
        .tagged = p.tagged,
        .binary = p.binary,
        .raw = false,
        .base64 = false,
        .zero = p.zero,
        .files = p.files.items,
    };
    const rc = try engine_mod.digestFiles(cmd_name, digest_opts, stdout, allocator);
    try stdout.flush();
    return rc;
}

fn printHelp(writer: *std.Io.Writer, cmd_name: []const u8, accepts_length: bool) !void {
    try writer.print("Usage: {s} [OPTION]... [FILE]...\n", .{cmd_name});
    try writer.print("Print or check checksums.\n\n", .{});
    if (accepts_length) {
        try writer.print("  -l, --length=BITS  digest length in bits; must not exceed maximum for blake2b\n", .{});
    }
    try writer.print("  -b, --binary         read in binary mode\n", .{});
    try writer.print("  -c, --check          read checksums from the FILEs and check them\n", .{});
    try writer.print("      --tag            create a BSD-style checksum\n", .{});
    try writer.print("  -t, --text           read in text mode (default)\n", .{});
    try writer.print("  -z, --zero           end each output line with NUL, not newline\n\n", .{});
    try writer.print("The following five options are useful only when verifying checksums:\n", .{});
    try writer.print("      --ignore-missing  don't fail or report status for missing files\n", .{});
    try writer.print("      --quiet          don't print OK for each successfully verified file\n", .{});
    try writer.print("      --status         don't output anything, status code shows success\n", .{});
    try writer.print("      --strict         exit non-zero for improperly formatted checksum lines\n", .{});
    try writer.print("  -w, --warn           warn about improperly formatted checksum lines\n\n", .{});
    try writer.print("      --help           display this help and exit\n", .{});
    try writer.print("      --version        output version information and exit\n", .{});
}

fn printVersion(writer: *std.Io.Writer, cmd_name: []const u8) !void {
    try writer.print("{s} (coreutilz) 0.1.0\n", .{cmd_name});
    try writer.print("Copyright (C) 2026 Rénich Bon Ćirić and coreutilz contributors.\n", .{});
    try writer.print("License GPLv3+: GNU GPL version 3 or later <https://gnu.org/licenses/gpl.html>.\n", .{});
    try writer.print("This is free software: you are free to change and redistribute it.\n", .{});
    try writer.print("There is NO WARRANTY, to the extent permitted by law.\n", .{});
}

fn validateParsed(cmd_name: []const u8, p: *legacy_opt.LegacyParsedArgs) u8 {
    if (!p.check) {
        const rc = validateLegacyDigest(cmd_name, p);
        if (rc != 0) return rc;
    } else {
        const rc = validateLegacyCheck(cmd_name, p);
        if (rc != 0) return rc;
    }
    if (p.length_str) |s| {
        p.length_bits = parseLength(cmd_name, s) orelse return 1;
    }
    return 0;
}

fn validateLegacyDigest(cmd_name: []const u8, p: *const legacy_opt.LegacyParsedArgs) u8 {
    if (p.ignore_missing) {
        opt_mod.emitVerifyOnly(cmd_name, "ignore-missing");
        return 1;
    }
    if (p.status_only) {
        opt_mod.emitVerifyOnly(cmd_name, "status");
        return 1;
    }
    if (p.warn) {
        opt_mod.emitVerifyOnly(cmd_name, "warn");
        return 1;
    }
    if (p.quiet) {
        opt_mod.emitVerifyOnly(cmd_name, "quiet");
        return 1;
    }
    if (p.strict) {
        opt_mod.emitVerifyOnly(cmd_name, "strict");
        return 1;
    }
    if (p.text_seen and p.tag_seen and p.tagged) {
        opt_mod.emitError(cmd_name, "--tag does not support --text mode", .{});
        opt_mod.emitTryHelp(cmd_name);
        return 1;
    }
    return 0;
}

fn validateLegacyCheck(cmd_name: []const u8, p: *const legacy_opt.LegacyParsedArgs) u8 {
    if (p.zero_seen) {
        opt_mod.emitError(cmd_name, "the --zero option is not supported when verifying checksums", .{});
        opt_mod.emitTryHelp(cmd_name);
        return 1;
    }
    if (p.tag_seen and p.tagged) {
        opt_mod.emitError(cmd_name, "the --tag option is meaningless when verifying checksums", .{});
        opt_mod.emitTryHelp(cmd_name);
        return 1;
    }
    if (p.binary_seen or p.text_seen) {
        opt_mod.emitError(cmd_name, "the --binary and --text options are meaningless when verifying checksums", .{});
        opt_mod.emitTryHelp(cmd_name);
        return 1;
    }
    return 0;
}

fn parseLength(cmd_name: []const u8, str: []const u8) ?usize {
    for (str) |ch| {
        if (!std.ascii.isDigit(ch)) {
            opt_mod.emitError(cmd_name, "invalid length: '{s}'", .{str});
            return null;
        }
    }
    const bits = std.fmt.parseInt(usize, str, 10) catch std.math.maxInt(usize);
    if (bits > 512) {
        opt_mod.emitError(cmd_name, "invalid length: '{s}'\n{s}: maximum digest length for 'BLAKE2b' is 512 bits", .{ str, cmd_name });
        return null;
    }
    if (bits % 8 != 0) {
        opt_mod.emitError(cmd_name, "invalid length: '{s}'\n{s}: length is not a multiple of 8", .{ str, cmd_name });
        return null;
    }
    return if (bits == 0) 512 else bits;
}
