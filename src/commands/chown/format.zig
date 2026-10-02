const std = @import("std");
const types = @import("types.zig");

pub const ChangeStatus = enum {
    retained,
    changed,
    failed,
};

pub fn formatUserGroup(
    is_chgrp: bool,
    user: ?[]const u8,
    group: ?[]const u8,
    allocator: std.mem.Allocator,
) ![]const u8 {
    if (is_chgrp) {
        return try allocator.dupe(u8, group orelse "");
    }
    if (user) |u| {
        if (group) |g| {
            if (u.len == 0) {
                return try std.fmt.allocPrint(allocator, ":{s}", .{g});
            }
            return try std.fmt.allocPrint(allocator, "{s}:{s}", .{ u, g });
        }
        return try allocator.dupe(u8, u);
    }
    if (group) |g| {
        return try std.fmt.allocPrint(allocator, ":{s}", .{g});
    }
    return try allocator.dupe(u8, "");
}

pub fn describeChange(
    cfg: *const types.ChownConfig,
    file: []const u8,
    status: ChangeStatus,
    old_spec: ?[]const u8,
    new_spec: []const u8,
    stdout: anytype,
) !void {
    if (cfg.verbosity == .off) return;
    if (cfg.verbosity == .changes_only and status != .changed) return;

    const noun = if (cfg.is_chgrp) "group" else "ownership";
    switch (status) {
        .retained => {
            const s = old_spec orelse new_spec;
            try stdout.print("{s} of '{s}' retained as {s}\n", .{ noun, file, s });
        },
        .changed => {
            const old = old_spec orelse "";
            try stdout.print("changed {s} of '{s}' from {s} to {s}\n", .{ noun, file, old, new_spec });
        },
        .failed => {
            try stdout.print("failed to change {s} of '{s}' to {s}\n", .{ noun, file, new_spec });
        },
    }
}
