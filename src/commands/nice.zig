const std = @import("std");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "nice";
pub const version: []const u8 = "0.1.0";

fn parseAdjustment(s: []const u8) ?i32 {
    if (s.len == 0) return null;
    var trimmed = s;
    var negative = false;
    if (trimmed[0] == '-') {
        negative = true;
        trimmed = trimmed[1..];
    } else if (trimmed[0] == '+') {
        trimmed = trimmed[1..];
    }
    if (trimmed.len == 0) return null;
    for (trimmed) |ch| {
        if (!std.ascii.isDigit(ch)) return null;
    }
    const val = std.fmt.parseInt(i64, trimmed, 10) catch {
        return if (negative) -40 else 40;
    };
    const signed_val: i64 = if (negative) -val else val;
    return @intCast(std.math.clamp(signed_val, -40, 40));
}

fn printCurrentNice(writer: anytype) !u8 {
    c.__errno_location().* = 0;
    const prio = c.getpriority(c.PRIO_PROCESS, 0);
    if (c.__errno_location().* != 0) {
        return 1;
    }
    try writer.print("{d}\n", .{prio});
    return 0;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &out_w.interface;
    const stderr = &err_w.interface;

    if (args.len <= 1) {
        const rc = try printCurrentNice(stdout);
        stdout.flush() catch return 125;
        return rc;
    }

    var adjustment: ?i32 = null;
    var cmd_start: usize = 1;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            try stdout.print("Usage: nice [OPTION] [COMMAND [ARG]...]\nRun COMMAND with an adjusted niceness, which affects process scheduling.\nWith no COMMAND, print the current niceness.  Adjustment is 10 by default.\n", .{});
            stdout.flush() catch return 125;
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try stdout.print("nice (coreutilz) {s}\n", .{version});
            stdout.flush() catch return 125;
            return 0;
        } else if (std.mem.startsWith(u8, arg, "-n")) {
            const val_str = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                if (i >= args.len) {
                    try stderr.print("nice: option requires an argument -- 'n'\n", .{});
                    stderr.flush() catch {};
                    return 125;
                }
                break :blk args[i];
            };
            adjustment = parseAdjustment(val_str) orelse {
                try stderr.print("nice: invalid adjustment '{s}'\n", .{val_str});
                stderr.flush() catch {};
                return 125;
            };
        } else if (std.mem.startsWith(u8, arg, "--adjustment=")) {
            const val_str = arg["--adjustment=".len..];
            adjustment = parseAdjustment(val_str) orelse {
                try stderr.print("nice: invalid adjustment '{s}'\n", .{val_str});
                stderr.flush() catch {};
                return 125;
            };
        } else if (arg.len > 1 and arg[0] == '-' and (std.ascii.isDigit(arg[1]) or ((arg[1] == '-' or arg[1] == '+') and arg.len > 2 and std.ascii.isDigit(arg[2])))) {
            adjustment = parseAdjustment(arg[1..]) orelse {
                try stderr.print("nice: invalid adjustment '{s}'\n", .{arg});
                stderr.flush() catch {};
                return 125;
            };
        } else if (std.mem.eql(u8, arg, "--")) {
            cmd_start = i + 1;
            break;
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            try stderr.print("nice: unrecognized option '{s}'\nTry 'nice --help' for more information.\n", .{arg});
            stderr.flush() catch {};
            return 125;
        } else {
            cmd_start = i;
            break;
        }
    } else {
        cmd_start = i;
    }

    if (cmd_start >= args.len) {
        if (adjustment != null) {
            try stderr.print("nice: a command must be given with an adjustment\n", .{});
            stderr.flush() catch {};
            return 125;
        }
        const rc = try printCurrentNice(stdout);
        stdout.flush() catch return 125;
        return rc;
    }

    const adj = adjustment orelse 10;
    c.__errno_location().* = 0;
    const cur_prio = c.getpriority(c.PRIO_PROCESS, 0);
    if (c.__errno_location().* == 0) {
        if (c.setpriority(c.PRIO_PROCESS, 0, cur_prio + adj) != 0) {
            const err = c.__errno_location().*;
            try stderr.print("nice: cannot set niceness: {s}\n", .{std.mem.span(c.strerror(err))});
            stderr.flush() catch return 125;
        }
    }

    const cmd = args[cmd_start];
    var c_argv: std.ArrayList(?*anyopaque) = .empty;
    defer c_argv.deinit(allocator);

    for (args[cmd_start..]) |arg| {
        const z_arg = allocator.dupeZ(u8, arg) catch return 125;
        c_argv.append(allocator, @ptrCast(z_arg.ptr)) catch return 125;
    }
    c_argv.append(allocator, null) catch return 125;

    const cmd_z = allocator.dupeZ(u8, cmd) catch return 125;
    _ = c.execvp(cmd_z.ptr, @ptrCast(c_argv.items.ptr));

    const err = c.__errno_location().*;
    const msg = std.mem.span(c.strerror(err));
    try stderr.print("nice: '{s}': {s}\n", .{ cmd, msg });
    stderr.flush() catch {};

    if (err == c.ENOENT) return 127;
    return 126;
}
