const std = @import("std");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "install";
pub const version: []const u8 = "0.1.0";

const InstallOptions = struct {
    directory: bool = false,
    create_leading: bool = false,
    mode: u32 = 0o755,
    owner: ?c.uid_t = null,
    group: ?c.gid_t = null,
    strip: bool = false,
    preserve_timestamps: bool = false,
    verbose: bool = false,
    target_dir: ?[]const u8 = null,
    no_target_dir: bool = false,
    compare: bool = false,
};

fn resolveUid(str: []const u8) ?c.uid_t {
    var str_z: [256]u8 = undefined;
    const pz = std.fmt.bufPrintZ(&str_z, "{s}", .{str}) catch return null;
    const pw = c.getpwnam(pz.ptr);
    if (pw != null) return pw.*.pw_uid;
    return std.fmt.parseInt(c.uid_t, str, 10) catch null;
}

fn resolveGid(str: []const u8) ?c.gid_t {
    var str_z: [256]u8 = undefined;
    const pz = std.fmt.bufPrintZ(&str_z, "{s}", .{str}) catch return null;
    const gr = c.getgrnam(pz.ptr);
    if (gr != null) return gr.*.gr_gid;
    return std.fmt.parseInt(c.gid_t, str, 10) catch null;
}

fn makePath(alloc: std.mem.Allocator, path: []const u8) !void {
    if (path.len == 0) return;
    var i: usize = 0;
    while (i < path.len) {
        while (i < path.len and path[i] == '/') i += 1;
        while (i < path.len and path[i] != '/') i += 1;
        if (i == 0) break;
        const sub = path[0..i];
        const sub_z = try alloc.dupeZ(u8, sub);
        defer alloc.free(sub_z);
        var st: c.struct_stat = undefined;
        if (c.stat(sub_z.ptr, &st) == 0) continue;
        _ = c.mkdir(sub_z.ptr, 0o777);
    }
}

fn isDirectory(path: []const u8) bool {
    var p_z: [std.fs.max_path_bytes]u8 = undefined;
    const pz = std.fmt.bufPrintZ(&p_z, "{s}", .{path}) catch return false;
    var st: c.struct_stat = undefined;
    if (c.stat(pz.ptr, &st) != 0) return false;
    return (st.st_mode & c.S_IFMT) == c.S_IFDIR;
}

fn installDir(dir: []const u8, opts: *const InstallOptions, alloc: std.mem.Allocator, stdout: anytype, stderr: anytype) bool {
    makePath(alloc, dir) catch |err| {
        stderr.print("install: cannot create directory '{s}': {s}\n", .{ dir, @errorName(err) }) catch {};
        return false;
    };
    var d_z: [std.fs.max_path_bytes]u8 = undefined;
    const dz = std.fmt.bufPrintZ(&d_z, "{s}", .{dir}) catch return false;
    _ = c.chmod(dz.ptr, opts.mode);
    if (opts.owner != null or opts.group != null) {
        _ = c.chown(dz.ptr, opts.owner orelse @as(c.uid_t, @bitCast(@as(c_uint, 0xFFFFFFFF))), opts.group orelse @as(c.gid_t, @bitCast(@as(c_uint, 0xFFFFFFFF))));
    }
    if (opts.verbose) stdout.print("creating directory '{s}'\n", .{dir}) catch {};
    return true;
}

