const std = @import("std");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "timeout";
pub const version: []const u8 = "0.1.0";

fn isZeroString(s: []const u8) bool {
    var has_digit = false;
    for (s) |ch| {
        if (ch >= '1' and ch <= '9') return false;
        if (ch == '0') has_digit = true;
    }
    return has_digit;
}

fn parseDuration(s: []const u8) ?f64 {
    if (s.len == 0) return null;
    var mult: f64 = 1.0;
    var num_part = s;
    const last = s[s.len - 1];
    switch (last) {
        's' => {
            mult = 1.0;
            num_part = s[0 .. s.len - 1];
        },
        'm' => {
            mult = 60.0;
            num_part = s[0 .. s.len - 1];
        },
        'h' => {
            mult = 3600.0;
            num_part = s[0 .. s.len - 1];
        },
        'd' => {
            mult = 86400.0;
            num_part = s[0 .. s.len - 1];
        },
        else => {},
    }
    var val = std.fmt.parseFloat(f64, num_part) catch return null;
    if (std.math.isNan(val) or val < 0.0) return null;
    if (val == 0.0 and !isZeroString(num_part)) val = 1e-9;
    return val * mult;
}

fn parseSignal(s: []const u8) ?c_int {
    if (std.fmt.parseInt(c_int, s, 10)) |num| {
        return num;
    } else |_| {}
    var name_str = s;
    if (std.mem.startsWith(u8, name_str, "SIG") or std.mem.startsWith(u8, name_str, "sig")) {
        name_str = name_str[3..];
    }
    if (std.ascii.eqlIgnoreCase(name_str, "HUP")) return c.SIGHUP;
    if (std.ascii.eqlIgnoreCase(name_str, "INT")) return c.SIGINT;
    if (std.ascii.eqlIgnoreCase(name_str, "QUIT")) return c.SIGQUIT;
    if (std.ascii.eqlIgnoreCase(name_str, "KILL")) return c.SIGKILL;
    if (std.ascii.eqlIgnoreCase(name_str, "TERM")) return c.SIGTERM;
    if (std.ascii.eqlIgnoreCase(name_str, "USR1")) return c.SIGUSR1;
    if (std.ascii.eqlIgnoreCase(name_str, "USR2")) return c.SIGUSR2;
    if (std.ascii.eqlIgnoreCase(name_str, "ALRM")) return c.SIGALRM;
    return null;
}

fn getMonotonicMs() i64 {
    var ts: c.struct_timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_MONOTONIC, &ts);
    return @as(i64, ts.tv_sec) * 1000 + @divTrunc(ts.tv_nsec, 1000000);
}

fn waitChild(pid: c.pid_t, duration: f64) ?c_int {
    var status: c_int = 0;
    if (duration <= 0.0) {
        if (c.waitpid(pid, &status, 0) == pid) return status;
        return null;
    }
    const safe_dur = @min(duration, 1e11);
    const start_ms = getMonotonicMs();
    const limit_ms = @as(i64, @intFromFloat(safe_dur * 1000.0));

    while (true) {
        const res = c.waitpid(pid, &status, c.WNOHANG);
        if (res == pid) return status;
        if (res < 0) return null;

        const elapsed = getMonotonicMs() - start_ms;
        if (elapsed >= limit_ms) return null;

        const rem = limit_ms - elapsed;
        const sleep_ms = @min(rem, 10);
        _ = c.usleep(@as(c_uint, @intCast(sleep_ms)) * 1000);
    }
}

fn execChild(cmd_args: []const []const u8, foreground: bool, allocator: std.mem.Allocator) noreturn {
    if (!foreground) {
        _ = c.setpgid(0, 0);
    }
    var c_argv: std.ArrayList(?*anyopaque) = .empty;
    defer c_argv.deinit(allocator);

    for (cmd_args) |arg| {
        const z_arg = allocator.dupeZ(u8, arg) catch c._exit(125);
        c_argv.append(allocator, @ptrCast(z_arg.ptr)) catch c._exit(125);
    }
    c_argv.append(allocator, null) catch c._exit(125);

    const cmd_z = allocator.dupeZ(u8, cmd_args[0]) catch c._exit(125);
    _ = c.execvp(cmd_z.ptr, @ptrCast(c_argv.items.ptr));

    const err = c.__errno_location().*;
    if (err == c.ENOENT) c._exit(127);
    c._exit(126);
}

