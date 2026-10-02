const std = @import("std");
const algo_mod = @import("algorithm.zig");
const Algorithm = algo_mod.Algorithm;

pub const ParsedLine = struct {
    algo: Algorithm,
    length_bits: ?usize,
    filename: []const u8,
    digest_str: [128]u8,
    digest_str_len: usize,
    is_base64: bool,
    escaped: bool,
};

pub const LineResult = union(enum) {
    parsed: ParsedLine,
    ignored: void,
    invalid: void,
};

pub fn parseLine(
    line: []const u8,
    expected_algo: ?Algorithm,
    expected_length: ?usize,
    bsd_reversed: *?bool,
) LineResult {
    const s = std.mem.trimEnd(u8, line, "\r\n");
    if (s.len == 0 or s[0] == '#') return .ignored;

    const trimmed = std.mem.trimStart(u8, s, " \t");
    if (trimmed.len == 0) return .ignored;
    const escaped = trimmed[0] == '\\';
    const content = if (escaped) trimmed[1..] else trimmed;

    if (parseTagged(content, escaped, expected_algo, expected_length)) |res| {
        return .{ .parsed = res };
    }

    if (parseUntagged(content, escaped, expected_algo, expected_length, bsd_reversed)) |res| {
        return .{ .parsed = res };
    }

    return .invalid;
}

pub fn parseLeadingTag(line: []const u8) ?[]const u8 {
    var s = std.mem.trimStart(u8, line, " \t");
    if (s.len > 0 and s[0] == '\\') {
        s = s[1..];
        if (s.len > 0 and (s[0] == ' ' or s[0] == '\t')) return null;
    }
    s = std.mem.trimStart(u8, s, " \t");

    var i: usize = 0;
    while (i < s.len and s[i] != ' ' and s[i] != '\t' and s[i] != '-' and s[i] != '(') : (i += 1) {}
    if (i == 0) return null;
    const tag = s[0..i];

    const known_tags = [_][]const u8{
        "BLAKE2b", "SHA3", "SHA2", "SHA512", "SHA384", "SHA256", "SHA224", "SHA1", "MD5", "SM3",
        "CRC32B",  "CRC",  "SYSV", "BSD",
    };
    for (known_tags) |t| {
        if (std.ascii.eqlIgnoreCase(tag, t)) return t;
    }
    return null;
}

fn makeParsedLine(algo: Algorithm, len_bits: ?usize, name: []const u8, digest: []const u8, is_b64: bool, esc: bool) ParsedLine {
    var pl = ParsedLine{
        .algo = algo,
        .length_bits = len_bits,
        .filename = name,
        .digest_str = undefined,
        .digest_str_len = digest.len,
        .is_base64 = is_b64,
        .escaped = esc,
    };
    @memcpy(pl.digest_str[0..digest.len], digest);
    return pl;
}

fn parseTagged(
    s: []const u8,
    escaped: bool,
    expected_algo: ?Algorithm,
    expected_length: ?usize,
) ?ParsedLine {
    const lparen = std.mem.indexOfScalar(u8, s, '(') orelse return null;
    const before = s[0..lparen];
    const tag_str = if (before.len > 0 and before[before.len - 1] == ' ') before[0 .. before.len - 1] else before;
    if (tag_str.len == 0 or (tag_str.len > 0 and tag_str[tag_str.len - 1] == ' ')) return null;

    var algo_val: Algorithm = undefined;
    var len_bits: ?usize = null;
    if (!matchTag(tag_str, &algo_val, &len_bits)) return null;

    if (expected_algo) |exp| {
        if (!exp.matches(algo_val)) return null;
    }

    const rparen = std.mem.lastIndexOfScalar(u8, s, ')') orelse return null;
    if (rparen <= lparen) return null;

    const after = std.mem.trimStart(u8, s[rparen + 1 ..], " \t");
    if (after.len == 0 or after[0] != '=') return null;
    const digest_str = std.mem.trimStart(u8, after[1..], " \t");
    if (digest_str.len == 0 or digest_str.len > 128) return null;

    const final_len = len_bits orelse expected_length;
    var is_b64 = false;
    if (!validDigest(digest_str, algo_val, final_len, &is_b64)) return null;

    return makeParsedLine(algo_val, final_len, s[lparen + 1 .. rparen], digest_str, is_b64, escaped);
}

pub fn matchTag(tag: []const u8, algo: *Algorithm, len_bits: *?usize) bool {
    if (std.mem.startsWith(u8, tag, "BLAKE2b")) {
        algo.* = .blake2b;
        if (tag.len == 7) {
            len_bits.* = 512;
            return true;
        }
        if (tag[7] != '-') return false;
        const bits = std.fmt.parseInt(usize, tag[8..], 10) catch return false;
        if (bits == 0 or bits > 512 or bits % 8 != 0) return false;
        len_bits.* = bits;
        return true;
    }
    if (std.mem.eql(u8, tag, "MD5")) {
        algo.* = .md5;
        return true;
    }
    if (std.mem.eql(u8, tag, "SHA1")) {
        algo.* = .sha1;
        return true;
    }
    if (std.mem.eql(u8, tag, "SM3")) {
        algo.* = .sm3;
        return true;
    }
    return matchShaTag(tag, algo, len_bits);
}

