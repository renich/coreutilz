const std = @import("std");
const ls = @import("ls.zig");

pub const name: []const u8 = "dir";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    return ls.runProfile(args, allocator, .columns, name);
}
