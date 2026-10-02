const std = @import("std");
const errors = @import("../../utils/errors.zig");
pub const args_number = @import("args_number.zig");

pub const ChunkMode = args_number.ChunkMode;
pub const NumberSpec = args_number.NumberSpec;

pub const SplitMode = union(enum) {
    lines: usize,
    bytes: usize,
    line_bytes: usize,
    number: NumberSpec,
};

pub const SuffixType = enum {
    alpha,
    numeric,
    hex,
};

pub const Options = struct {
    mode: SplitMode = .{ .lines = 1000 },
    suffix_len: usize = 2,
    suffix_len_explicit: bool = false,
    suffix_type: SuffixType = .alpha,
    auto_extend: bool = true,
    start_from: usize = 0,
    additional_suffix: []const u8 = "",
    elide_empty: bool = false,
    separator: u8 = '\n',
    separator_specified: bool = false,
    unbuffered: bool = false,
    verbose: bool = false,
    filter_cmd: ?[]const u8 = null,
    input_file: ?[]const u8 = null,
    prefix: []const u8 = "x",
};

pub const ParseResult = union(enum) {
    ok: Options,
    help,
    version,
    err: u8,
};

pub fn parseMultiplier(str: []const u8) ?usize {
    if (str.len == 0) return null;
    var end: usize = 0;
    while (end < str.len and std.ascii.isDigit(str[end])) : (end += 1) {}
    if (end == 0) return null;
    const base = std.fmt.parseUnsigned(u128, str[0..end], 10) catch return null;
    const suffix = str[end..];
    var mult: u128 = 1;
    if (suffix.len > 0) {
        if (std.mem.eql(u8, suffix, "b")) mult = 512 else if (std.mem.eql(u8, suffix, "c")) mult = 1 else if (std.mem.eql(u8, suffix, "w")) mult = 2 else if (std.mem.eql(u8, suffix, "k") or std.mem.eql(u8, suffix, "K") or std.mem.eql(u8, suffix, "KiB")) mult = 1024 else if (std.mem.eql(u8, suffix, "m") or std.mem.eql(u8, suffix, "M") or std.mem.eql(u8, suffix, "MiB")) mult = 1024 * 1024 else if (std.mem.eql(u8, suffix, "g") or std.mem.eql(u8, suffix, "G") or std.mem.eql(u8, suffix, "GiB")) mult = 1024 * 1024 * 1024 else if (std.mem.eql(u8, suffix, "KB")) mult = 1000 else if (std.mem.eql(u8, suffix, "MB")) mult = 1000 * 1000 else if (std.mem.eql(u8, suffix, "GB")) mult = 1000 * 1000 * 1000 else return null;
    }
    const total = std.math.mul(u128, base, mult) catch std.math.maxInt(usize);
    return @intCast(@min(total, @as(u128, std.math.maxInt(usize))));
}

fn setSeparator(val: []const u8, opts: *Options, stderr: anytype) ?ParseResult {
    const sep: u8 = if (std.mem.eql(u8, val, "\\0"))
        0
    else if (val.len == 1)
        val[0]
    else {
        errors.printError(stderr, "split", "multi-character tab is not allowed") catch {};
        return .{ .err = 1 };
    };
    if (opts.separator_specified and opts.separator != sep) {
        errors.printError(stderr, "split", "incompatible separators specified") catch {};
        return .{ .err = 1 };
    }
    opts.separator = sep;
    opts.separator_specified = true;
    return null;
}

fn handleLongNumeric(arg: []const u8, opts: *Options, stderr: anytype) ?ParseResult {
    opts.suffix_type = .numeric;
    if (std.mem.indexOfScalar(u8, arg, '=')) |eq| {
        const raw_from = arg[eq + 1 ..];
        for (raw_from) |ch| {
            if (!std.ascii.isDigit(ch)) {
                errors.printError(stderr, "split", "invalid numeric start value") catch {};
                return .{ .err = 1 };
            }
        }
        opts.start_from = std.fmt.parseUnsigned(usize, raw_from, 10) catch {
            errors.printError(stderr, "split", "invalid numeric start value") catch {};
            return .{ .err = 1 };
        };
        opts.auto_extend = false;
    }
    return null;
}

