const std = @import("std");
const errors = @import("../utils/errors.zig");

const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "stat";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buf: [16384]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), std.Options.debug_io, &stdout_buf);
    var stderr_writer: std.Io.File.Writer = .init(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var follow_symlinks = false;
    var terse = false;
    var filesystem = false;
    var format_str: ?[]const u8 = null;
    var is_printf = false;
    var files_start: usize = args.len;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            printHelp(stdout) catch return 1;
            stdout.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            printVersion(stdout) catch return 1;
            stdout.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "-L") or (std.mem.startsWith(u8, arg, "--d") and std.mem.startsWith(u8, "--dereference", arg))) {
            follow_symlinks = true;
        } else if (std.mem.eql(u8, arg, "-f") or (std.mem.startsWith(u8, arg, "--fi") and std.mem.startsWith(u8, "--file-system", arg))) {
            filesystem = true;
        } else if (std.mem.eql(u8, arg, "-t") or (std.mem.startsWith(u8, arg, "--t") and std.mem.startsWith(u8, "--terse", arg))) {
            terse = true;
        } else if (std.mem.eql(u8, arg, "-c")) {
            if (i + 1 >= args.len) {
                try errors.printError(stderr, name, "option requires an argument -- 'c'");
                return 1;
            }
            i += 1;
            format_str = args[i];
            is_printf = false;
        } else if (std.mem.startsWith(u8, arg, "--") and std.mem.indexOfScalar(u8, arg, '=') != null) {
            const eq = std.mem.indexOfScalar(u8, arg, '=').?;
            const opt_name = arg[2..eq];
            const opt_val = arg[eq + 1 ..];
            if (std.mem.startsWith(u8, "printf", opt_name)) {
                format_str = opt_val;
                is_printf = true;
            } else if (opt_name.len >= 2 and std.mem.startsWith(u8, "format", opt_name)) {
                format_str = opt_val;
                is_printf = false;
            } else {
                try errors.printUnrecognizedOption(stderr, name, arg);
                return 1;
            }
        } else if (std.mem.startsWith(u8, arg, "--p") and std.mem.startsWith(u8, "--printf", arg)) {
            if (i + 1 >= args.len) {
                try errors.printError(stderr, name, "option '--printf' requires an argument");
                return 1;
            }
            i += 1;
            format_str = args[i];
            is_printf = true;
        } else if (std.mem.startsWith(u8, arg, "--fo") and std.mem.startsWith(u8, "--format", arg)) {
            if (i + 1 >= args.len) {
                try errors.printError(stderr, name, "option '--format' requires an argument");
                return 1;
            }
            i += 1;
            format_str = args[i];
            is_printf = false;
        } else if (std.mem.eql(u8, arg, "--")) {
            files_start = i + 1;
            break;
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1 and arg[1] != '-') {
            var j: usize = 1;
            while (j < arg.len) : (j += 1) {
                switch (arg[j]) {
                    'L' => follow_symlinks = true,
                    'f' => filesystem = true,
                    't' => terse = true,
                    'c' => {
                        if (j + 1 < arg.len) {
                            format_str = arg[j + 1 ..];
                            j = arg.len;
                        } else {
                            if (i + 1 >= args.len) {
                                try errors.printError(stderr, name, "option requires an argument -- 'c'");
                                return 1;
                            }
                            i += 1;
                            format_str = args[i];
                        }
                        is_printf = false;
                        break;
                    },
                    else => {
                        const msg = try std.fmt.allocPrint(allocator, "invalid option -- '{c}'", .{arg[j]});
                        defer allocator.free(msg);
                        try errors.printError(stderr, name, msg);
                        return 1;
                    },
                }
            }
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            const msg = try std.fmt.allocPrint(allocator, "unrecognized option '{s}'", .{arg});
            defer allocator.free(msg);
            try errors.printError(stderr, name, msg);
            return 1;
        } else {
            files_start = i;
            break;
        }
    }

    if (files_start >= args.len) {
        try errors.printError(stderr, name, "missing operand");
        return 1;
    }

    var exit_status: u8 = 0;

    for (args[files_start..]) |file| {
        if (filesystem) {
            if (std.mem.eql(u8, file, "-")) {
                try errors.printError(stderr, name, "using '-' to denote standard input does not work in file system mode");
                exit_status = 1;
                continue;
            }

            const file_z = try allocator.dupeZ(u8, file);
            defer allocator.free(file_z);

            var sv: c.struct_statvfs = undefined;
            if (c.statvfs(file_z.ptr, &sv) != 0) {
                const err_msg = std.mem.span(c.strerror(c.__errno_location().*));
                const msg = try std.fmt.allocPrint(allocator, "cannot read file system information for '{s}': {s}", .{ file, err_msg });
                defer allocator.free(msg);
                try errors.printError(stderr, name, msg);
                exit_status = 1;
                continue;
            }

            if (format_str) |fmt| {
                const ok = try printFormatted(stdout, stderr, fmt, file, null, &sv, null, null, is_printf, allocator);
                if (!ok) exit_status = 1;
            } else if (terse) {
                try stdout.print("{s} {x} {d} {x} {d} {d} {d} {d} {d} {d} {d}\n", .{
                    file,
                    sv.f_fsid,
                    sv.f_namemax,
                    @as(u32, 0),
                    sv.f_bsize,
                    sv.f_frsize,
                    sv.f_blocks,
                    sv.f_bfree,
                    sv.f_bavail,
                    sv.f_files,
                    sv.f_ffree,
                });
            } else {
                try stdout.print("  File: \"{s}\"\n", .{file});
                try stdout.print("    ID: {x:<16} Namelen: {d:<7} Type: {s}\n", .{ sv.f_fsid, sv.f_namemax, "unknown" });
                try stdout.print("Block size: {d:<10} Fundamental block size: {d}\n", .{ sv.f_bsize, sv.f_frsize });
                try stdout.print("Blocks: Total: {d:<10} Free: {d:<10} Available: {d}\n", .{ sv.f_blocks, sv.f_bfree, sv.f_bavail });
                try stdout.print("Inodes: Total: {d:<10} Free: {d}\n", .{ sv.f_files, sv.f_ffree });
            }
        } else {
            var st: c.struct_stat = undefined;
            const is_stdin = std.mem.eql(u8, file, "-");
            var btime: ?c.struct_timespec = null;

            if (is_stdin) {
                if (c.fstat(0, &st) != 0) {
                    const err_msg = std.mem.span(c.strerror(c.__errno_location().*));
                    const msg = try std.fmt.allocPrint(allocator, "cannot stat standard input: {s}", .{err_msg});
                    defer allocator.free(msg);
                    try errors.printError(stderr, name, msg);
                    exit_status = 1;
                    continue;
                }
                var stx: c.struct_statx = undefined;
                const r = c.statx(0, "", c.AT_EMPTY_PATH, c.STATX_BTIME, &stx);
                if (r == 0 and (stx.stx_mask & c.STATX_BTIME) != 0) {
                    btime = .{ .tv_sec = stx.stx_btime.tv_sec, .tv_nsec = @intCast(stx.stx_btime.tv_nsec) };
                }
            } else {
                const file_z = try allocator.dupeZ(u8, file);
                defer allocator.free(file_z);

                const res = if (follow_symlinks) c.stat(file_z.ptr, &st) else c.lstat(file_z.ptr, &st);
                if (res != 0) {
                    const err_msg = std.mem.span(c.strerror(c.__errno_location().*));
                    const msg = try std.fmt.allocPrint(allocator, "cannot statx '{s}': {s}", .{ file, err_msg });
                    defer allocator.free(msg);
                    try errors.printError(stderr, name, msg);
                    exit_status = 1;
                    continue;
                }

                var stx: c.struct_statx = undefined;
                const flags: c_int = if (follow_symlinks) 0 else c.AT_SYMLINK_NOFOLLOW;
                const r = c.statx(c.AT_FDCWD, file_z.ptr, flags, c.STATX_BTIME, &stx);
                if (r == 0 and (stx.stx_mask & c.STATX_BTIME) != 0) {
                    btime = .{ .tv_sec = stx.stx_btime.tv_sec, .tv_nsec = @intCast(stx.stx_btime.tv_nsec) };
                }
            }

            var link_target_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
            var link_target: ?[]const u8 = null;
            if (!is_stdin and (st.st_mode & c.S_IFMT) == c.S_IFLNK) {
                const len = std.Io.Dir.cwd().readLink(std.Options.debug_io, file, &link_target_buf) catch 0;
                if (len > 0) {
                    link_target = link_target_buf[0..len];
                }
            }

            if (format_str) |fmt| {
                const ok = try printFormatted(stdout, stderr, fmt, file, &st, null, link_target, btime, is_printf, allocator);
                if (!ok) exit_status = 1;
            } else if (terse) {
                try stdout.print("{s} {d} {d} {x} {d} {d} {x} {d} {d} {d} {d} {d} {d} {d} 0 {d}\n", .{
                    file,
                    st.st_size,
                    st.st_blocks,
                    st.st_mode,
                    st.st_uid,
                    st.st_gid,
                    st.st_dev,
                    st.st_ino,
                    st.st_nlink,
                    @as(u32, 0),
                    @as(u32, 0),
                    st.st_atim.tv_sec,
                    st.st_mtim.tv_sec,
                    st.st_ctim.tv_sec,
                    st.st_blksize,
                });
            } else {
                const file_type = getFileType(st.st_mode, st.st_size);
                var perm_buf: [11]u8 = undefined;
                getPermString(st.st_mode, &perm_buf);

                if (link_target) |tgt| {
                    try stdout.print("  File: {s} -> {s}\n", .{ file, tgt });
                } else {
                    try stdout.print("  File: {s}\n", .{file});
                }

                const is_special = ((st.st_mode & c.S_IFMT) == c.S_IFCHR) or ((st.st_mode & c.S_IFMT) == c.S_IFBLK);
                try stdout.print("  Size: {d:<10}\tBlocks: {d:<10} IO Block: {d:<6} {s}\n", .{
                    st.st_size,
                    st.st_blocks,
                    st.st_blksize,
                    file_type,
                });

                const dev_major = c.gnu_dev_major(st.st_dev);
                const dev_minor = c.gnu_dev_minor(st.st_dev);
                if (is_special) {
                    const rdev_major = c.gnu_dev_major(st.st_rdev);
                    const rdev_minor = c.gnu_dev_minor(st.st_rdev);
                    try stdout.print("Device: {d},{d}\tInode: {d:<11} Links: {d:<5} Device type: {d},{d}\n", .{
                        dev_major,
                        dev_minor,
                        st.st_ino,
                        st.st_nlink,
                        rdev_major,
                        rdev_minor,
                    });
                } else {
                    try stdout.print("Device: {d},{d}\tInode: {d:<11} Links: {d}\n", .{
                        dev_major,
                        dev_minor,
                        st.st_ino,
                        st.st_nlink,
                    });
                }

                const pw = c.getpwuid(st.st_uid);
                const uname: []const u8 = if (pw != null and pw.*.pw_name != null) std.mem.span(pw.*.pw_name) else "UNKNOWN";
                const gr = c.getgrgid(st.st_gid);
                const gname: []const u8 = if (gr != null and gr.*.gr_name != null) std.mem.span(gr.*.gr_name) else "UNKNOWN";

                try stdout.print("Access: ({o:0>4}/{s})  Uid: ({d:>5}/{s:>8})   Gid: ({d:>5}/{s:>8})\n", .{
                    st.st_mode & 0o7777,
                    perm_buf[0..10],
                    st.st_uid,
                    uname,
                    st.st_gid,
                    gname,
                });

                try printTime(stdout, "Access", st.st_atim.tv_sec, st.st_atim.tv_nsec);
                try printTime(stdout, "Modify", st.st_mtim.tv_sec, st.st_mtim.tv_nsec);
                try printTime(stdout, "Change", st.st_ctim.tv_sec, st.st_ctim.tv_nsec);
                if (btime) |bt| {
                    try printTime(stdout, " Birth", bt.tv_sec, bt.tv_nsec);
                } else {
                    try stdout.writeAll(" Birth: -\n");
                }
            }
        }
    }

    return exit_status;
}

