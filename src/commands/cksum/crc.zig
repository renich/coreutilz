const std = @import("std");

pub const PosixCrc = struct {
    crc: u32 = 0,
    total_bytes: u64 = 0,

    const crctab: [256]u32 = blk: {
        @setEvalBranchQuota(10000);
        var table: [256]u32 = undefined;
        for (0..256) |i| {
            var r: u32 = @as(u32, @intCast(i)) << 24;
            for (0..8) |_| {
                if ((r & 0x80000000) != 0) {
                    r = (r << 1) ^ 0x04C11DB7;
                } else {
                    r <<= 1;
                }
            }
            table[i] = r;
        }
        break :blk table;
    };

    pub fn init() PosixCrc {
        return .{};
    }

    pub fn update(self: *PosixCrc, bytes: []const u8) void {
        self.total_bytes += bytes.len;
        for (bytes) |b| {
            self.crc = (self.crc << 8) ^ crctab[((self.crc >> 24) ^ b) & 0xFF];
        }
    }

    pub fn final(self: *PosixCrc) u32 {
        var len = self.total_bytes;
        while (len != 0) : (len >>= 8) {
            const b = @as(u8, @truncate(len & 0xFF));
            self.crc = (self.crc << 8) ^ crctab[((self.crc >> 24) ^ b) & 0xFF];
        }
        return ~self.crc;
    }
};

pub const Crc32b = struct {
    hasher: std.hash.crc.Crc32IsoHdlc,
    total_bytes: u64 = 0,

    pub fn init() Crc32b {
        return .{
            .hasher = std.hash.crc.Crc32IsoHdlc.init(),
            .total_bytes = 0,
        };
    }

    pub fn update(self: *Crc32b, bytes: []const u8) void {
        self.total_bytes += bytes.len;
        self.hasher.update(bytes);
    }

    pub fn final(self: *Crc32b) u32 {
        return self.hasher.final();
    }
};
