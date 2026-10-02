const std = @import("std");
const c = @import("../compat/c.zig").c;
const types = @import("od/types.zig");
const format = @import("od/format.zig");

pub const name: []const u8 = "od";
pub const version: []const u8 = "0.1.0";

pub const AddressRadix = types.AddressRadix;
pub const FormatKind = types.FormatKind;
pub const FormatSpec = types.FormatSpec;
pub const OdConfig = types.OdConfig;
pub const parseFormat = types.parseFormat;

fn parseArgs(cfg: *OdConfig, files: *std.ArrayList([]const u8), args: [][]const u8, allocator: std.mem.Allocator) !?u8 {
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            var buf: [256]u8 = undefined;
            var w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &buf);
            try w.interface.print("Usage: od [OPTION]... [FILE]...\nDump files in octal and other formats.\n", .{});
            w.interface.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            var buf: [256]u8 = undefined;
            var w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &buf);
            try w.interface.print("od (coreutilz) {s}\n", .{version});
            w.interface.flush() catch return 1;
            return 0;
        } else if (std.mem.startsWith(u8, arg, "-A")) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
            if (std.mem.eql(u8, val, "d")) cfg.radix = .decimal else if (std.mem.eql(u8, val, "o")) cfg.radix = .octal else if (std.mem.eql(u8, val, "x")) cfg.radix = .hex else if (std.mem.eql(u8, val, "n")) cfg.radix = .none else return 1;
        } else if (std.mem.startsWith(u8, arg, "-j")) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
            cfg.skip_bytes = std.fmt.parseInt(u64, val, 0) catch return 1;
        } else if (std.mem.startsWith(u8, arg, "-N")) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
            cfg.read_limit = std.fmt.parseInt(u64, val, 0) catch return 1;
            cfg.has_read_limit = true;
        } else if (std.mem.startsWith(u8, arg, "-w")) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
            cfg.line_bytes = std.fmt.parseInt(usize, val, 10) catch return 1;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--output-duplicates")) {
            cfg.output_duplicates = true;
        } else if (std.mem.startsWith(u8, arg, "-t")) {
            const val = if (arg.len > 2) arg[2..] else blk: {
                i += 1;
                break :blk args[i];
            };
            try parseFormat(cfg, val, allocator);
        } else if (std.mem.eql(u8, arg, "-c")) {
            try parseFormat(cfg, "c", allocator);
        } else if (std.mem.eql(u8, arg, "-b")) {
            try parseFormat(cfg, "o1", allocator);
        } else if (std.mem.eql(u8, arg, "-d")) {
            try parseFormat(cfg, "u2", allocator);
        } else if (std.mem.eql(u8, arg, "-o")) {
            try parseFormat(cfg, "o2", allocator);
        } else if (std.mem.eql(u8, arg, "-s")) {
            try parseFormat(cfg, "d2", allocator);
        } else if (std.mem.eql(u8, arg, "-x")) {
            try parseFormat(cfg, "x2", allocator);
        } else if (std.mem.startsWith(u8, arg, "-") and !std.mem.eql(u8, arg, "-")) {
            return 1;
        } else {
            try files.append(allocator, arg);
        }
    }
    if (cfg.formats.items.len == 0) {
        try parseFormat(cfg, "o2", allocator);
    }
    return null;
}

fn dumpBytes(writer: anytype, cfg: *const OdConfig, all_bytes: []const u8) !void {
    const lb = cfg.line_bytes;
    var offset: usize = 0;
    var last_chunk: ?[]const u8 = null;
    var suppressed = false;

    while (offset < all_bytes.len) {
        const chunk_len = @min(lb, all_bytes.len - offset);
        const chunk = all_bytes[offset .. offset + chunk_len];

        if (!cfg.output_duplicates and chunk_len == lb and last_chunk != null and std.mem.eql(u8, chunk, last_chunk.?)) {
            if (!suppressed) {
                try writer.writeAll("*\n");
                suppressed = true;
            }
        } else {
            suppressed = false;
            for (cfg.formats.items, 0..) |fmt_spec, idx| {
                if (idx == 0) {
                    try format.printAddress(writer, offset, cfg.radix);
                } else if (cfg.radix != .none) {
                    const pad_len: usize = if (cfg.radix == .hex) 6 else 7;
                    for (0..pad_len) |_| try writer.writeByte(' ');
                }
                try format.printChunk(writer, chunk, fmt_spec);
                try writer.writeByte('\n');
            }
        }
        last_chunk = chunk;
        offset += chunk_len;
    }

    if (cfg.radix != .none) {
        try format.printAddress(writer, offset, cfg.radix);
        try writer.writeByte('\n');
    }
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var cfg = OdConfig{};
    defer cfg.deinit(allocator);

    var files: std.ArrayList([]const u8) = .empty;
    defer files.deinit(allocator);

    if (parseArgs(&cfg, &files, args, allocator) catch return 1) |code| return code;

    var byte_list: std.ArrayList(u8) = .empty;
    defer byte_list.deinit(allocator);

    var skip_remaining = cfg.skip_bytes;

    if (files.items.len == 0) {
        try readAndFilter(c.STDIN_FILENO, &byte_list, &skip_remaining, &cfg, allocator);
    } else {
        for (files.items) |fp| {
            if (std.mem.eql(u8, fp, "-")) {
                try readAndFilter(c.STDIN_FILENO, &byte_list, &skip_remaining, &cfg, allocator);
            } else {
                var zpath: [std.fs.max_path_bytes:0]u8 = undefined;
                if (fp.len >= zpath.len) return 1;
                @memcpy(zpath[0..fp.len], fp);
                zpath[fp.len] = 0;
                const fd = c.open(&zpath, c.O_RDONLY);
                if (fd < 0) {
                    var err_buf: [256]u8 = undefined;
                    var ew = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &err_buf);
                    try ew.interface.print("od: {s}: No such file or directory\n", .{fp});
                    ew.interface.flush() catch {};
                    return 1;
                }
                defer _ = c.close(fd);
                try readAndFilter(fd, &byte_list, &skip_remaining, &cfg, allocator);
            }
        }
    }

    var out_buf: [16384]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &out_buf);
    dumpBytes(&out_w.interface, &cfg, byte_list.items) catch |err| {
        if (err == error.DiskFull or err == error.NoSpaceLeft or err == error.WriteFailed) return 1;
        return err;
    };

    out_w.interface.flush() catch return 1;
    return 0;
}

fn readAndFilter(fd: c_int, list: *std.ArrayList(u8), skip_rem: *u64, cfg: *const OdConfig, allocator: std.mem.Allocator) !void {
    var chunk: [16384]u8 = undefined;

    while (true) {
        if (cfg.has_read_limit and list.items.len >= cfg.read_limit) break;
        const nr = c.read(fd, &chunk, chunk.len);
        if (nr <= 0) break;
        const n: usize = @intCast(nr);
        var slice = chunk[0..n];
        if (skip_rem.* > 0) {
            if (skip_rem.* >= slice.len) {
                skip_rem.* -= slice.len;
                continue;
            }
            slice = slice[@as(usize, @intCast(skip_rem.*))..];
            skip_rem.* = 0;
        }
        if (cfg.has_read_limit) {
            const allowed = @as(usize, @intCast(@min(@as(u64, slice.len), cfg.read_limit - list.items.len)));
            slice = slice[0..allowed];
        }
        try list.appendSlice(allocator, slice);
    }
}
