const std = @import("std");
const errors = @import("../../utils/errors.zig");

pub const Options = struct {
    echo: bool = false,
    input_range: ?[2]u64 = null,
    head_count: ?usize = null,
    output_file: ?[]const u8 = null,
    random_source: ?[]const u8 = null,
    repeat: bool = false,
    zero_terminated: bool = false,
    file: ?[]const u8 = null,
};

pub fn printUsage(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: shuf [OPTION]... [FILE]
        \\  or:  shuf -e [OPTION]... [ARG]...
        \\  or:  shuf -i LO-HI [OPTION]...
        \\Write a random permutation of the input lines to standard output.
        \\
        \\With no FILE, or when FILE is -, read standard input.
        \\
        \\  -e, --echo                treat each ARG as an input line
        \\  -i, --input-range=LO-HI   treat each number LO through HI as an input line
        \\  -n, --head-count=COUNT    output at most COUNT lines
        \\  -o, --output=FILE         write result to FILE instead of standard output
        \\      --random-source=FILE  get random bytes from FILE
        \\  -r, --repeat              output lines can be repeated
        \\  -z, --zero-terminated     line delimiter is NUL, not newline
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
    );
}

fn parseRange(str: []const u8) ?[2]u64 {
    const dash = std.mem.indexOfScalar(u8, str, '-') orelse return null;
    const lo_str = str[0..dash];
    const hi_str = str[dash + 1 ..];
    if (lo_str.len == 0 or hi_str.len == 0) return null;
    const lo = std.fmt.parseInt(u64, lo_str, 10) catch return null;
    const hi = std.fmt.parseInt(u64, hi_str, 10) catch return null;
    if (lo > hi) return null;
    return .{ lo, hi };
}

fn parseLineCount(val: []const u8, opt: *Options, stderr: anytype) !?u8 {
    if (val.len == 0) {
        try stderr.print("shuf: invalid line count: '{s}'\n", .{val});
        return 1;
    }
    for (val) |ch| {
        if (!std.ascii.isDigit(ch)) {
            try stderr.print("shuf: invalid line count: '{s}'\n", .{val});
            return 1;
        }
    }
    const count = std.fmt.parseInt(usize, val, 10) catch std.math.maxInt(usize);
    if (opt.head_count) |cur| {
        opt.head_count = @min(cur, count);
    } else {
        opt.head_count = count;
    }
    return null;
}

fn parseLongArg(args: [][]const u8, i: *usize, pfx: []const u8) ?[]const u8 {
    const arg = args[i.*];
    if (std.mem.startsWith(u8, arg, pfx)) {
        if (arg.len > pfx.len and arg[pfx.len] == '=') return arg[pfx.len + 1 ..];
        if (arg.len == pfx.len) {
            if (i.* + 1 < args.len) {
                i.* += 1;
                return args[i.*];
            }
            return "";
        }
    }
    return null;
}

fn handleRangeVal(val: []const u8, opt: *Options, seen_i: *bool, stderr: anytype) !?u8 {
    if (seen_i.*) {
        try stderr.writeAll("shuf: multiple -i options specified\n");
        return 1;
    }
    seen_i.* = true;
    const range = parseRange(val) orelse {
        try stderr.print("shuf: invalid input range: '{s}'\n", .{val});
        return 1;
    };
    opt.input_range = range;
    return null;
}

fn handleOutputVal(val: []const u8, opt: *Options, seen_o: *bool, stderr: anytype) !?u8 {
    if (seen_o.* and !std.mem.eql(u8, opt.output_file orelse "", val)) {
        try stderr.writeAll("shuf: multiple -o options specified\n");
        return 1;
    }
    seen_o.* = true;
    opt.output_file = val;
    return null;
}

fn handleRandomSourceVal(val: []const u8, opt: *Options, seen_rs: *bool, stderr: anytype) !?u8 {
    if (seen_rs.* and !std.mem.eql(u8, opt.random_source orelse "", val)) {
        try stderr.writeAll("shuf: multiple --random-source options specified\n");
        return 1;
    }
    seen_rs.* = true;
    opt.random_source = val;
    return null;
}

