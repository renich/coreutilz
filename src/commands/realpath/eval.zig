const std = @import("std");
const c = @import("../../compat/c.zig").c;

pub const CanonMode = enum { all_but_last, existing, missing };

pub const RealpathOptions = struct {
    mode: CanonMode = .all_but_last,
    logical: bool = false,
    no_symlinks: bool = false,
    quiet: bool = false,
    zero: bool = false,
    relative_to: ?[]const u8 = null,
    relative_base: ?[]const u8 = null,
};

fn resolveMissing(path: []const u8, no_symlinks: bool, alloc: std.mem.Allocator) ![]const u8 {
    if (!no_symlinks) {
        const p_z = try alloc.dupeZ(u8, path);
        defer alloc.free(p_z);
        if (c.realpath(p_z.ptr, null)) |res_c| {
            defer c.free(res_c);
            return try alloc.dupe(u8, std.mem.span(res_c));
        }
    }
    const abs_path = if (std.fs.path.isAbsolute(path))
        try alloc.dupe(u8, path)
    else blk: {
        const cwd_c = c.getcwd(null, 0) orelse return error.OutOfMemory;
        defer c.free(cwd_c);
        const cwd = std.mem.span(cwd_c);
        break :blk try std.fs.path.join(alloc, &.{ cwd, path });
    };
    defer alloc.free(abs_path);
    return std.fs.path.resolve(alloc, &.{abs_path});
}

fn canonicalizeMissing(p: []const u8, opts: *const RealpathOptions, alloc: std.mem.Allocator, stderr: anytype) !?[]const u8 {
    const res = (resolveMissing(p, opts.no_symlinks, alloc) catch null) orelse return null;
    if (opts.mode == .existing) {
        const p_z = alloc.dupeZ(u8, res) catch {
            alloc.free(res);
            return null;
        };
        defer alloc.free(p_z);
        var st: c.struct_stat = undefined;
        if (c.lstat(p_z.ptr, &st) != 0) {
            if (!opts.quiet) stderr.print("realpath: '{s}': No such file or directory\n", .{p}) catch {};
            alloc.free(res);
            return null;
        }
    }
    return res;
}

fn canonicalizeParent(p: []const u8, alloc: std.mem.Allocator) !?[]const u8 {
    const parent = std.fs.path.dirname(p) orelse ".";
    const base = std.fs.path.basename(p);
    const parent_z = alloc.dupeZ(u8, parent) catch return null;
    defer alloc.free(parent_z);
    if (c.realpath(parent_z.ptr, null)) |res_p| {
        defer c.free(res_p);
        var st: c.struct_stat = undefined;
        if (c.stat(res_p, &st) == 0 and (st.st_mode & c.S_IFMT) == c.S_IFDIR) {
            return try std.fs.path.join(alloc, &.{ std.mem.span(res_p), base });
        }
    }
    return null;
}

pub fn canonicalizePath(p: []const u8, opts: *const RealpathOptions, alloc: std.mem.Allocator, stderr: anytype) !?[]const u8 {
    if (p.len == 0) {
        if (!opts.quiet) stderr.print("realpath: '': No such file or directory\n", .{}) catch {};
        return null;
    }
    if (opts.logical) {
        var log_opts = opts.*;
        log_opts.no_symlinks = true;
        log_opts.logical = false;
        const norm = (try canonicalizePath(p, &log_opts, alloc, stderr)) orelse return null;
        defer alloc.free(norm);
        var phys_opts = opts.*;
        phys_opts.no_symlinks = false;
        phys_opts.logical = false;
        return canonicalizePath(norm, &phys_opts, alloc, stderr);
    }
    if (opts.no_symlinks or opts.mode == .missing) return canonicalizeMissing(p, opts, alloc, stderr);
    const p_z = alloc.dupeZ(u8, p) catch return null;
    defer alloc.free(p_z);
    if (c.realpath(p_z.ptr, null)) |res_c| {
        defer c.free(res_c);
        return try alloc.dupe(u8, std.mem.span(res_c));
    }
    if (opts.mode == .all_but_last) {
        if (try canonicalizeParent(p, alloc)) |res| return res;
    }
    if (!opts.quiet) {
        const err = c.__errno_location().*;
        const msg = if (err == c.ENOENT) "No such file or directory" else "cannot resolve";
        stderr.print("realpath: '{s}': {s}\n", .{ p, msg }) catch {};
    }
    return null;
}