fn getFileType(mode: c.mode_t, size: c.off_t) []const u8 {
    return switch (mode & c.S_IFMT) {
        c.S_IFREG => if (size == 0) "regular empty file" else "regular file",
        c.S_IFDIR => "directory",
        c.S_IFLNK => "symbolic link",
        c.S_IFCHR => "character special file",
        c.S_IFBLK => "block special file",
        c.S_IFIFO => "fifo",
        c.S_IFSOCK => "socket",
        else => "unknown",
    };
}

fn getPermString(mode: c.mode_t, buf: *[11]u8) void {
    buf[0] = switch (mode & c.S_IFMT) {
        c.S_IFDIR => 'd',
        c.S_IFLNK => 'l',
        c.S_IFCHR => 'c',
        c.S_IFBLK => 'b',
        c.S_IFIFO => 'p',
        c.S_IFSOCK => 's',
        else => '-',
    };

    buf[1] = if ((mode & c.S_IRUSR) != 0) 'r' else '-';
    buf[2] = if ((mode & c.S_IWUSR) != 0) 'w' else '-';
    buf[3] = if ((mode & c.S_ISUID) != 0) (if ((mode & c.S_IXUSR) != 0) 's' else 'S') else (if ((mode & c.S_IXUSR) != 0) 'x' else '-');

    buf[4] = if ((mode & c.S_IRGRP) != 0) 'r' else '-';
    buf[5] = if ((mode & c.S_IWGRP) != 0) 'w' else '-';
    buf[6] = if ((mode & c.S_ISGID) != 0) (if ((mode & c.S_IXGRP) != 0) 's' else 'S') else (if ((mode & c.S_IXGRP) != 0) 'x' else '-');

    buf[7] = if ((mode & c.S_IROTH) != 0) 'r' else '-';
    buf[8] = if ((mode & c.S_IWOTH) != 0) 'w' else '-';
    buf[9] = if ((mode & c.S_ISVTX) != 0) (if ((mode & c.S_IXOTH) != 0) 't' else 'T') else (if ((mode & c.S_IXOTH) != 0) 'x' else '-');
    buf[10] = 0;
}

