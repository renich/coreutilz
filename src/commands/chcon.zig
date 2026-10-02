const std = @import("std");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "chcon";
pub const version: []const u8 = "0.1.0";

const XATTR_SELINUX = "security.selinux";

const ChconOptions = struct {
    user: ?[]const u8 = null,
    role: ?[]const u8 = null,
    type_name: ?[]const u8 = null,
    range: ?[]const u8 = null,
    reference: ?[]const u8 = null,
    recursive: bool = false,
    dereference: bool = true,
    preserve_root: bool = false,
    verbose: bool = false,
    changes: bool = false,
};

fn getFileContext(path: []const u8, deref: bool, buf: *[512]u8) ?[]const u8 {
    var path_z: [4096]u8 = undefined;
    const pz = std.fmt.bufPrintZ(&path_z, "{s}", .{path}) catch return null;
    const n = if (deref)
        c.getxattr(pz.ptr, XATTR_SELINUX, buf, buf.len)
    else
        c.lgetxattr(pz.ptr, XATTR_SELINUX, buf, buf.len);
    if (n <= 0) return null;
    var len = @as(usize, @intCast(n));
    if (len > 0 and (buf[len - 1] == 0 or buf[len - 1] == '\n')) len -= 1;
    return buf[0..len];
}

fn setFileContext(path: []const u8, ctx: []const u8, deref: bool) !void {
    var path_z: [4096]u8 = undefined;
    const pz = try std.fmt.bufPrintZ(&path_z, "{s}", .{path});
    var ctx_z: [512]u8 = undefined;
    const cz = try std.fmt.bufPrintZ(&ctx_z, "{s}", .{ctx});
    const rc = if (deref)
        c.setxattr(pz.ptr, XATTR_SELINUX, cz.ptr, cz.len + 1, 0)
    else
        c.lsetxattr(pz.ptr, XATTR_SELINUX, cz.ptr, cz.len + 1, 0);
    if (rc != 0) return error.SetAttrFailed;
}

fn mergeContext(existing: []const u8, opts: *const ChconOptions, out: *[512]u8) ?[]const u8 {
    var it = std.mem.splitScalar(u8, existing, ':');
    const u = opts.user orelse (it.next() orelse return null);
    const r = opts.role orelse (it.next() orelse return null);
    const t = opts.type_name orelse (it.next() orelse return null);
    const rest = it.rest();
    const l = opts.range orelse if (rest.len > 0) rest else "s0";
    return std.fmt.bufPrint(out, "{s}:{s}:{s}:{s}", .{ u, r, t, l }) catch null;
}

fn processFile(path: []const u8, fixed_ctx: ?[]const u8, opts: *const ChconOptions, stdout: anytype, stderr: anytype) bool {
    var cur_buf: [512]u8 = undefined;
    const cur_ctx = getFileContext(path, opts.dereference, &cur_buf);
    var target_buf: [512]u8 = undefined;
    const target = fixed_ctx orelse blk: {
        const cur = cur_ctx orelse {
            stderr.print("chcon: can't apply partial context to unlabeled file '{s}'\n", .{path}) catch {};
            return false;
        };
        break :blk mergeContext(cur, opts, &target_buf) orelse return false;
    };

    const changed = cur_ctx == null or !std.mem.eql(u8, cur_ctx.?, target);
    setFileContext(path, target, opts.dereference) catch |err| {
        stderr.print("chcon: failed to change context of '{s}' to '{s}': {s}\n", .{ path, target, @errorName(err) }) catch {};
        return false;
    };
    if (opts.verbose or (opts.changes and changed)) {
        stdout.print("changing security context of '{s}' to '{s}'\n", .{ path, target }) catch {};
    }
    return true;
}

fn processTree(path: []const u8, fixed_ctx: ?[]const u8, opts: *const ChconOptions, stdout: anytype, stderr: anytype, alloc: std.mem.Allocator) bool {
    if (opts.preserve_root and (std.mem.eql(u8, path, "/") or std.mem.endsWith(u8, path, "/.."))) {
        stderr.print("chcon: it is dangerous to operate recursively on '/'\nchcon: use --no-preserve-root to override this failsafe\n", .{}) catch {};
        return false;
    }
    var ok = processFile(path, fixed_ctx, opts, stdout, stderr);
    if (!opts.recursive) return ok;

    const path_z = alloc.dupeZ(u8, path) catch return ok;
    defer alloc.free(path_z);
    const dir = c.opendir(path_z.ptr) orelse return ok;
    defer _ = c.closedir(dir);

    while (c.readdir(dir)) |entry| {
        const entry_name = std.mem.span(@as([*:0]const u8, @ptrCast(&entry.*.d_name)));
        if (std.mem.eql(u8, entry_name, ".") or std.mem.eql(u8, entry_name, "..")) continue;
        const sub = std.fmt.allocPrint(alloc, "{s}/{s}", .{ path, entry_name }) catch continue;
        defer alloc.free(sub);
        if (!processTree(sub, fixed_ctx, opts, stdout, stderr, alloc)) ok = false;
    }
    return ok;
}

