const std = @import("std");
const types = @import("types.zig");
const parse_units = @import("parse_units.zig");

pub fn parseShortOptions(
    allocator: std.mem.Allocator,
    arg: []const u8,
    args: []const []const u8,
    i: *usize,
    cfg: *types.DuConfig,
    max_depth_specified: *bool,
    early_exit: *?u8,
    stderr: anytype,
) !bool {
    _ = early_exit;
    var j: usize = 1;
    while (j < arg.len) : (j += 1) {
        const ch = arg[j];
        if (applyShortFlag(ch, cfg)) continue;
        switch (ch) {
            'B', 'd', 't', 'X' => {
                const val = getShortOptVal(arg, &j, args, i, ch, stderr) orelse return false;
                if (!try applyShortValued(allocator, ch, val, cfg, max_depth_specified, stderr)) return false;
            },
            else => {
                try stderr.print("du: invalid option -- '{c}'\nTry 'du --help' for more information.\n", .{ch});
                return false;
            },
        }
    }
    return true;
}

fn applyShortFlag(ch: u8, cfg: *types.DuConfig) bool {
    switch (ch) {
        '0' => cfg.null_terminate = true,
        'a' => cfg.all_files = true,
        'A' => cfg.apparent_size = true,
        'b' => {
            cfg.apparent_size = true;
            cfg.display_mode = .{ .block_size = 1 };
        },
        'c' => cfg.total = true,
        'D', 'H' => cfg.dereference_args = true,
        'h' => cfg.display_mode = .human_1024,
        'k' => cfg.display_mode = .{ .block_size = 1024 },
        'L' => cfg.dereference_all = true,
        'l' => cfg.count_links = true,
        'm' => cfg.display_mode = .{ .block_size = 1024 * 1024 },
        'P' => {
            cfg.dereference_all = false;
            cfg.dereference_args = false;
        },
        'S' => cfg.separate_dirs = true,
        's' => cfg.summarize_only = true,
        'x' => cfg.one_file_system = true,
        else => return false,
    }
    return true;
}

fn getShortOptVal(opt_str: []const u8, j: *usize, args: []const []const u8, i: *usize, ch: u8, stderr: anytype) ?[]const u8 {
    if (j.* + 1 < opt_str.len) {
        const val = opt_str[j.* + 1 ..];
        j.* = opt_str.len - 1;
        return val;
    }
    if (i.* + 1 < args.len) {
        i.* += 1;
        return args[i.*];
    }
    stderr.print("du: option requires an argument -- '{c}'\nTry 'du --help' for more information.\n", .{ch}) catch {};
    return null;
}

fn applyShortValued(
    allocator: std.mem.Allocator,
    ch: u8,
    val: []const u8,
    cfg: *types.DuConfig,
    max_depth_specified: *bool,
    stderr: anytype,
) !bool {
    switch (ch) {
        'B' => {
            const sz = parse_units.parseSizeUnit(val) orelse {
                try stderr.print("du: invalid -B argument '{s}'\n", .{val});
                return false;
            };
            if (sz == 0) {
                try stderr.print("du: invalid -B argument '{s}'\n", .{val});
                return false;
            }
            cfg.display_mode = .{ .block_size = sz };
        },
        'd' => {
            const d = std.fmt.parseInt(usize, val, 10) catch {
                try stderr.print("du: invalid maximum depth ‘{s}’\nTry 'du --help' for more information.\n", .{val});
                return false;
            };
            cfg.max_depth = d;
            max_depth_specified.* = true;
        },
        't' => {
            cfg.threshold = parse_units.parseThreshold(val, "-t", stderr) orelse return false;
        },
        'X' => {
            if (!try parse_units.loadExcludeFile(allocator, val, cfg, stderr)) return false;
        },
        else => unreachable,
    }
    return true;
}
