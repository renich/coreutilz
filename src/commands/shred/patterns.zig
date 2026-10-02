const std = @import("std");
const c = @import("../../compat/c.zig").c;

pub const patterns = [_]i32{
    -2, // 2 random passes
    2, 0x000, 0xFFF, // 1-bit
    2, 0x555, 0xAAA, // 2-bit
    -1, // 1 random pass
    6,  0x249, 0x492, 0x6DB, 0x924, 0xB6D, 0xDB6, // 3-bit
    12, 0x111, 0x222, 0x333, 0x444, 0x666, 0x777,
    0x888, 0x999, 0xBBB, 0xCCC, 0xDDD, 0xEEE, // 4-bit
    -1, // 1 random pass
    8,
    0x1000,
    0x1249,
    0x1492,
    0x16DB,
    0x1924,
    0x1B6D,
    0x1DB6,
    0x1FFF,
    14,
    0x1111,
    0x1222,
    0x1333,
    0x1444,
    0x1555,
    0x1666,
    0x1777,
    0x1888,
    0x1999,
    0x1AAA,
    0x1BBB,
    0x1CCC,
    0x1DDD,
    0x1EEE,
    -1, // 1 random pass
    0, // End
};

pub const RandSource = struct {
    fd: ?c_int = null,
    randnum: usize = 0,
    randmax: usize = 0,

    pub fn init(source_path: ?[]const u8, alloc: std.mem.Allocator) !RandSource {
        if (source_path) |p| {
            const pz = try alloc.dupeZ(u8, p);
            defer alloc.free(pz);
            const fd = c.open(pz.ptr, c.O_RDONLY);
            if (fd >= 0) return .{ .fd = fd };
        }
        return .{};
    }

    pub fn deinit(self: *RandSource) void {
        if (self.fd) |fd| _ = c.close(fd);
    }

    pub fn readBytes(self: *RandSource, buf: []u8) void {
        if (self.fd) |fd| {
            var off: usize = 0;
            while (off < buf.len) {
                const n = c.read(fd, buf[off..].ptr, buf.len - off);
                if (n <= 0) break;
                off += @intCast(n);
            }
            if (off < buf.len) {
                var io_source: std.Random.IoSource = .{ .io = std.Options.debug_io };
                io_source.interface().bytes(buf[off..]);
            }
        } else {
            var io_source: std.Random.IoSource = .{ .io = std.Options.debug_io };
            io_source.interface().bytes(buf);
        }
    }

    pub fn choose(self: *RandSource, choices: usize) usize {
        if (choices <= 1) return 0;
        const genmax = choices - 1;
        while (true) {
            if (self.randmax < genmax) {
                var rmax = self.randmax;
                var count: usize = 0;
                while (rmax < genmax) {
                    rmax = (rmax << 8) | 255;
                    count += 1;
                }
                var buf: [8]u8 = undefined;
                self.readBytes(buf[0..count]);
                for (0..count) |idx| {
                    self.randnum = (self.randnum << 8) | buf[idx];
                    self.randmax = (self.randmax << 8) | 255;
                }
            }
            if (self.randmax == genmax) {
                const res = self.randnum;
                self.randnum = 0;
                self.randmax = 0;
                return res;
            }
            const excess = self.randmax - genmax;
            const unusable = excess % choices;
            const last_usable = self.randmax - unusable;
            const reduced = self.randnum % choices;
            if (self.randnum <= last_usable) {
                self.randnum /= choices;
                self.randmax = excess / choices;
                return reduced;
            }
            self.randnum = reduced;
            self.randmax = unusable - 1;
        }
    }
};

fn sampleRemaining(dest: []i32, d_idx: *usize, p_idx: *usize, n: usize, k: usize, rand: *RandSource) void {
    var cur_n = n;
    var rem_k = k;
    while (cur_n > 0) {
        if (cur_n == rem_k or rand.choose(rem_k) < cur_n) {
            dest[d_idx.*] = patterns[p_idx.*];
            d_idx.* += 1;
            cur_n -= 1;
        }
        p_idx.* += 1;
        rem_k -= 1;
    }
}

fn choosePasses(dest: []i32, rand: *RandSource) usize {
    var randpasses: usize = 0;
    var p_idx: usize = 0;
    var d_idx: usize = 0;
    var n = dest.len;

    while (true) {
        var k = patterns[p_idx];
        p_idx += 1;
        if (k == 0) {
            p_idx = 0;
        } else if (k < 0) {
            k = -k;
            if (@as(usize, @intCast(k)) >= n) {
                randpasses += n;
                break;
            }
            randpasses += @intCast(k);
            n -= @intCast(k);
        } else if (@as(usize, @intCast(k)) <= n) {
            const uk: usize = @intCast(k);
            @memcpy(dest[d_idx .. d_idx + uk], patterns[p_idx .. p_idx + uk]);
            p_idx += uk;
            d_idx += uk;
            n -= uk;
        } else if (n < 2 or 3 * n < @as(usize, @intCast(k))) {
            randpasses += n;
            break;
        } else {
            sampleRemaining(dest, &d_idx, &p_idx, n, @intCast(k), rand);
            break;
        }
    }
    return randpasses;
}

fn shufflePasses(dest: []i32, randpasses_in: usize, rand: *RandSource) void {
    var randpasses = randpasses_in;
    var top = dest.len - randpasses;
    if (randpasses > 0) randpasses -= 1;
    var accum = randpasses;
    for (0..dest.len) |i| {
        if (accum <= randpasses) {
            accum += dest.len - 1;
            dest[top] = dest[i];
            top += 1;
            dest[i] = -1;
        } else {
            const swap = i + rand.choose(top - i);
            const tmp = dest[i];
            dest[i] = dest[swap];
            dest[swap] = tmp;
        }
        accum -|= randpasses;
    }
}

pub fn genpattern(dest: []i32, rand: *RandSource) void {
    if (dest.len == 0) return;
    const randpasses = choosePasses(dest, rand);
    shufflePasses(dest, randpasses, rand);
}

pub fn fillpattern(ptype: i32, r: []u8) void {
    if (r.len == 0) return;
    const bits: u32 = @as(u32, @bitCast(ptype)) & 0xfff;
    const full_bits = bits | (bits << 12);
    var pat: [3]u8 = undefined;
    pat[0] = @truncate((full_bits >> 4) & 255);
    pat[1] = @truncate((full_bits >> 8) & 255);
    pat[2] = @truncate(full_bits & 255);

    var i: usize = 0;
    while (i < r.len) : (i += 1) {
        r[i] = pat[i % 3];
    }
    if ((ptype & 0x1000) != 0) {
        i = 0;
        while (i < r.len) : (i += 512) {
            r[i] ^= 0x80;
        }
    }
}

pub fn passname(ptype: i32, buf: *[7]u8) []const u8 {
    if (ptype < 0) return "random";
    const bits: u32 = @as(u32, @bitCast(ptype)) & 0xfff;
    const full_bits = bits | (bits << 12);
    const b0: u8 = @truncate((full_bits >> 4) & 255);
    const b1: u8 = @truncate((full_bits >> 8) & 255);
    const b2: u8 = @truncate(full_bits & 255);
    return std.fmt.bufPrint(buf, "{x:0>2}{x:0>2}{x:0>2}", .{ b0, b1, b2 }) catch "random";
}
