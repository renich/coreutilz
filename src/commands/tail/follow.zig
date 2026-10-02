const std = @import("std");
const c = @import("../../compat/c.zig").c;
const errors = @import("../../utils/errors.zig");
const args_mod = @import("args.zig");

pub const WatchedFile = struct {
    name: []const u8,
    is_stdin: bool,
    fd: c_int = -1,
    read_pos: u64 = 0,
    mtime: c.struct_timespec = undefined,
    mode: c.mode_t = 0,
    st_dev: c.dev_t = 0,
    st_ino: c.ino_t = 0,
    ignore: bool = false,
};

pub fn isPidDead(pid: c_int) bool {
    const rc = c.kill(pid, 0);
    if (rc == 0) return false;
    const err = c.__errno_location().*;
    if (err == c.EPERM) return false;
    return true;
}

pub fn isTailable(mode: c.mode_t) bool {
    const fmt = mode & c.S_IFMT;
    return fmt == c.S_IFREG or fmt == c.S_IFIFO or fmt == c.S_IFSOCK or fmt == c.S_IFCHR;
}

pub fn fdSafer(fd: c_int) c_int {
    if (fd >= 0 and fd <= 2) {
        const new_fd = c.fcntl(fd, c.F_DUPFD_CLOEXEC, @as(c_int, 3));
        if (new_fd >= 0) {
            _ = c.close(fd);
            return new_fd;
        }
    }
    return fd;
}

pub fn shouldWarnInotify(files: []const WatchedFile, opts: *const args_mod.Options) bool {
    if (opts.disable_inotify) return false;
    for (files) |w| {
        if (w.is_stdin) return false;
        if (w.fd >= 0 and (w.mode & c.S_IFMT) != c.S_IFREG) return false;
    }
    return true;
}

pub fn setNonblocking(fd: c_int) void {
    const flags = c.fcntl(fd, c.F_GETFL, @as(c_int, 0));
    if (flags >= 0) {
        _ = c.fcntl(fd, c.F_SETFL, flags | c.O_NONBLOCK);
    }
}

fn checkOutputAlive() bool {
    var pfd = [1]c.struct_pollfd{.{
        .fd = c.STDOUT_FILENO,
        .events = 0,
        .revents = 0,
    }};
    const rc = c.poll(&pfd, 1, 0);
    if (rc > 0 and (pfd[0].revents & (c.POLLERR | c.POLLHUP)) != 0) {
        _ = c.raise(c.SIGPIPE);
        return false;
    }
    return true;
}

fn readAndOutput(
    w: *WatchedFile,
    idx: usize,
    print_header: bool,
    last_header_idx: *?usize,
    stdout: anytype,
) !void {
    var buf: [65536]u8 = undefined;
    var printed_banner = false;
    while (true) {
        const n = c.read(w.fd, &buf, buf.len);
        if (n <= 0) break;

        if (print_header and (last_header_idx.* == null or last_header_idx.*.? != idx) and !printed_banner) {
            if (last_header_idx.* != null) {
                try stdout.writeAll("\n");
            }
            try stdout.print("==> {s} <==\n", .{w.name});
            last_header_idx.* = idx;
            printed_banner = true;
        }
        try stdout.writeAll(buf[0..@intCast(n)]);
        try stdout.flush();
        w.read_pos += @intCast(n);
        if (n < buf.len) break;
    }
}

fn tryReopen(
    w: *WatchedFile,
    opts: *const args_mod.Options,
    nonblocking: bool,
    idx: usize,
    print_header: bool,
    last_header_idx: *?usize,
    stdout: anytype,
    stderr: anytype,
) void {
    var path_z: [4096]u8 = undefined;
    if (w.name.len >= path_z.len) return;
    @memcpy(path_z[0..w.name.len], w.name);
    path_z[w.name.len] = 0;

    const flags: c_int = c.O_RDONLY | (if (nonblocking) c.O_NONBLOCK else 0);
    const fd = fdSafer(c.open(&path_z, flags));
    if (fd >= 0) {
        var st: c.struct_stat = undefined;
        if (c.fstat(fd, &st) == 0) {
            if (!isTailable(st.st_mode)) {
                _ = c.close(fd);
                w.fd = -1;
                const give_up = (opts.follow == .descriptor or !opts.retry);
                if (give_up) w.ignore = true;
                stderr.print("tail: '{s}' has been replaced with an untailable file{s}\n", .{
                    w.name,
                    if (give_up) "; giving up on this name" else "",
                }) catch {};
                stderr.flush() catch {};
                return;
            }
            w.fd = fd;
            w.st_dev = st.st_dev;
            w.st_ino = st.st_ino;
            w.mode = st.st_mode;
            w.mtime = st.st_mtim;
            w.read_pos = 0;
            stderr.print("tail: '{s}' has appeared;  following new file\n", .{w.name}) catch {};
            stderr.flush() catch {};
            readAndOutput(w, idx, print_header, last_header_idx, stdout) catch {};
        } else {
            _ = c.close(fd);
        }
    }
}

