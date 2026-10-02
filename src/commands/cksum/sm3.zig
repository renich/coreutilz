const std = @import("std");

pub const Sm3 = struct {
    s: [8]u32 = init_state,
    buf: [64]u8 = undefined,
    buf_len: usize = 0,
    total_bytes: u64 = 0,

    pub const digest_length = 32;
    pub const block_length = 64;

    const init_state = [8]u32{
        0x7380166f, 0x4914b2b9, 0x172442d7, 0xda8a0600,
        0xa96f30bc, 0x163138aa, 0xe38dee4d, 0xb0fb0e4e,
    };

    pub fn init() Sm3 {
        return .{};
    }

    pub fn update(self: *Sm3, b: []const u8) void {
        self.total_bytes += b.len;
        var off: usize = 0;
        if (self.buf_len != 0 and self.buf_len + b.len >= 64) {
            const need = 64 - self.buf_len;
            @memcpy(self.buf[self.buf_len..64], b[0..need]);
            self.compress(&self.buf);
            self.buf_len = 0;
            off += need;
        }
        while (off + 64 <= b.len) : (off += 64) {
            self.compress(b[off..][0..64]);
        }
        if (off < b.len) {
            const rem = b[off..];
            @memcpy(self.buf[self.buf_len .. self.buf_len + rem.len], rem);
            self.buf_len += rem.len;
        }
    }

    pub fn final(self: *Sm3, out: *[32]u8) void {
        const total_bits = self.total_bytes * 8;
        self.buf[self.buf_len] = 0x80;
        self.buf_len += 1;
        if (self.buf_len > 56) {
            @memset(self.buf[self.buf_len..64], 0);
            self.compress(&self.buf);
            self.buf_len = 0;
        }
        @memset(self.buf[self.buf_len..56], 0);
        std.mem.writeInt(u64, self.buf[56..64], total_bits, .big);
        self.compress(&self.buf);

        for (self.s, 0..) |word, i| {
            std.mem.writeInt(u32, out[i * 4 ..][0..4], word, .big);
        }
    }

    fn expandMessage(block: *const [64]u8, w: *[68]u32, w1: *[64]u32) void {
        for (0..16) |i| {
            w[i] = std.mem.readInt(u32, block[i * 4 ..][0..4], .big);
        }
        for (16..68) |j| {
            const p1_val = w[j - 16] ^ w[j - 9] ^ std.math.rotl(u32, w[j - 3], 15);
            w[j] = p1(p1_val) ^ std.math.rotl(u32, w[j - 13], 7) ^ w[j - 6];
        }
        for (0..64) |j| {
            w1[j] = w[j] ^ w[j + 4];
        }
    }

    fn compress(self: *Sm3, block: *const [64]u8) void {
        var w: [68]u32 = undefined;
        var w1: [64]u32 = undefined;
        expandMessage(block, &w, &w1);

        var a = self.s[0];
        var b = self.s[1];
        var c = self.s[2];
        var d = self.s[3];
        var e = self.s[4];
        var f = self.s[5];
        var g = self.s[6];
        var h = self.s[7];

        for (0..64) |j| {
            const tj: u32 = if (j < 16) 0x79cc4519 else 0x7a879d8a;
            const rot_j: u5 = @intCast(j % 32);
            const a_rot12 = std.math.rotl(u32, a, 12);
            const ss1 = std.math.rotl(u32, a_rot12 +% e +% std.math.rotl(u32, tj, rot_j), 7);
            const ss2 = ss1 ^ a_rot12;
            const tt1 = ff(j, a, b, c) +% d +% ss2 +% w1[j];
            const tt2 = gg(j, e, f, g) +% h +% ss1 +% w[j];
            d = c;
            c = std.math.rotl(u32, b, 9);
            b = a;
            a = tt1;
            h = g;
            g = std.math.rotl(u32, f, 19);
            f = e;
            e = p0(tt2);
        }
        self.s[0] ^= a;
        self.s[1] ^= b;
        self.s[2] ^= c;
        self.s[3] ^= d;
        self.s[4] ^= e;
        self.s[5] ^= f;
        self.s[6] ^= g;
        self.s[7] ^= h;
    }

    fn ff(j: usize, x: u32, y: u32, z: u32) u32 {
        return if (j < 16) (x ^ y ^ z) else ((x & y) | (x & z) | (y & z));
    }

    fn gg(j: usize, x: u32, y: u32, z: u32) u32 {
        return if (j < 16) (x ^ y ^ z) else ((x & y) | (~x & z));
    }

    fn p0(x: u32) u32 {
        return x ^ std.math.rotl(u32, x, 9) ^ std.math.rotl(u32, x, 17);
    }

    fn p1(x: u32) u32 {
        return x ^ std.math.rotl(u32, x, 15) ^ std.math.rotl(u32, x, 23);
    }
};

test "sm3 test vectors" {
    var hasher = Sm3.init();
    var out: [32]u8 = undefined;
    hasher.final(&out);
    const hex = std.fmt.bytesToHex(out, .lower);
    try std.testing.expectEqualStrings("1ab21d8355cfa17f8e61194831e81a8f22bec8c728fefb747ed035eb5082aa2b", &hex);

    var hasher2 = Sm3.init();
    hasher2.update("abc");
    var out2: [32]u8 = undefined;
    hasher2.final(&out2);
    const hex2 = std.fmt.bytesToHex(out2, .lower);
    try std.testing.expectEqualStrings("66c7f0f462eeedd9d1f2d46bdc10e4e24167c4875cf2f7a2297da02b8f4ba8e0", &hex2);
}
