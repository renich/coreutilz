const std = @import("std");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "runcon";
pub const version: []const u8 = "0.1.0";

const RunconOptions = struct {
    user: ?[]const u8 = null,
    role: ?[]const u8 = null,
    type_name: ?[]const u8 = null,
    range: ?[]const u8 = null,
    compute: bool = false,
};

fn getCurrentContext(buf: *[512]u8) ?[]const u8 {
    const fd = c.open("/proc/self/attr/current", c.O_RDONLY);
    if (fd < 0) return null;
    defer _ = c.close(fd);
    const n = c.read(fd, buf, buf.len);
    if (n <= 0) return null;
    var len: usize = @intCast(n);
    if (len > 0 and (buf[len - 1] == 0 or buf[len - 1] == '\n')) len -= 1;
    return buf[0..len];
}

fn mergeContext(cur: []const u8, opts: *const RunconOptions, out: *[512]u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, cur, ':');
    const orig_u = it.next() orelse return null;
    const orig_r = it.next() orelse return null;
    const orig_t = it.next() orelse return null;
    const rest = it.rest();
    const u = opts.user orelse orig_u;
    const r = opts.role orelse orig_r;
    const t = opts.type_name orelse orig_t;
    const l = opts.range orelse if (rest.len > 0) rest else "s0";
    return std.fmt.bufPrint(out, "{s}:{s}:{s}:{s}", .{ u, r, t, l }) catch null;
}

fn setExecContext(ctx: []const u8, stderr: anytype) bool {
    const fd = c.open("/proc/self/attr/exec", c.O_WRONLY);
    if (fd < 0) {
        stderr.print("runcon: runcon may be used only on a SELinux kernel\n", .{}) catch {};
        return false;
    }
    defer _ = c.close(fd);
    const n = c.write(fd, ctx.ptr, ctx.len);
    if (n < 0) {
        stderr.print("runcon: failed to create security context: '{s}': Invalid argument\n", .{ctx}) catch {};
        return false;
    }
    return true;
}

fn parseComponent(arg: []const u8, idx: *usize, args: [][]const u8) ?[]const u8 {
    if (arg.len > 2) return arg[2..];
    idx.* += 1;
    return if (idx.* < args.len) args[idx.*] else null;
}

fn parseShortOpt(arg: []const u8, i: *usize, args: [][]const u8, opts: *RunconOptions, stderr: anytype) bool {
    if (std.mem.startsWith(u8, arg, "-u")) {
        opts.user = parseComponent(arg, i, args);
    } else if (std.mem.startsWith(u8, arg, "-r")) {
        opts.role = parseComponent(arg, i, args);
    } else if (std.mem.startsWith(u8, arg, "-t")) {
        opts.type_name = parseComponent(arg, i, args);
    } else if (std.mem.startsWith(u8, arg, "-l")) {
        opts.range = parseComponent(arg, i, args);
    } else if (std.mem.eql(u8, arg, "-c")) {
        opts.compute = true;
    } else {
        stderr.print("runcon: invalid option -- '{c}'\nTry 'runcon --help' for more information.\n", .{arg[1]}) catch {};
        return false;
    }
    return true;
}

fn parseOptions(args: [][]const u8, opts: *RunconOptions, first_non_opt: *usize, stdout: anytype, stderr: anytype) !?u8 {
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            break;
        }
        if (std.mem.eql(u8, arg, "--help")) {
            try stdout.print("Usage: runcon [CONTEXT COMMAND [ARG]...]\n  or:  runcon [-c] [-u USER] [-r ROLE] [-t TYPE] [-l RANGE] COMMAND [ARG]...\nRun a program in a different SELinux security context.\n", .{});
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try stdout.print("runcon (coreutilz) {s}\n", .{version});
            return 0;
        } else if (std.mem.eql(u8, arg, "--compute")) {
            opts.compute = true;
        } else if (std.mem.startsWith(u8, arg, "--user=")) {
            opts.user = arg["--user=".len..];
        } else if (std.mem.startsWith(u8, arg, "--role=")) {
            opts.role = arg["--role=".len..];
        } else if (std.mem.startsWith(u8, arg, "--type=")) {
            opts.type_name = arg["--type=".len..];
        } else if (std.mem.startsWith(u8, arg, "--range=")) {
            opts.range = arg["--range=".len..];
        } else if (std.mem.startsWith(u8, arg, "--")) {
            stderr.print("runcon: unrecognized option '{s}'\nTry 'runcon --help' for more information.\n", .{arg}) catch {};
            return 125;
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            if (!parseShortOpt(arg, &i, args, opts, stderr)) return 125;
        } else {
            break;
        }
    }
    first_non_opt.* = i;
    return null;
}

