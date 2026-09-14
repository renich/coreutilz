const std = @import("std");
const types = @import("types.zig");
const colors_mod = @import("colors.zig");
const quoting = @import("quoting.zig");
const details = @import("details.zig");
const dired_mod = @import("dired.zig");
const hyperlink_mod = @import("hyperlink.zig");
const long_format_mod = @import("long_format.zig");

const FileEntry = types.FileEntry;
const Options = types.Options;
const Colors = colors_mod.Colors;

pub const getIndicatorChar = quoting.getIndicatorChar;
pub const formatQuotedName = quoting.formatQuotedName;
pub const printLongListing = long_format_mod.printLongListing;

fn printColoredQuotedName(
    writer: anytype,
    quoted: []const u8,
    entry: *const FileEntry,
    colors: *const Colors,
    use_color: bool,
    used_color: *bool,
) !void {
    if (!use_color) {
        try writer.writeAll(quoted);
        return;
    }
    const col_opt = colors.getColor(entry);
    const has_norm = colors_mod.isColored(colors.no);
    if (col_opt) |col| {
        if (has_norm) try writer.writeAll("\x1b[m");
        if (!used_color.*) {
            try writer.writeAll("\x1b[0m");
            used_color.* = true;
        }
        try writer.print("\x1b[{s}m", .{col});
    }
    try writer.writeAll(quoted);
    if (col_opt != null or has_norm) try writer.writeAll("\x1b[0m");
}

pub fn printEntryName(
    writer: anytype,
    entry: *const FileEntry,
    options: *const Options,
    colors: *const Colors,
    use_color: bool,
    used_color: *bool,
    arena: std.mem.Allocator,
) !void {
    var name_buf: [1024]u8 = undefined;
    const quoted = formatQuotedName(entry.name, options.quoting_style, options.hide_control_chars, &name_buf);

    if (options.hyperlink) {
        const uri = try hyperlink_mod.getAbsoluteUri(arena, entry.full_path);
        try hyperlink_mod.printHyperlinkStart(writer, uri);
    }
    try printColoredQuotedName(writer, quoted, entry, colors, use_color, used_color);
    if (options.hyperlink) try hyperlink_mod.printHyperlinkEnd(writer);
    if (getIndicatorChar(entry, options)) |ch| try writer.writeByte(ch);
}

pub fn printOnePerLine(
    writer: anytype,
    entries: []const FileEntry,
    options: *const Options,
    colors: *const Colors,
    use_color: bool,
    used_color: *bool,
    arena: std.mem.Allocator,
) !void {
    const term_char: u8 = if (options.zero) 0 else '\n';
    for (entries) |*entry| {
        try colors_mod.setNormalColor(writer, colors, use_color, used_color);
        try details.printPrefix(writer, entry, options);
        try printEntryName(writer, entry, options, colors, use_color, used_color, arena);
        try writer.writeByte(term_char);
    }
}

pub fn printCommaStream(
    writer: anytype,
    entries: []const FileEntry,
    options: *const Options,
    colors: *const Colors,
    use_color: bool,
    used_color: *bool,
    arena: std.mem.Allocator,
) !void {
    var cur_col: usize = 0;
    for (entries, 0..) |*entry, idx| {
        try colors_mod.setNormalColor(writer, colors, use_color, used_color);
        try details.printPrefix(writer, entry, options);
        try printEntryName(writer, entry, options, colors, use_color, used_color, arena);
        cur_col += details.getVisibleLen(entry, options);

        if (idx + 1 < entries.len) {
            const next_len = details.getVisibleLen(&entries[idx + 1], options);
            if (options.term_width > 0 and cur_col + 2 + next_len > options.term_width) {
                try writer.writeAll(",\n");
                cur_col = 0;
            } else {
                try writer.writeAll(", ");
                cur_col += 2;
            }
        }
    }
    if (entries.len > 0) try writer.writeByte(if (options.zero) 0 else '\n');
}

fn indentTo(writer: anytype, from: usize, to: usize, tabsize: usize) !void {
    var cur = from;
    while (cur < to) {
        if (tabsize != 0 and (to / tabsize) > ((cur + 1) / tabsize)) {
            try writer.writeByte('\t');
            cur += tabsize - (cur % tabsize);
        } else {
            try writer.writeByte(' ');
            cur += 1;
        }
    }
}

fn computeMaxWidth(entries: []const FileEntry, options: *const Options, align_quotes: bool, cwd_some_quoted: bool) usize {
    var max_width: usize = 0;
    for (entries) |*entry| {
        var len: usize = 0;
        if (options.inode) len += 10;
        if (options.size_blocks) len += 8;
        var name_buf: [1024]u8 = undefined;
        const quoted = formatQuotedName(entry.name, options.quoting_style, options.hide_control_chars, &name_buf);
        len += quoted.len;
        if (align_quotes and cwd_some_quoted and !quoting.needsQuoting(entry.name, options.quoting_style)) len += 1;
        if (getIndicatorChar(entry, options) != null) len += 1;
        if (len > max_width) max_width = len;
    }
    return max_width;
}

