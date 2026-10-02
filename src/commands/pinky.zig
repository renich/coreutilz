const std = @import("std");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "pinky";
pub const version: []const u8 = "0.1.0";

const PinkyOptions = struct {
    long_format: bool = false,
    omit_home_shell: bool = false,
    omit_project: bool = false,
    omit_plan: bool = false,
    omit_head: bool = false,
    omit_name: bool = false,
    omit_where: bool = false,
    omit_idle: bool = false,
};

fn parseOptions(args: [][]const u8, opts: *PinkyOptions, users: *std.ArrayListUnmanaged([]const u8), alloc: std.mem.Allocator, stdout: anytype) !?u8 {
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            try stdout.print("Usage: pinky [OPTION]... [USER]...\nPrint user information.\n", .{});
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try stdout.print("pinky (coreutilz) {s}\n", .{version});
            return 0;
        } else if (std.mem.eql(u8, arg, "--lookup")) {
            continue;
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            for (arg[1..]) |ch| switch (ch) {
                'l' => opts.long_format = true,
                'b' => opts.omit_home_shell = true,
                'h' => opts.omit_project = true,
                'p' => opts.omit_plan = true,
                's' => opts.long_format = false,
                'f' => opts.omit_head = true,
                'w' => opts.omit_name = true,
                'i' => {
                    opts.omit_name = true;
                    opts.omit_where = true;
                },
                'q' => {
                    opts.omit_name = true;
                    opts.omit_where = true;
                    opts.omit_idle = true;
                },
                else => return 1,
            };
        } else {
            try users.append(alloc, arg);
        }
    }
    return null;
}

fn printFileIfExists(prefix: []const u8, dir_path: []const u8, file_name: []const u8, stdout: anytype, alloc: std.mem.Allocator) !void {
    const full_path = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ dir_path, file_name });
    defer alloc.free(full_path);
    const full_path_z = try alloc.dupeZ(u8, full_path);
    defer alloc.free(full_path_z);
    const fd = c.open(full_path_z.ptr, c.O_RDONLY);
    if (fd < 0) return;
    defer _ = c.close(fd);
    var buf: [1024]u8 = undefined;
    const n = c.read(fd, &buf, buf.len);
    if (n > 0) {
        const slice = buf[0..@intCast(n)];
        try stdout.print("{s}:\n{s}", .{ prefix, slice });
        if (slice[slice.len - 1] != '\n') try stdout.writeByte('\n');
    }
}

fn printLongUser(un: []const u8, opts: *const PinkyOptions, stdout: anytype, alloc: std.mem.Allocator) !void {
    const un_z = try alloc.dupeZ(u8, un);
    defer alloc.free(un_z);
    const pw = c.getpwnam(un_z.ptr);

    var real_name: []const u8 = "???";
    var dir: []const u8 = "";
    var shell: []const u8 = "";
    if (pw) |p| {
        dir = std.mem.span(p.*.pw_dir);
        shell = std.mem.span(p.*.pw_shell);
        if (p.*.pw_gecos != null) {
            const gecos = std.mem.span(p.*.pw_gecos);
            const comma_idx = std.mem.indexOfScalar(u8, gecos, ',') orelse gecos.len;
            real_name = gecos[0..comma_idx];
        } else {
            real_name = "";
        }
    }

    var col1_buf: [40]u8 = undefined;
    const l1_col1 = std.fmt.bufPrint(&col1_buf, "Login name: {s}", .{un}) catch &col1_buf;
    try stdout.print("{s:<40}In real life:  {s}\n", .{ l1_col1, real_name });

    if (!opts.omit_home_shell) {
        const l2_col1 = std.fmt.bufPrint(&col1_buf, "Directory: {s}", .{dir}) catch &col1_buf;
        try stdout.print("{s:<40}Shell:  {s}\n", .{ l2_col1, shell });
    }

    if (dir.len > 0) {
        if (!opts.omit_project) try printFileIfExists("Project", dir, ".project", stdout, alloc);
        if (!opts.omit_plan) try printFileIfExists("Plan", dir, ".plan", stdout, alloc);
    }
    try stdout.writeByte('\n');
}

fn printShortHeader(opts: *const PinkyOptions, stdout: anytype) !void {
    if (opts.omit_head) return;
    if (opts.omit_name and opts.omit_idle and opts.omit_where) {
        try stdout.print("Login     TTY      When            \n", .{});
    } else if (opts.omit_name and opts.omit_where) {
        try stdout.print("Login     TTY      Idle   When            \n", .{});
    } else if (opts.omit_name) {
        try stdout.print("Login     TTY      Idle   When             Where\n", .{});
    } else {
        try stdout.print("Login    Name                 TTY      Idle   When             Where\n", .{});
    }
}

fn userMatches(target: []const u8, users: []const []const u8) bool {
    if (users.len == 0) return true;
    for (users) |u| {
        if (std.mem.eql(u8, u, target)) return true;
    }
    return false;
}

