const std = @import("std");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "chroot";
pub const version: []const u8 = "0.1.0";

fn parseUid(s: []const u8) ?c.uid_t {
    if (std.fmt.parseInt(c.uid_t, s, 10)) |u| {
        return u;
    } else |_| {}
    var z: [256:0]u8 = undefined;
    if (s.len >= z.len) return null;
    @memcpy(z[0..s.len], s);
    z[s.len] = 0;
    const pw = c.getpwnam(&z);
    if (pw != null) return pw.*.pw_uid;
    return null;
}

fn parseGid(s: []const u8) ?c.gid_t {
    if (std.fmt.parseInt(c.gid_t, s, 10)) |g| {
        return g;
    } else |_| {}
    var z: [256:0]u8 = undefined;
    if (s.len >= z.len) return null;
    @memcpy(z[0..s.len], s);
    z[s.len] = 0;
    const gr = c.getgrnam(&z);
    if (gr != null) return gr.*.gr_gid;
    return null;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &out_w.interface;
    const stderr = &err_w.interface;

    var userspec: ?[]const u8 = null;
    var groups_str: ?[]const u8 = null;
    var skip_chdir = false;
    var opt_idx: usize = 1;

    while (opt_idx < args.len) : (opt_idx += 1) {
        const arg = args[opt_idx];
        if (std.mem.eql(u8, arg, "--help")) {
            try stdout.print("Usage: chroot [OPTION] NEWROOT [COMMAND [ARG]...]\nRun COMMAND with root directory set to NEWROOT.\n", .{});
            stdout.flush() catch return 125;
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try stdout.print("chroot (coreutilz) {s}\n", .{version});
            stdout.flush() catch return 125;
            return 0;
        } else if (std.mem.startsWith(u8, arg, "--userspec=")) {
            userspec = arg["--userspec=".len..];
        } else if (std.mem.startsWith(u8, arg, "--groups=")) {
            groups_str = arg["--groups=".len..];
        } else if (std.mem.eql(u8, arg, "--skip-chdir")) {
            skip_chdir = true;
        } else if (std.mem.eql(u8, arg, "--")) {
            opt_idx += 1;
            break;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            try stderr.print("chroot: unrecognized option '{s}'\nTry 'chroot --help' for more information.\n", .{arg});
            stderr.flush() catch {};
            return 125;
        } else {
            break;
        }
    }

    if (opt_idx >= args.len) {
        try stderr.print("chroot: missing operand\nTry 'chroot --help' for more information.\n", .{});
        stderr.flush() catch {};
        return 125;
    }

    const newroot = args[opt_idx];
    opt_idx += 1;

    if (skip_chdir and !std.mem.eql(u8, newroot, "/")) {
        try stderr.print("chroot: option --skip-chdir only permitted if NEWROOT is old '/'\nTry 'chroot --help' for more information.\n", .{});
        stderr.flush() catch {};
        return 125;
    }

    var z_newroot: [std.fs.max_path_bytes:0]u8 = undefined;
    if (newroot.len >= z_newroot.len) return 125;
    @memcpy(z_newroot[0..newroot.len], newroot);
    z_newroot[newroot.len] = 0;

    if (c.chroot(&z_newroot) != 0) {
        const err = c.__errno_location().*;
        const msg = std.mem.span(c.strerror(err));
        try stderr.print("chroot: cannot change root directory to '{s}': {s}\n", .{ newroot, msg });
        stderr.flush() catch {};
        return 125;
    }

    if (!skip_chdir) {
        if (c.chdir("/") != 0) {
            try stderr.print("chroot: cannot change directory to '/'\n", .{});
            stderr.flush() catch {};
            return 125;
        }
    }

    if (groups_str) |g_list| {
        var gids: std.ArrayList(c.gid_t) = .empty;
        defer gids.deinit(allocator);
        var it = std.mem.splitScalar(u8, g_list, ',');
        while (it.next()) |item| {
            if (item.len > 0) {
                if (parseGid(item)) |g| {
                    try gids.append(allocator, g);
                }
            }
        }
        if (gids.items.len > 0) {
            _ = c.setgroups(@intCast(gids.items.len), gids.items.ptr);
        }
    }

    if (userspec) |us| {
        var u_part = us;
        var g_part: ?[]const u8 = null;
        if (std.mem.indexOfScalar(u8, us, ':')) |colon| {
            u_part = us[0..colon];
            g_part = us[colon + 1 ..];
        }
        if (g_part) |g| {
            if (parseGid(g)) |gid| {
                _ = c.setgid(gid);
            }
        }
        if (u_part.len > 0) {
            if (parseUid(u_part)) |uid| {
                _ = c.setuid(uid);
            }
        }
    }

    var default_cmd: [2][]const u8 = undefined;
    const cmd_slice: []const []const u8 = if (opt_idx < args.len)
        args[opt_idx..]
    else blk: {
        const sh = if (c.getenv("SHELL")) |ptr| std.mem.span(ptr) else "/bin/sh";
        default_cmd[0] = sh;
        default_cmd[1] = "-i";
        break :blk &default_cmd;
    };

    const cmd = cmd_slice[0];
    var c_argv: std.ArrayList(?*anyopaque) = .empty;
    defer c_argv.deinit(allocator);

    for (cmd_slice) |arg| {
        const z_arg = allocator.dupeZ(u8, arg) catch return 125;
        c_argv.append(allocator, @ptrCast(z_arg.ptr)) catch return 125;
    }
    c_argv.append(allocator, null) catch return 125;

    const cmd_z = allocator.dupeZ(u8, cmd) catch return 125;
    _ = c.execvp(cmd_z.ptr, @ptrCast(c_argv.items.ptr));

    const err = c.__errno_location().*;
    const msg = std.mem.span(c.strerror(err));
    try stderr.print("chroot: failed to run command '{s}': {s}\n", .{ cmd, msg });
    stderr.flush() catch {};

    if (err == c.ENOENT) return 127;
    return 126;
}
