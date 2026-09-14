const std = @import("std");
const c = @import("../../compat/c.zig").c;
const types = @import("types.zig");
const colors_mod = @import("colors.zig");
const quoting = @import("quoting.zig");
const details = @import("details.zig");
const dired_mod = @import("dired.zig");
const hyperlink_mod = @import("hyperlink.zig");

const FileEntry = types.FileEntry;
const Options = types.Options;
const Colors = colors_mod.Colors;
const formatQuotedName = quoting.formatQuotedName;

fn printSymlinkTarget(
    writer: anytype,
    entry: *const FileEntry,
    options: *const Options,
    colors: *const Colors,
    use_color: bool,
    dired_ctx: ?*dired_mod.DiredContext,
    arena: std.mem.Allocator,
) !void {
    const target = entry.link_target orelse return;
    var target_buf: [1024]u8 = undefined;
    const target_str = formatQuotedName(target, options.quoting_style, options.hide_control_chars, &target_buf);
    try writer.writeAll(" -> ");
    if (dired_ctx) |d| d.pos += 4;

    if (options.hyperlink) {
        const uri = try hyperlink_mod.getAbsoluteUri(arena, target);
        try hyperlink_mod.printHyperlinkStart(writer, uri);
    }

    if (use_color and (entry.is_broken_link or entry.has_stat_error) and (colors.mi != null or colors.or_col != null)) {
        const col = colors.mi orelse colors.or_col.?;
        try writer.print("\x1b[{s}m{s}\x1b[0m", .{ col, target_str });
    } else {
        try writer.writeAll(target_str);
    }

    if (options.hyperlink) {
        try hyperlink_mod.printHyperlinkEnd(writer);
    }
    if (dired_ctx) |d| d.pos += target_str.len;
}

fn computeLongListingWidths(entries: []const FileEntry, options: *const Options, max_nlink_w: *usize, max_size_w: *usize) void {
    var temp_buf: [64]u8 = undefined;
    for (entries) |*entry| {
        if (!entry.has_stat_error) {
            if (std.fmt.bufPrint(&temp_buf, "{d}", .{entry.stat.st_nlink})) |s| {
                if (s.len > max_nlink_w.*) max_nlink_w.* = s.len;
            } else |_| {}
            const sz = (details.formatFileSize(entry.stat.st_size, options.human_readable, options.block_size, &temp_buf)).len;
            if (sz > max_size_w.*) max_size_w.* = sz;
        }
    }
}

fn printOwnership(writer: anytype, entry: *const FileEntry, options: *const Options, cur_pos: *usize) !void {
    var owner_buf: [32]u8 = undefined;
    var group_buf: [32]u8 = undefined;
    if (!options.omit_owner) {
        const owner = if (entry.has_stat_error) "?" else details.getOwner(entry.stat.st_uid, options.numeric_ids, &owner_buf);
        try writer.print("{s} ", .{owner});
        cur_pos.* += owner.len + 1;
    }
    if (!options.omit_group) {
        const group = if (entry.has_stat_error) "?" else details.getGroup(entry.stat.st_gid, options.numeric_ids, &group_buf);
        try writer.print("{s} ", .{group});
        cur_pos.* += group.len + 1;
    }
}

