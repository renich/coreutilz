const std = @import("std");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "nohup";
pub const version: []const u8 = "0.1.0";

fn openNohupOut(allocator: std.mem.Allocator) ?c_int {
    const umask_val = c.umask(0);
    defer _ = c.umask(umask_val);

    const fd = c.open("nohup.out", c.O_CREAT | c.O_WRONLY | c.O_APPEND, @as(c.mode_t, 0o600));
    if (fd >= 0) return fd;

    if (c.getenv("HOME")) |home_ptr| {
        const home = std.mem.span(home_ptr);
        const home_out = std.fs.path.join(allocator, &[_][]const u8{ home, "nohup.out" }) catch return null;
        defer allocator.free(home_out);
        const z_path = allocator.dupeZ(u8, home_out) catch return null;
        defer allocator.free(z_path);
        const h_fd = c.open(z_path.ptr, c.O_CREAT | c.O_WRONLY | c.O_APPEND, @as(c.mode_t, 0o600));
        if (h_fd >= 0) return h_fd;
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

    const exit_fail: u8 = if (c.getenv("POSIXLY_CORRECT") != null) 127 else 125;

    if (args.len <= 1) {
        try stderr.print("nohup: missing operand\nTry 'nohup --help' for more information.\n", .{});
        stderr.flush() catch {};
        return exit_fail;
    }

    var cmd_start: usize = 1;
    if (std.mem.eql(u8, args[1], "--help")) {
        try stdout.print("Usage: nohup COMMAND [ARG]...\nRun COMMAND, ignoring hangup signals.\n", .{});
        stdout.flush() catch return exit_fail;
        return 0;
    } else if (std.mem.eql(u8, args[1], "--version")) {
        try stdout.print("nohup (coreutilz) {s}\n", .{version});
        stdout.flush() catch return exit_fail;
        return 0;
    } else if (std.mem.eql(u8, args[1], "--")) {
        cmd_start = 2;
    } else if (std.mem.startsWith(u8, args[1], "-") and args[1].len > 1) {
        try stderr.print("nohup: unrecognized option '{s}'\nTry 'nohup --help' for more information.\n", .{args[1]});
        stderr.flush() catch {};
        return exit_fail;
    }

    if (cmd_start >= args.len) {
        try stderr.print("nohup: missing operand\nTry 'nohup --help' for more information.\n", .{});
        stderr.flush() catch {};
        return exit_fail;
    }

    const ignoring_input = (c.isatty(c.STDIN_FILENO) == 1);
    const redirecting_stdout = (c.isatty(c.STDOUT_FILENO) == 1);
    const redirecting_stderr = (c.isatty(c.STDERR_FILENO) == 1);

    if (ignoring_input) {
        const null_fd = c.open("/dev/null", c.O_RDONLY);
        if (null_fd >= 0) {
            _ = c.dup2(null_fd, c.STDIN_FILENO);
            _ = c.close(null_fd);
        }
        if (!redirecting_stdout and !redirecting_stderr) {
            err_w.interface.print("nohup: ignoring input\n", .{}) catch return 125;
            err_w.interface.flush() catch return 125;
        }
    }

    var out_fd: c_int = c.STDOUT_FILENO;
    if (redirecting_stdout) {
        out_fd = openNohupOut(allocator) orelse {
            err_w.interface.print("nohup: failed to open 'nohup.out'\n", .{}) catch return 125;
            err_w.interface.flush() catch return 125;
            return 125;
        };
        if (ignoring_input) {
            err_w.interface.print("nohup: ignoring input and appending output to 'nohup.out'\n", .{}) catch return 125;
        } else {
            err_w.interface.print("nohup: appending output to 'nohup.out'\n", .{}) catch return 125;
        }
        err_w.interface.flush() catch return 125;
        _ = c.dup2(out_fd, c.STDOUT_FILENO);
    }

    if (redirecting_stderr) {
        if (!redirecting_stdout) {
            if (ignoring_input) {
                err_w.interface.print("nohup: ignoring input and redirecting standard error to standard output\n", .{}) catch return 125;
            } else {
                err_w.interface.print("nohup: redirecting standard error to standard output\n", .{}) catch return 125;
            }
            err_w.interface.flush() catch return 125;
        }
        _ = c.dup2(c.STDOUT_FILENO, c.STDERR_FILENO);
    }

    if (redirecting_stdout and out_fd != c.STDOUT_FILENO) {
        _ = c.close(out_fd);
    }

    _ = c.signal(c.SIGHUP, c.SIG_IGN);

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
    try stderr.print("nohup: failed to run command '{s}': {s}\n", .{ cmd, msg });
    stderr.flush() catch {};

    if (err == c.ENOENT) return 127;
    return 126;
}
