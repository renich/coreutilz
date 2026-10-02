const std = @import("std");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "who";
pub const version: []const u8 = "0.1.0";

const WhoOptions = struct {
    opt_a: bool = false,
    opt_b: bool = false,
    opt_d: bool = false,
    opt_H: bool = false,
    opt_l: bool = false,
    opt_m: bool = false,
    opt_p: bool = false,
    opt_q: bool = false,
    opt_r: bool = false,
    opt_s: bool = false,
    opt_t: bool = false,
    opt_u: bool = false,
    opt_w: bool = false,
};

fn setAllOpts(opts: *WhoOptions) void {
    opts.opt_b = true;
    opts.opt_d = true;
    opts.opt_l = true;
    opts.opt_p = true;
    opts.opt_r = true;
    opts.opt_t = true;
    opts.opt_u = true;
    opts.opt_w = true;
}

fn parseShortOpt(ch: u8, opts: *WhoOptions) bool {
    switch (ch) {
        'a' => setAllOpts(opts),
        'b' => opts.opt_b = true,
        'd' => opts.opt_d = true,
        'H' => opts.opt_H = true,
        'l' => opts.opt_l = true,
        'm' => opts.opt_m = true,
        'p' => opts.opt_p = true,
        'q' => opts.opt_q = true,
        'r' => opts.opt_r = true,
        's' => opts.opt_s = true,
        't' => opts.opt_t = true,
        'u' => opts.opt_u = true,
        'w', 'T' => opts.opt_w = true,
        else => return false,
    }
    return true;
}

fn parseLongOpt(arg: []const u8, opts: *WhoOptions) bool {
    if (std.mem.eql(u8, arg, "--all")) {
        setAllOpts(opts);
        return true;
    }
    if (std.mem.eql(u8, arg, "--boot")) {
        opts.opt_b = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--dead")) {
        opts.opt_d = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--heading")) {
        opts.opt_H = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--login")) {
        opts.opt_l = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--process")) {
        opts.opt_p = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--count")) {
        opts.opt_q = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--runlevel")) {
        opts.opt_r = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--short")) {
        opts.opt_s = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--time")) {
        opts.opt_t = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--users")) {
        opts.opt_u = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--mesg") or std.mem.eql(u8, arg, "--message") or std.mem.eql(u8, arg, "--writable")) {
        opts.opt_w = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--lookup")) return true;
    return false;
}

fn parseOptions(args: [][]const u8, opts: *WhoOptions, stdout: anytype, stderr: anytype) !?u8 {
    if (args.len >= 3 and !std.mem.startsWith(u8, args[1], "-")) {
        opts.opt_m = true;
        return null;
    }
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--help")) {
            try stdout.print("Usage: who [OPTION]... [ FILE | ARG1 ARG2 ]\nPrint information about users who are currently logged in.\n", .{});
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try stdout.print("who (coreutilz) {s}\n", .{version});
            return 0;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            if (!parseLongOpt(arg, opts)) {
                try stderr.print("who: unrecognized option '{s}'\nTry 'who --help' for more information.\n", .{arg});
                return 1;
            }
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            for (arg[1..]) |ch| {
                if (!parseShortOpt(ch, opts)) {
                    try stderr.print("who: invalid option -- '{c}'\nTry 'who --help' for more information.\n", .{ch});
                    return 1;
                }
            }
        }
    }
    return null;
}

fn printCount(stdout: anytype) !void {
    c.setutxent();
    defer c.endutxent();

    var count: usize = 0;
    while (c.getutxent()) |ut| {
        if (ut.*.ut_type == c.USER_PROCESS) {
            const user = std.mem.sliceTo(ut.*.ut_user[0..], 0);
            if (user.len > 0) {
                if (count > 0) try stdout.writeByte(' ');
                try stdout.print("{s}", .{user});
                count += 1;
            }
        }
    }
    if (count > 0) try stdout.writeByte('\n');
    try stdout.print("# users={d}\n", .{count});
}

fn formatTime(tv_sec: c.time_t, buf: []u8) []const u8 {
    var tm: c.struct_tm = undefined;
    _ = c.localtime_r(&tv_sec, &tm);
    const len = c.strftime(buf.ptr, buf.len, "%Y-%m-%d %H:%M", &tm);
    return if (len > 0) buf[0..len] else "";
}

fn printSessions(opts: *const WhoOptions, stdout: anytype) !void {
    if (opts.opt_H) {
        try stdout.print("NAME     LINE         TIME             COMMENT\n", .{});
    }
    c.setutxent();
    defer c.endutxent();

    var tbuf: [64]u8 = undefined;
    while (c.getutxent()) |ut| {
        if (opts.opt_b and ut.*.ut_type == c.BOOT_TIME) {
            const t_str = formatTime(ut.*.ut_tv.tv_sec, &tbuf);
            try stdout.print("         system boot  {s}\n", .{t_str});
            continue;
        }
        if (ut.*.ut_type == c.USER_PROCESS) {
            const user = std.mem.sliceTo(ut.*.ut_user[0..], 0);
            const line = std.mem.sliceTo(ut.*.ut_line[0..], 0);
            const host = std.mem.sliceTo(ut.*.ut_host[0..], 0);
            const t_str = formatTime(ut.*.ut_tv.tv_sec, &tbuf);

            try stdout.print("{s:<8} {s:<12} {s}", .{ user, line, t_str });
            if (host.len > 0) {
                try stdout.print(" ({s})", .{host});
            }
            try stdout.writeByte('\n');
        }
    }
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    _ = allocator;
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &out_w.interface;
    const stderr = &err_w.interface;

    var opts = WhoOptions{};
    if (try parseOptions(args, &opts, stdout, stderr)) |rc| {
        stdout.flush() catch return 1;
        stderr.flush() catch {};
        return rc;
    }

    if (opts.opt_q) {
        try printCount(stdout);
    } else {
        try printSessions(&opts, stdout);
    }

    stdout.flush() catch return 1;
    return 0;
}
