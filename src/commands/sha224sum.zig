const std = @import("std");
const legacy = @import("cksum/legacy.zig");

pub const name: []const u8 = "sha224sum";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    return legacy.runLegacy(name, .sha224, false, args, allocator);
}
