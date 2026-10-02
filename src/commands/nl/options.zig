const std = @import("std");
const types = @import("types.zig");

pub fn parseOptions(
    cfg: *types.NlConfig,
    files: *std.ArrayList([]const u8),
    args: [][]const u8,
    allocator: std.mem.Allocator,
    version: []const u8,
) !?u8 {
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            var buf: [256]u8 = undefined;
            var w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &buf);
            try w.interface.print("Usage: nl [OPTION]... [FILE]...\nNumber lines of files.\n", .{});
            w.interface.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            var buf: [256]u8 = undefined;
            var w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &buf);
            try w.interface.print("nl (coreutilz) {s}\n", .{version});
            w.interface.flush() catch return 1;
            return 0;
        } else if (std.mem.startsWith(u8, arg, "-b")) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
            cfg.body_style.deinit();
            cfg.body_style = try types.parseStyle(val);
        } else if (std.mem.startsWith(u8, arg, "-h")) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
            cfg.header_style.deinit();
            cfg.header_style = try types.parseStyle(val);
        } else if (std.mem.startsWith(u8, arg, "-f")) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
            cfg.footer_style.deinit();
            cfg.footer_style = try types.parseStyle(val);
        } else if (std.mem.startsWith(u8, arg, "-s")) {
            cfg.separator = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
        } else if (std.mem.startsWith(u8, arg, "-n")) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
            if (std.mem.eql(u8, val, "ln")) cfg.format = .ln else if (std.mem.eql(u8, val, "rn")) cfg.format = .rn else if (std.mem.eql(u8, val, "rz")) cfg.format = .rz else return 1;
        } else if (std.mem.startsWith(u8, arg, "-w")) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
            cfg.width = try std.fmt.parseInt(usize, val, 10);
        } else if (std.mem.startsWith(u8, arg, "-v")) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
            cfg.start_num = try std.fmt.parseInt(i64, val, 10);
        } else if (std.mem.startsWith(u8, arg, "-i")) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
            cfg.increment = try std.fmt.parseInt(i64, val, 10);
        } else if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--no-renumber")) {
            cfg.renumber = false;
        } else if (std.mem.startsWith(u8, arg, "-d")) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
            if (val.len == 0) {
                cfg.delim_enabled = false;
            } else if (val.len == 1) {
                var d: [2]u8 = undefined;
                d[0] = val[0];
                d[1] = ':';
                cfg.delim = try allocator.dupe(u8, &d);
            } else {
                cfg.delim = val;
            }
        } else if (std.mem.startsWith(u8, arg, "-l")) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
            cfg.blank_join = try std.fmt.parseInt(usize, val, 10);
        } else if (std.mem.startsWith(u8, arg, "-") and !std.mem.eql(u8, arg, "-")) {
            return 1;
        } else {
            try files.append(allocator, arg);
        }
    }
    return null;
}