fn parseComponent(arg: []const u8, idx: *usize, args: [][]const u8) ?[]const u8 {
    if (arg.len > 2) return arg[2..];
    idx.* += 1;
    return if (idx.* < args.len) args[idx.*] else null;
}

fn parseFlag(arg: []const u8, opts: *ChconOptions) bool {
    if (std.mem.eql(u8, arg, "-R") or std.mem.eql(u8, arg, "--recursive")) opts.recursive = true else if (std.mem.eql(u8, arg, "--dereference")) opts.dereference = true else if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--no-dereference")) opts.dereference = false else if (std.mem.eql(u8, arg, "--preserve-root")) opts.preserve_root = true else if (std.mem.eql(u8, arg, "--no-preserve-root")) opts.preserve_root = false else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) opts.verbose = true else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--changes")) opts.changes = true else return false;
    return true;
}

fn parseOptions(args: [][]const u8, opts: *ChconOptions, files: *std.ArrayListUnmanaged([]const u8), ctx_arg: *?[]const u8, stdout: anytype, stderr: anytype, alloc: std.mem.Allocator) !?u8 {
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            try stdout.print("Usage: chcon [OPTION]... CONTEXT FILE...\n  or:  chcon [OPTION]... [-u USER] [-r ROLE] [-l RANGE] [-t TYPE] FILE...\n  or:  chcon [OPTION]... --reference=RFILE FILE...\nChange the SELinux security context of each FILE to CONTEXT.\n", .{});
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try stdout.print("chcon (coreutilz) {s}\n", .{version});
            return 0;
        } else if (parseFlag(arg, opts)) {
            continue;
        } else if (std.mem.startsWith(u8, arg, "-u")) {
            opts.user = parseComponent(arg, &i, args);
        } else if (std.mem.startsWith(u8, arg, "-r")) {
            opts.role = parseComponent(arg, &i, args);
        } else if (std.mem.startsWith(u8, arg, "-t")) {
            opts.type_name = parseComponent(arg, &i, args);
        } else if (std.mem.startsWith(u8, arg, "-l")) {
            opts.range = parseComponent(arg, &i, args);
        } else if (std.mem.startsWith(u8, arg, "--reference=")) {
            opts.reference = arg["--reference=".len..];
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            try stderr.print("chcon: unrecognized option '{s}'\nTry 'chcon --help' for more information.\n", .{arg});
            return 1;
        } else {
            const has_s = opts.user != null or opts.role != null or opts.type_name != null or opts.range != null or opts.reference != null;
            if (!has_s and ctx_arg.* == null) ctx_arg.* = arg else try files.append(alloc, arg);
        }
    }
    return null;
}

fn checkOperands(ctx_arg: ?[]const u8, opts: *const ChconOptions, files_len: usize, stderr: anytype) bool {
    const has_spec = ctx_arg != null or opts.user != null or opts.role != null or opts.type_name != null or opts.range != null;
    if (!has_spec) {
        stderr.print("chcon: missing operand\nTry 'chcon --help' for more information.\n", .{}) catch {};
        return false;
    }
    if (files_len == 0) {
        if (ctx_arg) |c_str| {
            stderr.print("chcon: missing operand after '{s}'\nTry 'chcon --help' for more information.\n", .{c_str}) catch {};
        } else {
            stderr.print("chcon: missing operand\nTry 'chcon --help' for more information.\n", .{}) catch {};
        }
        return false;
    }
    return true;
}

fn resolveContext(opts: *const ChconOptions, ctx_arg: *?[]const u8, buf: *[512]u8, files_len: usize, stderr: anytype) bool {
    if (opts.reference) |ref| {
        ctx_arg.* = getFileContext(ref, opts.dereference, buf) orelse {
            stderr.print("chcon: failed to get security context of '{s}'\n", .{ref}) catch {};
            return false;
        };
    }
    return checkOperands(ctx_arg.*, opts, files_len, stderr);
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &out_w.interface;
    const stderr = &err_w.interface;

    var opts = ChconOptions{};
    var files: std.ArrayListUnmanaged([]const u8) = .empty;
    defer files.deinit(allocator);
    var ctx_arg: ?[]const u8 = null;

    if (try parseOptions(args, &opts, &files, &ctx_arg, stdout, stderr, allocator)) |rc| {
        stdout.flush() catch return 1;
        stderr.flush() catch return 1;
        return rc;
    }

    var ref_buf: [512]u8 = undefined;
    if (!resolveContext(&opts, &ctx_arg, &ref_buf, files.items.len, stderr)) {
        stderr.flush() catch {};
        return 1;
    }

    var ok = true;
    for (files.items) |f| {
        if (!processTree(f, ctx_arg, &opts, stdout, stderr, allocator)) ok = false;
    }
    stdout.flush() catch return 1;
    stderr.flush() catch return 1;
    return if (ok) 0 else 1;
}
