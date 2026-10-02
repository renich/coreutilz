const std = @import("std");
const crc_mod = @import("crc.zig");
const sum_mod = @import("sum.zig");
const sm3_mod = @import("sm3.zig");

pub const Algorithm = enum {
    bsd,
    sysv,
    crc,
    crc32b,
    md5,
    sha1,
    sha2,
    sha224,
    sha256,
    sha384,
    sha512,
    blake2b,
    sm3,
    sha3,
    sha3_224,
    sha3_256,
    sha3_384,
    sha3_512,

    pub fn fromName(str: []const u8) ?Algorithm {
        if (std.mem.eql(u8, str, "bsd")) return .bsd;
        if (std.mem.eql(u8, str, "sysv")) return .sysv;
        if (std.mem.eql(u8, str, "crc")) return .crc;
        if (std.mem.eql(u8, str, "crc32b")) return .crc32b;
        if (std.mem.eql(u8, str, "md5")) return .md5;
        if (std.mem.eql(u8, str, "sha1")) return .sha1;
        if (std.mem.eql(u8, str, "sha2")) return .sha2;
        if (std.mem.eql(u8, str, "sha224")) return .sha224;
        if (std.mem.eql(u8, str, "sha256")) return .sha256;
        if (std.mem.eql(u8, str, "sha384")) return .sha384;
        if (std.mem.eql(u8, str, "sha512")) return .sha512;
        if (std.mem.eql(u8, str, "blake2b")) return .blake2b;
        if (std.mem.eql(u8, str, "sm3")) return .sm3;
        if (std.mem.eql(u8, str, "sha3")) return .sha3;
        if (std.mem.eql(u8, str, "sha3-224")) return .sha3_224;
        if (std.mem.eql(u8, str, "sha3-256")) return .sha3_256;
        if (std.mem.eql(u8, str, "sha3-384")) return .sha3_384;
        if (std.mem.eql(u8, str, "sha3-512")) return .sha3_512;
        return null;
    }

    pub fn matches(self: Algorithm, other: Algorithm) bool {
        if (self == other) return true;
        if (self == .sha2 and (other == .sha224 or other == .sha256 or other == .sha384 or other == .sha512)) return true;
        if (self == .sha3 and (other == .sha3_224 or other == .sha3_256 or other == .sha3_384 or other == .sha3_512)) return true;
        return false;
    }

    pub fn isNumeric(self: Algorithm) bool {
        return switch (self) {
            .bsd, .sysv, .crc, .crc32b => true,
            else => false,
        };
    }

    pub fn digestBytes(self: Algorithm, custom_len_bits: ?usize) usize {
        return switch (self) {
            .crc, .crc32b => 4,
            .bsd, .sysv => 2,
            .md5 => 16,
            .sha1 => 20,
            .sha2 => if (custom_len_bits) |b| b / 8 else 32,
            .sha3 => if (custom_len_bits) |b| b / 8 else 32,
            .sha224, .sha3_224 => 28,
            .sha256, .sm3, .sha3_256 => 32,
            .sha384, .sha3_384 => 48,
            .sha512, .sha3_512 => 64,
            .blake2b => if (custom_len_bits) |bits| (if (bits == 0) 64 else bits / 8) else 64,
        };
    }
};

