const std = @import("std");
const c = @import("../../compat/c.zig").c;
const types = @import("types.zig");

pub fn printHeader(writer: anytype, filename: []const u8, page_num: usize, cfg: *const types.PrConfig) !void {
    if (cfg.omit_header) return;

    var time_buf: [64]u8 = undefined;
    const now = c.time(null);
    var tm_struct: c.struct_tm = undefined;
    _ = c.localtime_r(&now, &tm_struct);
    const date_len = c.strftime(&time_buf, time_buf.len, "%Y-%m-%d %H:%M", &tm_struct);
    const date_str = time_buf[0..date_len];

    const title = cfg.header_text orelse filename;

    try writer.writeAll("\n\n");
    for (0..cfg.indent) |_| try writer.writeByte(' ');
    try writer.print("{s}  {s}  Page {d}\n\n\n", .{ date_str, title, page_num });
}

pub fn printFooter(writer: anytype, cfg: *const types.PrConfig) !void {
    if (cfg.omit_header) return;
    try writer.writeAll("\n\n\n\n\n");
}

pub fn printIndent(writer: anytype, indent: usize) !void {
    for (0..indent) |_| try writer.writeByte(' ');
}
