const std = @import("std");
const c = @import("../compat/c.zig").c;
const types = @import("pr/types.zig");
const page = @import("pr/page.zig");

pub const name: []const u8 = "pr";
pub const version: []const u8 = "0.1.0";

pub const PrConfig = types.PrConfig;

fn processFd(fd: c_int, writer: anytype, filename: []const u8, cfg: *const PrConfig, allocator: std.mem.Allocator) !void {
    const body_lines = if (cfg.omit_header) cfg.page_length else (if (cfg.page_length > 10) cfg.page_length - 10 else cfg.page_length);

    var cur_page: usize = 1;
    var line_on_page: usize = 0;
    var line_num = cfg.start_line_num;

    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var all_lines: std.ArrayList([]const u8) = .empty;

    var in_buf: [16384]u8 = undefined;
    var cur_line: std.ArrayList(u8) = .empty;

    while (true) {
        const nr = c.read(fd, &in_buf, in_buf.len);
        if (nr <= 0) break;
        const n: usize = @intCast(nr);
        for (in_buf[0..n]) |b| {
            if (b == '\n') {
                try all_lines.append(a, try a.dupe(u8, cur_line.items));
                cur_line.clearRetainingCapacity();
            } else {
                try cur_line.append(a, b);
            }
        }
    }
    if (cur_line.items.len > 0) {
        try all_lines.append(a, try a.dupe(u8, cur_line.items));
    }

    if (cfg.columns > 1 and !cfg.across) {
        try renderDownColumns(writer, all_lines.items, filename, cfg, body_lines);
        return;
    }

    var i: usize = 0;
    while (i < all_lines.items.len) {
        if (line_on_page == 0) {
            if (shouldOutputPage(cur_page, cfg)) {
                try page.printHeader(writer, filename, cur_page, cfg);
            }
        }

        const out_active = shouldOutputPage(cur_page, cfg);
        if (out_active) {
            try page.printIndent(writer, cfg.indent);
            if (cfg.number_lines) {
                try writer.print("{d:>5}{s}", .{ line_num, cfg.number_sep });
            }
            try writer.writeAll(all_lines.items[i]);
            try writer.writeByte('\n');
            if (cfg.double_space) try writer.writeByte('\n');
        }

        line_num += 1;
        line_on_page += if (cfg.double_space) 2 else 1;
        i += 1;

        if (line_on_page >= body_lines) {
            if (out_active) {
                try page.printFooter(writer, cfg);
            }
            cur_page += 1;
            line_on_page = 0;
        }
    }

    if (line_on_page > 0 and shouldOutputPage(cur_page, cfg)) {
        if (!cfg.omit_header) {
            while (line_on_page < body_lines) : (line_on_page += 1) {
                try writer.writeByte('\n');
            }
            try page.printFooter(writer, cfg);
        }
    }
}

fn shouldOutputPage(p: usize, cfg: *const PrConfig) bool {
    if (p < cfg.first_page) return false;
    if (cfg.last_page) |lp| {
        if (p > lp) return false;
    }
    return true;
}

fn renderDownColumns(writer: anytype, lines: []const []const u8, filename: []const u8, cfg: *const PrConfig, body_lines: usize) !void {
    const col_width = if (cfg.page_width > cfg.columns) cfg.page_width / cfg.columns else 10;
    var cur_page: usize = 1;
    var i: usize = 0;

    while (i < lines.len) {
        if (shouldOutputPage(cur_page, cfg)) {
            try page.printHeader(writer, filename, cur_page, cfg);
        }
        const out_active = shouldOutputPage(cur_page, cfg);

        const page_line_count = @min(lines.len - i, body_lines * cfg.columns);
        const rows = (page_line_count + cfg.columns - 1) / cfg.columns;

        for (0..rows) |row| {
            if (out_active) {
                try page.printIndent(writer, cfg.indent);
                for (0..cfg.columns) |c_idx| {
                    const l_idx = i + c_idx * rows + row;
                    if (l_idx < i + page_line_count and l_idx < lines.len) {
                        const l = lines[l_idx];
                        try writer.writeAll(l);
                        if (c_idx + 1 < cfg.columns and l.len < col_width) {
                            for (0..(col_width - l.len)) |_| try writer.writeByte(' ');
                        }
                    }
                }
                try writer.writeByte('\n');
            }
        }

        if (out_active) {
            try page.printFooter(writer, cfg);
        }

        i += page_line_count;
        cur_page += 1;
    }
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var cfg = PrConfig{};
    var files: std.ArrayList([]const u8) = .empty;
    defer files.deinit(allocator);

    if (types.parseArgs(&cfg, &files, args, allocator, version) catch return 1) |code| return code;

    var out_buf: [16384]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &out_buf);
    const writer = &out_w.interface;

    if (files.items.len == 0) {
        processFd(0, writer, "", &cfg, allocator) catch |err| {
            if (err == error.DiskFull or err == error.NoSpaceLeft or err == error.WriteFailed) return 1;
            return err;
        };
    } else {
        for (files.items) |fp| {
            if (std.mem.eql(u8, fp, "-")) {
                processFd(0, writer, "", &cfg, allocator) catch return 1;
            } else {
                var zpath: [std.fs.max_path_bytes:0]u8 = undefined;
                if (fp.len >= zpath.len) return 1;
                @memcpy(zpath[0..fp.len], fp);
                zpath[fp.len] = 0;
                const fd = c.open(&zpath, c.O_RDONLY);
                if (fd < 0) return 1;
                defer _ = c.close(fd);
                processFd(fd, writer, fp, &cfg, allocator) catch return 1;
            }
        }
    }

    out_w.interface.flush() catch return 1;
    return 0;
}
