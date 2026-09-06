const std = @import("std");
const errors = @import("../utils/errors.zig");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "touch";
pub const version: []const u8 = "0.1.0";

fn errnoDescription(err: std.posix.E) []const u8 {
    return switch (err) {
        .SUCCESS => "Success",
        .NOENT => "No such file or directory",
        .NOTDIR => "Not a directory",
        .ISDIR => "Is a directory",
        .ACCES, .PERM => "Permission denied",
        .NXIO => "No such device or address",
        .ROFS => "Read-only file system",
        .BADF => "Bad file descriptor",
        .INVAL => "Invalid argument",
        .LOOP => "Too many levels of symbolic links",
        .NAMETOOLONG => "File name too long",
        else => @tagName(err),
    };
}

fn parseRelativeOffset(str: []const u8) ?i64 {
    var s = std.mem.trim(u8, str, " \t\r\n");
    if (s.len == 0) return null;

    var is_ago = false;
    if (s.len >= 4 and std.ascii.endsWithIgnoreCase(s, " ago")) {
        is_ago = true;
        s = std.mem.trim(u8, s[0 .. s.len - 4], " \t\r\n");
    }

    var sign: i64 = if (is_ago) -1 else 1;
    var num_start: usize = 0;
    if (s[0] == '+') {
        sign = if (is_ago) -1 else 1;
        num_start = 1;
    } else if (s[0] == '-') {
        sign = if (is_ago) 1 else -1;
        num_start = 1;
    }

    const rest = std.mem.trim(u8, s[num_start..], " \t\r\n");
    if (rest.len == 0) return null;

    var space_idx: ?usize = null;
    for (rest, 0..) |ch, idx| {
        if (ch == ' ' or ch == '\t') {
            space_idx = idx;
            break;
        }
    }

    const num_str = if (space_idx) |idx| rest[0..idx] else rest;
    const unit_str = if (space_idx) |idx| std.mem.trim(u8, rest[idx..], " \t\r\n") else "";

    const val = std.fmt.parseInt(i64, num_str, 10) catch return null;

    var multiplier: i64 = 1;
    if (unit_str.len > 0) {
        if (std.ascii.eqlIgnoreCase(unit_str, "day") or std.ascii.eqlIgnoreCase(unit_str, "days")) {
            multiplier = 86400;
        } else if (std.ascii.eqlIgnoreCase(unit_str, "hour") or std.ascii.eqlIgnoreCase(unit_str, "hours")) {
            multiplier = 3600;
        } else if (std.ascii.eqlIgnoreCase(unit_str, "min") or std.ascii.eqlIgnoreCase(unit_str, "mins") or std.ascii.eqlIgnoreCase(unit_str, "minute") or std.ascii.eqlIgnoreCase(unit_str, "minutes")) {
            multiplier = 60;
        } else if (std.ascii.eqlIgnoreCase(unit_str, "sec") or std.ascii.eqlIgnoreCase(unit_str, "secs") or std.ascii.eqlIgnoreCase(unit_str, "second") or std.ascii.eqlIgnoreCase(unit_str, "seconds")) {
            multiplier = 1;
        } else {
            return null;
        }
    }

    return sign * val * multiplier;
}