fn checkNameReplaced(
    w: *WatchedFile,
    nonblocking: bool,
    idx: usize,
    print_header: bool,
    last_header_idx: *?usize,
    stdout: anytype,
    stderr: anytype,
) void {
    var path_z: [4096]u8 = undefined;
    if (w.name.len >= path_z.len) return;
    @memcpy(path_z[0..w.name.len], w.name);
    path_z[w.name.len] = 0;

    var new_st: c.struct_stat = undefined;
    if (c.stat(&path_z, &new_st) != 0) {
        const errno_val = c.__errno_location().*;
        const err_str = std.mem.span(c.strerror(errno_val));
        stderr.print("tail: '{s}' has become inaccessible: {s}\n", .{ w.name, err_str }) catch {};
        stderr.flush() catch {};
        _ = c.close(w.fd);
        w.fd = -1;
        return;
    }

    if (new_st.st_ino != w.st_ino or new_st.st_dev != w.st_dev) {
        stderr.print("tail: '{s}' has been replaced;  following new file\n", .{w.name}) catch {};
        stderr.flush() catch {};
        _ = c.close(w.fd);
        const flags: c_int = c.O_RDONLY | (if (nonblocking) c.O_NONBLOCK else 0);
        const new_fd = fdSafer(c.open(&path_z, flags));
        if (new_fd >= 0) {
            w.fd = new_fd;
            w.st_dev = new_st.st_dev;
            w.st_ino = new_st.st_ino;
            w.mode = new_st.st_mode;
            w.mtime = new_st.st_mtim;
            w.read_pos = 0;
            readAndOutput(w, idx, print_header, last_header_idx, stdout) catch {};
        } else {
            w.fd = -1;
        }
    }
}

fn checkTruncationAndRead(
    w: *WatchedFile,
    idx: usize,
    print_header: bool,
    last_header_idx: *?usize,
    stdout: anytype,
    stderr: anytype,
) void {
    var st: c.struct_stat = undefined;
    if (c.fstat(w.fd, &st) == 0) {
        if ((st.st_mode & c.S_IFMT) == c.S_IFREG) {
            if (@as(u64, @intCast(st.st_size)) < w.read_pos) {
                stderr.print("tail: '{s}': file truncated\n", .{w.name}) catch {};
                stderr.flush() catch {};
                _ = c.lseek(w.fd, 0, c.SEEK_SET);
                w.read_pos = 0;
            }
        }
        w.mtime = st.st_mtim;
    }
    readAndOutput(w, idx, print_header, last_header_idx, stdout) catch {};
}

pub fn followFiles(
    files: []WatchedFile,
    opts: *const args_mod.Options,
    print_header: bool,
    last_header_idx: *?usize,
    has_error: bool,
    stdout: anytype,
    stderr: anytype,
) !u8 {
    const nonblocking = (opts.pid != null or files.len > 1);
    if (nonblocking) {
        for (files) |*w| {
            if (w.fd >= 0) setNonblocking(w.fd);
        }
    }

    while (true) {
        if (!checkOutputAlive()) return 0;

        if (opts.pid) |p| {
            if (isPidDead(p)) {
                try stdout.flush();
                return if (has_error) 1 else 0;
            }
        }

        var any_live = false;
        if (opts.retry and opts.follow == .name) {
            any_live = true;
        } else {
            for (files) |*w| {
                if (w.ignore) continue;
                if (w.fd >= 0 or opts.retry) {
                    any_live = true;
                    break;
                }
            }
        }
        if (!any_live) {
            stderr.print("tail: no files remaining\n", .{}) catch {};
            stderr.flush() catch {};
            try stdout.flush();
            return 1;
        }

        for (files, 0..) |*w, idx| {
            if (w.ignore) continue;

            if (w.fd < 0) {
                if (opts.retry or opts.follow == .name) {
                    tryReopen(w, opts, nonblocking, idx, print_header, last_header_idx, stdout, stderr);
                }
                continue;
            }

            if (opts.follow == .name and !w.is_stdin) {
                checkNameReplaced(w, nonblocking, idx, print_header, last_header_idx, stdout, stderr);
                if (w.fd < 0) continue;
            }

            checkTruncationAndRead(w, idx, print_header, last_header_idx, stdout, stderr);
        }

        if (!checkOutputAlive()) return 0;

        if (opts.pid) |p| {
            if (isPidDead(p)) {
                try stdout.flush();
                return if (has_error) 1 else 0;
            }
        }

        const s = if (opts.sleep_interval > 0.001) opts.sleep_interval else 0.01;
        const usec: c_uint = @intFromFloat(s * 1_000_000.0);
        _ = c.usleep(usec);
    }
}
