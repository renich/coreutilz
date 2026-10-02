const std = @import("std");
const c = @import("../compat/c.zig").c;
const types = @import("nl/types.zig");
const options = @import("nl/options.zig");

pub const name: []const u8 = "nl";
pub const version: []const u8 = "0.1.0";

pub const StyleType = types.StyleType;
pub const NumberingStyle = types.NumberingStyle;
pub const Format = types.Format;
pub const Section = types.Section;
pub const NlConfig = types.NlConfig;
pub const parseStyle = types.parseStyle;

fn printLineNumber(writer: anytype, num: i64, cfg: *const NlConfig) !void {
    var num_buf: [64]u8 = undefined;
    const str = std.fmt.bufPrint(&num_buf, "{d}", .{num}) catch return error.FormatError;
    const w = cfg.width;
    switch (cfg.format) {
        .ln => {
            try writer.writeAll(str);
            if (str.len < w) {
                for (0..(w - str.len)) |_| try writer.writeByte(' ');
            }
        },
        .rn => {
            if (str.len < w) {
                for (0..(w - str.len)) |_| try writer.writeByte(' ');
            }
            try writer.writeAll(str);
        },
        .rz => {
            if (num < 0) {
                try writer.writeByte('-');
                const abs_str = str[1..];
                if (abs_str.len + 1 < w) {
                    for (0..(w - (abs_str.len + 1))) |_| try writer.writeByte('0');
                }
                try writer.writeAll(abs_str);
            } else {
                if (str.len < w) {
                    for (0..(w - str.len)) |_| try writer.writeByte('0');
                }
                try writer.writeAll(str);
            }
        },
    }
    try writer.writeAll(cfg.separator);
}

fn printNoNumber(writer: anytype, cfg: *const NlConfig) !void {
    for (0..(cfg.width + cfg.separator.len)) |_| try writer.writeByte(' ');
}

fn matchesRegex(re_buf: *const [64]u8, line: []const u8) bool {
    var zline: [4096]u8 = undefined;
    const copy_len = @min(line.len, zline.len - 1);
    @memcpy(zline[0..copy_len], line[0..copy_len]);
    zline[copy_len] = 0;
    return c.regexec(@ptrCast(re_buf), &zline, 0, null, 0) == 0;
}

fn processFile(fd: c_int, writer: anytype, cfg: *const NlConfig) !void {
    var cur_section = Section.body;
    var line_num = cfg.start_num;
    var overflowed = false;
    var blank_count: usize = 0;

    var header_del: [64]u8 = undefined;
    var body_del: [64]u8 = undefined;
    var footer_del: [64]u8 = undefined;
    const dlen = cfg.delim.len;
    var hlen: usize = 0;
    var blen: usize = 0;
    var flen: usize = 0;
    if (cfg.delim_enabled and dlen > 0 and dlen * 3 <= 64) {
        @memcpy(header_del[0..dlen], cfg.delim);
        @memcpy(header_del[dlen .. dlen * 2], cfg.delim);
        @memcpy(header_del[dlen * 2 .. dlen * 3], cfg.delim);
        hlen = dlen * 3;
        @memcpy(body_del[0..dlen], cfg.delim);
        @memcpy(body_del[dlen .. dlen * 2], cfg.delim);
        blen = dlen * 2;
        @memcpy(footer_del[0..dlen], cfg.delim);
        flen = dlen;
    }

    var in_buf: [16384]u8 = undefined;
    var line_buf: [16384]u8 = undefined;
    var pos: usize = 0;

    while (true) {
        const nr = c.read(fd, &in_buf, in_buf.len);
        if (nr <= 0) {
            if (pos > 0) {
                try processLine(writer, line_buf[0..pos], &cur_section, &line_num, &overflowed, &blank_count, cfg, header_del[0..hlen], body_del[0..blen], footer_del[0..flen]);
            }
            break;
        }
        for (in_buf[0..@as(usize, @intCast(nr))]) |b| {
            if (b == '\n') {
                try processLine(writer, line_buf[0..pos], &cur_section, &line_num, &overflowed, &blank_count, cfg, header_del[0..hlen], body_del[0..blen], footer_del[0..flen]);
                pos = 0;
            } else {
                if (pos < line_buf.len) {
                    line_buf[pos] = b;
                    pos += 1;
                }
            }
        }
    }
}

