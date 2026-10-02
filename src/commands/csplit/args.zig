const std = @import("std");

pub const Options = struct {
    prefix: []const u8 = "xx",
    suffix_format: ?[:0]const u8 = null,
    digits: usize = 2,
    keep_files: bool = false,
    silent: bool = false,
    elide_empty: bool = false,
    suppress_matched: bool = false,
    input_file: []const u8 = "",
    pattern_args: [][]const u8 = &[_][]const u8{},
};

pub const ParseResult = union(enum) {
    ok: Options,
    help,
    version,
    err: u8,
};

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: csplit [OPTION]... FILE PATTERN...
        \\Output pieces of FILE separated by PATTERN(s) to files 'xx00', 'xx01', ...,
        \\and output byte counts of each piece to standard output.
        \\
        \\Read standard input if FILE is -.
        \\
        \\Mandatory arguments to long options are mandatory for short options too.
        \\  -b, --suffix-format=FORMAT  use sprintf FORMAT instead of %02d
        \\  -f, --prefix=PREFIX        use PREFIX instead of 'xx'
        \\  -k, --keep-files           do not remove output files on errors
        \\      --suppress-matched     suppress the lines matching PATTERN
        \\  -n, --digits=DIGITS        use specified number of digits instead of 2
        \\  -s, -q, --silent, --quiet  do not print counts of output file sizes
        \\  -z, --elide-empty-files    remove empty output files
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try writer.writeAll("csplit (coreutilz) 0.1.0\n");
}

fn validateFormat(format: []const u8, stderr: anytype) !void {
    var percent_count: usize = 0;
    var i: usize = 0;
    while (i < format.len) : (i += 1) {
        if (format[i] != '%') continue;
        i += 1;
        if (i < format.len and format[i] == '%') continue;
        if (percent_count > 0) {
            try stderr.print("csplit: too many %% conversion specifications in suffix\n", .{});
            return error.InvalidFormat;
        }
        percent_count += 1;
        i = try parseConversionSpecifier(format, i, stderr);
    }
    if (percent_count == 0) {
        try stderr.print("csplit: missing conversion specifier in suffix\n", .{});
        return error.InvalidFormat;
    }
}

fn parseConversionSpecifier(format: []const u8, start_idx: usize, stderr: anytype) !usize {
    var i = start_idx;
    var alt_flag = false;
    var thousands_flag = false;
    while (i < format.len) : (i += 1) {
        switch (format[i]) {
            '-', '0' => {},
            '#' => alt_flag = true,
            '\'' => thousands_flag = true,
            else => break,
        }
    }
    while (i < format.len and std.ascii.isDigit(format[i])) : (i += 1) {}
    if (i < format.len and format[i] == '.') {
        i += 1;
        while (i < format.len and std.ascii.isDigit(format[i])) : (i += 1) {}
    }
    if (i >= format.len) {
        try stderr.print("csplit: missing conversion specifier in suffix\n", .{});
        return error.InvalidFormat;
    }
    try checkSpecifierChar(format[i], alt_flag, thousands_flag, stderr);
    return i;
}

fn checkSpecifierChar(ch: u8, alt: bool, thousands: bool, stderr: anytype) !void {
    switch (ch) {
        'd', 'i', 'u' => {
            if (alt) {
                try stderr.print("csplit: invalid flags in conversion specification: %#{c}\n", .{ch});
                return error.InvalidFormat;
            }
        },
        'o', 'x', 'X' => {
            if (thousands) {
                try stderr.print("csplit: invalid flags in conversion specification: %'{c}\n", .{ch});
                return error.InvalidFormat;
            }
        },
        else => {
            try stderr.print("csplit: invalid conversion specifier in suffix: {c}\n", .{ch});
            return error.InvalidFormat;
        },
    }
}

pub fn parseArgs(
    allocator: std.mem.Allocator,
    args: [][]const u8,
    stderr: anytype,
) ParseResult {
    var opts = Options{};
    var idx: usize = 1;
    while (idx < args.len) {
        const arg = args[idx];
        if (std.mem.eql(u8, arg, "--")) {
            idx += 1;
            break;
        }
        if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            if (std.mem.eql(u8, arg, "--help")) return .help;
            if (std.mem.eql(u8, arg, "--version")) return .version;
            const consumed = parseOption(allocator, args, idx, &opts, stderr) catch return .{ .err = 1 };
            idx += consumed;
        } else break;
    }
    return finishPositional(args, idx, opts, stderr);
}

fn finishPositional(
    args: [][]const u8,
    idx: usize,
    initial_opts: Options,
    stderr: anytype,
) ParseResult {
    var opts = initial_opts;
    if (idx >= args.len) {
        stderr.print("csplit: missing operand\nTry 'csplit --help' for more information.\n", .{}) catch {};
        return .{ .err = 1 };
    }
    opts.input_file = args[idx];
    if (idx + 1 >= args.len) {
        stderr.print("csplit: missing operand after '{s}'\nTry 'csplit --help' for more information.\n", .{opts.input_file}) catch {};
        return .{ .err = 1 };
    }
    opts.pattern_args = args[idx + 1 ..];
    return .{ .ok = opts };
}

