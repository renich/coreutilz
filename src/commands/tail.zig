const std = @import("std");
const errors = @import("../utils/errors.zig");
const args_mod = @import("tail/args.zig");
const ring_buffer = @import("tail/ring_buffer.zig");
const seek_reader = @import("tail/seek_reader.zig");
const follow = @import("tail/follow.zig");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "tail";
pub const version: []const u8 = "0.1.0";

fn printHelp(writer: anytype) !void {
    try writer.print(
        \\Usage: {s} [OPTION]... [FILE]...
        \\Print the last 10 lines of each FILE to standard output.
        \\With more than one FILE, precede each with a header giving the file name.
        \\
        \\With no FILE, or when FILE is -, read standard input.
        \\
        \\Mandatory arguments to long options are mandatory for short options too.
        \\  -c, --bytes=[+]NUM       output the last NUM bytes; or use -c +NUM to
        \\                             output starting with byte NUM of each file
        \\  -f, --follow[={{fname|descriptor}}]
        \\                           output appended data as the file grows;
        \\                             an absent option argument means 'descriptor'
        \\  -F                       same as --follow=name --retry
        \\  -n, --lines=[+]NUM       output the last NUM lines, instead of the last 10;
        \\                             or use -n +NUM to output starting with line NUM
        \\      --pid=PID            with -f, terminate after process ID, PID dies
        \\  -q, --quiet, --silent    never output headers giving file names
        \\      --retry              keep trying to open a file if it is inaccessible
        \\  -s, --sleep-interval=N   with -f, sleep for approximately N seconds
        \\                             (default 1.0) between iterations
        \\  -v, --verbose            always output headers giving file names
        \\  -z, --zero-terminated    line delimiter is NUL, not newline
        \\      --help               display this help and exit
        \\      --version            output version information and exit
        \\
        \\GNU coreutils online help: <https://www.gnu.org/software/coreutils/>
        \\Full documentation <https://www.gnu.org/software/coreutils/tail>
        \\or available locally via: info '(coreutils) tail invocation'
        \\
    , .{name});
}

fn tailInitialContent(
    w: *follow.WatchedFile,
    opts: *const args_mod.Options,
    allocator: std.mem.Allocator,
    stdout: anytype,
) !void {
    const file = std.Io.File{ .handle = w.fd, .flags = .{ .nonblocking = false } };
    const delim: u8 = if (opts.zero_terminated) 0 else '\n';
    if (seek_reader.isSeekable(file)) {
        if (opts.bytes) |b| {
            try seek_reader.tailSeekBytes(file, b, opts.from_start, allocator, stdout);
        } else {
            try seek_reader.tailSeekLines(file, opts.lines orelse 10, delim, opts.from_start, allocator, stdout);
        }
        const cur = c.lseek(w.fd, 0, c.SEEK_CUR);
        if (cur >= 0) w.read_pos = @intCast(cur);
    } else {
        if (opts.bytes) |b| {
            if (opts.from_start) try ring_buffer.streamBytesForward(file, b, stdout) else try ring_buffer.bufferLastBytes(file, b, allocator, stdout);
        } else {
            const count = opts.lines orelse 10;
            if (opts.from_start) try ring_buffer.streamLinesForward(file, count, delim, stdout) else try ring_buffer.bufferLastLines(file, count, delim, allocator, stdout);
        }
    }
    try stdout.flush();
}

fn openInitialFile(
    w: *follow.WatchedFile,
    opts: *const args_mod.Options,
    num_files: usize,
    stderr: anytype,
) bool {
    if (w.is_stdin) {
        w.fd = c.STDIN_FILENO;
        var st: c.struct_stat = undefined;
        if (c.fstat(c.STDIN_FILENO, &st) != 0) {
            const errno_val = c.__errno_location().*;
            const err_str = std.mem.span(c.strerror(errno_val));
            stderr.print("tail: cannot fstat 'standard input': {s}\n", .{err_str}) catch {};
            stderr.flush() catch {};
            w.fd = -1;
            w.ignore = true;
            return false;
        }
        w.mode = st.st_mode;
        w.st_dev = st.st_dev;
        w.st_ino = st.st_ino;
        w.mtime = st.st_mtim;
        if (opts.follow != null and (num_files > 1 or opts.pid != null)) {
            follow.setNonblocking(c.STDIN_FILENO);
            if (c.isatty(c.STDIN_FILENO) != 0) {
                stderr.print("tail: warning: following standard input indefinitely is ineffective\n", .{}) catch {};
                stderr.flush() catch {};
            }
        }
        return true;
    }

    var path_z: [4096]u8 = undefined;
    if (w.name.len >= path_z.len) return false;
    @memcpy(path_z[0..w.name.len], w.name);
    path_z[w.name.len] = 0;

    const nonblocking = opts.follow != null and (opts.pid != null or num_files > 1);
    const flags: c_int = c.O_RDONLY | (if (nonblocking) c.O_NONBLOCK else 0);
    const fd = follow.fdSafer(c.open(&path_z, flags));
    if (fd < 0) {
        const errno_val = c.__errno_location().*;
        const err_str = std.mem.span(c.strerror(errno_val));
        stderr.print("tail: cannot open '{s}' for reading: {s}\n", .{ w.name, err_str }) catch {};
        stderr.flush() catch {};
        w.fd = -1;
        if (!opts.retry) w.ignore = true;
        return false;
    }

    w.fd = fd;
    var st: c.struct_stat = undefined;
    if (c.fstat(fd, &st) == 0) {
        w.mode = st.st_mode;
        w.st_dev = st.st_dev;
        w.st_ino = st.st_ino;
        w.mtime = st.st_mtim;
        if (opts.follow != null and !follow.isTailable(st.st_mode)) {
            _ = c.close(fd);
            w.fd = -1;
            if (!opts.retry) w.ignore = true;
            stderr.print("tail: '{s}': cannot follow end of this type of file{s}\n", .{
                w.name,
                if (!opts.retry) "; giving up on this name" else "",
            }) catch {};
            stderr.flush() catch {};
            return false;
        }
    }
    return true;
}

