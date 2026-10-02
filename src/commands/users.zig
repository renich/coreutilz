const std = @import("std");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "users";
pub const version: []const u8 = "0.1.0";

fn stringLessThan(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.order(u8, a, b) == .lt;
}

fn collectUsers(file: ?[]const u8, list: *std.ArrayListUnmanaged([]const u8), allocator: std.mem.Allocator) !void {
    if (file) |f| {
        const f_z = try allocator.dupeZ(u8, f);
        defer allocator.free(f_z);
        _ = c.utmpxname(f_z.ptr);
    }
    c.setutxent();
    defer c.endutxent();

    while (c.getutxent()) |ut| {
        if (ut.*.ut_type == c.USER_PROCESS) {
            const u = std.mem.sliceTo(ut.*.ut_user[0..], 0);
            if (u.len > 0) {
                const copy = try allocator.dupe(u8, u);
                try list.append(allocator, copy);
            }
        }
    }
}

fn parseOptions(args: [][]const u8, file: *?[]const u8, stdout: anytype, stderr: anytype) !?u8 {
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            try stdout.print("Usage: users [OPTION]... [FILE]\nOutput who is currently logged in according to FILE.\n", .{});
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try stdout.print("users (coreutilz) {s}\n", .{version});
            return 0;
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            try stderr.print("users: unrecognized option '{s}'\nTry 'users --help' for more information.\n", .{arg});
            return 1;
        } else {
            if (file.* != null) {
                try stderr.print("users: extra operand '{s}'\nTry 'users --help' for more information.\n", .{arg});
                return 1;
            }
            file.* = arg;
        }
    }
    return null;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &out_w.interface;
    const stderr = &err_w.interface;

    var file: ?[]const u8 = null;
    if (try parseOptions(args, &file, stdout, stderr)) |rc| {
        stdout.flush() catch return 1;
        stderr.flush() catch return 1;
        return rc;
    }

    var list: std.ArrayListUnmanaged([]const u8) = .empty;
    defer {
        for (list.items) |u| allocator.free(u);
        list.deinit(allocator);
    }

    try collectUsers(file, &list, allocator);
    std.mem.sort([]const u8, list.items, {}, stringLessThan);

    for (list.items, 0..) |u, idx| {
        if (idx > 0) try stdout.writeByte(' ');
        try stdout.print("{s}", .{u});
    }
    try stdout.writeByte('\n');
    stdout.flush() catch return 1;
    return 0;
}
