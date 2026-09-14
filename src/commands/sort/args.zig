const std = @import("std");
const types = @import("types.zig");
const key_parser = @import("key_parser.zig");
const errors = @import("../../utils/errors.zig");

pub fn printUsage(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: sort [OPTION]... [FILE]...
        \\Write sorted concatenation of all FILE(s) to standard output.
        \\With no FILE, or when FILE is -, read standard input.
        \\Ordering: -b, -d, -f, -g, -h, -i, -M, -n, -R, -r, -V
        \\Other:    -c, -C, -k, -m, -o, -s, -t, -u, -z, --files0-from, --batch-size
        \\
    );
}

fn appendOptChar(buf: []u8, len: *usize, cond: bool, ch: u8) void {
    if (cond) {
        buf[len.*] = ch;
        len.* += 1;
    }
}

pub fn checkOrderingCompatibility(key: *const types.KeySpec, stderr: anytype) !bool {
    const last: u32 = if (key.version or key.random or key.dictionary_order or key.ignore_nonprinting) 1 else 0;
    const count = (if (key.numeric) @as(u32, 1) else 0) +
        (if (key.general_numeric) @as(u32, 1) else 0) +
        (if (key.human_numeric) @as(u32, 1) else 0) +
        (if (key.month) @as(u32, 1) else 0) + last;
    if (count <= 1) return true;

    var buf: [16]u8 = undefined;
    var len: usize = 0;
    appendOptChar(&buf, &len, key.dictionary_order, 'd');
    appendOptChar(&buf, &len, key.ignore_case, 'f');
    appendOptChar(&buf, &len, key.general_numeric, 'g');
    appendOptChar(&buf, &len, key.human_numeric, 'h');
    appendOptChar(&buf, &len, key.ignore_nonprinting and !key.dictionary_order, 'i');
    appendOptChar(&buf, &len, key.month, 'M');
    appendOptChar(&buf, &len, key.numeric, 'n');
    appendOptChar(&buf, &len, key.random, 'R');
    appendOptChar(&buf, &len, key.version, 'V');
    try stderr.print("sort: options '-{s}' are incompatible\n", .{buf[0..len]});
    return false;
}

fn handleTab(val: []const u8, opt: *types.Options, stderr: anytype) !bool {
    if (val.len == 0) {
        try stderr.writeAll("sort: empty tab\n");
        return false;
    }
    const delim: u8 = if (std.mem.eql(u8, val, "\\0")) 0 else if (val.len == 1) val[0] else {
        try stderr.print("sort: multi-character tab '{s}'\n", .{val});
        return false;
    };
    if (opt.delimiter != null and opt.delimiter.? != delim) {
        try stderr.writeAll("sort: incompatible tabs\n");
        return false;
    }
    opt.delimiter = delim;
    return true;
}

fn parseBatchSize(val: []const u8, opt: *types.Options, stderr: anytype) !bool {
    for (val) |c| {
        if (!std.ascii.isDigit(c)) {
            try stderr.print("sort: invalid --batch-size argument '{s}'\n", .{val});
            return false;
        }
    }
    if (val.len == 0) return false;
    const n = std.fmt.parseInt(usize, val, 10) catch {
        try stderr.print("sort: --batch-size argument '{s}' too large\nsort: maximum --batch-size argument with current rlimit is 1024\n", .{val});
        return false;
    };
    if (n < 2) {
        try stderr.print("sort: invalid --batch-size argument '{s}'\nsort: minimum --batch-size argument is '2'\n", .{val});
        return false;
    }
    opt.batch_size = n;
    return true;
}

pub fn setOutputFile(opt: *types.Options, val: []const u8, stderr: anytype) !bool {
    if (opt.output_file) |existing| {
        if (!std.mem.eql(u8, existing, val)) {
            try stderr.writeAll("sort: multiple output files specified\n");
            return false;
        }
    }
    opt.output_file = val;
    return true;
}

pub fn setRandomSource(opt: *types.Options, val: []const u8, stderr: anytype) !bool {
    if (opt.random_source) |existing| {
        if (!std.mem.eql(u8, existing, val)) {
            try stderr.writeAll("sort: multiple random sources specified\n");
            return false;
        }
    }
    opt.random_source = val;
    return true;
}

