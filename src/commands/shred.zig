const std = @import("std");
const c = @import("../compat/c.zig").c;
const opts_mod = @import("shred/options.zig");
const wipe = @import("shred/wipe.zig");
const patterns = @import("shred/patterns.zig");

pub const name: []const u8 = "shred";
pub const version: []const u8 = "0.1.0";

pub const ShredOptions = opts_mod.ShredOptions;
const RandSource = patterns.RandSource;

fn openForShred(path: []const u8, force: bool) ?c_int {
    var p_z: [std.fs.max_path_bytes]u8 = undefined;
    const pz = std.fmt.bufPrintZ(&p_z, "{s}", .{path}) catch return null;
    var fd = c.open(pz.ptr, c.O_RDWR);
    if (fd < 0 and force) {
        _ = c.chmod(pz.ptr, 0o600);
        fd = c.open(pz.ptr, c.O_RDWR);
    }
    return if (fd >= 0) fd else null;
}

fn dopass(
    fd: c_int,
    path: []const u8,
    size: usize,
    k: usize,
    total: usize,
    ptype: i32,
    rand: *RandSource,
    verbose: bool,
    stderr: anytype,
) !void {
    if (verbose and total > 0) {
        var pbuf: [7]u8 = undefined;
        const pname = patterns.passname(ptype, &pbuf);
        stderr.print("shred: {s}: pass {d}/{d} ({s})...\n", .{ path, k, total, pname }) catch {};
    }
    _ = c.lseek(fd, 0, c.SEEK_SET);
    var buf: [65536]u8 = undefined;
    if (ptype >= 0) patterns.fillpattern(ptype, &buf);

    var written: usize = 0;
    while (written < size) {
        const chunk = @min(buf.len, size - written);
        if (ptype < 0) rand.readBytes(buf[0..chunk]);
        var offset: usize = 0;
        while (offset < chunk) {
            const n = c.write(fd, buf[offset..chunk].ptr, chunk - offset);
            if (n <= 0) return error.WriteError;
            offset += @intCast(n);
        }
        written += chunk;
    }
    _ = c.fdatasync(fd);
}

fn calcTargetSize(st: c.struct_stat, opts: *const ShredOptions) usize {
    if (opts.custom_size) |sz| return sz;
    var size: usize = @intCast(@max(0, st.st_size));
    if (!opts.exact) {
        const blk: usize = if (st.st_blksize > 0) @intCast(st.st_blksize) else 4096;
        const rem = size % blk;
        if (rem != 0) size += (blk - rem);
    }
    return size;
}

fn shredFile(path: []const u8, opts: *const ShredOptions, rand: *RandSource, stderr: anytype, alloc: std.mem.Allocator) bool {
    const fd = openForShred(path, opts.force) orelse {
        stderr.print("shred: '{s}': failed to open for writing\n", .{path}) catch {};
        return false;
    };
    var should_close = true;
    defer if (should_close) {
        _ = c.close(fd);
    };

    var st: c.struct_stat = undefined;
    if (c.fstat(fd, &st) != 0) return false;
    const target_size = calcTargetSize(st, opts);

    const zero_extra: usize = if (opts.zero) 1 else 0;
    const total_passes = if (target_size > 0) opts.iterations + zero_extra else 0;
    if (total_passes > 0) {
        const passarray = alloc.alloc(i32, opts.iterations) catch return false;
        defer alloc.free(passarray);
        patterns.genpattern(passarray, rand);

        for (passarray, 0..) |ptype, i| {
            dopass(fd, path, target_size, i + 1, total_passes, ptype, rand, opts.verbose, stderr) catch return false;
        }
        if (opts.zero) {
            dopass(fd, path, target_size, total_passes, total_passes, 0, rand, opts.verbose, stderr) catch return false;
        }
    }

    if (opts.remove) {
        _ = c.ftruncate(fd, 0);
        _ = c.close(fd);
        should_close = false;
        return wipe.wipeFileName(path, opts.verbose, stderr, alloc);
    }
    return true;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &out_w.interface;
    const stderr = &err_w.interface;

    var opts = ShredOptions{};
    var files: std.ArrayListUnmanaged([]const u8) = .empty;
    defer files.deinit(allocator);

    if (try opts_mod.parseArgs(args, &opts, &files, allocator, stdout, stderr)) |rc| {
        stdout.flush() catch return 1;
        stderr.flush() catch {};
        return rc;
    }
    if (files.items.len == 0) {
        stderr.print("shred: missing file operand\nTry 'shred --help' for more information.\n", .{}) catch {};
        stderr.flush() catch {};
        return 1;
    }

    var rand = try RandSource.init(opts.random_source, allocator);
    defer rand.deinit();

    var ok = true;
    for (files.items) |f| {
        if (!shredFile(f, &opts, &rand, stderr, allocator)) ok = false;
    }
    stdout.flush() catch return 1;
    stderr.flush() catch {};
    return if (ok) 0 else 1;
}
