const std = @import("std");

pub const BsdSum = struct {
    checksum: u16 = 0,
    total_bytes: u64 = 0,

    pub fn init() BsdSum {
        return .{};
    }

    pub fn update(self: *BsdSum, bytes: []const u8) void {
        self.total_bytes += bytes.len;
        for (bytes) |b| {
            self.checksum = (self.checksum >> 1) +% ((self.checksum & 1) << 15);
            self.checksum = (self.checksum +% b) & 0xFFFF;
        }
    }

    pub fn final(self: *const BsdSum) struct { checksum: u16, blocks: u64 } {
        const blocks = (self.total_bytes + 1023) / 1024;
        return .{
            .checksum = self.checksum,
            .blocks = blocks,
        };
    }
};

pub const SysvSum = struct {
    sum: u32 = 0,
    total_bytes: u64 = 0,

    pub fn init() SysvSum {
        return .{};
    }

    pub fn update(self: *SysvSum, bytes: []const u8) void {
        self.total_bytes += bytes.len;
        for (bytes) |b| {
            self.sum = self.sum +% b;
        }
    }

    pub fn final(self: *const SysvSum) struct { checksum: u16, blocks: u64 } {
        const r = (self.sum & 0xFFFF) +% (self.sum >> 16);
        const checksum = (r & 0xFFFF) +% (r >> 16);
        const blocks = (self.total_bytes + 511) / 512;
        return .{
            .checksum = @as(u16, @truncate(checksum)),
            .blocks = blocks,
        };
    }
};