fn computeColWidths(entries: []const FileEntry, options: *const Options, across: bool, num_cols: usize, num_rows: usize, col_widths: []usize) void {
    for (0..col_widths.len) |c_idx| {
        for (0..num_rows) |r| {
            const idx = if (across) r * num_cols + c_idx else c_idx * num_rows + r;
            if (idx >= entries.len) continue;
            var elen: usize = 0;
            if (options.inode) elen += 10;
            if (options.size_blocks) elen += 8;
            var name_buf: [1024]u8 = undefined;
            const quoted = formatQuotedName(entries[idx].name, options.quoting_style, options.hide_control_chars, &name_buf);
            elen += quoted.len;
            if (getIndicatorChar(&entries[idx], options) != null) elen += 1;
            if (elen > col_widths[c_idx]) col_widths[c_idx] = elen;
        }
    }
}

fn printColumnCell(
    writer: anytype,
    entry: *const FileEntry,
    options: *const Options,
    align_quotes: bool,
    cwd_some_quoted: bool,
    colors: *const Colors,
    use_color: bool,
    used_color: *bool,
    arena: std.mem.Allocator,
) !usize {
    try colors_mod.setNormalColor(writer, colors, use_color, used_color);
    var entry_len: usize = 0;
    if (options.inode or options.size_blocks) {
        try details.printPrefix(writer, entry, options);
        entry_len += 8;
    }
    var name_buf: [1024]u8 = undefined;
    const quoted = formatQuotedName(entry.name, options.quoting_style, options.hide_control_chars, &name_buf);
    entry_len += quoted.len;
    if (align_quotes and cwd_some_quoted and !quoting.needsQuoting(entry.name, options.quoting_style)) {
        try writer.writeByte(' ');
    }
    if (getIndicatorChar(entry, options) != null) entry_len += 1;
    try printEntryName(writer, entry, options, colors, use_color, used_color, arena);
    return entry_len;
}

pub fn printColumns(
    writer: anytype,
    entries: []const FileEntry,
    options: *const Options,
    across: bool,
    colors: *const Colors,
    use_color: bool,
    used_color: *bool,
    arena: std.mem.Allocator,
) !void {
    if (entries.len == 0) return;
    const align_quotes = options.term_width > 0 and quoting.shouldAlignVariableQuotes(options);
    const cwd_some_quoted = align_quotes and quoting.hasQuotedEntry(entries, options.quoting_style);
    const max_width = computeMaxWidth(entries, options, align_quotes, cwd_some_quoted);
    const num_cols = if (options.term_width == 0) entries.len else @min(entries.len, @max(1, (options.term_width + 2) / (max_width + 2)));
    const num_rows = if (options.term_width == 0) 1 else (entries.len + num_cols - 1) / num_cols;
    var col_widths: [256]usize = [_]usize{0} ** 256;
    const effective_cols = @min(num_cols, 256);
    computeColWidths(entries, options, across, num_cols, num_rows, col_widths[0..effective_cols]);

    for (0..num_rows) |r| {
        for (0..num_cols) |c_idx| {
            const idx = if (across) r * num_cols + c_idx else c_idx * num_rows + r;
            if (idx >= entries.len) continue;
            const entry_len = try printColumnCell(writer, &entries[idx], options, align_quotes, cwd_some_quoted, colors, use_color, used_color, arena);
            const is_last = if (across) (c_idx + 1 == num_cols or idx + 1 == entries.len) else ((c_idx + 1) * num_rows + r >= entries.len);
            if (!is_last) {
                const target_col_width = if (c_idx < effective_cols) col_widths[c_idx] else max_width;
                const effective_tabsize = if (options.term_width == 0) 0 else options.tab_size;
                try indentTo(writer, entry_len, target_col_width + 2, effective_tabsize);
            }
        }
        try writer.writeByte('\n');
    }
}

pub fn printTotal(
    writer: anytype,
    entries: []const FileEntry,
    options: *const Options,
    dired_ctx: ?*dired_mod.DiredContext,
) !void {
    var total_blocks: u64 = 0;
    for (entries) |*entry| {
        if (!entry.has_stat_error) {
            total_blocks += (@as(u64, @intCast(entry.stat.st_blocks)) * 512 + options.disk_block_size - 1) / options.disk_block_size;
        }
    }
    if (dired_ctx) |d| try d.indent(writer);
    try writer.print("total {d}\n", .{total_blocks});
    if (dired_ctx) |d| {
        var b: [32]u8 = undefined;
        const s = std.fmt.bufPrint(&b, "total {d}\n", .{total_blocks}) catch "";
        d.pos += s.len;
    }
}

pub fn renderEntries(
    writer: anytype,
    entries: []const FileEntry,
    options: *const Options,
    print_total: bool,
    colors: *const Colors,
    use_color: bool,
    used_color: *bool,
    dired_ctx: ?*dired_mod.DiredContext,
    arena: std.mem.Allocator,
) !void {
    if (print_total) {
        try printTotal(writer, entries, options, dired_ctx);
    }
    switch (options.format) {
        .long => try long_format_mod.printLongListing(writer, entries, options, colors, use_color, used_color, dired_ctx, arena, printEntryName),
        .one_per_line => try printOnePerLine(writer, entries, options, colors, use_color, used_color, arena),
        .comma => try printCommaStream(writer, entries, options, colors, use_color, used_color, arena),
        .columns => try printColumns(writer, entries, options, false, colors, use_color, used_color, arena),
        .across => try printColumns(writer, entries, options, true, colors, use_color, used_color, arena),
    }
}