fn processInitialFiles(
    files: []follow.WatchedFile,
    opts: *const args_mod.Options,
    print_header: bool,
    last_header_idx: *?usize,
    allocator: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) bool {
    var has_error = false;
    for (files, 0..) |*w, idx| {
        if (!openInitialFile(w, opts, files.len, stderr)) {
            has_error = true;
            continue;
        }
        if (print_header) {
            if (last_header_idx.* != null) stdout.writeAll("\n") catch {};
            const display_name = if (w.is_stdin) "standard input" else w.name;
            stdout.print("==> {s} <==\n", .{display_name}) catch {};
            last_header_idx.* = idx;
        }
        tailInitialContent(w, opts, allocator, stdout) catch {
            has_error = true;
        };
    }
    stdout.flush() catch {};
    stderr.flush() catch {};
    return has_error;
}

fn ignoreFifoAndPipe(files: []follow.WatchedFile) bool {
    var some_viable = false;
    for (files) |*w| {
        if (std.mem.eql(u8, w.name, "-") and !w.ignore and w.fd >= 0 and (w.mode & c.S_IFMT) == c.S_IFIFO) {
            w.fd = -1;
            w.ignore = true;
        } else some_viable = true;
    }
    return some_viable;
}

fn anyLiveFiles(files: []const follow.WatchedFile, opts: *const args_mod.Options) bool {
    if (opts.retry and opts.follow == .name) return true;
    for (files) |w| {
        if (w.fd >= 0) return true;
        if (!w.ignore and opts.retry) return true;
    }
    return false;
}

fn setupWatchedFiles(
    files_list: []const []const u8,
    allocator: std.mem.Allocator,
) ![]follow.WatchedFile {
    const num_files = if (files_list.len == 0) 1 else files_list.len;
    const watched_files = try allocator.alloc(follow.WatchedFile, num_files);
    if (files_list.len == 0) {
        watched_files[0] = .{ .name = "-", .is_stdin = true };
    } else {
        for (files_list, 0..) |p, i| {
            watched_files[i] = .{ .name = p, .is_stdin = std.mem.eql(u8, p, "-") };
        }
    }
    return watched_files;
}

fn checkStdoutOpen(stderr: anytype) bool {
    var out_stat: c.struct_stat = undefined;
    if (c.fstat(c.STDOUT_FILENO, &out_stat) < 0) {
        const errno_val = c.__errno_location().*;
        const err_str = std.mem.span(c.strerror(errno_val));
        stderr.print("tail: standard output: {s}\n", .{err_str}) catch {};
        stderr.flush() catch {};
        return false;
    }
    return true;
}

fn dispatchFollow(
    watched_files: []follow.WatchedFile,
    opts: *const args_mod.Options,
    print_header: bool,
    last_header_idx: *?usize,
    has_error: bool,
    stdout: anytype,
    stderr: anytype,
) !u8 {
    if (!ignoreFifoAndPipe(watched_files)) {
        return if (has_error) 1 else 0;
    }
    if (!checkStdoutOpen(stderr)) return 1;
    if (!anyLiveFiles(watched_files, opts)) {
        stderr.print("tail: no files remaining\n", .{}) catch {};
        stderr.flush() catch {};
        return 1;
    }
    if (follow.shouldWarnInotify(watched_files, opts)) {
        stderr.print("tail: inotify cannot be used, reverting to polling\n", .{}) catch {};
        stderr.flush() catch {};
    }
    if (opts.debug) {
        const mode_str = if (opts.follow == .name) "polling mode" else "blocking mode";
        stderr.print("tail: using {s}\n", .{mode_str}) catch {};
        stderr.flush() catch {};
    }
    return try follow.followFiles(watched_files, opts, print_header, last_header_idx, has_error, stdout, stderr);
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    _ = c.signal(c.SIGPIPE, c.SIG_DFL);

    var stdout_buf: [65536]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_w: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var stderr_w: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &stdout_w.interface;
    const stderr = &stderr_w.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    const res = args_mod.parseArgs(args, allocator, stderr);
    var opts = switch (res) {
        .ok => |o| o,
        .help => {
            try printHelp(stdout);
            return 0;
        },
        .version => {
            try errors.printVersion(stdout, name, version);
            return 0;
        },
        .err => |code| return code,
    };
    defer opts.deinit(allocator);

    if (opts.follow == null) {
        const count = if (opts.bytes) |b| b else (opts.lines orelse 10);
        if (!opts.from_start and count == 0) return 0;
    }

    const watched_files = try setupWatchedFiles(opts.files.items, allocator);
    defer {
        for (watched_files) |w| {
            if (w.fd >= 0 and !w.is_stdin) _ = c.close(w.fd);
        }
        allocator.free(watched_files);
    }

    const print_header = (opts.verbose or (watched_files.len > 1 and !opts.quiet));
    var last_header_idx: ?usize = null;
    const has_error = processInitialFiles(watched_files, &opts, print_header, &last_header_idx, allocator, stdout, stderr);

    if (opts.follow == null) return if (has_error) 1 else 0;
    return dispatchFollow(watched_files, &opts, print_header, &last_header_idx, has_error, stdout, stderr);
}