fn printTime(writer: anytype, label: []const u8, sec: isize, nsec: isize) !void {
    var tm_val: c.struct_tm = undefined;
    const time_val: c.time_t = @intCast(sec);
    _ = c.localtime_r(&time_val, &tm_val);

    var time_buf: [64]u8 = undefined;
    const len = c.strftime(&time_buf, time_buf.len, "%Y-%m-%d %H:%M:%S", &tm_val);

    var tz_buf: [16]u8 = undefined;
    const tz_len = c.strftime(&tz_buf, tz_buf.len, "%z", &tm_val);

    if (len > 0 and tz_len > 0) {
        try writer.print("{s}: {s}.{d:0>9} {s}\n", .{ label, time_buf[0..len], nsec, tz_buf[0..tz_len] });
    } else {
        try writer.print("{s}: {d}\n", .{ label, sec });
    }
}

fn findMountPoint(file: []const u8, st: *const c.struct_stat, buf: []u8) ?[]const u8 {
    const orig_fd = c.open(".", c.O_RDONLY | c.O_DIRECTORY | c.O_CLOEXEC);
    if (orig_fd < 0) return null;
    defer {
        _ = c.fchdir(orig_fd);
        _ = c.close(orig_fd);
    }

    var last_stat: c.struct_stat = st.*;

    if ((st.st_mode & c.S_IFMT) == c.S_IFDIR) {
        var file_z_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
        if (file.len + 1 > file_z_buf.len) return null;
        @memcpy(file_z_buf[0..file.len], file);
        file_z_buf[file.len] = 0;
        if (c.chdir(file_z_buf[0..file.len :0].ptr) < 0) return null;
    } else {
        const dir = std.fs.path.dirname(file) orelse ".";
        var dir_z_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
        if (dir.len + 1 > dir_z_buf.len) return null;
        @memcpy(dir_z_buf[0..dir.len], dir);
        dir_z_buf[dir.len] = 0;
        if (c.chdir(dir_z_buf[0..dir.len :0].ptr) < 0) return null;
        if (c.stat(".", &last_stat) < 0) return null;
    }

    while (true) {
        var parent_st: c.struct_stat = undefined;
        if (c.stat("..", &parent_st) < 0) break;
        if (parent_st.st_dev != last_stat.st_dev or parent_st.st_ino == last_stat.st_ino) {
            break;
        }
        if (c.chdir("..") < 0) break;
        last_stat = parent_st;
    }

    const cwd_ptr = c.getcwd(buf.ptr, buf.len);
    if (cwd_ptr != null) {
        return std.mem.span(cwd_ptr);
    }
    return null;
}

