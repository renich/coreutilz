const std = @import("std");
const errors = @import("../../utils/errors.zig");

pub const OrderCheck = enum {
    default,
    enabled,
    disabled,
};

pub const Options = struct {
    suppress_col1: bool = false,
    suppress_col2: bool = false,
    suppress_col3: bool = false,
    order_check: OrderCheck = .default,
    total: bool = false,
    zero_terminated: bool = false,
    delimiter: []const u8 = "\t",
    file1: ?[]const u8 = null,
    file2: ?[]const u8 = null,
};

pub fn printUsage(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: comm [OPTION]... FILE1 FILE2
        \\Compare sorted files FILE1 and FILE2 line by line.
        \\
        \\When FILE1 or FILE2 (not both) is -, read standard input.
        \\
        \\With no options, produce three-column output. Column one contains
        \\lines unique to FILE1, column two contains lines unique to FILE2,
        \\and column three contains lines common to both files.
        \\
        \\  -1                      suppress column 1 (lines unique to FILE1)
        \\  -2                      suppress column 2 (lines unique to FILE2)
        \\  -3                      suppress column 3 (lines that appear in both files)
        \\      --check-order       check that the input is correctly sorted
        \\      --nocheck-order     do not check that the input is correctly sorted
        \\      --output-delimiter=STR  separate columns with STR
        \\      --total             output a summary
        \\  -z, --zero-terminated   line delimiter is NUL, not newline
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
    );
}

fn parseShortFlags(arg: []const u8, opt: *Options) bool {
    var valid = true;
    for (arg[1..]) |ch| {
        switch (ch) {
            '1' => opt.suppress_col1 = true,
            '2' => opt.suppress_col2 = true,
            '3' => opt.suppress_col3 = true,
            'z' => opt.zero_terminated = true,
            else => {
                valid = false;
                break;
            },
        }
    }
    return valid;
}

fn parseDelimiter(arg: []const u8, opt: *Options, specified: *?[]const u8, stderr: anytype) !?u8 {
    if (!std.mem.startsWith(u8, arg, "--output-delimiter=")) return null;
    const val = arg["--output-delimiter=".len..];
    if (specified.*) |prev| {
        if (!std.mem.eql(u8, prev, val)) {
            try stderr.writeAll("comm: multiple output delimiters specified\n");
            return 1;
        }
    } else {
        specified.* = val;
    }
    opt.delimiter = if (val.len == 0) "\x00" else val;
    return null;
}

fn parseLongOption(arg: []const u8, opt: *Options) bool {
    if (std.mem.eql(u8, arg, "--check-order")) {
        opt.order_check = .enabled;
    } else if (std.mem.eql(u8, arg, "--nocheck-order")) {
        opt.order_check = .disabled;
    } else if (std.mem.eql(u8, arg, "--total")) {
        opt.total = true;
    } else if (std.mem.eql(u8, arg, "--zero-terminated")) {
        opt.zero_terminated = true;
    } else {
        return false;
    }
    return true;
}

fn handleFileOperand(arg: []const u8, opt: *Options, stderr: anytype) !?u8 {
    if (opt.file1 == null) {
        opt.file1 = arg;
    } else if (opt.file2 == null) {
        opt.file2 = arg;
    } else {
        try stderr.print(
            \\comm: extra operand '{s}'
            \\Try 'comm --help' for more information.
            \\
        , .{arg});
        return 1;
    }
    return null;
}

pub fn parseArgs(args: [][]const u8, opt: *Options, stdout: anytype, stderr: anytype) !?u8 {
    if (args.len <= 1) {
        try stderr.writeAll("comm: missing operand\nTry 'comm --help' for more information.\n");
        return 1;
    }
    var specified_delim: ?[]const u8 = null;
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            try printUsage(stdout);
            stdout.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try errors.printVersion(stdout, "comm", "0.1.0");
            stdout.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            while (i < args.len) : (i += 1) {
                if (try handleFileOperand(args[i], opt, stderr)) |code| return code;
            }
            break;
        } else if (try parseDelimiter(arg, opt, &specified_delim, stderr)) |code| {
            return code;
        } else if (std.mem.startsWith(u8, arg, "--output-delimiter=")) {
            continue;
        } else if (parseLongOption(arg, opt)) {
            continue;
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1 and !std.mem.eql(u8, arg, "-")) {
            if (!parseShortFlags(arg, opt)) {
                try stderr.print("comm: unrecognized option '{s}'\n", .{arg});
                return 1;
            }
        } else if (try handleFileOperand(arg, opt, stderr)) |code| {
            return code;
        }
    }
    if (opt.file1 == null) {
        try stderr.writeAll("comm: missing operand\nTry 'comm --help' for more information.\n");
        return 1;
    }
    if (opt.file2 == null) {
        try stderr.print("comm: missing operand after '{s}'\nTry 'comm --help' for more information.\n", .{opt.file1.?});
        return 1;
    }
    return null;
}