fn sigToName(sig: c_int, buf: []u8) []const u8 {
    return switch (sig) {
        0 => "0",
        c.SIGHUP => "HUP",
        c.SIGINT => "INT",
        c.SIGQUIT => "QUIT",
        c.SIGKILL => "KILL",
        c.SIGTERM => "TERM",
        c.SIGALRM => "ALRM",
        c.SIGUSR1 => "USR1",
        c.SIGUSR2 => "USR2",
        else => std.fmt.bufPrint(buf, "{d}", .{sig}) catch "TERM",
    };
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    _ = c.signal(c.SIGPIPE, c.SIG_IGN);
    var stdout_buf: [4096]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    const writer = &out_w.interface;

    _ = c.signal(c.SIGCHLD, c.SIG_DFL);

    var preserve_status = false;
    var foreground = false;
    var verbose = false;
    var kill_after: ?f64 = null;
    var sig: c_int = c.SIGTERM;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            try writer.print("Usage: timeout [OPTION] NUMBER[SUFFIX] COMMAND [ARG]...\nStart COMMAND, and kill it if still running after NUMBER seconds.\n", .{});
            out_w.interface.flush() catch return 125;
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try writer.print("timeout (coreutilz) {s}\n", .{version});
            out_w.interface.flush() catch return 125;
            return 0;
        } else if (std.mem.eql(u8, arg, "--preserve-status")) {
            preserve_status = true;
        } else if (std.mem.eql(u8, arg, "--foreground")) {
            foreground = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (std.mem.startsWith(u8, arg, "-k")) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                if (i >= args.len) return 125;
                break :blk args[i];
            };
            kill_after = parseDuration(val) orelse return 125;
        } else if (std.mem.startsWith(u8, arg, "--kill-after=")) {
            kill_after = parseDuration(arg["--kill-after=".len..]) orelse return 125;
        } else if (std.mem.startsWith(u8, arg, "-s")) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                if (i >= args.len) return 125;
                break :blk args[i];
            };
            sig = parseSignal(val) orelse return 125;
        } else if (std.mem.startsWith(u8, arg, "--signal=")) {
            sig = parseSignal(arg["--signal=".len..]) orelse return 125;
        } else if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            break;
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1 and !std.ascii.isDigit(arg[1])) {
            var err_buf: [256]u8 = undefined;
            var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &err_buf);
            try err_w.interface.print("timeout: unrecognized option '{s}'\nTry 'timeout --help' for more information.\n", .{arg});
            err_w.interface.flush() catch {};
            return 125;
        } else {
            break;
        }
    }

    if (i >= args.len) return 125;
    const duration = parseDuration(args[i]) orelse {
        var err_buf: [256]u8 = undefined;
        var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &err_buf);
        err_w.interface.print("timeout: invalid time interval '{s}'\nTry 'timeout --help' for more information.\n", .{args[i]}) catch {};
        err_w.interface.flush() catch {};
        return 125;
    };
    i += 1;
    if (i >= args.len) return 125;
    const cmd_args = args[i..];

    const pid = c.fork();
    if (pid < 0) return 125;
    if (pid == 0) {
        execChild(cmd_args, foreground, allocator);
    }

    if (waitChild(pid, duration)) |st| {
        const u_st: u32 = @bitCast(st);
        if (std.posix.W.IFEXITED(u_st)) return @intCast(std.posix.W.EXITSTATUS(u_st));
        if (std.posix.W.IFSIGNALED(u_st)) return 128 + @as(u8, @intCast(@intFromEnum(std.posix.W.TERMSIG(u_st))));
        return 0;
    }

    const target_pid: c.pid_t = if (foreground) pid else -pid;
    if (verbose) {
        var sbuf: [16]u8 = undefined;
        const sname = sigToName(sig, &sbuf);
        var err_buf: [256]u8 = undefined;
        var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &err_buf);
        err_w.interface.print("timeout: sending signal {s} to command '{s}'\n", .{ sname, cmd_args[0] }) catch {};
        err_w.interface.flush() catch {};
    }
    _ = c.kill(target_pid, sig);

    if (kill_after) |k_dur| {
        if (waitChild(pid, k_dur) == null) {
            if (verbose) {
                var err_buf: [256]u8 = undefined;
                var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &err_buf);
                err_w.interface.print("timeout: sending signal KILL to command '{s}'\n", .{cmd_args[0]}) catch {};
                err_w.interface.flush() catch {};
            }
            _ = c.kill(target_pid, c.SIGKILL);
            var st: c_int = 0;
            _ = c.waitpid(pid, &st, 0);
            if (preserve_status) {
                const u_st: u32 = @bitCast(st);
                if (std.posix.W.IFEXITED(u_st)) return @intCast(std.posix.W.EXITSTATUS(u_st));
                if (std.posix.W.IFSIGNALED(u_st)) return 128 + @as(u8, @intCast(@intFromEnum(std.posix.W.TERMSIG(u_st))));
            }
            return 137;
        }
    }

    var final_st: c_int = 0;
    _ = c.waitpid(pid, &final_st, 0);

    if (preserve_status) {
        const u_st: u32 = @bitCast(final_st);
        if (std.posix.W.IFEXITED(u_st)) return @intCast(std.posix.W.EXITSTATUS(u_st));
        if (std.posix.W.IFSIGNALED(u_st)) return 128 + @as(u8, @intCast(@intFromEnum(std.posix.W.TERMSIG(u_st))));
    }
    return 124;
}