fn copyFile(src: []const u8, dst: []const u8, opts: *const InstallOptions, alloc: std.mem.Allocator, stdout: anytype, stderr: anytype) bool {
    if (opts.create_leading) {
        if (std.fs.path.dirname(dst)) |p| makePath(alloc, p) catch {};
    }
    var src_z: [std.fs.max_path_bytes]u8 = undefined;
    const s_z = std.fmt.bufPrintZ(&src_z, "{s}", .{src}) catch return false;
    const s_fd = c.open(s_z.ptr, c.O_RDONLY);
    if (s_fd < 0) {
        stderr.print("install: cannot stat '{s}': No such file or directory\n", .{src}) catch {};
        return false;
    }
    defer _ = c.close(s_fd);

    var dst_z: [std.fs.max_path_bytes]u8 = undefined;
    const d_z = std.fmt.bufPrintZ(&dst_z, "{s}", .{dst}) catch return false;
    _ = c.unlink(d_z.ptr);
    const d_fd = c.open(d_z.ptr, c.O_WRONLY | c.O_CREAT | c.O_TRUNC, opts.mode);
    if (d_fd < 0) {
        stderr.print("install: cannot create regular file '{s}'\n", .{dst}) catch {};
        return false;
    }
    defer _ = c.close(d_fd);

    if (!copyBytes(s_fd, d_fd)) return false;

    _ = c.chmod(d_z.ptr, opts.mode);
    if (opts.owner != null or opts.group != null) {
        _ = c.chown(d_z.ptr, opts.owner orelse @as(c.uid_t, @bitCast(@as(c_uint, 0xFFFFFFFF))), opts.group orelse @as(c.gid_t, @bitCast(@as(c_uint, 0xFFFFFFFF))));
    }
    if (opts.verbose) stdout.print("'{s}' -> '{s}'\n", .{ src, dst }) catch {};
    if (opts.strip) stripBinary(d_z.ptr);
    return true;
}

fn copyBytes(s_fd: c_int, d_fd: c_int) bool {
    var buf: [65536]u8 = undefined;
    while (true) {
        const n = c.read(s_fd, &buf, buf.len);
        if (n < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            return false;
        }
        if (n == 0) break;
        var offset: usize = 0;
        while (offset < @as(usize, @intCast(n))) {
            const w = c.write(d_fd, buf[offset..@as(usize, @intCast(n))].ptr, @as(usize, @intCast(n)) - offset);
            if (w <= 0) return false;
            offset += @intCast(w);
        }
    }
    return true;
}

fn stripBinary(d_z: [*:0]const u8) void {
    const pid = c.fork();
    if (pid == 0) {
        const argv = [_:null]?[*:0]const u8{ "strip", d_z, null };
        _ = c.execvp("strip", @ptrCast(&argv));
        c._exit(1);
    } else if (pid > 0) {
        var status: c_int = 0;
        _ = c.waitpid(pid, &status, 0);
    }
}

fn parseFlag(arg: []const u8, opts: *InstallOptions) bool {
    if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--directory")) {
        opts.directory = true;
    } else if (std.mem.eql(u8, arg, "-D")) {
        opts.create_leading = true;
    } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--strip")) {
        opts.strip = true;
    } else if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--preserve-timestamps")) {
        opts.preserve_timestamps = true;
    } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
        opts.verbose = true;
    } else if (std.mem.eql(u8, arg, "-T") or std.mem.eql(u8, arg, "--no-target-directory")) {
        opts.no_target_dir = true;
    } else if (std.mem.eql(u8, arg, "-C") or std.mem.eql(u8, arg, "--compare")) {
        opts.compare = true;
    } else return false;
    return true;
}

fn parseValOpt(arg: []const u8, i: *usize, args: [][]const u8, opts: *InstallOptions) bool {
    if (std.mem.startsWith(u8, arg, "-m") or std.mem.startsWith(u8, arg, "--mode=")) {
        const s = if (std.mem.startsWith(u8, arg, "--mode=")) arg["--mode=".len..] else if (arg.len > 2) arg[2..] else if (i.* + 1 < args.len) blk: {
            i.* += 1;
            break :blk args[i.*];
        } else "755";
        opts.mode = std.fmt.parseInt(u32, s, 8) catch 0o755;
    } else if (std.mem.startsWith(u8, arg, "-o") or std.mem.startsWith(u8, arg, "--owner=")) {
        const s = if (std.mem.startsWith(u8, arg, "--owner=")) arg["--owner=".len..] else if (arg.len > 2) arg[2..] else if (i.* + 1 < args.len) blk: {
            i.* += 1;
            break :blk args[i.*];
        } else "";
        opts.owner = resolveUid(s);
    } else if (std.mem.startsWith(u8, arg, "-g") or std.mem.startsWith(u8, arg, "--group=")) {
        const s = if (std.mem.startsWith(u8, arg, "--group=")) arg["--group=".len..] else if (arg.len > 2) arg[2..] else if (i.* + 1 < args.len) blk: {
            i.* += 1;
            break :blk args[i.*];
        } else "";
        opts.group = resolveGid(s);
    } else if (std.mem.startsWith(u8, arg, "-t") or std.mem.startsWith(u8, arg, "--target-directory=")) {
        opts.target_dir = if (std.mem.startsWith(u8, arg, "--target-directory=")) arg["--target-directory=".len..] else if (arg.len > 2) arg[2..] else if (i.* + 1 < args.len) blk: {
            i.* += 1;
            break :blk args[i.*];
        } else null;
    } else return false;
    return true;
}