fn parseShortFlags(
    args: [][]const u8,
    i: *usize,
    opt: *Options,
    seen_i: *bool,
    seen_o: *bool,
    stderr: anytype,
) !?u8 {
    const arg = args[i.*];
    var j: usize = 1;
    while (j < arg.len) : (j += 1) {
        switch (arg[j]) {
            'e' => opt.echo = true,
            'r' => opt.repeat = true,
            'z' => opt.zero_terminated = true,
            'n' => {
                const val = if (j + 1 < arg.len) arg[j + 1 ..] else if (i.* + 1 < args.len) blk: {
                    i.* += 1;
                    break :blk args[i.*];
                } else "";
                return try parseLineCount(val, opt, stderr);
            },
            'i' => {
                const val = if (j + 1 < arg.len) arg[j + 1 ..] else if (i.* + 1 < args.len) blk: {
                    i.* += 1;
                    break :blk args[i.*];
                } else "";
                return try handleRangeVal(val, opt, seen_i, stderr);
            },
            'o' => {
                const val = if (j + 1 < arg.len) arg[j + 1 ..] else if (i.* + 1 < args.len) blk: {
                    i.* += 1;
                    break :blk args[i.*];
                } else "";
                return try handleOutputVal(val, opt, seen_o, stderr);
            },
            else => {
                try stderr.print("shuf: unrecognized option '{s}'\n", .{arg});
                return 1;
            },
        }
    }
    return null;
}

fn validateConflicts(
    opt: *const Options,
    operands: []const []const u8,
    stderr: anytype,
) !bool {
    if (opt.echo and opt.input_range != null) {
        try stderr.writeAll("shuf: cannot combine -e and -i options\nTry 'shuf --help' for more information.\n");
        return true;
    }
    if (opt.input_range != null and operands.len > 0) {
        try stderr.print("shuf: extra operand '{s}'\nTry 'shuf --help' for more information.\n", .{operands[0]});
        return true;
    }
    if (!opt.echo and operands.len > 1) {
        try stderr.print("shuf: extra operand '{s}'\nTry 'shuf --help' for more information.\n", .{operands[1]});
        return true;
    }
    return false;
}

pub fn parseArgs(
    args: [][]const u8,
    opt: *Options,
    operands: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) !?u8 {
    var seen_i = false;
    var seen_o = false;
    var seen_rs = false;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            try printUsage(stdout);
            stdout.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try errors.printVersion(stdout, "shuf", "0.1.0");
            stdout.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            while (i < args.len) : (i += 1) try operands.append(allocator, args[i]);
            break;
        } else if (std.mem.startsWith(u8, arg, "--rep")) {
            opt.repeat = true;
        } else if (std.mem.startsWith(u8, arg, "--echo")) {
            opt.echo = true;
        } else if (std.mem.startsWith(u8, arg, "--zero")) {
            opt.zero_terminated = true;
        } else if (parseLongArg(args, &i, "--input-range")) |val| {
            if (try handleRangeVal(val, opt, &seen_i, stderr)) |c| return c;
        } else if (parseLongArg(args, &i, "--head-count")) |val| {
            if (try parseLineCount(val, opt, stderr)) |c| return c;
        } else if (parseLongArg(args, &i, "--output")) |val| {
            if (try handleOutputVal(val, opt, &seen_o, stderr)) |c| return c;
        } else if (parseLongArg(args, &i, "--random-source")) |val| {
            if (try handleRandomSourceVal(val, opt, &seen_rs, stderr)) |c| return c;
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1 and !std.mem.eql(u8, arg, "-")) {
            if (try parseShortFlags(args, &i, opt, &seen_i, &seen_o, stderr)) |c| return c;
        } else {
            try operands.append(allocator, arg);
        }
    }
    if (try validateConflicts(opt, operands.items, stderr)) return 1;
    return null;
}
