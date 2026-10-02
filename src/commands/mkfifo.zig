const std = @import("std");
const errors = @import("../utils/errors.zig");
const mode_util = @import("../utils/mode.zig");
const selinux_util = @import("../utils/selinux.zig");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "mkfifo";
pub const version: []const u8 = "0.1.0";

const ParsedOptions = struct {
    mode: u32,
    mode_provided: bool,
    operands: std.ArrayList([]const u8),
    early_exit: ?u8 = null,
};

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buffer: [4096]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var parsed = try parseArgs(args, allocator, stdout, stderr);
    defer parsed.operands.deinit(allocator);

    if (parsed.early_exit) |code| {
        stdout.flush() catch return 1;
        return code;
    }
    if (parsed.operands.items.len == 0) {
        try stderr.print("mkfifo: missing operand\nTry 'mkfifo --help' for more information.\n", .{});
        return 1;
    }
    const rc = try createFifos(parsed.operands.items, parsed.mode, parsed.mode_provided, allocator, stderr);
    stdout.flush() catch return 1;
    return rc;
}

fn parseArgs(args: [][]const u8, allocator: std.mem.Allocator, stdout: anytype, stderr: anytype) !ParsedOptions {
    const cur_umask = c.umask(0);
    _ = c.umask(cur_umask);

    var res = ParsedOptions{
        .mode = 0o666 & ~@as(u32, @intCast(cur_umask)),
        .mode_provided = false,
        .operands = .empty,
    };

    var parsing_options = true;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (parsing_options and std.mem.eql(u8, arg, "--")) {
            parsing_options = false;
            continue;
        }
        if (parsing_options and std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            const ok = try handleOption(arg, &i, args, @intCast(cur_umask), &res, stdout, stderr);
            if (!ok) return res;
        } else {
            try res.operands.append(allocator, arg);
        }
    }
    return res;
}

fn handleOption(
    arg: []const u8,
    i: *usize,
    args: [][]const u8,
    cur_umask: u32,
    res: *ParsedOptions,
    stdout: anytype,
    stderr: anytype,
) !bool {
    if (std.mem.startsWith(u8, arg, "--")) {
        return handleLongOpt(arg, i, args, cur_umask, res, stdout, stderr);
    }
    return handleShortOpts(arg[1..], i, args, cur_umask, res, stderr);
}

fn handleLongOpt(
    arg: []const u8,
    i: *usize,
    args: [][]const u8,
    cur_umask: u32,
    res: *ParsedOptions,
    stdout: anytype,
    stderr: anytype,
) !bool {
    if (std.mem.eql(u8, arg, "--help")) {
        try printHelp(stdout);
        stdout.flush() catch {
            res.early_exit = 1;
            return false;
        };
        res.early_exit = 0;
        return false;
    } else if (std.mem.eql(u8, arg, "--version")) {
        try printVersion(stdout);
        stdout.flush() catch {
            res.early_exit = 1;
            return false;
        };
        res.early_exit = 0;
        return false;
    } else if (std.mem.startsWith(u8, arg, "--mode=") or std.mem.eql(u8, arg, "--mode")) {
        return handleLongMode(arg, i, args, cur_umask, res, stderr);
    } else if (std.mem.startsWith(u8, arg, "--context=")) {
        const ctx = arg["--context=".len..];
        if (ctx.len > 0) {
            if (!selinux_util.setFsCreateCon(name, ctx, stderr)) {
                res.early_exit = 1;
                return false;
            }
        }
    } else if (std.mem.eql(u8, arg, "--context")) {
        // default context
    } else {
        try stderr.print("mkfifo: unrecognized option '{s}'\nTry 'mkfifo --help' for more information.\n", .{arg});
        res.early_exit = 1;
        return false;
    }
    return true;
}

