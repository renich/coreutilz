const std = @import("std");
const types = @import("types.zig");
const parse_units = @import("parse_units.zig");

pub fn initDefaultBlockSize(cfg: *types.DuConfig) void {
    if (std.c.getenv("POSIXLY_CORRECT") != null) {
        cfg.display_mode = .{ .block_size = 512 };
    } else if (std.c.getenv("BLOCKSIZE")) |bs_env| {
        const bs_span = std.mem.span(bs_env);
        if (parse_units.parseSizeUnit(bs_span)) |sz| {
            if (sz > 0) cfg.display_mode = .{ .block_size = sz };
        }
    }
}

pub fn parseTimeWord(word: []const u8) types.TimeType {
    if (std.mem.eql(u8, word, "atime") or std.mem.eql(u8, word, "access") or std.mem.eql(u8, word, "use")) {
        return .atime;
    }
    if (std.mem.eql(u8, word, "ctime") or std.mem.eql(u8, word, "status")) {
        return .ctime;
    }
    return .mtime;
}

pub fn parseTimeStyle(val: []const u8) types.TimeStyle {
    if (std.mem.eql(u8, val, "full-iso")) return .full_iso;
    if (std.mem.eql(u8, val, "long-iso")) return .long_iso;
    if (std.mem.eql(u8, val, "iso")) return .iso;
    if (std.mem.startsWith(u8, val, "+")) return .{ .custom = val[1..] };
    return .long_iso;
}

pub fn validateOptions(cfg: *types.DuConfig, max_depth_specified: bool, stderr: anytype) ?u8 {
    if (cfg.all_files and cfg.summarize_only) {
        stderr.print("du: cannot both summarize and show all entries\nTry 'du --help' for more information.\n", .{}) catch {};
        return 1;
    }
    if (cfg.summarize_only and max_depth_specified) {
        if (cfg.max_depth.? == 0) {
            stderr.print("du: warning: summarizing is the same as using --max-depth=0\n", .{}) catch {};
        } else {
            stderr.print("du: warning: summarizing conflicts with --max-depth={d}\nTry 'du --help' for more information.\n", .{cfg.max_depth.?}) catch {};
            return 1;
        }
    }
    if (cfg.summarize_only) {
        cfg.max_depth = 0;
    }
    if (cfg.inodes_mode and cfg.apparent_size) {
        stderr.print("du: warning: options --apparent-size and -b are ineffective with --inodes\n", .{}) catch {};
    }
    return null;
}
