const std = @import("std");
const types = @import("types.zig");
const parse_units = @import("parse_units.zig");
const help = @import("help.zig");
const validate = @import("options_validate.zig");
const options_short = @import("options_short.zig");

pub fn parseOptions(
    allocator: std.mem.Allocator,
    args: []const []const u8,
    cfg: *types.DuConfig,
    operands: *std.ArrayList([]const u8),
    stdout: anytype,
    stderr: anytype,
) !?u8 {
    validate.initDefaultBlockSize(cfg);
    var i: usize = 1;
    var max_depth_specified = false;
    var seen_dash_dash = false;

    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (seen_dash_dash or !std.mem.startsWith(u8, arg, "-") or std.mem.eql(u8, arg, "-")) {
            try operands.append(allocator, arg);
            continue;
        }
        if (std.mem.eql(u8, arg, "--")) {
            seen_dash_dash = true;
            continue;
        }
        var early_exit: ?u8 = null;
        if (std.mem.startsWith(u8, arg, "--")) {
            const ok = try parseLongOption(allocator, arg, args, &i, cfg, &max_depth_specified, &early_exit, stdout, stderr);
            if (!ok) return 1;
            if (early_exit) |code| return code;
        } else {
            const ok = try options_short.parseShortOptions(allocator, arg, args, &i, cfg, &max_depth_specified, &early_exit, stderr);
            if (!ok) return 1;
            if (early_exit) |code| return code;
        }
    }
    return validate.validateOptions(cfg, max_depth_specified, stderr);
}

fn parseLongOption(
    allocator: std.mem.Allocator,
    arg: []const u8,
    args: []const []const u8,
    i: *usize,
    cfg: *types.DuConfig,
    max_depth_specified: *bool,
    early_exit: *?u8,
    stdout: anytype,
    stderr: anytype,
) !bool {
    if (std.mem.eql(u8, arg, "--help")) {
        try help.printHelp(stdout);
        stdout.flush() catch {
            early_exit.* = 1;
            return true;
        };
        early_exit.* = 0;
        return true;
    }
    if (std.mem.eql(u8, arg, "--version")) {
        try help.printVersion(stdout);
        stdout.flush() catch {
            early_exit.* = 1;
            return true;
        };
        early_exit.* = 0;
        return true;
    }
    return parseLongOptionFlags(allocator, arg, args, i, cfg, max_depth_specified, stderr);
}

fn parseLongOptionFlags(
    allocator: std.mem.Allocator,
    arg: []const u8,
    args: []const []const u8,
    i: *usize,
    cfg: *types.DuConfig,
    max_depth_specified: *bool,
    stderr: anytype,
) !bool {
    if (std.mem.eql(u8, arg, "--all")) {
        cfg.all_files = true;
    } else if (std.mem.eql(u8, arg, "--apparent-size")) {
        cfg.apparent_size = true;
    } else if (std.mem.eql(u8, arg, "--bytes")) {
        cfg.apparent_size = true;
        cfg.display_mode = .{ .block_size = 1 };
    } else if (std.mem.eql(u8, arg, "--total")) {
        cfg.total = true;
    } else if (std.mem.eql(u8, arg, "--count-links")) {
        cfg.count_links = true;
    } else if (std.mem.eql(u8, arg, "--dereference")) {
        cfg.dereference_all = true;
    } else if (std.mem.eql(u8, arg, "--dereference-args")) {
        cfg.dereference_args = true;
    } else if (std.mem.eql(u8, arg, "--no-dereference")) {
        cfg.dereference_all = false;
        cfg.dereference_args = false;
    } else if (parseLongOptionFlagsExtra(arg, cfg)) {
        return true;
    } else {
        return parseLongOptionValued(allocator, arg, args, i, cfg, max_depth_specified, stderr);
    }
    return true;
}

fn parseLongOptionFlagsExtra(arg: []const u8, cfg: *types.DuConfig) bool {
    if (std.mem.eql(u8, arg, "--human-readable")) {
        cfg.display_mode = .human_1024;
    } else if (std.mem.eql(u8, arg, "--si")) {
        cfg.display_mode = .human_1000;
    } else if (std.mem.eql(u8, arg, "--inodes")) {
        cfg.inodes_mode = true;
    } else if (std.mem.eql(u8, arg, "--null")) {
        cfg.null_terminate = true;
    } else if (std.mem.eql(u8, arg, "--one-file-system")) {
        cfg.one_file_system = true;
    } else if (std.mem.eql(u8, arg, "--separate-dirs")) {
        cfg.separate_dirs = true;
    } else if (std.mem.eql(u8, arg, "--summarize")) {
        cfg.summarize_only = true;
    } else {
        return false;
    }
    return true;
}