fn handleLongHex(arg: []const u8, opts: *Options, stderr: anytype) ?ParseResult {
    opts.suffix_type = .hex;
    if (std.mem.indexOfScalar(u8, arg, '=')) |eq| {
        const raw_from = arg[eq + 1 ..];
        for (raw_from) |ch| {
            if (!std.ascii.isHex(ch)) {
                errors.printError(stderr, "split", "invalid hex start value") catch {};
                return .{ .err = 1 };
            }
        }
        opts.start_from = std.fmt.parseUnsigned(usize, raw_from, 16) catch {
            errors.printError(stderr, "split", "invalid hex start value") catch {};
            return .{ .err = 1 };
        };
        opts.auto_extend = false;
    }
    return null;
}

const ConfigResult = enum { ok, err, none };

fn handleLongConfig(arg: []const u8, opts: *Options, stderr: anytype) ConfigResult {
    if (std.mem.eql(u8, arg, "--elide-empty-files")) {
        opts.elide_empty = true;
        return .ok;
    }
    if (std.mem.eql(u8, arg, "--unbuffered")) {
        opts.unbuffered = true;
        return .ok;
    }
    if (std.mem.eql(u8, arg, "--verbose")) {
        opts.verbose = true;
        return .ok;
    }
    if (std.mem.startsWith(u8, arg, "--additional-suffix=")) {
        opts.additional_suffix = arg["--additional-suffix=".len..];
        return .ok;
    }
    if (std.mem.startsWith(u8, arg, "--filter=")) {
        opts.filter_cmd = arg["--filter=".len..];
        return .ok;
    }
    if (std.mem.startsWith(u8, arg, "--suffix-length=")) {
        opts.suffix_len = std.fmt.parseUnsigned(usize, arg["--suffix-length=".len..], 10) catch 2;
        opts.suffix_len_explicit = true;
        opts.auto_extend = false;
        return .ok;
    }
    if (std.mem.startsWith(u8, arg, "--numeric")) {
        if (handleLongNumeric(arg, opts, stderr)) |_| return .err;
        return .ok;
    }
    if (std.mem.startsWith(u8, arg, "--hex")) {
        if (handleLongHex(arg, opts, stderr)) |_| return .err;
        return .ok;
    }
    return .none;
}

fn handleLong(arg: []const u8, opts: *Options, stderr: anytype) ?ParseResult {
    if (std.mem.eql(u8, arg, "--help")) return .help;
    if (std.mem.eql(u8, arg, "--version")) return .version;
    if (std.mem.startsWith(u8, arg, "---io")) return null;
    switch (handleLongConfig(arg, opts, stderr)) {
        .ok => return null,
        .err => return .{ .err = 1 },
        .none => {},
    }

    if (std.mem.startsWith(u8, arg, "--lines=")) {
        const n = parseMultiplier(arg["--lines=".len..]) orelse {
            errors.printError(stderr, "split", "invalid number of lines") catch {};
            return .{ .err = 1 };
        };
        if (n == 0) return .{ .err = 1 };
        opts.mode = .{ .lines = n };
        return null;
    }
    if (std.mem.startsWith(u8, arg, "--bytes=")) {
        const b = parseMultiplier(arg["--bytes=".len..]) orelse {
            errors.printError(stderr, "split", "invalid number of bytes") catch {};
            return .{ .err = 1 };
        };
        if (b == 0) return .{ .err = 1 };
        opts.mode = .{ .bytes = b };
        return null;
    }
    if (std.mem.startsWith(u8, arg, "--line-bytes=")) {
        const c = parseMultiplier(arg["--line-bytes=".len..]) orelse {
            errors.printError(stderr, "split", "invalid number of bytes") catch {};
            return .{ .err = 1 };
        };
        if (c == 0) return .{ .err = 1 };
        opts.mode = .{ .line_bytes = c };
        return null;
    }
    if (std.mem.startsWith(u8, arg, "--number=")) {
        const spec = args_number.parseNumberSpec(arg["--number=".len..], stderr) orelse return .{ .err = 1 };
        opts.mode = .{ .number = spec };
        return null;
    }
    errors.printUnrecognizedOption(stderr, "split", arg) catch {};
    return .{ .err = 1 };
}