fn processLine(
    writer: anytype,
    line: []const u8,
    cur_section: *Section,
    line_num: *i64,
    overflowed: *bool,
    blank_count: *usize,
    cfg: *const NlConfig,
    hdel: []const u8,
    bdel: []const u8,
    fdel: []const u8,
) !void {
    if (cfg.delim_enabled and hdel.len > 0) {
        if (std.mem.eql(u8, line, hdel)) {
            cur_section.* = .header;
            if (cfg.renumber) {
                line_num.* = cfg.start_num;
                overflowed.* = false;
            }
            try writer.writeByte('\n');
            return;
        } else if (std.mem.eql(u8, line, bdel)) {
            cur_section.* = .body;
            if (cfg.renumber) {
                line_num.* = cfg.start_num;
                overflowed.* = false;
            }
            try writer.writeByte('\n');
            return;
        } else if (std.mem.eql(u8, line, fdel)) {
            cur_section.* = .footer;
            if (cfg.renumber) {
                line_num.* = cfg.start_num;
                overflowed.* = false;
            }
            try writer.writeByte('\n');
            return;
        }
    }

    const cur_style = switch (cur_section.*) {
        .header => &cfg.header_style,
        .body => &cfg.body_style,
        .footer => &cfg.footer_style,
    };

    var should_number = false;
    switch (cur_style.type) {
        .all => {
            if (line.len == 0) {
                blank_count.* += 1;
                if (blank_count.* >= cfg.blank_join) {
                    should_number = true;
                    blank_count.* = 0;
                }
            } else {
                blank_count.* = 0;
                should_number = true;
            }
        },
        .nonempty => {
            blank_count.* = 0;
            should_number = line.len > 0;
        },
        .none => {
            should_number = false;
        },
        .regex => {
            should_number = if (cur_style.has_regex) matchesRegex(&cur_style.regex_buf, line) else false;
        },
    }

    if (should_number) {
        if (overflowed.*) {
            var err_buf: [128]u8 = undefined;
            var ew = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &err_buf);
            try ew.interface.print("nl: line number overflow\n", .{});
            ew.interface.flush() catch {};
            return error.Overflow;
        }
        try printLineNumber(writer, line_num.*, cfg);
        const add_res = @addWithOverflow(line_num.*, cfg.increment);
        if (add_res[1] != 0) {
            overflowed.* = true;
        } else {
            line_num.* = add_res[0];
        }
    } else {
        try printNoNumber(writer, cfg);
    }
    try writer.writeAll(line);
    try writer.writeByte('\n');
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var cfg = NlConfig{};
    defer cfg.deinit();

    var files: std.ArrayList([]const u8) = .empty;
    defer files.deinit(allocator);

    if (options.parseOptions(&cfg, &files, args, allocator, version) catch return 1) |code| return code;

    var out_buf: [16384]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &out_buf);

    if (files.items.len == 0) {
        processFile(c.STDIN_FILENO, &out_w.interface, &cfg) catch |err| {
            if (err == error.DiskFull or err == error.NoSpaceLeft or err == error.WriteFailed or err == error.Overflow) return 1;
            return err;
        };
    } else {
        for (files.items) |fp| {
            if (std.mem.eql(u8, fp, "-")) {
                processFile(c.STDIN_FILENO, &out_w.interface, &cfg) catch return 1;
            } else {
                var zpath: [std.fs.max_path_bytes:0]u8 = undefined;
                if (fp.len >= zpath.len) return 1;
                @memcpy(zpath[0..fp.len], fp);
                zpath[fp.len] = 0;
                const fd = c.open(&zpath, c.O_RDONLY);
                if (fd < 0) {
                    var err_buf: [256]u8 = undefined;
                    var ew = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &err_buf);
                    try ew.interface.print("nl: {s}: No such file or directory\n", .{fp});
                    ew.interface.flush() catch {};
                    return 1;
                }
                defer _ = c.close(fd);
                processFile(fd, &out_w.interface, &cfg) catch return 1;
            }
        }
    }

    out_w.interface.flush() catch return 1;
    return 0;
}
