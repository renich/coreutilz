const std = @import("std");

pub const FmtOptions = struct {
    max_width: usize = 75,
    goal_width: usize = 0,
    crown_margin: bool = false,
    tagged_paragraph: bool = false,
    split_only: bool = false,
    uniform_spacing: bool = false,
    prefix: ?[]const u8 = null,

    pub fn getGoal(self: *const FmtOptions) usize {
        if (self.goal_width > 0) return self.goal_width;
        return (self.max_width * 7) / 8;
    }
};

pub fn parseOptions(
    opts: *FmtOptions,
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
            try w.interface.print("Usage: fmt [-WIDTH] [OPTION]... [FILE]...\nReformat each paragraph in the FILE(s), writing to standard output.\n", .{});
            w.interface.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            var buf: [256]u8 = undefined;
            var w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &buf);
            try w.interface.print("fmt (coreutilz) {s}\n", .{version});
            w.interface.flush() catch return 1;
            return 0;
        } else if (isObsoleteWidth(arg)) {
            if (i != 1) {
                var err_buf: [256]u8 = undefined;
                var ew = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &err_buf);
                try ew.interface.print("fmt: invalid option -- {c}; -WIDTH is recognized only when it is the first\noption; use -w N instead\nTry 'fmt --help' for more information.\n", .{arg[1]});
                ew.interface.flush() catch {};
                return 1;
            }
            opts.max_width = parseWidthVal(arg[1..]) catch {
                var err_buf: [256]u8 = undefined;
                var ew = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &err_buf);
                try ew.interface.print("fmt: invalid width: '{s}'\n", .{arg[1..]});
                ew.interface.flush() catch {};
                return 1;
            };
        } else if (std.mem.startsWith(u8, arg, "-w")) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
            opts.max_width = parseWidthVal(val) catch {
                var err_buf: [256]u8 = undefined;
                var ew = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &err_buf);
                try ew.interface.print("fmt: invalid width: '{s}'\n", .{val});
                ew.interface.flush() catch {};
                return 1;
            };
        } else if (std.mem.startsWith(u8, arg, "--width=")) {
            const val = arg["--width=".len..];
            opts.max_width = parseWidthVal(val) catch {
                var err_buf: [256]u8 = undefined;
                var ew = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &err_buf);
                try ew.interface.print("fmt: invalid width: '{s}'\n", .{val});
                ew.interface.flush() catch {};
                return 1;
            };
        } else if (std.mem.startsWith(u8, arg, "-g")) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
            opts.goal_width = try std.fmt.parseInt(usize, val, 10);
        } else if (std.mem.startsWith(u8, arg, "--goal=")) {
            opts.goal_width = try std.fmt.parseInt(usize, arg["--goal=".len..], 10);
        } else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--crown-margin")) {
            opts.crown_margin = true;
        } else if (std.mem.eql(u8, arg, "-t") or std.mem.eql(u8, arg, "--tagged-paragraph")) {
            opts.tagged_paragraph = true;
        } else if (std.mem.eql(u8, arg, "-s") or std.mem.eql(u8, arg, "--split-only")) {
            opts.split_only = true;
        } else if (std.mem.eql(u8, arg, "-u") or std.mem.eql(u8, arg, "--uniform-spacing")) {
            opts.uniform_spacing = true;
        } else if (std.mem.startsWith(u8, arg, "-p")) {
            opts.prefix = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
        } else if (std.mem.startsWith(u8, arg, "--prefix=")) {
            opts.prefix = arg["--prefix=".len..];
        } else if (std.mem.startsWith(u8, arg, "-") and !std.mem.eql(u8, arg, "-")) {
            return 1;
        } else {
            try files.append(allocator, arg);
        }
    }
    return null;
}

fn isObsoleteWidth(arg: []const u8) bool {
    if (arg.len < 2 or arg[0] != '-') return false;
    return std.ascii.isDigit(arg[1]);
}

fn parseWidthVal(val: []const u8) !usize {
    const w = try std.fmt.parseInt(usize, val, 10);
    if (w >= 32768) return error.InvalidWidth;
    return w;
}
