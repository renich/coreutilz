const std = @import("std");
const c = @import("../compat/c.zig").c;
const types = @import("ptx/types.zig");
const index = @import("ptx/index.zig");

pub const name: []const u8 = "ptx";
pub const version: []const u8 = "0.1.0";

pub const OutputFormat = types.OutputFormat;
pub const PtxConfig = types.PtxConfig;

fn processFiles(writer: anytype, files: []const []const u8, cfg: *const PtxConfig, allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var all_lines: std.ArrayList([]const u8) = .empty;

    if (files.len == 0) {
        try readAllLinesFd(c.STDIN_FILENO, &all_lines, a);
    } else {
        for (files) |fp| {
            if (std.mem.eql(u8, fp, "-")) {
                try readAllLinesFd(c.STDIN_FILENO, &all_lines, a);
            } else {
                var zpath: [std.fs.max_path_bytes:0]u8 = undefined;
                if (fp.len >= zpath.len) return;
                @memcpy(zpath[0..fp.len], fp);
                zpath[fp.len] = 0;
                const fd = c.open(&zpath, c.O_RDONLY);
                if (fd < 0) {
                    var err_buf: [256]u8 = undefined;
                    var ew = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &err_buf);
                    try ew.interface.print("ptx: {s}: No such file or directory\n", .{fp});
                    ew.interface.flush() catch {};
                    return;
                }
                defer _ = c.close(fd);
                try readAllLinesFd(fd, &all_lines, a);
            }
        }
    }

    var occurs: std.ArrayList(index.Occurrence) = .empty;

    for (all_lines.items, 0..) |line, l_idx| {
        var words: std.ArrayList([]const u8) = .empty;
        var it = std.mem.tokenizeAny(u8, line, " \t\r");
        while (it.next()) |tok| {
            try words.append(a, tok);
        }

        for (words.items, 0..) |kw, k_idx| {
            var before: std.ArrayList(u8) = .empty;
            for (words.items[0..k_idx], 0..) |prev_w, pi| {
                if (pi > 0) try before.append(a, ' ');
                try before.appendSlice(a, prev_w);
            }

            var after: std.ArrayList(u8) = .empty;
            for (words.items[k_idx + 1 ..], 0..) |post_w, ai| {
                if (ai > 0) try after.append(a, ' ');
                try after.appendSlice(a, post_w);
            }

            try occurs.append(a, .{
                .keyword = kw,
                .before = before.items,
                .after = after.items,
                .line_idx = l_idx,
            });
        }
    }

    std.mem.sort(index.Occurrence, occurs.items, cfg.ignore_case, index.lessThanOccurs);

    try index.renderOutput(writer, occurs.items, cfg);
}

fn readAllLinesFd(fd: c_int, lines: *std.ArrayList([]const u8), a: std.mem.Allocator) !void {
    var in_buf: [16384]u8 = undefined;
    var cur: std.ArrayList(u8) = .empty;
    while (true) {
        const nr = c.read(fd, &in_buf, in_buf.len);
        if (nr <= 0) break;
        for (in_buf[0..@as(usize, @intCast(nr))]) |b| {
            if (b == '\n') {
                try lines.append(a, try a.dupe(u8, cur.items));
                cur.clearRetainingCapacity();
            } else {
                try cur.append(a, b);
            }
        }
    }
    if (cur.items.len > 0) {
        try lines.append(a, try a.dupe(u8, cur.items));
    }
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var cfg = PtxConfig{};
    var files: std.ArrayList([]const u8) = .empty;
    defer files.deinit(allocator);

    if (types.parseArgs(&cfg, &files, args, allocator, version) catch return 1) |code| return code;

    var out_buf: [16384]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &out_buf);
    const writer = &out_w.interface;

    processFiles(writer, files.items, &cfg, allocator) catch |err| {
        if (err == error.DiskFull or err == error.NoSpaceLeft or err == error.WriteFailed) return 1;
        return err;
    };

    out_w.interface.flush() catch return 1;
    return 0;
}
