const std = @import("std");
const c = @import("../../compat/c.zig").c;
const types = @import("types.zig");
const long_flags = @import("long_flags.zig");

const Options = types.Options;
const FormatMode = types.FormatMode;

pub const Action = union(enum) {
    proceed: struct {
        options: Options,
        paths: []const []const u8,
    },
    help,
    version,
    error_exit: u8,
};

const parseShortFlag = types.parseShortFlag;
const parseWidth = types.parseWidth;

fn parseLongFlag(
    arg: []const u8,
    opt: *Options,
    arena: std.mem.Allocator,
    ignore_patterns: *std.ArrayList([]const u8),
    hide_patterns: *std.ArrayList([]const u8),
    stderr: anytype,
    prog_name: []const u8,
) !?Action {
    if (long_flags.parseDisplayFlag(arg, opt)) return null;
    if (long_flags.parseQuotingFlag(arg, opt)) return null;
    if (try long_flags.parseFilterFlag(arg, opt, arena, ignore_patterns, hide_patterns)) return null;
    switch (long_flags.parseIndicatorFlag(arg, opt, stderr, prog_name)) {
        .success => return null,
        .action => |act| return act,
        .not_matched => {},
    }
    switch (long_flags.parseColorAndHyperlink(arg, opt, stderr, prog_name)) {
        .success => return null,
        .action => |act| return act,
        .not_matched => {},
    }
    switch (long_flags.parseSortAndSize(arg, opt, stderr, prog_name)) {
        .success => return null,
        .action => |act| return act,
        .not_matched => {},
    }
    return error.InvalidOption;
}

fn parseEnvOptions(opt: *Options) void {
    const env_vars = [_][]const u8{ "LS_BLOCK_SIZE", "BLOCK_SIZE", "BLOCKSIZE" };
    for (env_vars, 0..) |v, idx| {
        if (c.getenv(v.ptr)) |raw| {
            if (types.parseBlockSize(std.mem.span(raw))) |bs| {
                if (idx < 2) opt.block_size = bs;
                opt.disk_block_size = bs;
                break;
            }
        }
    }
    var ws: c.struct_winsize = undefined;
    if (c.ioctl(c.STDOUT_FILENO, c.TIOCGWINSZ, &ws) == 0 and ws.ws_col > 0) opt.term_width = ws.ws_col;
}

fn handleShortWithParam(
    ch: u8,
    arg: []const u8,
    args: [][]const u8,
    i: *usize,
    j: *usize,
    opt: *Options,
    ignore_patterns: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    stderr: anytype,
    prog_name: []const u8,
) !?Action {
    const val_str = if (j.* + 1 < arg.len) blk: {
        const s = arg[j.* + 1 ..];
        j.* = arg.len;
        break :blk s;
    } else if (i.* + 1 < args.len) blk: {
        i.* += 1;
        break :blk args[i.*];
    } else "";

    if (ch == 'w') {
        opt.term_width = parseWidth(val_str) catch {
            try stderr.print("{s}: invalid line width: '{s}'\nTry '{s} --help' for more information.\n", .{ prog_name, val_str, prog_name });
            return Action{ .error_exit = 2 };
        };
    } else if (ch == 'T') {
        opt.tab_size = std.fmt.parseInt(usize, val_str, 10) catch 8;
    } else if (ch == 'I') {
        try ignore_patterns.append(allocator, val_str);
    }
    return null;
}

