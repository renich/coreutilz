const std = @import("std");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "mktemp";
pub const version: []const u8 = "0.1.0";

const MktempOptions = struct {
    directory: bool = false,
    dry_run: bool = false,
    quiet: bool = false,
    use_dest_dir: bool = false,
    deprecated_t: bool = false,
    dest_dir_arg: ?[]const u8 = null,
    suffix: ?[]const u8 = null,
};

fn countConsecutiveXs(s: []const u8) usize {
    var count: usize = 0;
    var i = s.len;
    while (i > 0 and s[i - 1] == 'X') : (i -= 1) count += 1;
    return count;
}

fn fillRandomXs(buf: []u8, count: usize, suffix_len: usize) void {
    const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
    const body = buf[0 .. buf.len - suffix_len];
    const start = body.len - count;
    var io_source: std.Random.IoSource = .{ .io = std.Options.debug_io };
    const rand = io_source.interface();
    for (body[start..]) |*byte| {
        byte.* = chars[rand.uintLessThan(usize, chars.len)];
    }
}

fn tryCreate(path: []const u8, is_dir: bool, last_errno: *c_int) bool {
    var path_z: [std.fs.max_path_bytes]u8 = undefined;
    const pz = std.fmt.bufPrintZ(&path_z, "{s}", .{path}) catch {
        last_errno.* = c.ENAMETOOLONG;
        return false;
    };
    if (is_dir) {
        if (c.mkdir(pz.ptr, 0o700) == 0) return true;
        last_errno.* = c.__errno_location().*;
        return false;
    } else {
        const fd = c.open(pz.ptr, c.O_RDWR | c.O_CREAT | c.O_EXCL, @as(c_uint, 0o600));
        if (fd < 0) {
            last_errno.* = c.__errno_location().*;
            return false;
        }
        _ = c.close(fd);
        return true;
    }
}

fn generateAndCreate(
    base_path: []const u8,
    x_count: usize,
    suff_len: usize,
    is_dir: bool,
    dry_run: bool,
    alloc: std.mem.Allocator,
    last_errno: *c_int,
) !?[]const u8 {
    const candidate = try alloc.dupe(u8, base_path);
    var attempts: usize = 0;
    while (attempts < 100) : (attempts += 1) {
        fillRandomXs(candidate, x_count, suff_len);
        if (dry_run) return candidate;
        if (tryCreate(candidate, is_dir, last_errno)) return candidate;
        if (last_errno.* != c.EEXIST) break;
    }
    alloc.free(candidate);
    return null;
}

fn resolveDir(opts: *const MktempOptions) []const u8 {
    const env_tmp = if (c.getenv("TMPDIR")) |t| std.mem.span(t) else null;
    if (opts.deprecated_t) {
        if (env_tmp) |t| if (t.len > 0) return t;
        if (opts.dest_dir_arg) |d| if (d.len > 0) return d;
        return "/tmp";
    }
    if (opts.dest_dir_arg) |d| if (d.len > 0) return d;
    if (env_tmp) |t| if (t.len > 0) return t;
    return "/tmp";
}

fn buildFullTemplate(tmpl: []const u8, suff: []const u8, opts: *const MktempOptions, alloc: std.mem.Allocator, stderr: anytype) !?[]const u8 {
    if (!opts.use_dest_dir) {
        return try std.fmt.allocPrint(alloc, "{s}{s}", .{ tmpl, suff });
    }
    if (opts.deprecated_t and std.mem.indexOfScalar(u8, tmpl, '/') != null) {
        stderr.print("mktemp: invalid template, '{s}', contains directory separator\n", .{tmpl}) catch {};
        return null;
    }
    if (!opts.deprecated_t and std.mem.startsWith(u8, tmpl, "/")) {
        stderr.print("mktemp: invalid template, '{s}'; with --tmpdir, it may not be absolute\n", .{tmpl}) catch {};
        return null;
    }
    const dir = resolveDir(opts);
    if (std.mem.endsWith(u8, dir, "/")) {
        return try std.fmt.allocPrint(alloc, "{s}{s}{s}", .{ dir, tmpl, suff });
    }
    return try std.fmt.allocPrint(alloc, "{s}/{s}{s}", .{ dir, tmpl, suff });
}

fn parseOptVal(arg: []const u8, prefix: []const u8, i: *usize, args: [][]const u8) ?[]const u8 {
    if (arg.len > prefix.len) return arg[prefix.len..];
    if (i.* + 1 < args.len) {
        i.* += 1;
        return args[i.*];
    }
    return null;
}

fn parseOption(arg: []const u8, i: *usize, args: [][]const u8, opts: *MktempOptions, stderr: anytype) bool {
    if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--directory")) {
        opts.directory = true;
    } else if (std.mem.eql(u8, arg, "-u") or std.mem.eql(u8, arg, "--dry-run")) {
        opts.dry_run = true;
    } else if (std.mem.eql(u8, arg, "-q") or std.mem.eql(u8, arg, "--quiet")) {
        opts.quiet = true;
    } else if (std.mem.startsWith(u8, arg, "--suffix=")) {
        opts.suffix = arg["--suffix=".len..];
    } else if (std.mem.eql(u8, arg, "--suffix")) {
        opts.suffix = parseOptVal(arg, "--suffix", i, args);
    } else if (std.mem.startsWith(u8, arg, "--tmpdir=")) {
        opts.use_dest_dir = true;
        opts.dest_dir_arg = arg["--tmpdir=".len..];
    } else if (std.mem.eql(u8, arg, "--tmpdir")) {
        opts.use_dest_dir = true;
    } else if (std.mem.startsWith(u8, arg, "-p")) {
        opts.use_dest_dir = true;
        opts.dest_dir_arg = parseOptVal(arg, "-p", i, args);
    } else if (std.mem.eql(u8, arg, "-t")) {
        opts.use_dest_dir = true;
        opts.deprecated_t = true;
    } else {
        stderr.print("mktemp: unrecognized option '{s}'\nTry 'mktemp --help' for more information.\n", .{arg}) catch {};
        return false;
    }
    return true;
}