fn parseLongSortOption(val: []const u8, opt: *types.Options) void {
    if (std.mem.eql(u8, val, "numeric")) opt.numeric = true else if (std.mem.eql(u8, val, "general-numeric")) opt.general_numeric = true else if (std.mem.eql(u8, val, "human-numeric")) opt.human_numeric = true else if (std.mem.eql(u8, val, "month")) opt.month = true else if (std.mem.eql(u8, val, "random")) opt.random = true else if (std.mem.eql(u8, val, "version")) opt.version = true;
}

fn parseLongOption(arg: []const u8, opt: *types.Options, keys: *std.ArrayList(types.KeySpec), alloc: std.mem.Allocator, stdout: anytype, stderr: anytype) !?u8 {
    if (std.mem.eql(u8, arg, "--help")) {
        try printUsage(stdout);
        stdout.flush() catch return 2;
        return 0;
    } else if (std.mem.eql(u8, arg, "--version")) {
        try errors.printVersion(stdout, "sort", "0.1.0");
        stdout.flush() catch return 2;
        return 0;
    } else if (std.mem.eql(u8, arg, "--stable") or std.mem.startsWith(u8, arg, "--sta")) {
        opt.stable = true;
    } else if (std.mem.startsWith(u8, arg, "--files0-from=")) {
        opt.files0_from = arg["--files0-from=".len..];
    } else if (std.mem.startsWith(u8, arg, "--batch-size=")) {
        if (!try parseBatchSize(arg["--batch-size=".len..], opt, stderr)) return 2;
    } else if (std.mem.startsWith(u8, arg, "--temporary-directory=")) {
        opt.temp_dir = arg["--temporary-directory=".len..];
    } else if (std.mem.startsWith(u8, arg, "--parallel=") or std.mem.startsWith(u8, arg, "--p=")) {
        const val = if (std.mem.startsWith(u8, arg, "--parallel=")) arg["--parallel=".len..] else arg["--p=".len..];
        opt.parallel = std.fmt.parseInt(usize, val, 10) catch 1;
    } else if (std.mem.startsWith(u8, arg, "--field-separator=")) {
        if (!try handleTab(arg["--field-separator=".len..], opt, stderr)) return 2;
    } else if (std.mem.startsWith(u8, arg, "--key=")) {
        const k = (try key_parser.parseKeySpec(arg["--key=".len..], stderr)) orelse return 2;
        try keys.append(alloc, k);
    } else if (std.mem.startsWith(u8, arg, "--output=")) {
        if (!try setOutputFile(opt, arg["--output=".len..], stderr)) return 2;
    } else if (std.mem.startsWith(u8, arg, "--random-source=")) {
        if (!try setRandomSource(opt, arg["--random-source=".len..], stderr)) return 2;
    } else if (std.mem.eql(u8, arg, "--check") or std.mem.eql(u8, arg, "--check=diagnose-first")) {
        if (opt.check_silent) {
            try stderr.writeAll("sort: options '-cC' are incompatible\n");
            return 2;
        }
        opt.check = true;
    } else if (std.mem.eql(u8, arg, "--check=silent") or std.mem.eql(u8, arg, "--check=quiet")) {
        if (opt.check) {
            try stderr.writeAll("sort: options '-cC' are incompatible\n");
            return 2;
        }
        opt.check_silent = true;
    } else if (std.mem.startsWith(u8, arg, "--sort=")) {
        parseLongSortOption(arg["--sort=".len..], opt);
    } else if (std.mem.startsWith(u8, arg, "--compress-program=")) {
        const val = arg["--compress-program=".len..];
        if (opt.compress_program) |existing| {
            if (!std.mem.eql(u8, existing, val)) {
                try stderr.writeAll("sort: multiple compress programs specified\n");
                return 2;
            }
        }
        opt.compress_program = val;
    } else if (!parseLongFlag(arg, opt)) {
        if (!std.mem.eql(u8, arg, "--debug")) {
            try stderr.print("sort: unrecognized option '{s}'\n", .{arg});
            return 2;
        }
    }
    return null;
}