fn printQuoted(writer: anytype, name_str: []const u8) !void {
    const q_style = c.getenv("QUOTING_STYLE");
    const is_locale = if (q_style != null) std.mem.eql(u8, std.mem.span(q_style), "locale") else false;
    if (is_locale) {
        try writer.writeByte('\'');
        for (name_str) |ch| {
            if (ch == '\'') {
                try writer.writeAll("\\'");
            } else {
                try writer.writeByte(ch);
            }
        }
        try writer.writeByte('\'');
    } else {
        const has_single_quote = std.mem.indexOfScalar(u8, name_str, '\'') != null;
        const has_double_quote = std.mem.indexOfScalar(u8, name_str, '"') != null;
        const has_special = for (name_str) |ch| {
            if (ch == '$' or ch == '`' or ch == '\\' or ch == '!' or ch == '\n' or ch == '\t') break true;
        } else false;

        if (has_single_quote and !has_double_quote and !has_special) {
            try writer.writeByte('"');
            try writer.writeAll(name_str);
            try writer.writeByte('"');
        } else {
            try writer.writeByte('\'');
            for (name_str) |ch| {
                if (ch == '\'') {
                    try writer.writeAll("'\\''");
                } else {
                    try writer.writeByte(ch);
                }
            }
            try writer.writeByte('\'');
        }
    }
}

fn printPaddedString(writer: anytype, prefix: []const u8, str: []const u8) !void {
    if (prefix.len <= 1) {
        try writer.writeAll(str);
        return;
    }

    var left_align = false;
    var zero_pad = false;
    var idx: usize = 1;
    while (idx < prefix.len) : (idx += 1) {
        if (prefix[idx] == '-') {
            left_align = true;
        } else if (prefix[idx] == '0') {
            zero_pad = true;
        } else if (std.ascii.isDigit(prefix[idx])) {
            break;
        }
    }
    const width_start = idx;
    while (idx < prefix.len and std.ascii.isDigit(prefix[idx])) : (idx += 1) {}
    const width = if (idx > width_start) std.fmt.parseInt(usize, prefix[width_start..idx], 10) catch 0 else 0;

    if (str.len >= width) {
        try writer.writeAll(str);
    } else {
        const pad_len = width - str.len;
        if (left_align) {
            try writer.writeAll(str);
            var k: usize = 0;
            while (k < pad_len) : (k += 1) try writer.writeByte(' ');
        } else if (zero_pad) {
            var k: usize = 0;
            while (k < pad_len) : (k += 1) try writer.writeByte('0');
            try writer.writeAll(str);
        } else {
            var k: usize = 0;
            while (k < pad_len) : (k += 1) try writer.writeByte(' ');
            try writer.writeAll(str);
        }
    }
}