fn parseDateRelative(str: []const u8, base_sec: i64) !std.os.linux.timespec {
    const s = std.mem.trim(u8, str, " \t\r\n'\"");
    if (s.len == 0) return error.InvalidDateFormat;

    if (std.ascii.eqlIgnoreCase(s, "now")) {
        var now_ts: c.struct_timespec = undefined;
        _ = c.clock_gettime(c.CLOCK_REALTIME, &now_ts);
        return .{ .sec = now_ts.tv_sec, .nsec = now_ts.tv_nsec };
    }

    if (std.ascii.eqlIgnoreCase(s, "yesterday")) {
        var now_ts: c.struct_timespec = undefined;
        _ = c.clock_gettime(c.CLOCK_REALTIME, &now_ts);
        return .{ .sec = now_ts.tv_sec - 86400, .nsec = now_ts.tv_nsec };
    }

    if (std.ascii.eqlIgnoreCase(s, "tomorrow")) {
        var now_ts: c.struct_timespec = undefined;
        _ = c.clock_gettime(c.CLOCK_REALTIME, &now_ts);
        return .{ .sec = now_ts.tv_sec + 86400, .nsec = now_ts.tv_nsec };
    }

    if (s.len > 1 and s[0] == '@') {
        const sec = std.fmt.parseInt(i64, s[1..], 10) catch return error.InvalidDateFormat;
        return .{ .sec = sec, .nsec = 0 };
    }

    if (parseRelativeOffset(s)) |offset| {
        return .{ .sec = base_sec + offset, .nsec = 0 };
    }

    var str_buf: [128]u8 = undefined;
    if (s.len >= str_buf.len) return error.InvalidDateFormat;
    @memcpy(str_buf[0..s.len], s);
    str_buf[s.len] = 0;
    const c_str: [*:0]const u8 = @ptrCast(&str_buf);

    const patterns = [_][*:0]const u8{
        "%Y-%m-%d %H:%M:%S %z",
        "%Y-%m-%d %H:%M %z",
        "%Y-%m-%d %H:%M:%S",
        "%Y-%m-%d %H:%M",
        "%Y-%m-%d",
        "%Y-%m-%dT%H:%M:%S%z",
        "%Y-%m-%dT%H:%M:%S",
        "%Y-%m-%dT%H:%M",
        "%Y%m%d%H%M.%S",
        "%Y%m%d%H%M%S",
        "%Y%m%d%H%M",
    };

    for (patterns) |pattern| {
        var tm: c.struct_tm = std.mem.zeroes(c.struct_tm);
        tm.tm_isdst = -1;
        const res = c.strptime(c_str, pattern, &tm);
        if (res != null) {
            const has_tz = std.mem.indexOf(u8, std.mem.sliceTo(pattern, 0), "%z") != null;
            if (has_tz) {
                const sec = c.timegm(&tm) - tm.tm_gmtoff;
                return .{ .sec = sec, .nsec = 0 };
            } else if (std.mem.endsWith(u8, s, "Z") or std.mem.endsWith(u8, s, "UTC")) {
                const sec = c.timegm(&tm);
                return .{ .sec = sec, .nsec = 0 };
            } else {
                const sec = c.mktime(&tm);
                if (sec == -1) return error.InvalidDateFormat;
                return .{ .sec = sec, .nsec = 0 };
            }
        }
    }

    return error.InvalidDateFormat;
}