fn handleLongMode(
    arg: []const u8,
    i: *usize,
    args: [][]const u8,
    cur_umask: u32,
    res: *ParsedOptions,
    stderr: anytype,
) !bool {
    const val = if (std.mem.startsWith(u8, arg, "--mode="))
        arg["--mode=".len..]
    else blk: {
        if (i.* + 1 >= args.len) {
            try errors.printErrorWithHelp(stderr, name, "option '--mode' requires an argument");
            res.early_exit = 1;
            return false;
        }
        i.* += 1;
        break :blk args[i.*];
    };
    res.mode = try parseFifoMode(val, cur_umask, stderr) orelse {
        res.early_exit = 1;
        return false;
    };
    res.mode_provided = true;
    return true;
}

fn handleShortOpts(
    opts: []const u8,
    i: *usize,
    args: [][]const u8,
    cur_umask: u32,
    res: *ParsedOptions,
    stderr: anytype,
) !bool {
    var j: usize = 0;
    while (j < opts.len) : (j += 1) {
        const ch = opts[j];
        if (ch == 'm') {
            const mstr = if (j + 1 < opts.len) opts[j + 1 ..] else blk: {
                if (i.* + 1 >= args.len) {
                    try errors.printErrorWithHelp(stderr, name, "option requires an argument -- 'm'");
                    res.early_exit = 1;
                    return false;
                }
                i.* += 1;
                break :blk args[i.*];
            };
            res.mode = try parseFifoMode(mstr, cur_umask, stderr) orelse {
                res.early_exit = 1;
                return false;
            };
            res.mode_provided = true;
            break;
        } else if (ch == 'Z') {
            // SELinux parity
        } else {
            try stderr.print("mkfifo: invalid option -- '{c}'\nTry 'mkfifo --help' for more information.\n", .{ch});
            res.early_exit = 1;
            return false;
        }
    }
    return true;
}

fn parseFifoMode(mode_str: []const u8, umask_val: u32, stderr: anytype) !?u32 {
    const parsed = mode_util.parseMode(mode_str, 0o666, false, umask_val) catch {
        try stderr.print("mkfifo: invalid mode '{s}'\n", .{mode_str});
        return null;
    };
    if (parsed & ~@as(u32, 0o777) != 0) {
        try stderr.print("mkfifo: mode must specify only file permission bits\n", .{});
        return null;
    }
    return parsed;
}

fn createFifos(
    paths: []const []const u8,
    mode: u32,
    mode_provided: bool,
    allocator: std.mem.Allocator,
    stderr: anytype,
) !u8 {
    var exit_status: u8 = 0;
    for (paths) |path| {
        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);

        const create_mode: c.mode_t = if (mode_provided) 0o666 else @intCast(mode);
        if (c.mkfifo(path_z.ptr, create_mode) != 0) {
            const err_str = std.mem.span(c.strerror(c.__errno_location().*));
            try stderr.print("mkfifo: cannot create fifo '{s}': {s}\n", .{ path, err_str });
            exit_status = 1;
            continue;
        }

        if (mode_provided) {
            if (c.chmod(path_z.ptr, @intCast(mode)) != 0) {
                const err_str = std.mem.span(c.strerror(c.__errno_location().*));
                try stderr.print("mkfifo: cannot set permissions of '{s}': {s}\n", .{ path, err_str });
                exit_status = 1;
            }
        }
    }
    return exit_status;
}

fn printHelp(stdout: anytype) !void {
    try stdout.print(
        \\Usage: mkfifo [OPTION]... NAME...
        \\Create named pipes (FIFOs) with the given NAMEs.
        \\
        \\Mandatory arguments to long options are mandatory for short options too.
        \\  -m, --mode=MODE    set file permission bits to MODE, not a=rw - umask
        \\  -Z                 set the SELinux security context to default type
        \\      --context[=CTX]  like -Z, or if CTX is specified then set the
        \\                         SELinux or SMACK security context to CTX
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
    , .{});
}

fn printVersion(stdout: anytype) !void {
    try stdout.print("mkfifo (coreutilz) {s}\n", .{version});
}
