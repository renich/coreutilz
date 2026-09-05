const std = @import("std");
const errors = @import("../utils/errors.zig");

const c = @cImport({
    @cInclude("sys/stat.h");
    @cInclude("sys/statvfs.h");
    @cInclude("pwd.h");
    @cInclude("grp.h");
    @cInclude("unistd.h");
    @cInclude("time.h");
    @cInclude("string.h");
    @cInclude("errno.h");
});

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
            try printHelp(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try printVersion(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "-L") or std.mem.eql(u8, arg, "--dereference")) {
            follow_symlinks = true;
        } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--file-system")) {
            filesystem = true;
        } else if (std.mem.eql(u8, arg, "-t") or std.mem.eql(u8, arg, "--terse")) {
            terse = true;
        } else if (std.mem.startsWith(u8, arg, "--format=")) {
            format_str = arg["--format=".len..];
            is_printf = false;
        } else if (std.mem.eql(u8, arg, "-c")) {
            if (i + 1 >= args.len) {
                try errors.printError(stderr, name, "option requires an argument -- 'c'");
                return 1;
            }
            i += 1;
            format_str = args[i];
            is_printf = false;
        } else if (std.mem.startsWith(u8, arg, "--printf=")) {
            format_str = arg["--printf=".len..];
            is_printf = true;
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
        const file_z = try allocator.dupeZ(u8, file);
        defer allocator.free(file_z);

        if (filesystem) {
            var sv: c.struct_statvfs = undefined;
            if (c.statvfs(file_z.ptr, &sv) != 0) {
                const err_msg = std.mem.span(c.strerror(c.__errno_location().*));
                const msg = try std.fmt.allocPrint(allocator, "cannot statx '{s}': {s}", .{ file, err_msg });
                defer allocator.free(msg);
                try errors.printError(stderr, name, msg);
                exit_status = 1;
                continue;
            }

            if (format_str) |fmt| {
                try printFormattedFs(stdout, fmt, file, &sv, is_printf);
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
            const res = if (follow_symlinks) c.stat(file_z.ptr, &st) else c.lstat(file_z.ptr, &st);
            if (res != 0) {
                const err_msg = std.mem.span(c.strerror(c.__errno_location().*));
                const msg = try std.fmt.allocPrint(allocator, "cannot statx '{s}': {s}", .{ file, err_msg });
                defer allocator.free(msg);
                try errors.printError(stderr, name, msg);
                exit_status = 1;
                continue;
            }

            var link_target_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
            var link_target: ?[]const u8 = null;
            if ((st.st_mode & c.S_IFMT) == c.S_IFLNK) {
                const len = std.Io.Dir.cwd().readLink(std.Options.debug_io, file, &link_target_buf) catch 0;
                if (len > 0) {
                    link_target = link_target_buf[0..len];
                }
            }

            if (format_str) |fmt| {
                try printFormattedFile(stdout, fmt, file, &st, link_target, is_printf);
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
                try stdout.print("  Size: {d:<10}\tBlocks: {d:<10} IO Block: {d:<6} {s}\n", .{
                    st.st_size,
                    st.st_blocks,
                    st.st_blksize,
                    file_type,
                });

                const dev_major = @as(u32, @intCast((st.st_dev >> 8) & 0xfff));
                const dev_minor = @as(u32, @intCast((st.st_dev & 0xff) | ((st.st_dev >> 12) & 0xfff00)));
                try stdout.print("Device: {d},{d}\tInode: {d:<11} Links: {d}\n", .{
                    dev_major,
                    dev_minor,
                    st.st_ino,
                    st.st_nlink,
                });

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

fn printFormattedFile(writer: anytype, fmt: []const u8, name_str: []const u8, st: *const c.struct_stat, link_target: ?[]const u8, is_printf: bool) !void {
    var idx: usize = 0;
    while (idx < fmt.len) {
        if (fmt[idx] == '%' and idx + 1 < fmt.len) {
            idx += 1;
            switch (fmt[idx]) {
                'a' => try writer.print("{o}", .{st.st_mode & 0o7777}),
                'A' => {
                    var perm_buf: [11]u8 = undefined;
                    getPermString(st.st_mode, &perm_buf);
                    try writer.writeAll(perm_buf[0..10]);
                },
                'b' => try writer.print("{d}", .{st.st_blocks}),
                'B' => try writer.print("{d}", .{512}),
                'd' => try writer.print("{d}", .{st.st_dev}),
                'D' => try writer.print("{x}", .{st.st_dev}),
                'f' => try writer.print("{x}", .{st.st_mode}),
                'F' => try writer.writeAll(getFileType(st.st_mode, st.st_size)),
                'g' => try writer.print("{d}", .{st.st_gid}),
                'G' => {
                    const gr = c.getgrgid(st.st_gid);
                    if (gr != null and gr.*.gr_name != null) try writer.writeAll(std.mem.span(gr.*.gr_name)) else try writer.writeAll("UNKNOWN");
                },
                'h' => try writer.print("{d}", .{st.st_nlink}),
                'i' => try writer.print("{d}", .{st.st_ino}),
                'n' => try writer.writeAll(name_str),
                'N' => {
                    if (link_target) |tgt| {
                        try writer.print("'{s}' -> '{s}'", .{ name_str, tgt });
                    } else {
                        try writer.print("'{s}'", .{name_str});
                    }
                },
                'o' => try writer.print("{d}", .{st.st_blksize}),
                's' => try writer.print("{d}", .{st.st_size}),
                'u' => try writer.print("{d}", .{st.st_uid}),
                'U' => {
                    const pw = c.getpwuid(st.st_uid);
                    if (pw != null and pw.*.pw_name != null) try writer.writeAll(std.mem.span(pw.*.pw_name)) else try writer.writeAll("UNKNOWN");
                },
                'x' => {
                    var tm_val: c.struct_tm = undefined;
                    const time_val: c.time_t = @intCast(st.st_atim.tv_sec);
                    _ = c.localtime_r(&time_val, &tm_val);
                    var t_buf: [64]u8 = undefined;
                    const len = c.strftime(&t_buf, t_buf.len, "%Y-%m-%d %H:%M:%S", &tm_val);
                    var tz_buf: [16]u8 = undefined;
                    const tz_len = c.strftime(&tz_buf, tz_buf.len, "%z", &tm_val);
                    try writer.print("{s}.{d:0>9} {s}", .{ t_buf[0..len], st.st_atim.tv_nsec, tz_buf[0..tz_len] });
                },
                'X' => try writer.print("{d}", .{st.st_atim.tv_sec}),
                'y' => {
                    var tm_val: c.struct_tm = undefined;
                    const time_val: c.time_t = @intCast(st.st_mtim.tv_sec);
                    _ = c.localtime_r(&time_val, &tm_val);
                    var t_buf: [64]u8 = undefined;
                    const len = c.strftime(&t_buf, t_buf.len, "%Y-%m-%d %H:%M:%S", &tm_val);
                    var tz_buf: [16]u8 = undefined;
                    const tz_len = c.strftime(&tz_buf, tz_buf.len, "%z", &tm_val);
                    try writer.print("{s}.{d:0>9} {s}", .{ t_buf[0..len], st.st_mtim.tv_nsec, tz_buf[0..tz_len] });
                },
                'Y' => try writer.print("{d}", .{st.st_mtim.tv_sec}),
                'z' => {
                    var tm_val: c.struct_tm = undefined;
                    const time_val: c.time_t = @intCast(st.st_ctim.tv_sec);
                    _ = c.localtime_r(&time_val, &tm_val);
                    var t_buf: [64]u8 = undefined;
                    const len = c.strftime(&t_buf, t_buf.len, "%Y-%m-%d %H:%M:%S", &tm_val);
                    var tz_buf: [16]u8 = undefined;
                    const tz_len = c.strftime(&tz_buf, tz_buf.len, "%z", &tm_val);
                    try writer.print("{s}.{d:0>9} {s}", .{ t_buf[0..len], st.st_ctim.tv_nsec, tz_buf[0..tz_len] });
                },
                'Z' => try writer.print("{d}", .{st.st_ctim.tv_sec}),
                '%' => try writer.writeByte('%'),
                else => {
                    try writer.writeByte('%');
                    try writer.writeByte(fmt[idx]);
                },
            }
        } else if (is_printf and fmt[idx] == '\\' and idx + 1 < fmt.len) {
            idx += 1;
            switch (fmt[idx]) {
                'n' => try writer.writeByte('\n'),
                't' => try writer.writeByte('\t'),
                'r' => try writer.writeByte('\r'),
                '\\' => try writer.writeByte('\\'),
                else => {
                    try writer.writeByte('\\');
                    try writer.writeByte(fmt[idx]);
                },
            }
        } else {
            try writer.writeByte(fmt[idx]);
        }
        idx += 1;
    }
    if (!is_printf) {
        try writer.writeByte('\n');
    }
}

fn printFormattedFs(writer: anytype, fmt: []const u8, name_str: []const u8, sv: *const c.struct_statvfs, is_printf: bool) !void {
    var idx: usize = 0;
    while (idx < fmt.len) {
        if (fmt[idx] == '%' and idx + 1 < fmt.len) {
            idx += 1;
            switch (fmt[idx]) {
                'n' => try writer.writeAll(name_str),
                'i' => try writer.print("{x}", .{sv.f_fsid}),
                'l' => try writer.print("{d}", .{sv.f_namemax}),
                's' => try writer.print("{d}", .{sv.f_bsize}),
                'S' => try writer.print("{d}", .{sv.f_frsize}),
                'b' => try writer.print("{d}", .{sv.f_blocks}),
                'f' => try writer.print("{d}", .{sv.f_bfree}),
                'a' => try writer.print("{d}", .{sv.f_bavail}),
                'c' => try writer.print("{d}", .{sv.f_files}),
                'd' => try writer.print("{d}", .{sv.f_ffree}),
                '%' => try writer.writeByte('%'),
                else => {
                    try writer.writeByte('%');
                    try writer.writeByte(fmt[idx]);
                },
            }
        } else if (is_printf and fmt[idx] == '\\' and idx + 1 < fmt.len) {
            idx += 1;
            switch (fmt[idx]) {
                'n' => try writer.writeByte('\n'),
                't' => try writer.writeByte('\t'),
                '\\' => try writer.writeByte('\\'),
                else => {
                    try writer.writeByte('\\');
                    try writer.writeByte(fmt[idx]);
                },
            }
        } else {
            try writer.writeByte(fmt[idx]);
        }
        idx += 1;
    }
    if (!is_printf) {
        try writer.writeByte('\n');
    }
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