fn printLongMetadata(
    writer: anytype,
    entry: *const FileEntry,
    options: *const Options,
    max_nlink_w: usize,
    max_size_w: usize,
    dired_ctx: ?*dired_mod.DiredContext,
) !usize {
    var perm_buf: [10]u8 = undefined;
    var size_buf: [32]u8 = undefined;
    var time_buf: [64]u8 = undefined;
    var num_buf: [32]u8 = undefined;

    const perms = if (entry.has_stat_error) "??????????" else details.formatPermissions(&entry.stat, &perm_buf);
    const size_str = if (entry.has_stat_error) "?" else details.formatFileSize(entry.stat.st_size, options.human_readable, options.block_size, &size_buf);
    const time_str = if (entry.has_stat_error) "           ?" else details.formatTimestamp(&entry.stat, options.full_time, options.time_style, &time_buf);
    const nl_s = if (entry.has_stat_error) "?" else std.fmt.bufPrint(&num_buf, "{d}", .{entry.stat.st_nlink}) catch "?";

    var cur_pos = if (dired_ctx) |d| d.pos else 0;
    try writer.print("{s} ", .{perms});
    cur_pos += perms.len + 1;
    for (0..max_nlink_w -| nl_s.len) |_| {
        try writer.writeByte(' ');
        cur_pos += 1;
    }
    try writer.print("{s} ", .{nl_s});
    cur_pos += nl_s.len + 1;
    try printOwnership(writer, entry, options, &cur_pos);
    for (0..max_size_w -| size_str.len) |_| {
        try writer.writeByte(' ');
        cur_pos += 1;
    }
    try writer.print("{s} {s} ", .{ size_str, time_str });
    cur_pos += size_str.len + 1 + time_str.len + 1;
    if (dired_ctx) |d| d.pos = cur_pos;
    return cur_pos;
}

fn printLongEntry(
    writer: anytype,
    entry: *const FileEntry,
    options: *const Options,
    max_nlink_w: usize,
    max_size_w: usize,
    align_quotes: bool,
    cwd_some_quoted: bool,
    colors: *const Colors,
    use_color: bool,
    used_color: *bool,
    dired_ctx: ?*dired_mod.DiredContext,
    arena: std.mem.Allocator,
    printEntryNameFn: anytype,
) !void {
    try colors_mod.setNormalColor(writer, colors, use_color, used_color);
    if (dired_ctx) |d| try d.indent(writer);
    try details.printPrefix(writer, entry, options);
    const cur_pos = try printLongMetadata(writer, entry, options, max_nlink_w, max_size_w, dired_ctx);

    if (align_quotes and cwd_some_quoted and !quoting.needsQuoting(entry.name, options.quoting_style)) {
        try writer.writeByte(' ');
        if (dired_ctx) |d| d.pos += 1;
    }

    var name_buf: [1024]u8 = undefined;
    const quoted = formatQuotedName(entry.name, options.quoting_style, options.hide_control_chars, &name_buf);
    if (dired_ctx) |d| try d.pushDired(arena);
    try printEntryNameFn(writer, entry, options, colors, use_color, used_color, arena);
    if (dired_ctx) |d| {
        d.pos += quoted.len;
        try d.pushDired(arena);
    }
    if (entry.is_symlink) try printSymlinkTarget(writer, entry, options, colors, use_color, dired_ctx, arena);
    if (use_color and colors.getColor(entry) != null and colors.cl != null and options.term_width > 0) {
        if (cur_pos / options.term_width != (cur_pos + quoted.len - 1) / options.term_width) try writer.writeAll(colors.cl.?);
    }
    try writer.writeByte('\n');
    if (dired_ctx) |d| d.pos += 1;
}

pub fn printLongListing(
    writer: anytype,
    entries: []const FileEntry,
    options: *const Options,
    colors: *const Colors,
    use_color: bool,
    used_color: *bool,
    dired_ctx: ?*dired_mod.DiredContext,
    arena: std.mem.Allocator,
    printEntryNameFn: anytype,
) !void {
    const align_quotes = quoting.shouldAlignVariableQuotes(options);
    const cwd_some_quoted = align_quotes and quoting.hasQuotedEntry(entries, options.quoting_style);
    var max_nlink_w: usize = 1;
    var max_size_w: usize = 1;
    computeLongListingWidths(entries, options, &max_nlink_w, &max_size_w);

    for (entries) |*entry| {
        try printLongEntry(writer, entry, options, max_nlink_w, max_size_w, align_quotes, cwd_some_quoted, colors, use_color, used_color, dired_ctx, arena, printEntryNameFn);
    }
}
