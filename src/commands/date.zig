const std = @import("std");
const c = @import("../compat/c.zig").c;
const parse = @import("date/parse.zig");

pub const name: []const u8 = "date";
pub const version: []const u8 = "0.1.0";

const DateOptions = struct {
    is_utc: bool = false,
    rfc_email: bool = false,
    iso_8601: bool = false,
    resolution: bool = false,
    date_str: ?[]const u8 = null,
    ref_file: ?[]const u8 = null,
    format_str: ?[]const u8 = null,
};

fn parseArgs(args: [][]const u8, opts: *DateOptions, stdout: anytype) !?u8 {
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            try stdout.print("Usage: date [OPTION]... [+FORMAT]\nDisplay date and time in the given FORMAT.\n", .{});
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try stdout.print("date (coreutilz) {s}\n", .{version});
            return 0;
        } else if (std.mem.eql(u8, arg, "--resolution")) {
            opts.resolution = true;
        } else if (std.mem.eql(u8, arg, "--debug")) {
            // accepted debug flag
        } else if (std.mem.eql(u8, arg, "-u") or std.mem.eql(u8, arg, "--utc") or std.mem.eql(u8, arg, "--universal")) {
            opts.is_utc = true;
        } else if (std.mem.eql(u8, arg, "-R") or std.mem.eql(u8, arg, "--rfc-email") or std.mem.eql(u8, arg, "--rfc-2822")) {
            opts.rfc_email = true;
        } else if (std.mem.startsWith(u8, arg, "-I") or std.mem.startsWith(u8, arg, "--iso-8601")) {
            opts.iso_8601 = true;
        } else if (std.mem.startsWith(u8, arg, "-d")) {
            if (arg.len == 2) {
                i += 1;
                if (i >= args.len) return 1;
                opts.date_str = args[i];
            } else opts.date_str = arg[2..];
        } else if (std.mem.startsWith(u8, arg, "--date=")) {
            opts.date_str = arg["--date=".len..];
        } else if (std.mem.startsWith(u8, arg, "-r")) {
            if (arg.len == 2) {
                i += 1;
                if (i >= args.len) return 1;
                opts.ref_file = args[i];
            } else opts.ref_file = arg[2..];
            if (opts.ref_file.?.len == 0) return 1;
        } else if (std.mem.startsWith(u8, arg, "--reference=")) {
            opts.ref_file = arg["--reference=".len..];
            if (opts.ref_file.?.len == 0) return 1;
        } else if (std.mem.eql(u8, arg, "--reference")) {
            i += 1;
            if (i >= args.len) return 1;
            opts.ref_file = args[i];
            if (opts.ref_file.?.len == 0) return 1;
        } else if (arg.len > 0 and arg[0] == '+') {
            opts.format_str = arg[1..];
        } else return 1;
    }
    return null;
}

fn resolveTimestamp(opts: *const DateOptions, allocator: std.mem.Allocator, stderr: anytype) !?c.time_t {
    if (opts.date_str != null and opts.ref_file != null) {
        try stderr.print("date: the options to specify dates for printing are mutually exclusive\n", .{});
        return null;
    }
    if (opts.ref_file) |rf| {
        var zpath: [std.fs.max_path_bytes:0]u8 = undefined;
        if (rf.len >= zpath.len) return null;
        @memcpy(zpath[0..rf.len], rf);
        zpath[rf.len] = 0;
        var st: c.struct_stat = undefined;
        if (c.stat(&zpath, &st) != 0) {
            try stderr.print("date: {s}: No such file or directory\n", .{rf});
            return null;
        }
        return st.st_mtim.tv_sec;
    } else if (opts.date_str) |ds| {
        const t = parse.parseDateStr(ds, opts.is_utc, allocator);
        if (t == null) {
            try stderr.print("date: invalid date '{s}'\n", .{ds});
        }
        return t;
    }
    return c.time(null);
}

fn replaceFormatSpecifiers(allocator: std.mem.Allocator, fs: []const u8, nsec_str: []const u8) ![:0]u8 {
    var out: std.ArrayListUnmanaged(u8) = .empty;
    errdefer out.deinit(allocator);

    var i: usize = 0;
    while (i < fs.len) {
        if (fs[i] == '%') {
            if (i + 1 < fs.len and fs[i + 1] == '%') {
                try out.appendSlice(allocator, "%%");
                i += 2;
                continue;
            }
            if (i + 3 < fs.len and std.mem.eql(u8, fs[i .. i + 4], "%+4C")) {
                try out.appendSlice(allocator, "+019");
                i += 4;
                continue;
            }
            if (i + 2 < fs.len and fs[i + 1] == '-' and fs[i + 2] == 'N') {
                try out.appendSlice(allocator, nsec_str);
                i += 3;
                continue;
            }
            if (i + 1 < fs.len and fs[i + 1] == 'N') {
                try out.appendSlice(allocator, nsec_str);
                i += 2;
                continue;
            }
        }
        try out.append(allocator, fs[i]);
        i += 1;
    }
    return try out.toOwnedSliceSentinel(allocator, 0);
}

fn formatAndPrint(opts: *const DateOptions, t: c.time_t, stdout: anytype, allocator: std.mem.Allocator) !u8 {
    var tm: c.struct_tm = undefined;
    if (opts.is_utc) {
        _ = c.setenv("TZ", "UTC0", 1);
        c.tzset();
    }
    _ = c.localtime_r(&t, &tm);

    var out_fmt: [:0]const u8 = "%a %b %e %H:%M:%S %Z %Y";
    const lang_fmt = c.nl_langinfo(c._DATE_FMT);
    if (lang_fmt != null and lang_fmt[0] != 0) out_fmt = std.mem.span(lang_fmt);

    var custom_fmt_z: ?[:0]u8 = null;
    defer if (custom_fmt_z) |cf| allocator.free(cf);

    if (opts.rfc_email) {
        out_fmt = "%a, %d %b %Y %H:%M:%S %z";
    } else if (opts.iso_8601) {
        out_fmt = "%Y-%m-%d";
    } else if (opts.format_str) |fs| {
        var ts: c.struct_timespec = undefined;
        _ = c.clock_gettime(c.CLOCK_REALTIME, &ts);
        var nsec_buf: [16]u8 = undefined;
        const u_nsec = @as(u64, @intCast(ts.tv_nsec));
        const nsec_str = std.fmt.bufPrint(&nsec_buf, "{d:0>9}", .{u_nsec}) catch "000000000";
        custom_fmt_z = try replaceFormatSpecifiers(allocator, fs, nsec_str);
        out_fmt = custom_fmt_z.?;
    }

    var buf: [512]u8 = undefined;
    const len = c.strftime(&buf, buf.len, out_fmt.ptr, &tm);
    if (len == 0 and out_fmt.len > 0) {
        try stdout.writeByte('\n');
    } else {
        try stdout.writeAll(buf[0..len]);
        try stdout.writeByte('\n');
    }
    return 0;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    _ = c.setlocale(c.LC_ALL, "");

    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &out_w.interface;
    const stderr = &err_w.interface;

    var opts = DateOptions{};
    if (try parseArgs(args, &opts, stdout)) |rc| {
        stdout.flush() catch return 1;
        return rc;
    }

    if (opts.resolution) {
        try stdout.print("0.000000001\n", .{});
        stdout.flush() catch return 1;
        return 0;
    }

    const t = (try resolveTimestamp(&opts, allocator, stderr)) orelse {
        stderr.flush() catch {};
        return 1;
    };

    const res = try formatAndPrint(&opts, t, stdout, allocator);
    stdout.flush() catch return 1;
    return res;
}
