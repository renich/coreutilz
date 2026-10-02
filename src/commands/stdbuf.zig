const std = @import("std");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "stdbuf";
pub const version: []const u8 = "0.1.0";

fn parseModeSize(s: []const u8) ?u64 {
    if (s.len == 0) return null;
    var mult: u64 = 1;
    var num_str = s;
    const last = s[s.len - 1];
    if (last == 'k' or last == 'K') {
        mult = 1024;
        num_str = s[0 .. s.len - 1];
    } else if (last == 'm' or last == 'M') {
        mult = 1024 * 1024;
        num_str = s[0 .. s.len - 1];
    } else if (last == 'g' or last == 'G') {
        mult = 1024 * 1024 * 1024;
        num_str = s[0 .. s.len - 1];
    } else if (std.ascii.isAlphabetic(last)) {
        return null;
    }
    if (num_str.len == 0) return mult;
    for (num_str) |ch| {
        if (!std.ascii.isDigit(ch)) return null;
    }
    const val = std.fmt.parseInt(u64, num_str, 10) catch return null;
    const res, const ovf = @mulWithOverflow(val, mult);
    if (ovf != 0) return null;
    return res;
}

fn isValidMode(s: []const u8) bool {
    if (s.len == 0) return false;
    if (std.mem.eql(u8, s, "L") or std.mem.eql(u8, s, "0")) return true;
    return parseModeSize(s) != null;
}

fn locateLibstdbuf() ?[:0]const u8 {
    const paths = [_][:0]const u8{
        "/usr/libexec/coreutils/libstdbuf.so",
        "/usr/lib64/coreutils/libstdbuf.so",
        "/usr/lib/coreutils/libstdbuf.so",
    };
    for (paths) |p| {
        if (c.access(p.ptr, c.R_OK) == 0) return p;
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

    if (args.len <= 1) {
        try stderr.print("stdbuf: missing operand\nTry 'stdbuf --help' for more information.\n", .{});
        stderr.flush() catch {};
        return 125;
    }

    var i_mode: ?[]const u8 = null;
    var o_mode: ?[]const u8 = null;
    var e_mode: ?[]const u8 = null;
    var cmd_start: usize = 1;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            try stdout.print("Usage: stdbuf OPTION... COMMAND\nRun COMMAND , with modified buffering operations for its standard streams.\n", .{});
            stdout.flush() catch return 125;
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try stdout.print("stdbuf (coreutilz) {s}\n", .{version});
            stdout.flush() catch return 125;
            return 0;
        } else if (std.mem.startsWith(u8, arg, "-i")) {
            const m = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                if (i >= args.len) return 125;
                break :blk args[i];
            };
            if (std.mem.eql(u8, m, "L")) {
                try stderr.print("stdbuf: line buffering standard input is meaningless\nTry 'stdbuf --help' for more information.\n", .{});
                stderr.flush() catch {};
                return 125;
            }
            if (!isValidMode(m)) {
                try stderr.print("stdbuf: invalid mode '{s}'\nTry 'stdbuf --help' for more information.\n", .{m});
                stderr.flush() catch {};
                return 125;
            }
            i_mode = m;
        } else if (std.mem.startsWith(u8, arg, "-o")) {
            const m = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                if (i >= args.len) return 125;
                break :blk args[i];
            };
            if (!isValidMode(m)) {
                try stderr.print("stdbuf: invalid mode '{s}'\nTry 'stdbuf --help' for more information.\n", .{m});
                stderr.flush() catch {};
                return 125;
            }
            o_mode = m;
        } else if (std.mem.startsWith(u8, arg, "-e")) {
            const m = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                if (i >= args.len) return 125;
                break :blk args[i];
            };
            if (!isValidMode(m)) {
                try stderr.print("stdbuf: invalid mode '{s}'\nTry 'stdbuf --help' for more information.\n", .{m});
                stderr.flush() catch {};
                return 125;
            }
            e_mode = m;
        } else if (std.mem.eql(u8, arg, "--")) {
            cmd_start = i + 1;
            break;
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            try stderr.print("stdbuf: unrecognized option '{s}'\nTry 'stdbuf --help' for more information.\n", .{arg});
            stderr.flush() catch {};
            return 125;
        } else {
            cmd_start = i;
            break;
        }
    }

    if (cmd_start >= args.len) {
        try stderr.print("stdbuf: missing operand\nTry 'stdbuf --help' for more information.\n", .{});
        stderr.flush() catch {};
        return 125;
    }

    if (i_mode == null and o_mode == null and e_mode == null) {
        try stderr.print("stdbuf: you must specify a buffering mode option\nTry 'stdbuf --help' for more information.\n", .{});
        stderr.flush() catch {};
        return 125;
    }

    if (locateLibstdbuf()) |lib_path| {
        _ = c.setenv("LD_PRELOAD", lib_path.ptr, 1);
    }
    if (i_mode) |m| {
        const zm = allocator.dupeZ(u8, m) catch return 125;
        defer allocator.free(zm);
        _ = c.setenv("_STDBUF_I", zm.ptr, 1);
    }
    if (o_mode) |m| {
        const zm = allocator.dupeZ(u8, m) catch return 125;
        defer allocator.free(zm);
        _ = c.setenv("_STDBUF_O", zm.ptr, 1);
    }
    if (e_mode) |m| {
        const zm = allocator.dupeZ(u8, m) catch return 125;
        defer allocator.free(zm);
        _ = c.setenv("_STDBUF_E", zm.ptr, 1);
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
    try stderr.print("stdbuf: failed to run command '{s}': {s}\n", .{ cmd, msg });
    stderr.flush() catch {};

    if (err == c.ENOENT) return 127;
    return 126;
}
