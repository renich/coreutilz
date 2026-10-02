const std = @import("std");
const c = @import("../compat/c.zig").c;
const eval = @import("realpath/eval.zig");

pub const name: []const u8 = "realpath";
pub const version: []const u8 = "0.1.0";

pub const CanonMode = eval.CanonMode;
pub const RealpathOptions = eval.RealpathOptions;

fn parseModeOrFlag(arg: []const u8, opts: *RealpathOptions) bool {
    if (std.mem.eql(u8, arg, "--canonicalize") or std.mem.eql(u8, arg, "-E")) {
        opts.mode = .all_but_last;
    } else if (std.mem.eql(u8, arg, "--canonicalize-existing")) {
        opts.mode = .existing;
    } else if (std.mem.eql(u8, arg, "--canonicalize-missing")) {
        opts.mode = .missing;
    } else if (std.mem.eql(u8, arg, "--logical")) {
        opts.logical = true;
    } else if (std.mem.eql(u8, arg, "--physical")) {
        opts.logical = false;
        opts.no_symlinks = false;
    } else if (std.mem.eql(u8, arg, "--quiet")) {
        opts.quiet = true;
    } else if (std.mem.eql(u8, arg, "--strip") or std.mem.eql(u8, arg, "--no-symlinks")) {
        opts.no_symlinks = true;
    } else if (std.mem.eql(u8, arg, "--zero")) {
        opts.zero = true;
    } else {
        return false;
    }
    return true;
}

fn parseRelativeArg(arg: []const u8, i: *usize, args: [][]const u8, opts: *RealpathOptions, stderr: anytype) bool {
    if (std.mem.startsWith(u8, arg, "--relative-to=")) {
        opts.relative_to = arg["--relative-to=".len..];
    } else if (std.mem.eql(u8, arg, "--relative-to")) {
        if (i.* + 1 < args.len) {
            i.* += 1;
            opts.relative_to = args[i.*];
        } else {
            stderr.print("realpath: option '--relative-to' requires an argument\nTry 'realpath --help' for more information.\n", .{}) catch {};
            return false;
        }
    } else if (std.mem.startsWith(u8, arg, "--relative-base=")) {
        opts.relative_base = arg["--relative-base=".len..];
    } else if (std.mem.eql(u8, arg, "--relative-base")) {
        if (i.* + 1 < args.len) {
            i.* += 1;
            opts.relative_base = args[i.*];
        } else {
            stderr.print("realpath: option '--relative-base' requires an argument\nTry 'realpath --help' for more information.\n", .{}) catch {};
            return false;
        }
    } else {
        stderr.print("realpath: unrecognized option '{s}'\nTry 'realpath --help' for more information.\n", .{arg}) catch {};
        return false;
    }
    return true;
}

fn parseOption(arg: []const u8, i: *usize, args: [][]const u8, opts: *RealpathOptions, stderr: anytype) bool {
    if (std.mem.startsWith(u8, arg, "--")) {
        if (parseModeOrFlag(arg, opts)) return true;
        return parseRelativeArg(arg, i, args, opts, stderr);
    }
    for (arg[1..]) |ch| {
        switch (ch) {
            'E' => opts.mode = .all_but_last,
            'e' => opts.mode = .existing,
            'm' => opts.mode = .missing,
            'L' => opts.logical = true,
            'P' => {
                opts.logical = false;
                opts.no_symlinks = false;
            },
            'q' => opts.quiet = true,
            's' => opts.no_symlinks = true,
            'z' => opts.zero = true,
            else => {
                stderr.print("realpath: invalid option -- '{c}'\nTry 'realpath --help' for more information.\n", .{ch}) catch {};
                return false;
            },
        }
    }
    return true;
}

fn parseArgs(args: [][]const u8, opts: *RealpathOptions, files: *std.ArrayListUnmanaged([]const u8), alloc: std.mem.Allocator, stdout: anytype, stderr: anytype) !?u8 {
    var past = false;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (past or !std.mem.startsWith(u8, arg, "-") or std.mem.eql(u8, arg, "-")) {
            try files.append(alloc, arg);
        } else if (std.mem.eql(u8, arg, "--")) {
            past = true;
        } else if (std.mem.eql(u8, arg, "--help")) {
            try stdout.print("Usage: realpath [OPTION]... FILE...\nPrint the resolved absolute file name.\n", .{});
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try stdout.print("realpath (coreutilz) {s}\n", .{version});
            return 0;
        } else if (!parseOption(arg, &i, args, opts, stderr)) {
            return 1;
        }
    }
    return null;
}

