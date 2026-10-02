const std = @import("std");
const errors = @import("../../utils/errors.zig");
const parse_units = @import("parse_units.zig");

pub const FollowMode = enum { descriptor, name };

pub const Options = struct {
    lines: ?usize = 10,
    bytes: ?usize = null,
    from_start: bool = false,
    zero_terminated: bool = false,
    quiet: bool = false,
    verbose: bool = false,
    follow: ?FollowMode = null,
    retry: bool = false,
    sleep_interval: f64 = 1.0,
    pid: ?c_int = null,
    debug: bool = false,
    disable_inotify: bool = false,
    files: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) Options {
        _ = allocator;
        return .{ .files = std.ArrayList([]const u8).empty };
    }

    pub fn deinit(self: *Options, allocator: std.mem.Allocator) void {
        self.files.deinit(allocator);
    }
};

pub const ParseResult = union(enum) {
    ok: Options,
    help,
    version,
    err: u8,
};

fn isObsoleteContext(args: [][]const u8) bool {
    if (args.len < 2 or args.len > 4) return false;
    if (args.len == 2) return true;
    if (args.len == 3) return !(args[2].len > 1 and args[2][0] == '-');
    return std.mem.eql(u8, args[2], "--");
}

fn parseObsoleteOption(arg: []const u8, opts: *Options) bool {
    if (arg.len < 2) return false;
    const sign = arg[0];
    if (sign != '+' and sign != '-') return false;
    var p: usize = 1;
    var has_digits = false;
    while (p < arg.len and std.ascii.isDigit(arg[p])) : (p += 1) {
        has_digits = true;
    }
    if (sign == '-' and !has_digits and !(p < arg.len and (arg[p] == 'l' or arg[p] == 'b'))) return false;
    var n: usize = if (has_digits) std.fmt.parseUnsigned(usize, arg[1..p], 10) catch std.math.maxInt(usize) else 10;
    var count_lines = true;
    if (p < arg.len) {
        if (arg[p] == 'b') {
            n = std.math.mul(usize, n, 512) catch std.math.maxInt(usize);
            count_lines = false;
            p += 1;
        } else if (arg[p] == 'c') {
            count_lines = false;
            p += 1;
        } else if (arg[p] == 'l') {
            count_lines = true;
            p += 1;
        }
    }
    if (p < arg.len and arg[p] == 'f') {
        opts.follow = .descriptor;
        p += 1;
    }
    if (p != arg.len) return false;
    opts.from_start = (sign == '+');
    opts.lines = if (count_lines) n else null;
    opts.bytes = if (!count_lines) n else null;
    return true;
}

fn handleLongOption(long_name: []const u8, full_arg: []const u8, opts: *Options, stderr: anytype) ?ParseResult {
    if (std.mem.eql(u8, long_name, "help")) return .help;
    if (std.mem.eql(u8, long_name, "version")) return .version;
    if (std.mem.eql(u8, long_name, "debug")) {
        opts.debug = true;
        return null;
    }
    if (std.mem.eql(u8, long_name, "disable-inotify")) {
        opts.disable_inotify = true;
        return null;
    }
    if (std.mem.startsWith(u8, long_name, "max-unchanged-stats")) return null;
    if (std.mem.eql(u8, long_name, "zero-terminated")) {
        opts.zero_terminated = true;
        return null;
    }
    if (std.mem.eql(u8, long_name, "quiet") or std.mem.eql(u8, long_name, "silent")) {
        opts.quiet = true;
        opts.verbose = false;
        return null;
    }
    if (std.mem.eql(u8, long_name, "verbose")) {
        opts.verbose = true;
        opts.quiet = false;
        return null;
    }
    if (std.mem.eql(u8, long_name, "retry")) {
        opts.retry = true;
        return null;
    }
    if (std.mem.eql(u8, long_name, "follow") or std.mem.eql(u8, long_name, "follow=descriptor")) {
        opts.follow = .descriptor;
        return null;
    }
    if (std.mem.eql(u8, long_name, "follow=name")) {
        opts.follow = .name;
        return null;
    }
    return handleLongValOption(long_name, full_arg, opts, stderr);
}

fn handleLongValOption(long_name: []const u8, full_arg: []const u8, opts: *Options, stderr: anytype) ?ParseResult {
    if (std.mem.startsWith(u8, long_name, "lines=")) {
        var raw: []const u8 = "";
        if (parse_units.parseOffset(long_name["lines=".len..], &opts.from_start, &raw)) |n| {
            opts.lines = n;
            opts.bytes = null;
            return null;
        }
        stderr.print("tail: invalid number of lines: '{s}'\n", .{raw}) catch {};
        return .{ .err = 1 };
    }
    if (std.mem.startsWith(u8, long_name, "bytes=")) {
        var raw: []const u8 = "";
        if (parse_units.parseOffset(long_name["bytes=".len..], &opts.from_start, &raw)) |c| {
            opts.bytes = c;
            opts.lines = null;
            return null;
        }
        stderr.print("tail: invalid number of bytes: '{s}'\n", .{raw}) catch {};
        return .{ .err = 1 };
    }
    if (std.mem.startsWith(u8, long_name, "sleep-interval=") or std.mem.startsWith(u8, long_name, "sleep=")) {
        const pfx = if (std.mem.startsWith(u8, long_name, "sleep-interval=")) "sleep-interval=".len else "sleep=".len;
        opts.sleep_interval = std.fmt.parseFloat(f64, long_name[pfx..]) catch 1.0;
        return null;
    }
    if (std.mem.startsWith(u8, long_name, "pid=")) {
        opts.pid = std.fmt.parseInt(c_int, long_name["pid=".len..], 10) catch null;
        return null;
    }
    errors.printUnrecognizedOption(stderr, "tail", full_arg) catch {};
    return .{ .err = 1 };
}

