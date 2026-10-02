const std = @import("std");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "pathchk";
pub const version: []const u8 = "0.1.0";

const PathchkOptions = struct {
    check_posix: bool = false,
    check_extra: bool = false,
};

fn isPortableChar(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '.' or ch == '_' or ch == '-';
}

fn checkComponent(comp: []const u8, full_name: []const u8, opts: *const PathchkOptions, stderr: anytype) bool {
    const max_comp: usize = if (opts.check_posix) 14 else 255;
    if (comp.len > max_comp) {
        stderr.print("pathchk: limit {d} exceeded by length {d} of file name component '{s}'\n", .{ max_comp, comp.len, comp }) catch {};
        return false;
    }
    if (opts.check_extra and comp.len > 0 and comp[0] == '-') {
        stderr.print("pathchk: leading '-' in a component of file name '{s}'\n", .{full_name}) catch {};
        return false;
    }
    if (opts.check_posix) {
        for (comp) |ch| {
            if (!isPortableChar(ch)) {
                stderr.print("pathchk: non-portable character '{c}' in file name '{s}'\n", .{ ch, full_name }) catch {};
                return false;
            }
        }
    }
    return true;
}

fn checkPath(p: []const u8, opts: *const PathchkOptions, stderr: anytype) bool {
    if (p.len == 0) {
        if (opts.check_extra or opts.check_posix) {
            stderr.print("pathchk: empty file name\n", .{}) catch {};
            return false;
        }
        return true;
    }
    if (!opts.check_posix) {
        var p_z: [std.fs.max_path_bytes]u8 = undefined;
        const pz = std.fmt.bufPrintZ(&p_z, "{s}", .{p}) catch return false;
        var st: c.struct_stat = undefined;
        if (c.lstat(pz.ptr, &st) != 0) {
            const err = c.__errno_location().*;
            if (err != c.ENOENT) {
                stderr.print("pathchk: '{s}': {s}\n", .{ p, c.strerror(err) }) catch {};
                return false;
            }
        }
    }
    const max_path: usize = if (opts.check_posix) 256 else 4096;
    if (p.len > max_path) {
        stderr.print("pathchk: limit {d} exceeded by length {d} of file name '{s}'\n", .{ max_path, p.len, p }) catch {};
        return false;
    }
    var ok = true;
    var it = std.mem.splitScalar(u8, p, '/');
    while (it.next()) |comp| {
        if (comp.len == 0) continue;
        if (!checkComponent(comp, p, opts, stderr)) ok = false;
    }
    return ok;
}

fn parseOption(arg: []const u8, opts: *PathchkOptions, stderr: anytype) ?bool {
    if (std.mem.eql(u8, arg, "--portability")) {
        opts.check_posix = true;
        opts.check_extra = true;
        return true;
    }
    if (std.mem.startsWith(u8, arg, "--")) {
        stderr.print("pathchk: unrecognized option '{s}'\nTry 'pathchk --help' for more information.\n", .{arg}) catch {};
        return false;
    }
    for (arg[1..]) |ch| switch (ch) {
        'p' => opts.check_posix = true,
        'P' => opts.check_extra = true,
        else => {
            stderr.print("pathchk: invalid option -- '{c}'\nTry 'pathchk --help' for more information.\n", .{ch}) catch {};
            return false;
        },
    };
    return true;
}

fn parseArgs(args: [][]const u8, opts: *PathchkOptions, names: *std.ArrayListUnmanaged([]const u8), alloc: std.mem.Allocator, stdout: anytype, stderr: anytype) !?u8 {
    var past = false;
    for (args[1..]) |arg| {
        if (past or !std.mem.startsWith(u8, arg, "-") or std.mem.eql(u8, arg, "-")) {
            try names.append(alloc, arg);
        } else if (std.mem.eql(u8, arg, "--")) {
            past = true;
        } else if (std.mem.eql(u8, arg, "--help")) {
            try stdout.print("Usage: pathchk [OPTION]... NAME...\nDiagnose invalid or non-portable file names.\n", .{});
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try stdout.print("pathchk (coreutilz) {s}\n", .{version});
            return 0;
        } else if (parseOption(arg, opts, stderr)) |valid| {
            if (!valid) return 1;
        }
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

    var opts = PathchkOptions{};
    var names: std.ArrayListUnmanaged([]const u8) = .empty;
    defer names.deinit(allocator);

    if (try parseArgs(args, &opts, &names, allocator, stdout, stderr)) |rc| {
        stdout.flush() catch return 1;
        stderr.flush() catch {};
        return rc;
    }
    if (names.items.len == 0) {
        stderr.print("pathchk: missing operand\nTry 'pathchk --help' for more information.\n", .{}) catch {};
        stderr.flush() catch {};
        return 1;
    }
    var ok = true;
    for (names.items) |name_arg| {
        if (!checkPath(name_arg, &opts, stderr)) ok = false;
    }
    stdout.flush() catch return 1;
    stderr.flush() catch {};
    return if (ok) 0 else 1;
}
