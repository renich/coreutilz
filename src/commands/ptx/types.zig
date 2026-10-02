const std = @import("std");

pub const OutputFormat = enum { dumb, roff, tex };

pub const PtxConfig = struct {
    ignore_case: bool = false,
    gap_size: usize = 3,
    line_width: ?usize = null,
    format: OutputFormat = .dumb,
    macro_name: []const u8 = "xx",
    truncation_string: []const u8 = "/",
    auto_reference: bool = false,
    break_file: ?[]const u8 = null,
    ignore_file: ?[]const u8 = null,
    only_file: ?[]const u8 = null,

    pub fn getWidth(self: *const PtxConfig) usize {
        if (self.line_width) |w| return w;
        return if (self.format == .tex) 100 else 72;
    }
};

pub fn parseArgs(
    cfg: *PtxConfig,
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
            try w.interface.print("Usage: ptx [OPTION]... [INPUT]...   (without -G)\nOutput a permuted index of the words in the input files.\n", .{});
            w.interface.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            var buf: [256]u8 = undefined;
            var w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &buf);
            try w.interface.print("ptx (coreutilz) {s}\n", .{version});
            w.interface.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--ignore-case")) {
            cfg.ignore_case = true;
        } else if (std.mem.startsWith(u8, arg, "-g")) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
            cfg.gap_size = try std.fmt.parseInt(usize, val, 10);
        } else if (std.mem.startsWith(u8, arg, "-w")) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
            cfg.line_width = try std.fmt.parseInt(usize, val, 10);
        } else if (std.mem.eql(u8, arg, "-t") or std.mem.eql(u8, arg, "--format=tex")) {
            cfg.format = .tex;
            if (cfg.line_width == null) cfg.line_width = 100;
        } else if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "-O") or std.mem.eql(u8, arg, "--format=roff")) {
            cfg.format = .roff;
        } else if (std.mem.startsWith(u8, arg, "--format=")) {
            const fmt = arg["--format=".len..];
            if (std.mem.eql(u8, fmt, "roff")) cfg.format = .roff else if (std.mem.eql(u8, fmt, "tex")) {
                cfg.format = .tex;
                if (cfg.line_width == null) cfg.line_width = 100;
            } else if (std.mem.eql(u8, fmt, "dumb")) cfg.format = .dumb else return 1;
        } else if (std.mem.startsWith(u8, arg, "-b")) {
            cfg.break_file = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
        } else if (std.mem.startsWith(u8, arg, "-i")) {
            cfg.ignore_file = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
        } else if (std.mem.startsWith(u8, arg, "-o")) {
            cfg.only_file = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
        } else if (std.mem.startsWith(u8, arg, "-S")) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
            if (std.mem.eql(u8, val, "^")) {
                var err_buf: [256]u8 = undefined;
                var ew = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &err_buf);
                try ew.interface.print("ptx: regular expression has length zero\n", .{});
                ew.interface.flush() catch {};
                return 1;
            }
        } else if (std.mem.startsWith(u8, arg, "-") and !std.mem.eql(u8, arg, "-")) {
            return 1;
        } else {
            try files.append(allocator, arg);
        }
    }
    return null;
}