fn parseArgs(args: [][]const u8, opts: *InstallOptions, ops: *std.ArrayListUnmanaged([]const u8), alloc: std.mem.Allocator, stdout: anytype, stderr: anytype) !?u8 {
    var i: usize = 1;
    var past = false;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (past or !std.mem.startsWith(u8, arg, "-") or std.mem.eql(u8, arg, "-")) {
            try ops.append(alloc, arg);
        } else if (std.mem.eql(u8, arg, "--")) {
            past = true;
        } else if (std.mem.eql(u8, arg, "--help")) {
            try stdout.print("Usage: install [OPTION]... [-T] SOURCE DEST\n  or:  install [OPTION]... SOURCE... DIRECTORY\n  or:  install [OPTION]... -t DIRECTORY SOURCE...\n  or:  install [OPTION]... -d DIRECTORY...\n", .{});
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try stdout.print("install (coreutilz) {s}\n", .{version});
            return 0;
        } else if (parseFlag(arg, opts) or parseValOpt(arg, &i, args, opts)) {
            continue;
        } else {
            stderr.print("install: unrecognized option '{s}'\nTry 'install --help' for more information.\n", .{arg}) catch {};
            return 1;
        }
    }
    return null;
}

fn executeInstall(opts: *const InstallOptions, ops: [][]const u8, alloc: std.mem.Allocator, stdout: anytype, stderr: anytype) !bool {
    if (opts.directory) {
        var ok = true;
        for (ops) |d| if (!installDir(d, opts, alloc, stdout, stderr)) {
            ok = false;
        };
        return ok;
    }
    if (opts.target_dir) |td| {
        var ok = true;
        for (ops) |s| {
            const b = std.fs.path.basename(s);
            const dst = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ td, b });
            defer alloc.free(dst);
            if (!copyFile(s, dst, opts, alloc, stdout, stderr)) ok = false;
        }
        return ok;
    }
    if (ops.len == 2 and !opts.no_target_dir) {
        const dest = ops[1];
        if (isDirectory(dest)) {
            const b = std.fs.path.basename(ops[0]);
            const full = try std.fmt.allocPrint(alloc, "{s}/{s}", .{ dest, b });
            defer alloc.free(full);
            return copyFile(ops[0], full, opts, alloc, stdout, stderr);
        }
    }
    if (ops.len == 2) {
        return copyFile(ops[0], ops[1], opts, alloc, stdout, stderr);
    }
    return false;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &out_w.interface;
    const stderr = &err_w.interface;

    var opts = InstallOptions{};
    var ops: std.ArrayListUnmanaged([]const u8) = .empty;
    defer ops.deinit(allocator);

    if (try parseArgs(args, &opts, &ops, allocator, stdout, stderr)) |rc| {
        stdout.flush() catch return 1;
        stderr.flush() catch {};
        return rc;
    }
    if (ops.items.len == 0 and opts.target_dir == null) {
        stderr.print("install: missing file operand\nTry 'install --help' for more information.\n", .{}) catch {};
        stderr.flush() catch {};
        return 1;
    }

    const ok = try executeInstall(&opts, ops.items, allocator, stdout, stderr);
    stdout.flush() catch return 1;
    stderr.flush() catch {};
    return if (ok) 0 else 1;
}