fn matchShaTag(tag: []const u8, algo: *Algorithm, len_bits: *?usize) bool {
    const fixed = [_]struct { name: []const u8, a: Algorithm, bits: usize }{
        .{ .name = "SHA224", .a = .sha224, .bits = 224 },
        .{ .name = "SHA256", .a = .sha256, .bits = 256 },
        .{ .name = "SHA384", .a = .sha384, .bits = 384 },
        .{ .name = "SHA512", .a = .sha512, .bits = 512 },
    };
    for (fixed) |f| {
        if (std.mem.eql(u8, tag, f.name)) {
            algo.* = f.a;
            len_bits.* = f.bits;
            return true;
        }
    }
    if (std.mem.startsWith(u8, tag, "SHA2-") or std.mem.startsWith(u8, tag, "SHA3-")) {
        const is_sha3 = tag[3] == '3';
        const bits = std.fmt.parseInt(usize, tag[5..], 10) catch return false;
        algo.* = mapShaAlgo(if (is_sha3) .sha3 else .sha2, bits) orelse return false;
        len_bits.* = bits;
        return true;
    }
    return false;
}

fn checkBsdReversed(rem: []const u8, bsd_reversed: *?bool) ?bool {
    if (bsd_reversed.*) |b| {
        if (b) return true;
        if (rem.len < 1 or (rem[0] != ' ' and rem[0] != '*')) return null;
        return false;
    }
    const is_rev = rem.len == 1 or (rem[0] != ' ' and rem[0] != '*');
    bsd_reversed.* = is_rev;
    return is_rev;
}

fn parseUntagged(
    s: []const u8,
    escaped: bool,
    expected_algo: ?Algorithm,
    expected_length: ?usize,
    bsd_reversed: *?bool,
) ?ParsedLine {
    const raw_algo = expected_algo orelse return null;
    const sep = std.mem.indexOfAny(u8, s, " \t") orelse return null;
    const digest_str = s[0..sep];
    if (digest_str.len == 0 or digest_str.len > 128) return null;

    const rem = s[sep + 1 ..];
    if (rem.len == 0) return null;

    var final_algo = raw_algo;
    var final_len = expected_length;

    if (raw_algo == .sha2 or raw_algo == .sha3) {
        const bits = deduceShaBits(digest_str.len, expected_length, isHexOnly(digest_str)) orelse return null;
        final_len = bits;
        final_algo = mapShaAlgo(raw_algo, bits) orelse return null;
    } else if (raw_algo == .blake2b) {
        final_len = deduceBlake2bBits(digest_str, expected_length) orelse return null;
    }

    var is_b64 = false;
    if (!validDigest(digest_str, final_algo, final_len, &is_b64)) return null;

    const is_bsd_rev = checkBsdReversed(rem, bsd_reversed) orelse return null;
    const filename = if (is_bsd_rev) rem else rem[1..];
    if (filename.len == 0) return null;

    return makeParsedLine(final_algo, final_len, filename, digest_str, is_b64, escaped);
}

fn isHexOnly(s: []const u8) bool {
    for (s) |c| {
        if (!std.ascii.isHex(c)) return false;
    }
    return true;
}

fn isBase64Char(c: u8) bool {
    return std.ascii.isAlphanumeric(c) or c == '+' or c == '/';
}

fn validDigest(str: []const u8, algo: Algorithm, len_bits: ?usize, is_b64: *bool) bool {
    const exp_bytes = algo.digestBytes(len_bits);
    if (str.len == exp_bytes * 2 and isHexOnly(str)) {
        is_b64.* = false;
        return true;
    }
    const b64_padded = ((exp_bytes + 2) / 3) * 4;
    if (str.len == b64_padded) {
        const pad = (3 - (exp_bytes % 3)) % 3;
        for (str[0 .. str.len - pad]) |c| if (!isBase64Char(c)) return false;
        for (str[str.len - pad ..]) |c| if (c != '=') return false;
        is_b64.* = true;
        return true;
    }
    return false;
}

fn deduceShaBits(len: usize, exp_len: ?usize, is_hex: bool) ?usize {
    const bits: usize = switch (len) {
        40, 56 => 224,
        44 => 256,
        64 => if (exp_len == 384 or !is_hex) 384 else 256,
        88, 128 => 512,
        96 => 384,
        else => return null,
    };
    if (exp_len) |exp| {
        if (bits != exp) return null;
    }
    return bits;
}

fn deduceBlake2bBits(str: []const u8, exp_len: ?usize) ?usize {
    var num_equals: usize = 0;
    var end = str.len;
    while (end > 0 and str[end - 1] == '=') : (end -= 1) num_equals += 1;
    const is_b64 = num_equals > 0 or !isHexOnly(str);
    const bits = if (is_b64) blk: {
        if (str.len % 4 != 0) return null;
        const bytes = (str.len / 4) * 3 - num_equals;
        if ((3 - (bytes % 3)) % 3 != num_equals) return null;
        break :blk bytes * 8;
    } else (str.len / 2) * 8;
    if (bits == 0 or bits > 512 or bits % 8 != 0) return null;
    if (exp_len) |exp| {
        if (bits != exp) return null;
    }
    return bits;
}

fn mapShaAlgo(raw: Algorithm, bits: usize) ?Algorithm {
    return if (raw == .sha2) switch (bits) {
        224 => .sha224,
        256 => .sha256,
        384 => .sha384,
        512 => .sha512,
        else => null,
    } else switch (bits) {
        224 => .sha3_224,
        256 => .sha3_256,
        384 => .sha3_384,
        512 => .sha3_512,
        else => null,
    };
}