fn parseArgs(args: [][]const u8, opts: *MktempOptions, tmpl: *?[]const u8, stdout: anytype, stderr: anytype) !?u8 {
    const posixly_correct = c.getenv("POSIXLY_CORRECT") != null;
    var i: usize = 1;
    var past = false;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (past or !std.mem.startsWith(u8, arg, "-") or std.mem.eql(u8, arg, "-")) {
            if (posixly_correct) past = true;
            if (tmpl.* == null) tmpl.* = arg else {
                stderr.print("mktemp: too many templates\nTry 'mktemp --help' for more information.\n", .{}) catch {};
                return 1;
            }
        } else if (std.mem.eql(u8, arg, "--")) {
            past = true;
        } else if (std.mem.eql(u8, arg, "--help")) {
            try stdout.print("Usage: mktemp [OPTION]... [TEMPLATE]\nCreate a temporary file or directory, safely, and print its name.\n", .{});
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try stdout.print("mktemp (coreutilz) {s}\n", .{version});
            return 0;
        } else if (!parseOption(arg, &i, args, opts, stderr)) {
            return 1;
        }
    }
    return null;
}

fn splitTemplate(raw_tmpl: []const u8, custom_suffix: ?[]const u8, stderr: anytype) ?struct { tmpl: []const u8, suff: []const u8 } {
    if (custom_suffix) |s| {
        if (raw_tmpl.len == 0 or raw_tmpl[raw_tmpl.len - 1] != 'X') {
            stderr.print("mktemp: with --suffix, template '{s}' must end in X\n", .{raw_tmpl}) catch {};
            return null;
        }
        if (std.mem.indexOfScalar(u8, s, '/') != null) {
            stderr.print("mktemp: invalid suffix '{s}', contains directory separator\n", .{s}) catch {};
            return null;
        }
        return .{ .tmpl = raw_tmpl, .suff = s };
    }
    if (std.mem.lastIndexOfScalar(u8, raw_tmpl, 'X')) |last_x| {
        const suff = raw_tmpl[last_x + 1 ..];
        if (suff.len > 0 and std.mem.indexOfScalar(u8, suff, '/') != null) {
            stderr.print("mktemp: invalid suffix '{s}', contains directory separator\n", .{suff}) catch {};
            return null;
        }
        return .{ .tmpl = raw_tmpl[0 .. last_x + 1], .suff = suff };
    }
    return .{ .tmpl = raw_tmpl, .suff = "" };
}

fn resolveTemplate(tmpl_arg: ?[]const u8, suffix: ?[]const u8, stderr: anytype) ?struct { raw: []const u8, tmpl: []const u8, suff: []const u8, x_count: usize } {
    const raw = tmpl_arg orelse "tmp.XXXXXXXXXX";
    const parts = splitTemplate(raw, suffix, stderr) orelse return null;
    const x_count = countConsecutiveXs(parts.tmpl);
    if (x_count < 3) {
        stderr.print("mktemp: too few X's in template '{s}'\n", .{raw}) catch {};
        return null;
    }
    return .{ .raw = raw, .tmpl = parts.tmpl, .suff = parts.suff, .x_count = x_count };
}

fn doGenerate(full_tmpl: []const u8, t: anytype, opts: *const MktempOptions, alloc: std.mem.Allocator, stdout: anytype, stderr: anytype) !u8 {
    var last_errno: c_int = 0;
    const created = try generateAndCreate(full_tmpl, t.x_count, t.suff.len, opts.directory, opts.dry_run, alloc, &last_errno);
    if (created) |path| {
        defer alloc.free(path);
        try stdout.print("{s}\n", .{path});
        stdout.flush() catch return 1;
        return 0;
    }
    if (!opts.quiet) {
        const kind = if (opts.directory) "directory" else "file";
        stderr.print("mktemp: failed to create {s} via template '{s}': {s}\n", .{ kind, full_tmpl, std.mem.span(c.strerror(last_errno)) }) catch {};
    }
    stderr.flush() catch {};
    return 1;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &out_w.interface;
    const stderr = &err_w.interface;

    var opts = MktempOptions{};
    var tmpl_arg: ?[]const u8 = null;
    if (try parseArgs(args, &opts, &tmpl_arg, stdout, stderr)) |rc| {
        stdout.flush() catch return 1;
        stderr.flush() catch {};
        return rc;
    }

    if (tmpl_arg == null) opts.use_dest_dir = true;
    const t = resolveTemplate(tmpl_arg, opts.suffix, stderr) orelse {
        stderr.flush() catch {};
        return 1;
    };

    const full_tmpl = (try buildFullTemplate(t.tmpl, t.suff, &opts, allocator, stderr)) orelse {
        stderr.flush() catch {};
        return 1;
    };
    defer allocator.free(full_tmpl);

    return doGenerate(full_tmpl, t, &opts, allocator, stdout, stderr);
}