fn formatSecFrac(writer: anytype, prefix: []const u8, sec: isize, nsec: isize, has_precision: bool, precision: usize) !void {
    if (has_precision) {
        var nsec_buf: [16]u8 = undefined;
        _ = c.snprintf(&nsec_buf, nsec_buf.len, "%09ld", nsec);
        const prec = @min(precision, 9);
        var time_buf: [128]u8 = undefined;
        var f_idx: usize = 0;
        const s_str = try std.fmt.bufPrint(time_buf[f_idx..], "{d}.", .{sec});
        f_idx += s_str.len;
        @memcpy(time_buf[f_idx .. f_idx + prec], nsec_buf[0..prec]);
        f_idx += prec;
        while (f_idx - s_str.len < precision and f_idx < time_buf.len) : (f_idx += 1) {
            time_buf[f_idx] = '0';
        }
        const full_time = time_buf[0..f_idx];
        try printPaddedString(writer, prefix, full_time);
    } else {
        var int_buf: [32]u8 = undefined;
        const s_str = try std.fmt.bufPrint(&int_buf, "{d}", .{sec});
        try printPaddedString(writer, prefix, s_str);
    }
}

fn printFormatted(
    stdout: anytype,
    stderr: anytype,
    fmt: []const u8,
    file: []const u8,
    st: ?*const c.struct_stat,
    sv: ?*const c.struct_statvfs,
    link_target: ?[]const u8,
    btime: ?c.struct_timespec,
    is_printf: bool,
    allocator: std.mem.Allocator,
) !bool {
    var success = true;
    var idx: usize = 0;

    while (idx < fmt.len) {
        if (fmt[idx] == '%') {
            const pct_start = idx;
            idx += 1;

            // Flags: '-', '+', ' ', '#', '0', '\'', 'I'
            while (idx < fmt.len and (fmt[idx] == '-' or fmt[idx] == '+' or fmt[idx] == ' ' or fmt[idx] == '#' or fmt[idx] == '0' or fmt[idx] == '\'' or fmt[idx] == 'I')) : (idx += 1) {}

            // Width
            while (idx < fmt.len and std.ascii.isDigit(fmt[idx])) : (idx += 1) {}

            // Precision
            var has_precision = false;
            var precision: usize = 0;
            if (idx < fmt.len and fmt[idx] == '.') {
                has_precision = true;
                idx += 1;
                const prec_start = idx;
                while (idx < fmt.len and std.ascii.isDigit(fmt[idx])) : (idx += 1) {}
                if (idx > prec_start) {
                    precision = std.fmt.parseInt(usize, fmt[prec_start..idx], 10) catch 9;
                } else {
                    precision = 9;
                }
            }

            const prefix_len = idx - pct_start;

            if (idx >= fmt.len) {
                if (prefix_len > 1) {
                    const msg = try std.fmt.allocPrint(allocator, "'{s}': invalid directive", .{fmt[pct_start..]});
                    defer allocator.free(msg);
                    try errors.printError(stderr, name, msg);
                    return false;
                }
                try stdout.writeByte('%');
                break;
            }

            const next_ch = fmt[idx];
            if (next_ch == '%') {
                if (prefix_len > 1) {
                    const msg = try std.fmt.allocPrint(allocator, "'{s}%': invalid directive", .{fmt[pct_start..idx]});
                    defer allocator.free(msg);
                    try errors.printError(stderr, name, msg);
                    return false;
                }
                try stdout.writeByte('%');
                idx += 1;
                continue;
            }

            var mod_char: ?u8 = null;
            var spec = next_ch;
            const prefix = fmt[pct_start..idx];
            idx += 1;

            if ((spec == 'H' or spec == 'L') and st != null and idx < fmt.len and (fmt[idx] == 'd' or fmt[idx] == 'r')) {
                mod_char = spec;
                spec = fmt[idx];
                idx += 1;
            }

            if (st) |stat_ptr| {
                switch (spec) {
                    'a' => {
                        var buf: [32]u8 = undefined;
                        const s = try std.fmt.bufPrint(&buf, "{o}", .{stat_ptr.st_mode & 0o7777});
                        try printPaddedString(stdout, prefix, s);
                    },
                    'A' => {
                        var perm_buf: [11]u8 = undefined;
                        getPermString(stat_ptr.st_mode, &perm_buf);
                        try printPaddedString(stdout, prefix, perm_buf[0..10]);
                    },
                    'b' => {
                        var buf: [32]u8 = undefined;
                        const s = try std.fmt.bufPrint(&buf, "{d}", .{stat_ptr.st_blocks});
                        try printPaddedString(stdout, prefix, s);
                    },
                    'B' => {
                        try printPaddedString(stdout, prefix, "512");
                    },
                    'd' => {
                        var buf: [32]u8 = undefined;
                        const val = if (mod_char == 'H')
                            c.gnu_dev_major(stat_ptr.st_dev)
                        else if (mod_char == 'L')
                            c.gnu_dev_minor(stat_ptr.st_dev)
                        else
                            stat_ptr.st_dev;
                        const s = try std.fmt.bufPrint(&buf, "{d}", .{val});
                        try printPaddedString(stdout, prefix, s);
                    },
                    'D' => {
                        var buf: [32]u8 = undefined;
                        const s = try std.fmt.bufPrint(&buf, "{x}", .{stat_ptr.st_dev});
                        try printPaddedString(stdout, prefix, s);
                    },
                    'f' => {
                        var buf: [32]u8 = undefined;
                        const s = try std.fmt.bufPrint(&buf, "{x}", .{stat_ptr.st_mode});
                        try printPaddedString(stdout, prefix, s);
                    },
                    'F' => {
                        try printPaddedString(stdout, prefix, getFileType(stat_ptr.st_mode, stat_ptr.st_size));
                    },
                    'g' => {
                        var buf: [32]u8 = undefined;
                        const s = try std.fmt.bufPrint(&buf, "{d}", .{stat_ptr.st_gid});
                        try printPaddedString(stdout, prefix, s);
                    },
                    'G' => {
                        const gr = c.getgrgid(stat_ptr.st_gid);
                        const gname = if (gr != null and gr.*.gr_name != null) std.mem.span(gr.*.gr_name) else "UNKNOWN";
                        try printPaddedString(stdout, prefix, gname);
                    },
                    'h' => {
                        var buf: [32]u8 = undefined;
                        const s = try std.fmt.bufPrint(&buf, "{d}", .{stat_ptr.st_nlink});
                        try printPaddedString(stdout, prefix, s);
                    },
                    'i' => {
                        var buf: [32]u8 = undefined;
                        const s = try std.fmt.bufPrint(&buf, "{d}", .{stat_ptr.st_ino});
                        try printPaddedString(stdout, prefix, s);
                    },
                    'm' => {
                        var mp_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
                        const mp = findMountPoint(file, stat_ptr, &mp_buf) orelse blk: {
                            success = false;
                            break :blk "?";
                        };
                        try printPaddedString(stdout, prefix, mp);
                    },
                    'n' => {
                        try printPaddedString(stdout, prefix, file);
                    },
                    'N' => {
                        try printQuoted(stdout, file);
                        if (link_target) |tgt| {
                            try stdout.writeAll(" -> ");
                            try printQuoted(stdout, tgt);
                        }
                    },
                    'o' => {
                        var buf: [32]u8 = undefined;
                        const s = try std.fmt.bufPrint(&buf, "{d}", .{stat_ptr.st_blksize});
                        try printPaddedString(stdout, prefix, s);
                    },
                    'r' => {
                        var buf: [32]u8 = undefined;
                        const val = if (mod_char == 'H')
                            c.gnu_dev_major(stat_ptr.st_rdev)
                        else if (mod_char == 'L')
                            c.gnu_dev_minor(stat_ptr.st_rdev)
                        else
                            stat_ptr.st_rdev;
                        const s = try std.fmt.bufPrint(&buf, "{d}", .{val});
                        try printPaddedString(stdout, prefix, s);
                    },
                    'R' => {
                        var buf: [32]u8 = undefined;
                        const s = try std.fmt.bufPrint(&buf, "{x}", .{stat_ptr.st_rdev});
                        try printPaddedString(stdout, prefix, s);
                    },
                    's' => {
                        var buf: [32]u8 = undefined;
                        const s = try std.fmt.bufPrint(&buf, "{d}", .{stat_ptr.st_size});
                        try printPaddedString(stdout, prefix, s);
                    },
                    't' => {
                        var buf: [32]u8 = undefined;
                        const s = try std.fmt.bufPrint(&buf, "{x}", .{c.gnu_dev_major(stat_ptr.st_rdev)});
                        try printPaddedString(stdout, prefix, s);
                    },
                    'T' => {
                        var buf: [32]u8 = undefined;
                        const s = try std.fmt.bufPrint(&buf, "{x}", .{c.gnu_dev_minor(stat_ptr.st_rdev)});
                        try printPaddedString(stdout, prefix, s);
                    },
                    'u' => {
                        var buf: [32]u8 = undefined;
                        const s = try std.fmt.bufPrint(&buf, "{d}", .{stat_ptr.st_uid});
                        try printPaddedString(stdout, prefix, s);
                    },
                    'U' => {
                        const pw = c.getpwuid(stat_ptr.st_uid);
                        const uname = if (pw != null and pw.*.pw_name != null) std.mem.span(pw.*.pw_name) else "UNKNOWN";
                        try printPaddedString(stdout, prefix, uname);
                    },
                    'w' => {
                        if (btime) |bt| {
                            var tm_val: c.struct_tm = undefined;
                            const time_val: c.time_t = @intCast(bt.tv_sec);
                            _ = c.localtime_r(&time_val, &tm_val);
                            var t_buf: [64]u8 = undefined;
                            const len = c.strftime(&t_buf, t_buf.len, "%Y-%m-%d %H:%M:%S", &tm_val);
                            var tz_buf: [16]u8 = undefined;
                            const tz_len = c.strftime(&tz_buf, tz_buf.len, "%z", &tm_val);
                            var full_buf: [128]u8 = undefined;
                            const str = try std.fmt.bufPrint(&full_buf, "{s}.{d:0>9} {s}", .{ t_buf[0..len], bt.tv_nsec, tz_buf[0..tz_len] });
                            try printPaddedString(stdout, prefix, str);
                        } else {
                            try printPaddedString(stdout, prefix, "-");
                        }
                    },
                    'W' => {
                        if (btime) |bt| {
                            try formatSecFrac(stdout, prefix, bt.tv_sec, bt.tv_nsec, has_precision, precision);
                        } else {
                            try printPaddedString(stdout, prefix, "0");
                        }
                    },
                    'x' => {
                        var tm_val: c.struct_tm = undefined;
                        const time_val: c.time_t = @intCast(stat_ptr.st_atim.tv_sec);
                        _ = c.localtime_r(&time_val, &tm_val);
                        var t_buf: [64]u8 = undefined;
                        const len = c.strftime(&t_buf, t_buf.len, "%Y-%m-%d %H:%M:%S", &tm_val);
                        var tz_buf: [16]u8 = undefined;
                        const tz_len = c.strftime(&tz_buf, tz_buf.len, "%z", &tm_val);
                        var full_buf: [128]u8 = undefined;
                        const str = try std.fmt.bufPrint(&full_buf, "{s}.{d:0>9} {s}", .{ t_buf[0..len], stat_ptr.st_atim.tv_nsec, tz_buf[0..tz_len] });
                        try printPaddedString(stdout, prefix, str);
                    },
                    'X' => {
                        try formatSecFrac(stdout, prefix, stat_ptr.st_atim.tv_sec, stat_ptr.st_atim.tv_nsec, has_precision, precision);
                    },
                    'y' => {
                        var tm_val: c.struct_tm = undefined;
                        const time_val: c.time_t = @intCast(stat_ptr.st_mtim.tv_sec);
                        _ = c.localtime_r(&time_val, &tm_val);
                        var t_buf: [64]u8 = undefined;
                        const len = c.strftime(&t_buf, t_buf.len, "%Y-%m-%d %H:%M:%S", &tm_val);
                        var tz_buf: [16]u8 = undefined;
                        const tz_len = c.strftime(&tz_buf, tz_buf.len, "%z", &tm_val);
                        var full_buf: [128]u8 = undefined;
                        const str = try std.fmt.bufPrint(&full_buf, "{s}.{d:0>9} {s}", .{ t_buf[0..len], stat_ptr.st_mtim.tv_nsec, tz_buf[0..tz_len] });
                        try printPaddedString(stdout, prefix, str);
                    },
                    'Y' => {
                        try formatSecFrac(stdout, prefix, stat_ptr.st_mtim.tv_sec, stat_ptr.st_mtim.tv_nsec, has_precision, precision);
                    },
                    'z' => {
                        var tm_val: c.struct_tm = undefined;
                        const time_val: c.time_t = @intCast(stat_ptr.st_ctim.tv_sec);
                        _ = c.localtime_r(&time_val, &tm_val);
                        var t_buf: [64]u8 = undefined;
                        const len = c.strftime(&t_buf, t_buf.len, "%Y-%m-%d %H:%M:%S", &tm_val);
                        var tz_buf: [16]u8 = undefined;
                        const tz_len = c.strftime(&tz_buf, tz_buf.len, "%z", &tm_val);
                        var full_buf: [128]u8 = undefined;
                        const str = try std.fmt.bufPrint(&full_buf, "{s}.{d:0>9} {s}", .{ t_buf[0..len], stat_ptr.st_ctim.tv_nsec, tz_buf[0..tz_len] });
                        try printPaddedString(stdout, prefix, str);
                    },
                    'Z' => {
                        try formatSecFrac(stdout, prefix, stat_ptr.st_ctim.tv_sec, stat_ptr.st_ctim.tv_nsec, has_precision, precision);
                    },
                    else => {
                        try stdout.writeByte('?');
                    },
                }
            } else if (sv) |sv_ptr| {
                switch (spec) {
                    'a' => {
                        var buf: [32]u8 = undefined;
                        const s = try std.fmt.bufPrint(&buf, "{d}", .{sv_ptr.f_bavail});
                        try printPaddedString(stdout, prefix, s);
                    },
                    'b' => {
                        var buf: [32]u8 = undefined;
                        const s = try std.fmt.bufPrint(&buf, "{d}", .{sv_ptr.f_blocks});
                        try printPaddedString(stdout, prefix, s);
                    },
                    'c' => {
                        var buf: [32]u8 = undefined;
                        const s = try std.fmt.bufPrint(&buf, "{d}", .{sv_ptr.f_files});
                        try printPaddedString(stdout, prefix, s);
                    },
                    'd' => {
                        var buf: [32]u8 = undefined;
                        const s = try std.fmt.bufPrint(&buf, "{d}", .{sv_ptr.f_ffree});
                        try printPaddedString(stdout, prefix, s);
                    },
                    'f' => {
                        var buf: [32]u8 = undefined;
                        const s = try std.fmt.bufPrint(&buf, "{d}", .{sv_ptr.f_bfree});
                        try printPaddedString(stdout, prefix, s);
                    },
                    'i' => {
                        var buf: [32]u8 = undefined;
                        const s = try std.fmt.bufPrint(&buf, "{x}", .{sv_ptr.f_fsid});
                        try printPaddedString(stdout, prefix, s);
                    },
                    'l' => {
                        var buf: [32]u8 = undefined;
                        const s = try std.fmt.bufPrint(&buf, "{d}", .{sv_ptr.f_namemax});
                        try printPaddedString(stdout, prefix, s);
                    },
                    'n' => {
                        try printPaddedString(stdout, prefix, file);
                    },
                    's' => {
                        var buf: [32]u8 = undefined;
                        const s = try std.fmt.bufPrint(&buf, "{d}", .{sv_ptr.f_bsize});
                        try printPaddedString(stdout, prefix, s);
                    },
                    'S' => {
                        var buf: [32]u8 = undefined;
                        const s = try std.fmt.bufPrint(&buf, "{d}", .{sv_ptr.f_frsize});
                        try printPaddedString(stdout, prefix, s);
                    },
                    else => {
                        try stdout.writeByte('?');
                    },
                }
            }
            continue;
        } else if (is_printf and fmt[idx] == '\\') {
            idx += 1;
            if (idx >= fmt.len) {
                try errors.printError(stderr, name, "warning: backslash at end of format");
                try stdout.writeByte('\\');
                break;
            }
            const esc = fmt[idx];
            if (esc >= '0' and esc <= '7') {
                var val: u8 = esc - '0';
                var count: usize = 1;
                idx += 1;
                while (count < 3 and idx < fmt.len and fmt[idx] >= '0' and fmt[idx] <= '7') : (count += 1) {
                    val = val * 8 + (fmt[idx] - '0');
                    idx += 1;
                }
                try stdout.writeByte(val);
            } else if (esc == 'x') {
                if (idx + 1 < fmt.len and std.ascii.isHex(fmt[idx + 1])) {
                    idx += 1;
                    var val: u8 = std.fmt.charToDigit(fmt[idx], 16) catch 0;
                    idx += 1;
                    if (idx < fmt.len and std.ascii.isHex(fmt[idx])) {
                        val = val * 16 + (std.fmt.charToDigit(fmt[idx], 16) catch 0);
                        idx += 1;
                    }
                    try stdout.writeByte(val);
                } else {
                    try errors.printError(stderr, name, "warning: unrecognized escape '\\x'");
                    try stdout.writeByte('x');
                    idx += 1;
                }
            } else {
                idx += 1;
                switch (esc) {
                    'a' => try stdout.writeByte(0x07),
                    'b' => try stdout.writeByte(0x08),
                    'e' => try stdout.writeByte(0x1B),
                    'f' => try stdout.writeByte(0x0C),
                    'n' => try stdout.writeByte('\n'),
                    'r' => try stdout.writeByte('\r'),
                    't' => try stdout.writeByte('\t'),
                    'v' => try stdout.writeByte(0x0B),
                    '\\', '"' => try stdout.writeByte(esc),
                    else => {
                        const warn = try std.fmt.allocPrint(allocator, "warning: unrecognized escape '\\{c}'", .{esc});
                        defer allocator.free(warn);
                        try errors.printError(stderr, name, warn);
                        try stdout.writeByte(esc);
                    },
                }
            }
            continue;
        } else {
            try stdout.writeByte(fmt[idx]);
            idx += 1;
        }
    }

    if (!is_printf) {
        try stdout.writeByte('\n');
    }
    return success;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: stat [OPTION]... FILE...
        \\Display file or file system status.
        \\
        \\  -L, --dereference     follow links
        \\  -f, --file-system     display file system status instead of file status
        \\  -c, --format=FORMAT   use the specified FORMAT instead of the default;
        \\                        output a newline after each use of FORMAT
        \\      --printf=FORMAT   like --format, but interpret backslash escapes,
        \\                        and do not output a mandatory trailing newline;
        \\                        if you want a newline, include \n in FORMAT
        \\  -t, --terse           print the information in terse form
        \\      --help     display this help and exit
        \\      --version  output version information and exit
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