fn parseShortArg(
    arg: []const u8,
    args: [][]const u8,
    i: *usize,
    opt: *Options,
    ignore_patterns: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    stderr: anytype,
    prog_name: []const u8,
) !?Action {
    var j: usize = 1;
    while (j < arg.len) : (j += 1) {
        const ch = arg[j];
        if (ch == 'w' or ch == 'T' or ch == 'I') {
            if (try handleShortWithParam(ch, arg, args, i, &j, opt, ignore_patterns, allocator, stderr, prog_name)) |action| return action;
            break;
        } else if (ch == 'B') {
            opt.ignore_backups = true;
            try ignore_patterns.append(allocator, "*~");
            try ignore_patterns.append(allocator, ".*~");
        } else {
            parseShortFlag(ch, opt) catch {
                try stderr.print("{s}: invalid option -- '{c}'\nTry '{s} --help' for more information.\n", .{ prog_name, ch, prog_name });
                return Action{ .error_exit = 2 };
            };
        }
    }
    return null;
}

fn validateZeroOptions(opt: *Options, stderr: anytype, prog_name: []const u8) !?Action {
    if (opt.zero and opt.dired) {
        try stderr.print("{s}: --dired and --zero are incompatible\n", .{prog_name});
        return Action{ .error_exit = 2 };
    }
    if (opt.zero and opt.format != .long) {
        opt.format = .one_per_line;
        opt.quoting_style = .literal;
        opt.hide_control_chars = false;
    }
    return null;
}

fn parseSingleArg(
    arg: []const u8,
    args: [][]const u8,
    i: *usize,
    past_delimiter: *bool,
    opt: *Options,
    paths: *std.ArrayList([]const u8),
    ignore_patterns: *std.ArrayList([]const u8),
    hide_patterns: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    stderr: anytype,
    prog_name: []const u8,
) !?Action {
    if (!past_delimiter.* and std.mem.eql(u8, arg, "--")) {
        past_delimiter.* = true;
        return null;
    }
    if (!past_delimiter.* and std.mem.startsWith(u8, arg, "--") and arg.len > 2) {
        if (std.mem.eql(u8, arg, "--help")) return .help;
        if (std.mem.eql(u8, arg, "--version")) return .version;
        const long_res = parseLongFlag(arg, opt, allocator, ignore_patterns, hide_patterns, stderr, prog_name) catch {
            try stderr.print("{s}: unrecognized option '{s}'\nTry '{s} --help' for more information.\n", .{ prog_name, arg, prog_name });
            return Action{ .error_exit = 2 };
        };
        if (long_res) |action| return action;
    } else if (!past_delimiter.* and std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
        if (try parseShortArg(arg, args, i, opt, ignore_patterns, allocator, stderr, prog_name)) |action| return action;
    } else {
        try paths.append(allocator, arg);
    }
    return null;
}

pub fn parseArgs(
    args: [][]const u8,
    default_format: FormatMode,
    is_ls: bool,
    prog_name: []const u8,
    allocator: std.mem.Allocator,
    stderr: anytype,
) !Action {
    var opt = Options{ .format = default_format };
    if (is_ls and c.isatty(c.STDOUT_FILENO) == 0) opt.format = .one_per_line;
    parseEnvOptions(&opt);

    var paths: std.ArrayList([]const u8) = .empty;
    defer paths.deinit(allocator);
    var ignore_patterns: std.ArrayList([]const u8) = .empty;
    defer ignore_patterns.deinit(allocator);
    var hide_patterns: std.ArrayList([]const u8) = .empty;
    defer hide_patterns.deinit(allocator);

    var i: usize = 1;
    var past_delimiter = false;
    while (i < args.len) : (i += 1) {
        if (try parseSingleArg(args[i], args, &i, &past_delimiter, &opt, &paths, &ignore_patterns, &hide_patterns, allocator, stderr, prog_name)) |action| return action;
    }

    if (try validateZeroOptions(&opt, stderr, prog_name)) |action| return action;

    opt.ignore_patterns = try ignore_patterns.toOwnedSlice(allocator);
    opt.hide_patterns = try hide_patterns.toOwnedSlice(allocator);
    const final_paths = if (paths.items.len == 0) try allocator.dupe([]const u8, &[_][]const u8{"."}) else try paths.toOwnedSlice(allocator);
    return Action{ .proceed = .{ .options = opt, .paths = final_paths } };
}
