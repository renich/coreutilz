const std = @import("std");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "uptime";
pub const version: []const u8 = "0.1.0";

fn printHelp(stdout: anytype) !void {
    try stdout.print(
        \\Usage: {s} [OPTION]...
        \\Tell how long the system has been running.
        \\
        \\  -s, --since     display the date/time since system is up
        \\      --help      display this help and exit
        \\      --version   output version information and exit
        \\
    , .{name});
}

fn getBootTime() c.time_t {
    c.setutxent();
    defer c.endutxent();

    while (c.getutxent()) |ut| {
        if (ut.*.ut_type == c.BOOT_TIME) {
            return ut.*.ut_tv.tv_sec;
        }
    }

    var ts: c.struct_timespec = undefined;
    if (c.clock_gettime(c.CLOCK_BOOTTIME, &ts) == 0) {
        return c.time(null) - ts.tv_sec;
    }
    return 0;
}

fn countUsers() usize {
    c.setutxent();
    defer c.endutxent();

    var count: usize = 0;
    while (c.getutxent()) |ut| {
        if (ut.*.ut_type == c.USER_PROCESS) {
            const user = std.mem.sliceTo(ut.*.ut_user[0..], 0);
            if (user.len > 0) count += 1;
        }
    }
    return count;
}

fn printSince(boot_time: c.time_t, stdout: anytype) !void {
    var tm: c.struct_tm = undefined;
    _ = c.localtime_r(&boot_time, &tm);
    try stdout.print("{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}\n", .{
        tm.tm_year + 1900,
        tm.tm_mon + 1,
        tm.tm_mday,
        tm.tm_hour,
        tm.tm_min,
        tm.tm_sec,
    });
}

fn printDuration(elapsed: i64, stdout: anytype) !void {
    const days = @divTrunc(elapsed, 86400);
    const rem_days = @rem(elapsed, 86400);
    const hours = @divTrunc(rem_days, 3600);
    const minutes = @divTrunc(@rem(rem_days, 3600), 60);

    if (days > 0) {
        if (days == 1) {
            try stdout.print("up 1 day, {d}:{d:0>2},  ", .{ hours, minutes });
        } else {
            try stdout.print("up {d} days, {d}:{d:0>2},  ", .{ days, hours, minutes });
        }
    } else if (hours > 0) {
        try stdout.print("up {d}:{d:0>2},  ", .{ hours, minutes });
    } else {
        try stdout.print("up {d} min,  ", .{minutes});
    }
}

fn printStandardUptime(boot_time: c.time_t, stdout: anytype) !void {
    const now = c.time(null);
    var tm_now: c.struct_tm = undefined;
    _ = c.localtime_r(&now, &tm_now);

    try stdout.print(" {d:0>2}:{d:0>2}:{d:0>2}  ", .{
        tm_now.tm_hour,
        tm_now.tm_min,
        tm_now.tm_sec,
    });

    const elapsed = if (now > boot_time) (now - boot_time) else 0;
    try printDuration(elapsed, stdout);

    const users = countUsers();
    if (users == 1) {
        try stdout.print("1 user,  ", .{});
    } else {
        try stdout.print("{d} users,  ", .{users});
    }

    var loads: [3]f64 = undefined;
    _ = c.getloadavg(&loads, 3);
    try stdout.print("load average: {d:.2}, {d:.2}, {d:.2}\n", .{
        loads[0],
        loads[1],
        loads[2],
    });
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    _ = allocator;
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &out_w.interface;
    const stderr = &err_w.interface;

    var opt_since = false;
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--help") or std.mem.eql(u8, arg, "-h")) {
            try printHelp(stdout);
            stdout.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--version") or std.mem.eql(u8, arg, "-v")) {
            try stdout.print("{s} (coreutilz) {s}\n", .{ name, version });
            stdout.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--since")) {
            opt_since = true;
        } else if (std.mem.startsWith(u8, arg, "-") and !std.mem.eql(u8, arg, "-")) {
            try stderr.print("{s}: unrecognized option '{s}'\nTry '{s} --help' for more information.\n", .{ name, arg, name });
            stderr.flush() catch {};
            return 1;
        }
    }

    const boot_time = getBootTime();
    if (boot_time == 0) {
        try stderr.print("{s}: couldn't get boot time\n", .{name});
        stderr.flush() catch {};
        return 1;
    }

    if (opt_since) {
        try printSince(boot_time, stdout);
    } else {
        try printStandardUptime(boot_time, stdout);
    }

    stdout.flush() catch return 1;
    stderr.flush() catch {};
    return 0;
}
