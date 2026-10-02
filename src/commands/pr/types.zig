const std = @import("std");

pub const PrConfig = struct {
    first_page: usize = 1,
    last_page: ?usize = null,
    columns: usize = 1,
    across: bool = false,
    merge: bool = false,
    double_space: bool = false,
    omit_header: bool = false,
    page_length: usize = 66,
    page_width: usize = 72,
    header_text: ?[]const u8 = null,
    indent: usize = 0,
    number_lines: bool = false,
    number_digits: usize = 5,
    number_sep: []const u8 = "\t",
    start_line_num: usize = 1,
};

pub fn parseArgs(
    cfg: *PrConfig,
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
            try w.interface.print("Usage: pr [OPTION]... [FILE]...\nPaginate or columnate FILE(s) for printing.\n", .{});
            w.interface.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            var buf: [256]u8 = undefined;
            var w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &buf);
            try w.interface.print("pr (coreutilz) {s}\n", .{version});
            w.interface.flush() catch return 1;
            return 0;
        } else if (arg.len > 1 and arg[0] == '+') {
            const page_spec = arg[1..];
            if (std.mem.indexOfScalar(u8, page_spec, ':')) |colon| {
                cfg.first_page = try std.fmt.parseInt(usize, page_spec[0..colon], 10);
                cfg.last_page = try std.fmt.parseInt(usize, page_spec[colon + 1 ..], 10);
            } else {
                cfg.first_page = try std.fmt.parseInt(usize, page_spec, 10);
            }
        } else if (arg.len > 1 and arg[0] == '-' and std.ascii.isDigit(arg[1])) {
            cfg.columns = try std.fmt.parseInt(usize, arg[1..], 10);
        } else if (std.mem.eql(u8, arg, "-a") or std.mem.eql(u8, arg, "--across")) {
            cfg.across = true;
        } else if (std.mem.eql(u8, arg, "-m") or std.mem.eql(u8, arg, "--merge")) {
            cfg.merge = true;
        } else if (std.mem.eql(u8, arg, "-t") or std.mem.eql(u8, arg, "--omit-header")) {
            cfg.omit_header = true;
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--double-space")) {
            cfg.double_space = true;
        } else if (std.mem.startsWith(u8, arg, "-l")) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
            cfg.page_length = try std.fmt.parseInt(usize, val, 10);
        } else if (std.mem.startsWith(u8, arg, "-w")) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
            cfg.page_width = try std.fmt.parseInt(usize, val, 10);
        } else if (std.mem.startsWith(u8, arg, "-o")) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
            cfg.indent = try std.fmt.parseInt(usize, val, 10);
        } else if (std.mem.startsWith(u8, arg, "-h")) {
            cfg.header_text = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
        } else if (std.mem.startsWith(u8, arg, "-n")) {
            cfg.number_lines = true;
            if (arg.len > 2) {
                cfg.number_digits = std.fmt.parseInt(usize, arg[2..], 10) catch 5;
            }
        } else if (std.mem.startsWith(u8, arg, "-N")) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
            cfg.start_line_num = try std.fmt.parseInt(usize, val, 10);
        } else if (std.mem.startsWith(u8, arg, "-") and !std.mem.eql(u8, arg, "-")) {
            return 1;
        } else {
            try files.append(allocator, arg);
        }
    }
    return null;
}