pub fn pathPrefix(prefix: []const u8, path: []const u8) bool {
    var pfx = prefix;
    var pth = path;
    if (pfx.len > 0 and pfx[0] == '/') pfx = pfx[1..];
    if (pth.len > 0 and pth[0] == '/') pth = pth[1..];
    if (pfx.len == 0) return pth.len == 0 or pth[0] != '/';
    if (pfx.len == 1 and pfx[0] == '/') return pth.len > 0 and pth[0] == '/';
    var i: usize = 0;
    while (i < pfx.len and i < pth.len) : (i += 1) {
        if (pfx[i] != pth[i]) return false;
    }
    if (i < pfx.len) return false;
    return i == pth.len or pth[i] == '/';
}

fn pathCommonPrefix(p1: []const u8, p2: []const u8) usize {
    if (p1.len == 0 or p2.len == 0) return 0;
    if ((p1.len > 1 and p1[1] == '/') != (p2.len > 1 and p2[1] == '/')) return 0;
    var i: usize = 0;
    var ret: usize = 0;
    while (i < p1.len and i < p2.len) : (i += 1) {
        if (p1[i] != p2[i]) break;
        if (p1[i] == '/') ret = i + 1;
    }
    if ((i == p1.len and i == p2.len) or (i == p1.len and p2[i] == '/') or (i == p2.len and p1[i] == '/')) {
        ret = i;
    }
    return ret;
}

pub fn computeRelpath(can_fname: []const u8, can_reldir: []const u8, alloc: std.mem.Allocator) ![]const u8 {
    const common = pathCommonPrefix(can_reldir, can_fname);
    if (common == 0) return try alloc.dupe(u8, can_fname);
    var relto_suffix = can_reldir[common..];
    var fname_suffix = can_fname[common..];
    if (relto_suffix.len > 0 and relto_suffix[0] == '/') relto_suffix = relto_suffix[1..];
    if (fname_suffix.len > 0 and fname_suffix[0] == '/') fname_suffix = fname_suffix[1..];

    if (relto_suffix.len > 0) {
        var list: std.ArrayListUnmanaged(u8) = .empty;
        defer list.deinit(alloc);
        try list.appendSlice(alloc, "..");
        for (relto_suffix) |ch| {
            if (ch == '/') try list.appendSlice(alloc, "/..");
        }
        if (fname_suffix.len > 0) {
            try list.append(alloc, '/');
            try list.appendSlice(alloc, fname_suffix);
        }
        return list.toOwnedSlice(alloc);
    } else {
        if (fname_suffix.len == 0) return try alloc.dupe(u8, ".");
        return try alloc.dupe(u8, fname_suffix);
    }
}

pub fn formatAndPrint(res_path: []const u8, can_rel_to: ?[]const u8, can_rel_base: ?[]const u8, zero: bool, alloc: std.mem.Allocator, stdout: anytype) !void {
    var out_path = res_path;
    var to_free: ?[]const u8 = null;
    defer if (to_free) |f| alloc.free(f);

    if (can_rel_to) |rel_to| {
        if (can_rel_base == null or pathPrefix(can_rel_base.?, res_path)) {
            const rel = try computeRelpath(res_path, rel_to, alloc);
            out_path = rel;
            to_free = rel;
        }
    }
    try stdout.print("{s}", .{out_path});
    try stdout.writeByte(if (zero) 0 else '\n');
}