pub const AnyHasher = union(Algorithm) {
    bsd: sum_mod.BsdSum,
    sysv: sum_mod.SysvSum,
    crc: crc_mod.PosixCrc,
    crc32b: crc_mod.Crc32b,
    md5: std.crypto.hash.Md5,
    sha1: std.crypto.hash.Sha1,
    sha2: void,
    sha224: std.crypto.hash.sha2.Sha224,
    sha256: std.crypto.hash.sha2.Sha256,
    sha384: std.crypto.hash.sha2.Sha384,
    sha512: std.crypto.hash.sha2.Sha512,
    blake2b: struct { hasher: std.crypto.hash.blake2.Blake2b512, out_bytes: usize },
    sm3: sm3_mod.Sm3,
    sha3: void,
    sha3_224: std.crypto.hash.sha3.Sha3_224,
    sha3_256: std.crypto.hash.sha3.Sha3_256,
    sha3_384: std.crypto.hash.sha3.Sha3_384,
    sha3_512: std.crypto.hash.sha3.Sha3_512,

    pub fn init(algo: Algorithm, len_bits: ?usize) AnyHasher {
        return switch (algo) {
            .bsd => .{ .bsd = sum_mod.BsdSum.init() },
            .sysv => .{ .sysv = sum_mod.SysvSum.init() },
            .crc => .{ .crc = crc_mod.PosixCrc.init() },
            .crc32b => .{ .crc32b = crc_mod.Crc32b.init() },
            .md5 => .{ .md5 = std.crypto.hash.Md5.init(.{}) },
            .sha1 => .{ .sha1 = std.crypto.hash.Sha1.init(.{}) },
            .sha2, .sha3 => unreachable,
            .sha224 => .{ .sha224 = std.crypto.hash.sha2.Sha224.init(.{}) },
            .sha256 => .{ .sha256 = std.crypto.hash.sha2.Sha256.init(.{}) },
            .sha384 => .{ .sha384 = std.crypto.hash.sha2.Sha384.init(.{}) },
            .sha512 => .{ .sha512 = std.crypto.hash.sha2.Sha512.init(.{}) },
            .blake2b => blk: {
                const bits = if (len_bits) |b| (if (b == 0) 512 else b) else 512;
                break :blk .{
                    .blake2b = .{
                        .hasher = std.crypto.hash.blake2.Blake2b512.init(.{ .expected_out_bits = bits }),
                        .out_bytes = bits / 8,
                    },
                };
            },
            .sm3 => .{ .sm3 = sm3_mod.Sm3.init() },
            .sha3_224 => .{ .sha3_224 = std.crypto.hash.sha3.Sha3_224.init(.{}) },
            .sha3_256 => .{ .sha3_256 = std.crypto.hash.sha3.Sha3_256.init(.{}) },
            .sha3_384 => .{ .sha3_384 = std.crypto.hash.sha3.Sha3_384.init(.{}) },
            .sha3_512 => .{ .sha3_512 = std.crypto.hash.sha3.Sha3_512.init(.{}) },
        };
    }

    pub fn update(self: *AnyHasher, bytes: []const u8) void {
        switch (self.*) {
            .bsd => |*h| h.update(bytes),
            .sysv => |*h| h.update(bytes),
            .crc => |*h| h.update(bytes),
            .crc32b => |*h| h.update(bytes),
            .md5 => |*h| h.update(bytes),
            .sha1 => |*h| h.update(bytes),
            .sha2, .sha3 => unreachable,
            .sha224 => |*h| h.update(bytes),
            .sha256 => |*h| h.update(bytes),
            .sha384 => |*h| h.update(bytes),
            .sha512 => |*h| h.update(bytes),
            .blake2b => |*h| h.hasher.update(bytes),
            .sm3 => |*h| h.update(bytes),
            .sha3_224 => |*h| h.update(bytes),
            .sha3_256 => |*h| h.update(bytes),
            .sha3_384 => |*h| h.update(bytes),
            .sha3_512 => |*h| h.update(bytes),
        }
    }

    fn finalNumeric(self: *AnyHasher, out: []u8) usize {
        switch (self.*) {
            .bsd => |*h| {
                const res = h.final();
                std.mem.writeInt(u16, out[0..2], res.checksum, .big);
                return 2;
            },
            .sysv => |*h| {
                const res = h.final();
                std.mem.writeInt(u16, out[0..2], res.checksum, .big);
                return 2;
            },
            .crc => |*h| {
                const val = h.final();
                std.mem.writeInt(u32, out[0..4], val, .big);
                return 4;
            },
            .crc32b => |*h| {
                const val = h.final();
                std.mem.writeInt(u32, out[0..4], val, .big);
                return 4;
            },
            else => unreachable,
        }
    }

    fn finalSha2(self: *AnyHasher, out: []u8) usize {
        switch (self.*) {
            .sha224 => |*h| {
                h.final(out[0..28]);
                return 28;
            },
            .sha256 => |*h| {
                h.final(out[0..32]);
                return 32;
            },
            .sha384 => |*h| {
                h.final(out[0..48]);
                return 48;
            },
            .sha512 => |*h| {
                h.final(out[0..64]);
                return 64;
            },
            else => unreachable,
        }
    }

    fn finalSha3(self: *AnyHasher, out: []u8) usize {
        switch (self.*) {
            .sha3_224 => |*h| {
                h.final(out[0..28]);
                return 28;
            },
            .sha3_256 => |*h| {
                h.final(out[0..32]);
                return 32;
            },
            .sha3_384 => |*h| {
                h.final(out[0..48]);
                return 48;
            },
            .sha3_512 => |*h| {
                h.final(out[0..64]);
                return 64;
            },
            else => unreachable,
        }
    }

    fn finalOther(self: *AnyHasher, out: []u8) usize {
        switch (self.*) {
            .md5 => |*h| {
                h.final(out[0..16]);
                return 16;
            },
            .sha1 => |*h| {
                h.final(out[0..20]);
                return 20;
            },
            .blake2b => |*h| {
                var full: [64]u8 = undefined;
                h.hasher.final(&full);
                @memcpy(out[0..h.out_bytes], full[0..h.out_bytes]);
                return h.out_bytes;
            },
            .sm3 => |*h| {
                var d: [32]u8 = undefined;
                h.final(&d);
                @memcpy(out[0..32], d[0..32]);
                return 32;
            },
            else => unreachable,
        }
    }

    pub fn final(self: *AnyHasher, out: []u8) usize {
        return switch (self.*) {
            .bsd, .sysv, .crc, .crc32b => self.finalNumeric(out),
            .md5, .sha1, .blake2b, .sm3 => self.finalOther(out),
            .sha224, .sha256, .sha384, .sha512 => self.finalSha2(out),
            .sha3_224, .sha3_256, .sha3_384, .sha3_512 => self.finalSha3(out),
            .sha2, .sha3 => unreachable,
        };
    }
};

test "blake2b 128 bit" {
    var hasher = AnyHasher.init(.blake2b, 128);
    var out: [64]u8 = undefined;
    const n = hasher.final(&out);
    try std.testing.expectEqual(@as(usize, 16), n);
    const hex = std.fmt.bytesToHex(out[0..16].*, .lower);
    try std.testing.expectEqualStrings("cae66941d9efbd404e4d88758ea67670", &hex);
}