fn parsePosixTime(arg: []const u8) !std.os.linux.timespec {
    var sec_val: u8 = 0;
    var main_part = arg;

    if (std.mem.indexOfScalar(u8, arg, '.')) |dot_idx| {
        main_part = arg[0..dot_idx];
        const sec_part = arg[dot_idx + 1 ..];
        if (sec_part.len != 2) return error.InvalidDateFormat;
        sec_val = std.fmt.parseInt(u8, sec_part, 10) catch return error.InvalidDateFormat;
        if (sec_val > 60) return error.InvalidDateFormat;
    }

    var tm: c.struct_tm = std.mem.zeroes(c.struct_tm);
    tm.tm_sec = sec_val;
    tm.tm_isdst = -1;

    if (main_part.len == 8) {
        var now_ts: c.struct_timespec = undefined;
        _ = c.clock_gettime(c.CLOCK_REALTIME, &now_ts);
        const cur_tm = c.localtime(&now_ts.tv_sec);
        if (cur_tm != null) {
            tm.tm_year = cur_tm.*.tm_year;
        } else {
            tm.tm_year = 2026 - 1900;
        }
        tm.tm_mon = (std.fmt.parseInt(c_int, main_part[0..2], 10) catch return error.InvalidDateFormat) - 1;
        tm.tm_mday = std.fmt.parseInt(c_int, main_part[2..4], 10) catch return error.InvalidDateFormat;
        tm.tm_hour = std.fmt.parseInt(c_int, main_part[4..6], 10) catch return error.InvalidDateFormat;
        tm.tm_min = std.fmt.parseInt(c_int, main_part[6..8], 10) catch return error.InvalidDateFormat;
    } else if (main_part.len == 10) {
        const yy = std.fmt.parseInt(c_int, main_part[0..2], 10) catch return error.InvalidDateFormat;
        if (yy >= 69) {
            tm.tm_year = yy;
        } else {
            tm.tm_year = yy + 100;
        }
        tm.tm_mon = (std.fmt.parseInt(c_int, main_part[2..4], 10) catch return error.InvalidDateFormat) - 1;
        tm.tm_mday = std.fmt.parseInt(c_int, main_part[4..6], 10) catch return error.InvalidDateFormat;
        tm.tm_hour = std.fmt.parseInt(c_int, main_part[6..8], 10) catch return error.InvalidDateFormat;
        tm.tm_min = std.fmt.parseInt(c_int, main_part[8..10], 10) catch return error.InvalidDateFormat;
    } else if (main_part.len == 12) {
        const ccyy = std.fmt.parseInt(c_int, main_part[0..4], 10) catch return error.InvalidDateFormat;
        tm.tm_year = ccyy - 1900;
        tm.tm_mon = (std.fmt.parseInt(c_int, main_part[4..6], 10) catch return error.InvalidDateFormat) - 1;
        tm.tm_mday = std.fmt.parseInt(c_int, main_part[6..8], 10) catch return error.InvalidDateFormat;
        tm.tm_hour = std.fmt.parseInt(c_int, main_part[8..10], 10) catch return error.InvalidDateFormat;
        tm.tm_min = std.fmt.parseInt(c_int, main_part[10..12], 10) catch return error.InvalidDateFormat;
    } else {
        return error.InvalidDateFormat;
    }

    if (tm.tm_mon < 0 or tm.tm_mon > 11) return error.InvalidDateFormat;
    if (tm.tm_mday < 1 or tm.tm_mday > 31) return error.InvalidDateFormat;
    if (tm.tm_hour < 0 or tm.tm_hour > 23) return error.InvalidDateFormat;
    if (tm.tm_min < 0 or tm.tm_min > 59) return error.InvalidDateFormat;

    const t = c.mktime(&tm);
    if (t == -1) return error.InvalidDateFormat;

    return .{ .sec = t, .nsec = 0 };
}

fn getPosix2Version() i64 {
    if (std.c.getenv("_POSIX2_VERSION")) |val| {
        const s = std.mem.span(val);
        return std.fmt.parseInt(i64, s, 10) catch 200809;
    }
    return 200809;
}

fn parseObsoleteTime(arg: []const u8) ?std.os.linux.timespec {
    if (arg.len != 8 and arg.len != 10) return null;
    for (arg) |ch| {
        if (!std.ascii.isDigit(ch)) return null;
    }

    const month = std.fmt.parseInt(c_int, arg[0..2], 10) catch return null;
    const day = std.fmt.parseInt(c_int, arg[2..4], 10) catch return null;
    const hour = std.fmt.parseInt(c_int, arg[4..6], 10) catch return null;
    const min = std.fmt.parseInt(c_int, arg[6..8], 10) catch return null;

    if (month < 1 or month > 12) return null;
    if (day < 1 or day > 31) return null;
    if (hour < 0 or hour > 23) return null;
    if (min < 0 or min > 59) return null;

    var year: c_int = undefined;
    if (arg.len == 8) {
        var now_ts: c.struct_timespec = undefined;
        _ = c.clock_gettime(c.CLOCK_REALTIME, &now_ts);
        const cur_tm = c.localtime(&now_ts.tv_sec);
        if (cur_tm != null) {
            year = cur_tm.*.tm_year + 1900;
        } else {
            year = 2026;
        }
    } else {
        const yy = std.fmt.parseInt(c_int, arg[8..10], 10) catch return null;
        // PDS_PRE_2000 rule: Year must be in range 69..99
        if (yy < 69) return null;
        year = 1900 + yy;
    }

    var tm: c.struct_tm = std.mem.zeroes(c.struct_tm);
    tm.tm_year = year - 1900;
    tm.tm_mon = month - 1;
    tm.tm_mday = day;
    tm.tm_hour = hour;
    tm.tm_min = min;
    tm.tm_sec = 0;
    tm.tm_isdst = -1;

    const t = c.mktime(&tm);
    if (t == -1) return null;
    return .{ .sec = t, .nsec = 0 };
}