fn parseLongOptionValued(
    allocator: std.mem.Allocator,
    arg: []const u8,
    args: []const []const u8,
    i: *usize,
    cfg: *types.DuConfig,
    max_depth_specified: *bool,
    stderr: anytype,
) !bool {
    if (splitLongOption(arg, "--block-size")) |val_opt| {
        const val = getLongVal(val_opt, args, i, "--block-size", stderr) orelse return false;
        const sz = parse_units.parseSizeUnit(val) orelse {
            try stderr.print("du: invalid --block-size argument '{s}'\n", .{val});
            return false;
        };
        if (sz == 0) {
            try stderr.print("du: invalid --block-size argument '{s}'\n", .{val});
            return false;
        }
        cfg.display_mode = .{ .block_size = sz };
    } else if (splitLongOption(arg, "--max-depth")) |val_opt| {
        const val = getLongVal(val_opt, args, i, "--max-depth", stderr) orelse return false;
        const d = std.fmt.parseInt(usize, val, 10) catch {
            try stderr.print("du: invalid maximum depth ‘{s}’\nTry 'du --help' for more information.\n", .{val});
            return false;
        };
        cfg.max_depth = d;
        max_depth_specified.* = true;
    } else if (splitLongOption(arg, "--threshold")) |val_opt| {
        const val = getLongVal(val_opt, args, i, "--threshold", stderr) orelse return false;
        cfg.threshold = parse_units.parseThreshold(val, "--threshold", stderr) orelse return false;
    } else {
        return parseLongOptionValuedExtra(allocator, arg, args, i, cfg, stderr);
    }
    return true;
}

fn parseLongOptionValuedExtra(
    allocator: std.mem.Allocator,
    arg: []const u8,
    args: []const []const u8,
    i: *usize,
    cfg: *types.DuConfig,
    stderr: anytype,
) !bool {
    if (splitLongOption(arg, "--exclude")) |val_opt| {
        const val = getLongVal(val_opt, args, i, "--exclude", stderr) orelse return false;
        try parse_units.addExcludePattern(allocator, val, cfg);
    } else if (splitLongOption(arg, "--exclude-from")) |val_opt| {
        const val = getLongVal(val_opt, args, i, "--exclude-from", stderr) orelse return false;
        if (!try parse_units.loadExcludeFile(allocator, val, cfg, stderr)) return false;
    } else if (splitLongOption(arg, "--files0-from")) |val_opt| {
        const val = getLongVal(val_opt, args, i, "--files0-from", stderr) orelse return false;
        cfg.files0_from = val;
    } else if (splitLongOption(arg, "--time")) |val_opt| {
        cfg.time_type = validate.parseTimeWord(val_opt orelse "mtime");
    } else if (splitLongOption(arg, "--time-style")) |val_opt| {
        const val = getLongVal(val_opt, args, i, "--time-style", stderr) orelse return false;
        cfg.time_style = validate.parseTimeStyle(val);
    } else {
        try stderr.print("du: unrecognized option '{s}'\nTry 'du --help' for more information.\n", .{arg});
        return false;
    }
    return true;
}

fn splitLongOption(arg: []const u8, prefix: []const u8) ??[]const u8 {
    if (std.mem.eql(u8, arg, prefix)) return @as(?[]const u8, null);
    if (std.mem.startsWith(u8, arg, prefix) and arg.len > prefix.len and arg[prefix.len] == '=') {
        return arg[prefix.len + 1 ..];
    }
    return null;
}

fn getLongVal(val_opt: ?[]const u8, args: []const []const u8, i: *usize, opt: []const u8, stderr: anytype) ?[]const u8 {
    if (val_opt) |v| return v;
    if (i.* + 1 < args.len) {
        i.* += 1;
        return args[i.*];
    }
    stderr.print("du: option '{s}' requires an argument\nTry 'du --help' for more information.\n", .{opt}) catch {};
    return null;
}