fn parseLongFlag(arg: []const u8, opt: *types.Options) bool {
    if (std.mem.eql(u8, arg, "--reverse")) opt.reverse = true else if (std.mem.eql(u8, arg, "--numeric-sort")) opt.numeric = true else if (std.mem.eql(u8, arg, "--general-numeric-sort")) opt.general_numeric = true else if (std.mem.eql(u8, arg, "--human-numeric-sort")) opt.human_numeric = true else if (std.mem.eql(u8, arg, "--month-sort")) opt.month = true else if (std.mem.eql(u8, arg, "--version-sort")) opt.version = true else if (std.mem.eql(u8, arg, "--random-sort")) opt.random = true else if (std.mem.eql(u8, arg, "--unique")) opt.unique = true else if (std.mem.eql(u8, arg, "--ignore-leading-blanks")) opt.ignore_blanks = true else if (std.mem.eql(u8, arg, "--ignore-case")) opt.ignore_case = true else if (std.mem.eql(u8, arg, "--dictionary-order")) opt.dictionary_order = true else if (std.mem.eql(u8, arg, "--ignore-nonprinting")) opt.ignore_nonprinting = true else if (std.mem.eql(u8, arg, "--merge")) opt.merge = true else if (std.mem.eql(u8, arg, "--zero-terminated")) opt.zero_terminated = true else return false;
    return true;
}

fn parseShortFlagChar(ch: u8, opt: *types.Options, stderr: anytype) !?u8 {
    switch (ch) {
        'r' => opt.reverse = true,
        'n' => opt.numeric = true,
        'g' => opt.general_numeric = true,
        'h' => opt.human_numeric = true,
        'M' => opt.month = true,
        'V' => opt.version = true,
        'R' => opt.random = true,
        'u' => opt.unique = true,
        'b' => opt.ignore_blanks = true,
        'f' => opt.ignore_case = true,
        'd' => opt.dictionary_order = true,
        'i' => opt.ignore_nonprinting = true,
        's' => opt.stable = true,
        'c' => {
            if (opt.check_silent) {
                try stderr.writeAll("sort: options '-cC' are incompatible\n");
                return 2;
            }
            opt.check = true;
        },
        'C' => {
            if (opt.check) {
                try stderr.writeAll("sort: options '-cC' are incompatible\n");
                return 2;
            }
            opt.check_silent = true;
        },
        'm' => opt.merge = true,
        'z' => opt.zero_terminated = true,
        'y' => {},
        else => {
            try stderr.print("sort: invalid option -- '{c}'\n", .{ch});
            return 2;
        },
    }
    return null;
}

fn parseShortArg(
    arg: []const u8,
    args: [][]const u8,
    i: *usize,
    opt: *types.Options,
    keys: *std.ArrayList(types.KeySpec),
    alloc: std.mem.Allocator,
    stderr: anytype,
) !?u8 {
    var j: usize = 1;
    while (j < arg.len) : (j += 1) {
        const ch = arg[j];
        if (ch == 'k' or ch == 't' or ch == 'o' or ch == 'T' or ch == 'S') {
            const val = if (j + 1 < arg.len) arg[j + 1 ..] else if (i.* + 1 < args.len) blk: {
                i.* += 1;
                break :blk args[i.*];
            } else "";
            if (ch == 'k') {
                const k = (try key_parser.parseKeySpec(val, stderr)) orelse return 2;
                try keys.append(alloc, k);
            } else if (ch == 't') {
                if (!try handleTab(val, opt, stderr)) return 2;
            } else if (ch == 'o') {
                if (!try setOutputFile(opt, val, stderr)) return 2;
            } else if (ch == 'T') {
                opt.temp_dir = val;
            }
            break;
        }
        if (try parseShortFlagChar(ch, opt, stderr)) |code| return code;
    }
    return null;
}

pub fn parseArgs(
    args: [][]const u8,
    opt: *types.Options,
    keys: *std.ArrayList(types.KeySpec),
    files: *std.ArrayList([]const u8),
    alloc: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) !?u8 {
    var i: usize = 1;
    var seen_dd: bool = false;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (seen_dd) {
            try files.append(alloc, arg);
            continue;
        }
        if (std.mem.eql(u8, arg, "--")) {
            seen_dd = true;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--")) {
            if (try parseLongOption(arg, opt, keys, alloc, stdout, stderr)) |code| return code;
        } else if (arg.len > 1 and arg[0] == '+') {
            var consumed2: bool = false;
            const arg2 = if (i + 1 < args.len) args[i + 1] else null;
            if (key_parser.parseObsoleteKey(arg, arg2, &consumed2)) |k| {
                try keys.append(alloc, k);
                if (consumed2) i += 1;
            } else {
                try files.append(alloc, arg);
            }
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1 and !std.mem.eql(u8, arg, "-")) {
            if (try parseShortArg(arg, args, &i, opt, keys, alloc, stderr)) |code| return code;
        } else {
            try files.append(alloc, arg);
        }
    }
    return null;
}