fn handleShortOption(args: [][]const u8, i: *usize, opts: *Options, stderr: anytype) ?ParseResult {
    const arg = args[i.*];
    var j: usize = 1;
    while (j < arg.len) : (j += 1) {
        switch (arg[j]) {
            'z' => opts.zero_terminated = true,
            'q' => {
                opts.quiet = true;
                opts.verbose = false;
            },
            'v' => {
                opts.verbose = true;
                opts.quiet = false;
            },
            'f' => opts.follow = .descriptor,
            'F' => {
                opts.follow = .name;
                opts.retry = true;
            },
            'n', 'c' => return handleCountOption(args, i, &j, opts, stderr),
            's' => {
                const rest = arg[j + 1 ..];
                if (rest.len > 0) {
                    opts.sleep_interval = std.fmt.parseFloat(f64, rest) catch 1.0;
                    return null;
                } else if (i.* + 1 < args.len) {
                    i.* += 1;
                    opts.sleep_interval = std.fmt.parseFloat(f64, args[i.*]) catch 1.0;
                    return null;
                }
            },
            '0'...'9' => {
                stderr.print("tail: option used in invalid context -- {c}\n", .{arg[j]}) catch {};
                return .{ .err = 1 };
            },
            else => {
                errors.printInvalidOption(stderr, "tail", arg[j]) catch {};
                return .{ .err = 1 };
            },
        }
    }
    return null;
}

fn handleCountOption(args: [][]const u8, i: *usize, j: *usize, opts: *Options, stderr: anytype) ?ParseResult {
    const arg = args[i.*];
    const is_bytes = arg[j.*] == 'c';
    const rest = arg[j.* + 1 ..];
    var opt_val: ?[]const u8 = null;
    if (rest.len > 0) {
        opt_val = rest;
        j.* = arg.len - 1;
    } else if (i.* + 1 < args.len) {
        i.* += 1;
        opt_val = args[i.*];
    }
    var raw: []const u8 = "";
    if (opt_val) |val| {
        if (parse_units.parseOffset(val, &opts.from_start, &raw)) |num| {
            opts.lines = if (is_bytes) null else num;
            opts.bytes = if (is_bytes) num else null;
            return null;
        }
    }
    const label = if (is_bytes) "invalid number of bytes" else "invalid number of lines";
    stderr.print("tail: {s}: '{s}'\n", .{ label, raw }) catch {};
    return .{ .err = 1 };
}

fn adjustFromStart(opts: *Options) void {
    if (opts.from_start) {
        if (opts.lines) |*l| {
            if (l.* > 0 and l.* < std.math.maxInt(usize)) l.* -= 1;
        }
        if (opts.bytes) |*b| {
            if (b.* > 0 and b.* < std.math.maxInt(usize)) b.* -= 1;
        }
    }
}

pub fn parseArgs(args: [][]const u8, allocator: std.mem.Allocator, stderr: anytype) ParseResult {
    var opts = Options.init(allocator);
    errdefer opts.deinit(allocator);

    if (isObsoleteContext(args) and parseObsoleteOption(args[1], &opts)) {
        var idx: usize = 2;
        if (idx < args.len and std.mem.eql(u8, args[idx], "--")) idx += 1;
        while (idx < args.len) : (idx += 1) {
            opts.files.append(allocator, args[idx]) catch return .{ .err = 1 };
        }
        adjustFromStart(&opts);
        return .{ .ok = opts };
    }

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            while (i < args.len) : (i += 1) {
                opts.files.append(allocator, args[i]) catch return .{ .err = 1 };
            }
            break;
        }
        if (std.mem.eql(u8, arg, "-")) {
            opts.files.append(allocator, "-") catch return .{ .err = 1 };
            continue;
        }
        var dash_count: usize = 0;
        while (dash_count < arg.len and arg[dash_count] == '-') : (dash_count += 1) {}
        if (dash_count >= 2 and arg.len > dash_count) {
            if (handleLongOption(arg[dash_count..], arg, &opts, stderr)) |res| return res;
            continue;
        }
        if (arg.len > 1 and arg[0] == '-') {
            if (handleShortOption(args, &i, &opts, stderr)) |res| return res;
            continue;
        }
        opts.files.append(allocator, arg) catch return .{ .err = 1 };
    }

    adjustFromStart(&opts);
    if (opts.retry) {
        if (opts.follow == null) {
            stderr.print("tail: warning: --retry ignored; --retry is useful only when following\n", .{}) catch {};
            stderr.flush() catch {};
            opts.retry = false;
        } else if (opts.follow == .descriptor) {
            stderr.print("tail: warning: --retry only effective for the initial open\n", .{}) catch {};
            stderr.flush() catch {};
        }
    }
    return .{ .ok = opts };
}
