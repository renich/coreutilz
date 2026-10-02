const std = @import("std");
const c = @import("../compat/c.zig").c;
const options = @import("fmt/options.zig");
const paragraph = @import("fmt/paragraph.zig");

pub const name: []const u8 = "fmt";
pub const version: []const u8 = "0.1.0";

pub const FmtOptions = options.FmtOptions;

fn processFd(fd: c_int, writer: anytype, opts: *const FmtOptions, allocator: std.mem.Allocator) !void {
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var lines: std.ArrayList([]const u8) = .empty;

    var buf: [16384]u8 = undefined;
    var line_buf: std.ArrayList(u8) = .empty;

    while (true) {
        const nr = c.read(fd, &buf, buf.len);
        if (nr <= 0) break;
        const n: usize = @intCast(nr);
        for (buf[0..n]) |b| {
            if (b == '\n') {
                try lines.append(a, try a.dupe(u8, line_buf.items));
                line_buf.clearRetainingCapacity();
            } else {
                try line_buf.append(a, b);
            }
        }
    }
    if (line_buf.items.len > 0) {
        try lines.append(a, try a.dupe(u8, line_buf.items));
    }

    try processLines(writer, lines.items, opts, a);
}

fn processLines(writer: anytype, lines: []const []const u8, opts: *const FmtOptions, a: std.mem.Allocator) !void {
    var p_start: usize = 0;
    while (p_start < lines.len) {
        const line = lines[p_start];
        if (opts.prefix) |pfx| {
            if (!std.mem.startsWith(u8, line, pfx)) {
                try writer.writeAll(line);
                try writer.writeByte('\n');
                p_start += 1;
                continue;
            }
        }
        if (isLineBlank(line, opts.prefix)) {
            try writer.writeAll(line);
            try writer.writeByte('\n');
            p_start += 1;
            continue;
        }

        var p_end = p_start + 1;
        while (p_end < lines.len) {
            const next_line = lines[p_end];
            if (opts.prefix) |pfx| {
                if (!std.mem.startsWith(u8, next_line, pfx)) break;
            }
            if (isLineBlank(next_line, opts.prefix)) break;
            p_end += 1;
        }

        try formatLines(writer, lines[p_start..p_end], opts, a);
        p_start = p_end;
    }
}

fn isLineBlank(line: []const u8, prefix: ?[]const u8) bool {
    var s = line;
    if (prefix) |pfx| {
        if (std.mem.startsWith(u8, s, pfx)) s = s[pfx.len..];
    }
    for (s) |ch| {
        if (ch != ' ' and ch != '\t') return false;
    }
    return true;
}

fn formatLines(writer: anytype, p_lines: []const []const u8, opts: *const FmtOptions, a: std.mem.Allocator) !void {
    if (p_lines.len == 0) return;

    const pfx = opts.prefix orelse "";
    const first_full = p_lines[0];
    const first_raw = if (pfx.len > 0 and std.mem.startsWith(u8, first_full, pfx)) first_full[pfx.len..] else first_full;
    const first_indent = getIndent(first_raw);

    var other_indent = first_indent;
    if (opts.crown_margin and p_lines.len > 1) {
        const snd_full = p_lines[1];
        const snd_raw = if (pfx.len > 0 and std.mem.startsWith(u8, snd_full, pfx)) snd_full[pfx.len..] else snd_full;
        other_indent = getIndent(snd_raw);
    } else if (opts.tagged_paragraph and p_lines.len > 1) {
        const snd_full = p_lines[1];
        const snd_raw = if (pfx.len > 0 and std.mem.startsWith(u8, snd_full, pfx)) snd_full[pfx.len..] else snd_full;
        const snd_ind = getIndent(snd_raw);
        if (!std.mem.eql(u8, first_indent, snd_ind)) {
            other_indent = snd_ind;
        } else {
            other_indent = "   ";
        }
    }

    var words: std.ArrayList(paragraph.Word) = .empty;
    for (p_lines) |line| {
        const content = if (pfx.len > 0 and std.mem.startsWith(u8, line, pfx)) line[pfx.len..] else line;
        var it = std.mem.tokenizeAny(u8, content, " \t");
        while (it.next()) |tok| {
            try words.append(a, .{
                .text = tok,
                .is_sentence_end = paragraph.isSentenceEnd(tok),
                .space_after = 1,
            });
        }
    }

    try paragraph.formatParagraph(writer, words.items, pfx, first_indent, other_indent, opts, a);
}

fn getIndent(s: []const u8) []const u8 {
    var i: usize = 0;
    while (i < s.len and (s[i] == ' ' or s[i] == '\t')) : (i += 1) {}
    return s[0..i];
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var opts = FmtOptions{};
    var files: std.ArrayList([]const u8) = .empty;
    defer files.deinit(allocator);

    if (options.parseOptions(&opts, &files, args, allocator, version) catch return 1) |code| return code;

    var out_buf: [16384]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &out_buf);
    const writer = &out_w.interface;

    if (files.items.len == 0) {
        processFd(0, writer, &opts, allocator) catch |err| {
            if (err == error.DiskFull or err == error.NoSpaceLeft or err == error.WriteFailed) return 1;
            return err;
        };
    } else {
        for (files.items) |fp| {
            if (std.mem.eql(u8, fp, "-")) {
                processFd(0, writer, &opts, allocator) catch return 1;
            } else {
                var zpath: [std.fs.max_path_bytes:0]u8 = undefined;
                if (fp.len >= zpath.len) return 1;
                @memcpy(zpath[0..fp.len], fp);
                zpath[fp.len] = 0;
                const fd = c.open(&zpath, c.O_RDONLY);
                if (fd < 0) {
                    var err_buf: [256]u8 = undefined;
                    var ew = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &err_buf);
                    try ew.interface.print("fmt: cannot open '{s}' for reading: No such file or directory\n", .{fp});
                    ew.interface.flush() catch {};
                    return 1;
                }
                defer _ = c.close(fd);
                processFd(fd, writer, &opts, allocator) catch return 1;
            }
        }
    }

    out_w.interface.flush() catch return 1;
    return 0;
}
