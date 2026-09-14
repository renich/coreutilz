const std = @import("std");
const errors = @import("../../utils/errors.zig");

pub const GroupingMethod = enum {
    none,
    prepend,
    append,
    separate,
    both,
};

pub const AllRepeatedMethod = enum {
    none,
    prepend,
    separate,
};

pub const Options = struct {
    count: bool = false,
    repeated: bool = false,
    all_repeated: bool = false,
    all_repeated_method: AllRepeatedMethod = .none,
    unique_only: bool = false,
    ignore_case: bool = false,
    grouping: GroupingMethod = .none,
    skip_fields: usize = 0,
    skip_chars: usize = 0,
    check_chars: ?usize = null,
    zero_terminated: bool = false,
    input_file: ?[]const u8 = null,
    output_file: ?[]const u8 = null,
};

pub fn printUsage(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: uniq [OPTION]... [INPUT [OUTPUT]]
        \\Filter adjacent matching lines from INPUT (or standard input),
        \\writing to OUTPUT (or standard output).
        \\
        \\With no options, matching lines are merged to the first occurrence.
        \\
        \\Mandatory arguments to long options are mandatory for short options too.
        \\  -c, --count           prefix lines by the number of occurrences
        \\  -d, --repeated        only print duplicate lines, one for each group
        \\  -D                    print all duplicate lines
        \\      --all-repeated[=METHOD]  like -D, but allow separating groups
        \\      --group[=METHOD]  show all items, separating groups with an empty line;
        \\                        METHOD={separate(default),prepend,append,both}
        \\  -f, --skip-fields=N   avoid comparing the first N fields
        \\  -i, --ignore-case     ignore differences in case when comparing
        \\  -s, --skip-chars=N    avoid comparing the first N characters
        \\  -u, --unique          only print unique lines
        \\  -w, --check-chars=N   compare no more than N characters in lines
        \\  -z, --zero-terminated line delimiter is NUL, not newline
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
    );
}

fn isDigits(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |ch| {
        if (!std.ascii.isDigit(ch)) return false;
    }
    return true;
}

fn parseNumber(s: []const u8) !usize {
    return std.fmt.parseInt(usize, s, 10) catch |err| switch (err) {
        error.Overflow => std.math.maxInt(usize),
        else => return err,
    };
}

fn parseAllRepeated(arg: []const u8, opt: *Options, stderr: anytype) !?u8 {
    if (std.mem.eql(u8, arg, "--all-repeated") or std.mem.eql(u8, arg, "--all-repeated=none")) {
        opt.all_repeated = true;
        opt.all_repeated_method = .none;
        return null;
    }
    if (!std.mem.startsWith(u8, arg, "--all-repeated=")) return null;
    const val = arg["--all-repeated=".len..];
    if (std.mem.eql(u8, val, "prepend")) {
        opt.all_repeated = true;
        opt.all_repeated_method = .prepend;
    } else if (std.mem.eql(u8, val, "separate")) {
        opt.all_repeated = true;
        opt.all_repeated_method = .separate;
    } else {
        try stderr.print(
            \\uniq: invalid argument '{s}' for '--all-repeated'
            \\Valid arguments are:
            \\  - 'none'
            \\  - 'prepend'
            \\  - 'separate'
            \\Try 'uniq --help' for more information.
            \\
        , .{val});
        return 1;
    }
    return null;
}

fn parseGroupOption(arg: []const u8, opt: *Options, stderr: anytype) !?u8 {
    if (std.mem.eql(u8, arg, "--group")) {
        opt.grouping = .separate;
        return null;
    }
    if (!std.mem.startsWith(u8, arg, "--group=")) return null;
    const val = arg["--group=".len..];
    if (std.mem.eql(u8, val, "prepend")) {
        opt.grouping = .prepend;
    } else if (std.mem.eql(u8, val, "append")) {
        opt.grouping = .append;
    } else if (std.mem.eql(u8, val, "separate")) {
        opt.grouping = .separate;
    } else if (std.mem.eql(u8, val, "both")) {
        opt.grouping = .both;
    } else {
        try stderr.print(
            \\uniq: invalid argument '{s}' for '--group'
            \\Valid arguments are:
            \\  - 'prepend'
            \\  - 'append'
            \\  - 'separate'
            \\  - 'both'
            \\Try 'uniq --help' for more information.
            \\
        , .{val});
        return 1;
    }
    return null;
}