fn touchFile(
    file_path: []const u8,
    no_create: bool,
    no_dereference: bool,
    change_times: u8,
    newtime: [2]std.os.linux.timespec,
    amtime_now: bool,
    stderr: anytype,
) !bool {
    const is_dash = std.mem.eql(u8, file_path, "-");
    var open_errno: ?std.posix.E = null;

    if (!is_dash and !(no_create or no_dereference)) {
        const flags: std.posix.O = .{
            .ACCMODE = .WRONLY,
            .CREAT = true,
            .NONBLOCK = true,
            .NOCTTY = true,
        };
        const res = std.posix.openat(std.posix.AT.FDCWD, file_path, flags, 0o666);
        if (res) |fd| {
            const f = std.Io.File{ .handle = fd, .flags = .{ .nonblocking = true } };
            f.close(std.Options.debug_io);
        } else |err| {
            open_errno = switch (err) {
                error.FileNotFound => .NOENT,
                error.IsDir => .ISDIR,
                error.NotDir => .NOTDIR,
                error.AccessDenied, error.PermissionDenied => .ACCES,
                error.NoDevice => .NXIO,
                else => .INVAL,
            };
        }
    }

    var times = newtime;
    if (change_times != 3) {
        if (change_times == 2) {
            times[0] = std.os.linux.UTIME.OMIT;
        } else if (change_times == 1) {
            times[1] = std.os.linux.UTIME.OMIT;
        }
    }

    const times_ptr: ?*const [2]std.os.linux.timespec = if (amtime_now) null else &times;
    var atflag: u32 = if (no_dereference) std.posix.AT.SYMLINK_NOFOLLOW else 0;

    var utime_rc: usize = 0;
    if (is_dash) {
        atflag |= std.os.linux.AT.EMPTY_PATH;
        utime_rc = std.os.linux.utimensat(std.posix.STDOUT_FILENO, "", @ptrCast(times_ptr), atflag);
    } else {
        var path_buf: [std.fs.max_path_bytes]u8 = undefined;
        if (file_path.len >= path_buf.len) {
            try stderr.print("touch: file name too long\n", .{});
            return false;
        }
        @memcpy(path_buf[0..file_path.len], file_path);
        path_buf[file_path.len] = 0;
        const path_z: [*:0]const u8 = @ptrCast(&path_buf);

        utime_rc = std.os.linux.utimensat(std.posix.AT.FDCWD, path_z, @ptrCast(times_ptr), atflag);
    }

    const utime_errno = std.os.linux.errno(utime_rc);

    if (is_dash) {
        if (utime_errno == .BADF and no_create) return true;
    }

    if (utime_errno != .SUCCESS) {
        if (no_create and utime_errno == .NOENT) {
            return true;
        }

        if (open_errno) |o_err| {
            if (o_err != .ISDIR) {
                const err_str = errnoDescription(o_err);
                try stderr.print("touch: cannot touch '{s}': {s}\n", .{ file_path, err_str });
                return false;
            }
        }

        const err_str = errnoDescription(utime_errno);
        try stderr.print("touch: setting times of '{s}': {s}\n", .{ file_path, err_str });
        return false;
    }

    return true;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buffer: [4096]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var change_times: u8 = 0; // 1 = atime, 2 = mtime, 3 = both
    var no_create = false;
    var no_dereference = false;
    var use_ref = false;
    var ref_file: ?[]const u8 = null;
    var flex_date: ?[]const u8 = null;
    var date_set = false;
    var newtime: [2]std.os.linux.timespec = undefined;

    var file_operands: std.ArrayList([]const u8) = .empty;
    defer file_operands.deinit(allocator);

    const posixly_correct = errors.isPosixlyCorrect();
    var parsing_options = true;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (parsing_options and arg.len > 0 and arg[0] == '-') {
            if (std.mem.eql(u8, arg, "-")) {
                if (posixly_correct) parsing_options = false;
                try file_operands.append(allocator, arg);
                continue;
            }
            if (std.mem.eql(u8, arg, "--")) {
                parsing_options = false;
                continue;
            }

            if (std.mem.startsWith(u8, arg, "--")) {
                if (std.mem.indexOfScalar(u8, arg, '=')) |eq| {
                    const opt_name = arg[2..eq];
                    const opt_val = arg[eq + 1 ..];
                    if (std.mem.startsWith(u8, "reference", opt_name)) {
                        use_ref = true;
                        ref_file = opt_val;
                    } else if (std.mem.startsWith(u8, "date", opt_name)) {
                        flex_date = opt_val;
                    } else if (std.mem.startsWith(u8, "time", opt_name)) {
                        if (std.mem.eql(u8, opt_val, "atime") or std.mem.eql(u8, opt_val, "access") or std.mem.eql(u8, opt_val, "use")) {
                            change_times |= 1;
                        } else if (std.mem.eql(u8, opt_val, "mtime") or std.mem.eql(u8, opt_val, "modify")) {
                            change_times |= 2;
                        } else {
                            try stderr.print(
                                \\touch: invalid argument '{s}' for '--time'
                                \\Valid arguments are:
                                \\  - 'atime', 'access', 'use'
                                \\  - 'mtime', 'modify'
                                \\Try 'touch --help' for more information.
                                \\
                            , .{opt_val});
                            return 1;
                        }
                    } else {
                        try errors.printUnrecognizedOption(stderr, name, arg);
                        return 1;
                    }
                } else {
                    const opt_name = arg[2..];
                    if (std.mem.startsWith(u8, "help", opt_name)) {
                        printHelp(stdout) catch return 1;
                        stdout.flush() catch return 1;
                        return 0;
                    } else if (std.mem.startsWith(u8, "version", opt_name)) {
                        printVersion(stdout) catch return 1;
                        stdout.flush() catch return 1;
                        return 0;
                    } else if (opt_name.len >= 4 and std.mem.startsWith(u8, "no-create", opt_name)) {
                        no_create = true;
                    } else if (opt_name.len >= 4 and std.mem.startsWith(u8, "no-dereference", opt_name)) {
                        no_dereference = true;
                    } else if (std.mem.startsWith(u8, "reference", opt_name)) {
                        i += 1;
                        if (i >= args.len) {
                            try stderr.print("touch: option '--reference' requires an argument\n", .{});
                            return 1;
                        }
                        use_ref = true;
                        ref_file = args[i];
                    } else if (std.mem.startsWith(u8, "date", opt_name)) {
                        i += 1;
                        if (i >= args.len) {
                            try stderr.print("touch: option '--date' requires an argument\n", .{});
                            return 1;
                        }
                        flex_date = args[i];
                    } else if (std.mem.startsWith(u8, "time", opt_name)) {
                        i += 1;
                        if (i >= args.len) {
                            try stderr.print("touch: option '--time' requires an argument\n", .{});
                            return 1;
                        }
                        const opt_val = args[i];
                        if (std.mem.eql(u8, opt_val, "atime") or std.mem.eql(u8, opt_val, "access") or std.mem.eql(u8, opt_val, "use")) {
                            change_times |= 1;
                        } else if (std.mem.eql(u8, opt_val, "mtime") or std.mem.eql(u8, opt_val, "modify")) {
                            change_times |= 2;
                        } else {
                            try stderr.print(
                                \\touch: invalid argument '{s}' for '--time'
                                \\Valid arguments are:
                                \\  - 'atime', 'access', 'use'
                                \\  - 'mtime', 'modify'
                                \\Try 'touch --help' for more information.
                                \\
                            , .{opt_val});
                            return 1;
                        }
                    } else {
                        try errors.printUnrecognizedOption(stderr, name, arg);
                        return 1;
                    }
                }
                continue;
            }

            // Short options
            var j: usize = 1;
            while (j < arg.len) : (j += 1) {
                const c_opt = arg[j];
                switch (c_opt) {
                    'a' => change_times |= 1,
                    'm' => change_times |= 2,
                    'c' => no_create = true,
                    'h' => no_dereference = true,
                    'f' => {}, // ignored
                    'r' => {
                        use_ref = true;
                        if (j + 1 < arg.len) {
                            ref_file = arg[j + 1 ..];
                            j = arg.len;
                        } else {
                            i += 1;
                            if (i >= args.len) {
                                try stderr.print("touch: option requires an argument -- 'r'\nTry 'touch --help' for more information.\n", .{});
                                return 1;
                            }
                            ref_file = args[i];
                        }
                    },
                    'd' => {
                        if (j + 1 < arg.len) {
                            flex_date = arg[j + 1 ..];
                            j = arg.len;
                        } else {
                            i += 1;
                            if (i >= args.len) {
                                try stderr.print("touch: option requires an argument -- 'd'\nTry 'touch --help' for more information.\n", .{});
                                return 1;
                            }
                            flex_date = args[i];
                        }
                    },
                    't' => {
                        var t_str: []const u8 = undefined;
                        if (j + 1 < arg.len) {
                            t_str = arg[j + 1 ..];
                            j = arg.len;
                        } else {
                            i += 1;
                            if (i >= args.len) {
                                try stderr.print("touch: option requires an argument -- 't'\nTry 'touch --help' for more information.\n", .{});
                                return 1;
                            }
                            t_str = args[i];
                        }

                        if (date_set) {
                            try stderr.print("touch: cannot specify times from more than one source\nTry 'touch --help' for more information.\n", .{});
                            return 1;
                        }

                        const parsed = parsePosixTime(t_str) catch {
                            try stderr.print("touch: invalid date format '{s}'\n", .{t_str});
                            return 1;
                        };
                        newtime[0] = parsed;
                        newtime[1] = parsed;
                        date_set = true;
                    },
                    else => {
                        try stderr.print("touch: invalid option -- '{c}'\nTry 'touch --help' for more information.\n", .{c_opt});
                        return 1;
                    },
                }
            }
            continue;
        }

        if (posixly_correct) parsing_options = false;
        try file_operands.append(allocator, arg);
    }

    if (!date_set and file_operands.items.len >= 2 and getPosix2Version() < 200112) {
        if (parseObsoleteTime(file_operands.items[0])) |ot| {
            newtime[0] = ot;
            newtime[1] = ot;
            date_set = true;
            _ = file_operands.orderedRemove(0);
        }
    }

    if (change_times == 0) {
        change_times = 3;
    }

    if (date_set and (use_ref or flex_date != null)) {
        try stderr.print("touch: cannot specify times from more than one source\nTry 'touch --help' for more information.\n", .{});
        return 1;
    }

    var amtime_now = false;

    if (use_ref) {
        const rpath = ref_file orelse {
            try stderr.print("touch: option '--reference' requires an argument\n", .{});
            return 1;
        };

        var stx = std.mem.zeroes(std.os.linux.Statx);
        var ref_path_buf: [std.fs.max_path_bytes]u8 = undefined;
        if (rpath.len >= ref_path_buf.len) {
            try stderr.print("touch: file name too long\n", .{});
            return 1;
        }
        @memcpy(ref_path_buf[0..rpath.len], rpath);
        ref_path_buf[rpath.len] = 0;
        const ref_path_z: [*:0]const u8 = @ptrCast(&ref_path_buf);

        const atflag: u32 = if (no_dereference) std.posix.AT.SYMLINK_NOFOLLOW else 0;
        const statx_rc = std.os.linux.statx(std.posix.AT.FDCWD, ref_path_z, atflag, .{ .ATIME = true, .MTIME = true }, &stx);
        const statx_err = std.os.linux.errno(statx_rc);
        if (statx_err != .SUCCESS) {
            const err_str = errnoDescription(statx_err);
            try stderr.print("touch: failed to get attributes of '{s}': {s}\n", .{ rpath, err_str });
            return 1;
        }

        newtime[0] = .{ .sec = stx.atime.sec, .nsec = @intCast(stx.atime.nsec) };
        newtime[1] = .{ .sec = stx.mtime.sec, .nsec = @intCast(stx.mtime.nsec) };
        date_set = true;

        if (flex_date) |fd| {
            if (change_times & 1 != 0) {
                newtime[0] = parseDateRelative(fd, newtime[0].sec) catch {
                    try stderr.print("touch: invalid date format '{s}'\n", .{fd});
                    return 1;
                };
            }
            if (change_times & 2 != 0) {
                newtime[1] = parseDateRelative(fd, newtime[1].sec) catch {
                    try stderr.print("touch: invalid date format '{s}'\n", .{fd});
                    return 1;
                };
            }
        }
    } else if (flex_date) |fd| {
        var now_ts: c.struct_timespec = undefined;
        _ = c.clock_gettime(c.CLOCK_REALTIME, &now_ts);
        const parsed = parseDateRelative(fd, now_ts.tv_sec) catch {
            try stderr.print("touch: invalid date format '{s}'\n", .{fd});
            return 1;
        };
        newtime[0] = parsed;
        newtime[1] = parsed;
        date_set = true;
    }

    if (!date_set) {
        if (change_times == 3) {
            amtime_now = true;
        } else {
            newtime[0] = std.os.linux.UTIME.NOW;
            newtime[1] = std.os.linux.UTIME.NOW;
        }
    }

    if (file_operands.items.len == 0) {
        try stderr.print("touch: missing file operand\nTry 'touch --help' for more information.\n", .{});
        return 1;
    }

    var exit_status: u8 = 0;
    for (file_operands.items) |file| {
        const ok = try touchFile(file, no_create, no_dereference, change_times, newtime, amtime_now, stderr);
        if (!ok) {
            exit_status = 1;
        }
    }

    return exit_status;
}

fn printHelp(writer: anytype) !void {
    try writer.print(
        \\Usage: {s} [OPTION]... FILE...
        \\Update the access and modification times of each FILE to the current time.
        \\
        \\A FILE argument that does not exist is created empty, unless -c or -h
        \\is supplied.
        \\
        \\A FILE argument string of - is handled specially and causes touch to
        \\change the times of the file associated with standard output.
        \\
        \\Mandatory arguments to long options are mandatory for short options too.
        \\  -a                     change only the access time
        \\  -c, --no-create        do not create any files
        \\  -d, --date=STRING      parse STRING and use it instead of current time
        \\  -f                     (ignored)
        \\  -h, --no-dereference   affect each symbolic link instead of any referenced
        \\                         file (useful only on systems that can change the
        \\                         timestamps of a symlink)
        \\  -m                     change only the modification time
        \\  -r, --reference=FILE   use this file's times instead of current time
        \\  -t [[CC]YY]MMDDhhmm[.ss]  use specified time instead of current time,
        \\                         with a date-time format that differs from -d's
        \\      --time=WORD        change the specified time:
        \\                           WORD is access, atime, or use: equivalent to -a
        \\                           WORD is modify or mtime: equivalent to -m
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
    , .{name});
}

fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