fn getLineStatus(line: []const u8, tty_out: *[16]u8, idle_out: *[8]u8) void {
    var dev_path: [64]u8 = undefined;
    const path = std.fmt.bufPrintZ(&dev_path, "/dev/{s}", .{line}) catch {
        @memcpy(tty_out[0..6], "?seat0");
        @memcpy(idle_out[0..5], "?????");
        return;
    };
    var st: c.struct_stat = undefined;
    if (c.stat(path.ptr, &st) != 0) {
        const l_fmt = std.fmt.bufPrint(tty_out, "?{s}", .{line}) catch "?";
        _ = l_fmt;
        @memcpy(idle_out[0..5], "?????");
        return;
    }
    const mesg: u8 = if ((st.st_mode & (c.S_IWGRP | c.S_IWOTH)) != 0) ' ' else '*';
    _ = std.fmt.bufPrint(tty_out, "{c}{s}", .{ mesg, line }) catch {};

    const now = c.time(null);
    const atime = st.st_atim.tv_sec;
    const idle_sec: u64 = if (now > atime) @intCast(now - atime) else 0;
    if (idle_sec >= 86400) {
        _ = std.fmt.bufPrint(idle_out, "{d}d", .{idle_sec / 86400}) catch {};
    } else if (idle_sec >= 3600) {
        _ = std.fmt.bufPrint(idle_out, "{d:0>2}:{d:0>2}", .{ idle_sec / 3600, (idle_sec % 3600) / 60 }) catch {};
    } else if (idle_sec >= 60) {
        _ = std.fmt.bufPrint(idle_out, ":{d:0>2}", .{idle_sec / 60}) catch {};
    } else {
        @memcpy(idle_out[0..5], "     ");
    }
}

fn printSessionRow(u: []const u8, line: []const u8, host: []const u8, tv_sec: c.time_t, opts: *const PinkyOptions, stdout: anytype) !void {
    var tm: c.struct_tm = undefined;
    _ = c.localtime_r(&tv_sec, &tm);
    var tbuf: [64]u8 = undefined;
    const t_len = c.strftime(&tbuf, tbuf.len, "%Y-%m-%d %H:%M", &tm);
    const t_str = if (t_len > 0) tbuf[0..t_len] else "";

    var tty_buf = [_]u8{0} ** 16;
    var idle_buf = [_]u8{0} ** 8;
    getLineStatus(line, &tty_buf, &idle_buf);
    const tty_s = std.mem.sliceTo(&tty_buf, 0);
    const idle_s = std.mem.sliceTo(&idle_buf, 0);

    var pw_name: []const u8 = "";
    const u_z = std.fmt.bufPrintZ(&tbuf, "{s}", .{u}) catch null;
    if (u_z) |uz| {
        if (c.getpwnam(uz.ptr)) |p| {
            if (p.*.pw_gecos != null) {
                const gecos = std.mem.span(p.*.pw_gecos);
                const c_idx = std.mem.indexOfScalar(u8, gecos, ',') orelse gecos.len;
                pw_name = gecos[0..c_idx];
            }
        }
    }

    if (opts.omit_name) {
        try stdout.print("{s:<8} {s:<8}", .{ u, tty_s });
    } else {
        try stdout.print("{s:<8} {s:<20} {s:<8}", .{ u, pw_name, tty_s });
    }
    if (!opts.omit_idle) try stdout.print(" {s:<6}", .{idle_s});
    try stdout.print(" {s:<16}", .{t_str});
    if (!opts.omit_where and host.len > 0) try stdout.print(" {s}", .{host});
    try stdout.writeByte('\n');
}

fn printShortSessions(opts: *const PinkyOptions, users: []const []const u8, stdout: anytype) !void {
    try printShortHeader(opts, stdout);
    c.setutxent();
    defer c.endutxent();

    while (c.getutxent()) |ut| {
        if (ut.*.ut_type != c.USER_PROCESS) continue;
        const u = std.mem.sliceTo(ut.*.ut_user[0..], 0);
        if (u.len == 0 or !userMatches(u, users)) continue;
        const line = std.mem.sliceTo(ut.*.ut_line[0..], 0);
        const host = std.mem.sliceTo(ut.*.ut_host[0..], 0);
        try printSessionRow(u, line, host, ut.*.ut_tv.tv_sec, opts, stdout);
    }
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buf: [4096]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    const stdout = &out_w.interface;

    var opts = PinkyOptions{};
    var users: std.ArrayListUnmanaged([]const u8) = .empty;
    defer users.deinit(allocator);

    if (try parseOptions(args, &opts, &users, allocator, stdout)) |rc| {
        stdout.flush() catch return 1;
        return rc;
    }

    if (opts.long_format) {
        for (users.items) |u| {
            try printLongUser(u, &opts, stdout, allocator);
        }
    } else {
        try printShortSessions(&opts, users.items, stdout);
    }

    stdout.flush() catch return 1;
    return 0;
}