fn parseOption(
    allocator: std.mem.Allocator,
    args: [][]const u8,
    idx: usize,
    opts: *Options,
    stderr: anytype,
) !usize {
    const arg = args[idx];
    if (std.mem.startsWith(u8, arg, "--")) {
        return parseLongOption(allocator, args, idx, opts, stderr);
    }
    return parseShortOption(allocator, args, idx, opts, stderr);
}

fn parseLongOption(
    allocator: std.mem.Allocator,
    args: [][]const u8,
    idx: usize,
    opts: *Options,
    stderr: anytype,
) !usize {
    const arg = args[idx];
    if (std.mem.eql(u8, arg, "--keep-files")) {
        opts.keep_files = true;
        return 1;
    } else if (std.mem.eql(u8, arg, "--silent") or std.mem.eql(u8, arg, "--quiet")) {
        opts.silent = true;
        return 1;
    } else if (std.mem.eql(u8, arg, "--elide-empty-files")) {
        opts.elide_empty = true;
        return 1;
    } else if (std.mem.eql(u8, arg, "--suppress-matched") or std.mem.eql(u8, arg, "--suppress-match")) {
        opts.suppress_matched = true;
        return 1;
    } else if (std.mem.startsWith(u8, arg, "--prefix=")) {
        opts.prefix = arg["--prefix=".len..];
        return 1;
    } else if (std.mem.startsWith(u8, arg, "--digits=")) {
        opts.digits = try std.fmt.parseInt(usize, arg["--digits=".len..], 10);
        return 1;
    } else if (std.mem.startsWith(u8, arg, "--suffix-format=")) {
        const val = arg["--suffix-format=".len..];
        try validateFormat(val, stderr);
        opts.suffix_format = try allocator.dupeZ(u8, val);
        return 1;
    }
    return parseLongOptionWithArg(allocator, args, idx, opts, stderr);
}

fn parseLongOptionWithArg(
    allocator: std.mem.Allocator,
    args: [][]const u8,
    idx: usize,
    opts: *Options,
    stderr: anytype,
) !usize {
    const arg = args[idx];
    if (std.mem.eql(u8, arg, "--prefix")) {
        if (idx + 1 >= args.len) return error.MissingArgument;
        opts.prefix = args[idx + 1];
        return 2;
    } else if (std.mem.eql(u8, arg, "--digits")) {
        if (idx + 1 >= args.len) return error.MissingArgument;
        opts.digits = try std.fmt.parseInt(usize, args[idx + 1], 10);
        return 2;
    } else if (std.mem.eql(u8, arg, "--suffix-format")) {
        if (idx + 1 >= args.len) return error.MissingArgument;
        try validateFormat(args[idx + 1], stderr);
        opts.suffix_format = try allocator.dupeZ(u8, args[idx + 1]);
        return 2;
    }
    try stderr.print("csplit: unrecognized option '{s}'\n", .{arg});
    return error.UnrecognizedOption;
}

fn parseShortOption(
    allocator: std.mem.Allocator,
    args: [][]const u8,
    idx: usize,
    opts: *Options,
    stderr: anytype,
) !usize {
    const arg = args[idx];
    var j: usize = 1;
    while (j < arg.len) : (j += 1) {
        switch (arg[j]) {
            'k' => opts.keep_files = true,
            's', 'q' => opts.silent = true,
            'z' => opts.elide_empty = true,
            'f' => return handleShortWithVal(allocator, args, idx, j, opts, 'f', stderr),
            'n' => return handleShortWithVal(allocator, args, idx, j, opts, 'n', stderr),
            'b' => return handleShortWithVal(allocator, args, idx, j, opts, 'b', stderr),
            else => {
                try stderr.print("csplit: invalid option -- '{c}'\n", .{arg[j]});
                return error.InvalidOption;
            },
        }
    }
    return 1;
}

fn handleShortWithVal(
    allocator: std.mem.Allocator,
    args: [][]const u8,
    idx: usize,
    opt_idx: usize,
    opts: *Options,
    kind: u8,
    stderr: anytype,
) !usize {
    const arg = args[idx];
    const rest = arg[opt_idx + 1 ..];
    const val: []const u8 = if (rest.len > 0) rest else blk: {
        if (idx + 1 >= args.len) return error.MissingArgument;
        break :blk args[idx + 1];
    };
    const consumed: usize = if (rest.len > 0) 1 else 2;
    switch (kind) {
        'f' => opts.prefix = val,
        'n' => opts.digits = try std.fmt.parseInt(usize, val, 10),
        'b' => {
            try validateFormat(val, stderr);
            opts.suffix_format = try allocator.dupeZ(u8, val);
        },
        else => unreachable,
    }
    return consumed;
}