fn parseLongOption(arg: []const u8, opt: *Options) bool {
    if (std.mem.eql(u8, arg, "--count")) {
        opt.count = true;
    } else if (std.mem.eql(u8, arg, "--repeated")) {
        opt.repeated = true;
    } else if (std.mem.eql(u8, arg, "--unique")) {
        opt.unique_only = true;
    } else if (std.mem.eql(u8, arg, "--ignore-case")) {
        opt.ignore_case = true;
    } else if (std.mem.eql(u8, arg, "--zero-terminated")) {
        opt.zero_terminated = true;
    } else {
        return false;
    }
    return true;
}

fn parseShortArg(args: [][]const u8, i: *usize, rest: []const u8) !usize {
    if (rest.len > 0) return try parseNumber(rest);
    if (i.* + 1 < args.len) {
        i.* += 1;
        return try parseNumber(args[i.*]);
    }
    return 0;
}

fn parseShortFlags(args: [][]const u8, i: *usize, opt: *Options, stderr: anytype) !?u8 {
    const arg = args[i.*];
    var j: usize = 1;
    while (j < arg.len) : (j += 1) {
        switch (arg[j]) {
            'c' => opt.count = true,
            'd' => opt.repeated = true,
            'D' => {
                opt.all_repeated = true;
                opt.all_repeated_method = .none;
            },
            'i' => opt.ignore_case = true,
            'u' => opt.unique_only = true,
            'z' => opt.zero_terminated = true,
            'f' => {
                opt.skip_fields = try parseShortArg(args, i, arg[j + 1 ..]);
                return null;
            },
            's' => {
                opt.skip_chars = try parseShortArg(args, i, arg[j + 1 ..]);
                return null;
            },
            'w' => {
                opt.check_chars = try parseShortArg(args, i, arg[j + 1 ..]);
                return null;
            },
            '0'...'9' => {
                opt.skip_fields = try parseNumber(arg[j..]);
                return null;
            },
            else => {
                try stderr.print("uniq: unrecognized option '{s}'\n", .{arg});
                return 1;
            },
        }
    }
    return null;
}

fn validateOptions(opt: *const Options, stderr: anytype) !bool {
    if (opt.grouping != .none and (opt.count or opt.repeated or opt.all_repeated or opt.unique_only)) {
        try stderr.writeAll("uniq: --group is mutually exclusive with -c/-d/-D/-u\nTry 'uniq --help' for more information.\n");
        return true;
    }
    if (opt.all_repeated and opt.count) {
        try stderr.writeAll("uniq: printing all duplicated lines and repeat counts is meaningless\nTry 'uniq --help' for more information.\n");
        return true;
    }
    return false;
}

fn handleFileOperand(arg: []const u8, opt: *Options, stderr: anytype) !?u8 {
    if (opt.input_file == null) {
        opt.input_file = arg;
    } else if (opt.output_file == null) {
        opt.output_file = arg;
    } else {
        try stderr.print("uniq: extra operand '{s}'\n", .{arg});
        return 1;
    }
    return null;
}

pub fn parseArgs(args: [][]const u8, opt: *Options, stdout: anytype, stderr: anytype) !?u8 {
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            try printUsage(stdout);
            stdout.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try errors.printVersion(stdout, "uniq", "0.1.0");
            stdout.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            while (i < args.len) : (i += 1) {
                if (try handleFileOperand(args[i], opt, stderr)) |code| return code;
            }
            break;
        } else if (std.mem.startsWith(u8, arg, "+") and isDigits(arg[1..])) {
            opt.skip_chars = try parseNumber(arg[1..]);
        } else if (try parseGroupOption(arg, opt, stderr)) |code| {
            return code;
        } else if (std.mem.startsWith(u8, arg, "--group")) {
            continue;
        } else if (try parseAllRepeated(arg, opt, stderr)) |code| {
            return code;
        } else if (std.mem.startsWith(u8, arg, "--all-repeated")) {
            continue;
        } else if (parseLongOption(arg, opt)) {
            continue;
        } else if (std.mem.startsWith(u8, arg, "--skip-fields=")) {
            opt.skip_fields = try parseNumber(arg["--skip-fields=".len..]);
        } else if (std.mem.startsWith(u8, arg, "--skip-chars=")) {
            opt.skip_chars = try parseNumber(arg["--skip-chars=".len..]);
        } else if (std.mem.startsWith(u8, arg, "--check-chars=")) {
            opt.check_chars = try parseNumber(arg["--check-chars=".len..]);
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1 and !std.mem.eql(u8, arg, "-")) {
            if (try parseShortFlags(args, &i, opt, stderr)) |code| return code;
        } else if (try handleFileOperand(arg, opt, stderr)) |code| {
            return code;
        }
    }
    if (try validateOptions(opt, stderr)) return 1;
    return null;
}
