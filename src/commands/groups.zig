const std = @import("std");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "groups";
pub const version: []const u8 = "0.1.0";

fn printCurrentGroups(stdout: anytype) !u8 {
    var groups: [128]c.gid_t = undefined;
    const count = c.getgroups(128, &groups);
    if (count < 0) return 1;

    const egid = c.getegid();
    var first = true;
    const eg_gr = c.getgrgid(egid);
    if (eg_gr != null and eg_gr.*.gr_name != null) {
        try stdout.print("{s}", .{std.mem.span(eg_gr.*.gr_name)});
        first = false;
    }

    for (groups[0..@intCast(count)]) |gid| {
        if (gid == egid) continue;
        if (!first) try stdout.writeByte(' ');
        first = false;
        const gr = c.getgrgid(gid);
        if (gr != null and gr.*.gr_name != null) {
            try stdout.print("{s}", .{std.mem.span(gr.*.gr_name)});
        } else {
            try stdout.print("{d}", .{gid});
        }
    }
    try stdout.writeByte('\n');
    return 0;
}

fn printUserGroups(un: []const u8, stdout: anytype, stderr: anytype, allocator: std.mem.Allocator) !bool {
    const un_z = allocator.dupeZ(u8, un) catch return false;
    defer allocator.free(un_z);

    const pw = c.getpwnam(un_z.ptr) orelse {
        try stderr.print("groups: '{s}': no such user\n", .{un});
        return false;
    };

    var groups: [128]c.gid_t = undefined;
    var ngroups: c_int = 128;
    _ = c.getgrouplist(pw.*.pw_name, pw.*.pw_gid, &groups, &ngroups);

    try stdout.print("{s} :", .{un});
    var i: usize = 0;
    while (i < @as(usize, @intCast(ngroups))) : (i += 1) {
        const gr = c.getgrgid(groups[i]);
        if (gr != null and gr.*.gr_name != null) {
            try stdout.print(" {s}", .{std.mem.span(gr.*.gr_name)});
        } else {
            try stdout.print(" {d}", .{groups[i]});
        }
    }
    try stdout.writeByte('\n');
    return true;
}

fn parseArgs(args: [][]const u8, users: *std.ArrayListUnmanaged([]const u8), alloc: std.mem.Allocator, stdout: anytype, stderr: anytype) !?u8 {
    var options_done = false;
    for (args[1..]) |arg| {
        if (!options_done and std.mem.eql(u8, arg, "--")) {
            options_done = true;
            continue;
        }
        if (!options_done and std.mem.eql(u8, arg, "--help")) {
            try stdout.print("Usage: groups [OPTION]... [USER]...\nPrint group memberships for each USER or, if no USER is specified, for\nthe current process (which may differ if the groups database has changed).\n", .{});
            return 0;
        } else if (!options_done and std.mem.eql(u8, arg, "--version")) {
            try stdout.print("groups (coreutilz) {s}\n", .{version});
            return 0;
        } else if (!options_done and std.mem.startsWith(u8, arg, "-") and !std.mem.eql(u8, arg, "-")) {
            if (std.mem.startsWith(u8, arg, "--")) {
                try stderr.print("groups: unrecognized option '{s}'\nTry 'groups --help' for more information.\n", .{arg});
            } else {
                try stderr.print("groups: invalid option -- '{c}'\nTry 'groups --help' for more information.\n", .{arg[1]});
            }
            return 1;
        } else {
            try users.append(alloc, arg);
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

    var users: std.ArrayListUnmanaged([]const u8) = .empty;
    defer users.deinit(allocator);

    if (try parseArgs(args, &users, allocator, stdout, stderr)) |rc| {
        stdout.flush() catch return 1;
        stderr.flush() catch {};
        return rc;
    }

    if (users.items.len == 0) {
        const rc = try printCurrentGroups(stdout);
        stdout.flush() catch return 1;
        return rc;
    }

    var exit_code: u8 = 0;
    for (users.items) |un| {
        if (!try printUserGroups(un, stdout, stderr, allocator)) exit_code = 1;
    }
    stdout.flush() catch return 1;
    stderr.flush() catch {};
    return exit_code;
}