fn execChild(cmd: []const u8, cmd_args: [][]const u8, alloc: std.mem.Allocator, stderr: anytype) noreturn {
    var argv = alloc.alloc(?[*:0]u8, cmd_args.len + 1) catch c.exit(125);
    for (cmd_args, 0..) |a, idx| {
        const z = alloc.dupeZ(u8, a) catch c.exit(125);
        argv[idx] = z.ptr;
    }
    argv[cmd_args.len] = null;

    const cmd_z = alloc.dupeZ(u8, cmd) catch c.exit(125);
    _ = c.execvp(cmd_z.ptr, @ptrCast(argv.ptr));

    const err = c.__errno_location().*;
    if (err == c.ENOENT) {
        stderr.print("runcon: '{s}': No such file or directory\n", .{cmd}) catch {};
        c.exit(127);
    } else if (err == c.EACCES) {
        stderr.print("runcon: '{s}': Permission denied\n", .{cmd}) catch {};
        c.exit(126);
    } else {
        stderr.print("runcon: '{s}': execution failed\n", .{cmd}) catch {};
        c.exit(126);
    }
}

fn handleNoCommand(has_comp: bool, argc: usize, cur_ctx: ?[]const u8, stdout: anytype, stderr: anytype) u8 {
    if (has_comp or argc == 1) {
        if (cur_ctx) |ctx| {
            stdout.print("{s}\n", .{ctx}) catch return 125;
            stdout.flush() catch return 125;
            return 0;
        }
        stderr.print("runcon: runcon may be used only on a SELinux kernel\n", .{}) catch {};
        return 125;
    }
    stderr.print("runcon: no command specified\nTry 'runcon --help' for more information.\n", .{}) catch {};
    return 125;
}

fn resolveTargetContext(args: [][]const u8, opts: *const RunconOptions, non_opt: usize, cur_ctx: ?[]const u8, cmd_idx: *usize, out_buf: *[512]u8, stderr: anytype) ?[]const u8 {
    const has_comp = opts.user != null or opts.role != null or opts.type_name != null or opts.range != null;
    if (has_comp) {
        const cur = cur_ctx orelse {
            stderr.print("runcon: runcon may be used only on a SELinux kernel\n", .{}) catch {};
            return null;
        };
        cmd_idx.* = non_opt;
        return mergeContext(cur, opts, out_buf);
    }
    cmd_idx.* = non_opt + 1;
    if (cmd_idx.* >= args.len) {
        stderr.print("runcon: no command specified\nTry 'runcon --help' for more information.\n", .{}) catch {};
        return null;
    }
    return args[non_opt];
}

fn forkAndExec(cmd_idx: usize, args: [][]const u8, alloc: std.mem.Allocator, stderr: anytype) u8 {
    const pid = c.fork();
    if (pid < 0) return 125;
    if (pid == 0) execChild(args[cmd_idx], args[cmd_idx..], alloc, stderr);

    var status: c_int = 0;
    _ = c.waitpid(pid, &status, 0);
    if (c.WIFEXITED(status)) return @intCast(c.WEXITSTATUS(status));
    if (c.WIFSIGNALED(status)) return @intCast(128 + c.WTERMSIG(status));
    return 125;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &out_w.interface;
    const stderr = &err_w.interface;

    var opts = RunconOptions{};
    var non_opt: usize = 1;
    if (try parseOptions(args, &opts, &non_opt, stdout, stderr)) |rc| {
        stdout.flush() catch return 125;
        stderr.flush() catch return 125;
        return rc;
    }

    var cur_buf: [512]u8 = undefined;
    const cur_ctx = getCurrentContext(&cur_buf);
    const has_comp = opts.user != null or opts.role != null or opts.type_name != null or opts.range != null;

    if (non_opt >= args.len) {
        const rc = handleNoCommand(has_comp, args.len, cur_ctx, stdout, stderr);
        stderr.flush() catch {};
        return rc;
    }

    var target_buf: [512]u8 = undefined;
    var cmd_idx: usize = non_opt;
    const target = resolveTargetContext(args, &opts, non_opt, cur_ctx, &cmd_idx, &target_buf, stderr) orelse {
        stderr.flush() catch {};
        return 125;
    };

    if (!setExecContext(target, stderr)) {
        stderr.flush() catch {};
        return 125;
    }

    return forkAndExec(cmd_idx, args, allocator, stderr);
}