fn checkRelDir(can: []const u8, orig: []const u8, alloc: std.mem.Allocator, stderr: anytype) bool {
    const rt_z = alloc.dupeZ(u8, can) catch return false;
    defer alloc.free(rt_z);
    var st: c.struct_stat = undefined;
    if (c.stat(rt_z.ptr, &st) != 0 or (st.st_mode & c.S_IFMT) != c.S_IFDIR) {
        stderr.print("realpath: '{s}': Not a directory\n", .{orig}) catch {};
        return false;
    }
    return true;
}

fn prepareRelBases(opts: *RealpathOptions, alloc: std.mem.Allocator, stderr: anytype) !struct { ?[]const u8, ?[]const u8, bool } {
    if (opts.relative_base != null and opts.relative_to == null) opts.relative_to = opts.relative_base;
    var can_rel_to: ?[]const u8 = null;
    var can_rel_base: ?[]const u8 = null;
    const need_dir = opts.mode == .existing;

    if (opts.relative_to) |rt| {
        if (rt.len == 0) return .{ null, null, false };
        const can = (try eval.canonicalizePath(rt, opts, alloc, stderr)) orelse return .{ null, null, false };
        if (need_dir and !checkRelDir(can, rt, alloc, stderr)) {
            alloc.free(can);
            return .{ null, null, false };
        }
        can_rel_to = can;
    }
    if (opts.relative_base) |rb| {
        if (rb.len == 0) return .{ can_rel_to, null, false };
        const can = (try eval.canonicalizePath(rb, opts, alloc, stderr)) orelse return .{ can_rel_to, null, false };
        if (need_dir and !checkRelDir(can, rb, alloc, stderr)) {
            alloc.free(can);
            return .{ can_rel_to, null, false };
        }
        if (can_rel_to != null and eval.pathPrefix(can, can_rel_to.?)) {
            can_rel_base = can;
        } else {
            alloc.free(can);
            can_rel_base = can_rel_to;
            can_rel_to = null;
        }
    }
    return .{ can_rel_to, can_rel_base, true };
}

fn processFiles(files: []const []const u8, opts: *const RealpathOptions, can_to: ?[]const u8, can_base: ?[]const u8, alloc: std.mem.Allocator, stdout: anytype, stderr: anytype) !bool {
    var ok = true;
    for (files) |file_arg| {
        const can = try eval.canonicalizePath(file_arg, opts, alloc, stderr);
        if (can) |p| {
            defer alloc.free(p);
            try eval.formatAndPrint(p, can_to, can_base, opts.zero, alloc, stdout);
        } else {
            ok = false;
        }
    }
    return ok;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &out_w.interface;
    const stderr = &err_w.interface;

    var opts = RealpathOptions{};
    var files: std.ArrayListUnmanaged([]const u8) = .empty;
    defer files.deinit(allocator);

    if (try parseArgs(args, &opts, &files, allocator, stdout, stderr)) |rc| {
        stdout.flush() catch return 1;
        stderr.flush() catch {};
        return rc;
    }
    if (files.items.len == 0) {
        stderr.print("realpath: missing operand\nTry 'realpath --help' for more information.\n", .{}) catch {};
        stderr.flush() catch {};
        return 1;
    }
    const rel_res = try prepareRelBases(&opts, allocator, stderr);
    if (!rel_res[2]) {
        if (rel_res[0]) |to| allocator.free(to);
        if (rel_res[1]) |base| allocator.free(base);
        stderr.flush() catch {};
        return 1;
    }
    const can_rel_to = rel_res[0];
    defer if (can_rel_to) |to| allocator.free(to);
    const can_rel_base = rel_res[1];
    defer if (can_rel_base) |base| allocator.free(base);

    const ok = try processFiles(files.items, &opts, can_rel_to, can_rel_base, allocator, stdout, stderr);
    stdout.flush() catch return 1;
    stderr.flush() catch {};
    return if (ok) 0 else 1;
}