fn nextArg(args: [][]const u8, i: usize, j: usize) ?[]const u8 {
    if (j + 1 < args[i].len) return args[i][j + 1 ..];
    if (i + 1 < args.len) return args[i + 1];
    return null;
}

fn handleShort(args: [][]const u8, i: usize, opts: *Options, stderr: anytype) ?ParseResult {
    const arg = args[i];
    if (arg.len > 1 and std.ascii.isDigit(arg[1])) {
        const n = parseMultiplier(arg[1..]) orelse return .{ .err = 1 };
        if (n == 0) return .{ .err = 1 };
        opts.mode = .{ .lines = n };
        return null;
    }

    var j: usize = 1;
    while (j < arg.len) : (j += 1) {
        switch (arg[j]) {
            'd' => {
                opts.suffix_type = .numeric;
                if (j + 1 < arg.len and std.ascii.isDigit(arg[j + 1])) {
                    opts.start_from = std.fmt.parseUnsigned(usize, arg[j + 1 ..], 10) catch 0;
                    opts.auto_extend = false;
                    break;
                }
            },
            'x' => {
                opts.suffix_type = .hex;
                if (j + 1 < arg.len and std.ascii.isHex(arg[j + 1])) {
                    opts.start_from = std.fmt.parseUnsigned(usize, arg[j + 1 ..], 16) catch 0;
                    opts.auto_extend = false;
                    break;
                }
            },
            'e' => opts.elide_empty = true,
            'u' => opts.unbuffered = true,
            'a' => {
                const val = nextArg(args, i, j) orelse return .{ .err = 1 };
                opts.suffix_len = std.fmt.parseUnsigned(usize, val, 10) catch 2;
                opts.suffix_len_explicit = true;
                opts.auto_extend = false;
                break;
            },
            'l' => {
                const val = nextArg(args, i, j) orelse return .{ .err = 1 };
                const n = parseMultiplier(val) orelse return .{ .err = 1 };
                if (n == 0) return .{ .err = 1 };
                opts.mode = .{ .lines = n };
                break;
            },
            'b' => {
                const val = nextArg(args, i, j) orelse return .{ .err = 1 };
                const b = parseMultiplier(val) orelse return .{ .err = 1 };
                if (b == 0) return .{ .err = 1 };
                opts.mode = .{ .bytes = b };
                break;
            },
            'C' => {
                const val = nextArg(args, i, j) orelse return .{ .err = 1 };
                const c = parseMultiplier(val) orelse return .{ .err = 1 };
                if (c == 0) return .{ .err = 1 };
                opts.mode = .{ .line_bytes = c };
                break;
            },
            'n' => {
                const val = nextArg(args, i, j) orelse return .{ .err = 1 };
                const spec = args_number.parseNumberSpec(val, stderr) orelse return .{ .err = 1 };
                opts.mode = .{ .number = spec };
                break;
            },
            't' => {
                const val = nextArg(args, i, j) orelse return .{ .err = 1 };
                if (setSeparator(val, opts, stderr)) |res| return res;
                break;
            },
            else => {
                errors.printInvalidOption(stderr, "split", arg[j]) catch {};
                return .{ .err = 1 };
            },
        }
    }
    return null;
}

pub fn parseArgs(args: [][]const u8, stderr: anytype) ParseResult {
    var opts = Options{};
    var operands_list: [2][]const u8 = undefined;
    var op_count: usize = 0;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            while (i < args.len) : (i += 1) {
                if (op_count < 2) {
                    operands_list[op_count] = args[i];
                    op_count += 1;
                }
            }
            break;
        }

        if (std.mem.startsWith(u8, arg, "--")) {
            if (handleLong(arg, &opts, stderr)) |res| return res;
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            if (handleShort(args, i, &opts, stderr)) |res| return res;
            if (arg.len == 2 and (arg[1] == 'a' or arg[1] == 'l' or arg[1] == 'b' or arg[1] == 'C' or arg[1] == 'n' or arg[1] == 't')) {
                i += 1;
            }
        } else {
            if (op_count < 2) {
                operands_list[op_count] = arg;
                op_count += 1;
            }
        }
    }

    if (op_count > 0) opts.input_file = operands_list[0];
    if (op_count > 1) opts.prefix = operands_list[1];
    return .{ .ok = opts };
}
