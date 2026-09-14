const std = @import("std");
const c = @import("../../compat/c.zig").c;

fn isRfc3986Unreserved(ch: u8) bool {
    return std.ascii.isAlphanumeric(ch) or ch == '-' or ch == '.' or ch == '_' or ch == '~';
}

pub fn fileEscape(arena: std.mem.Allocator, str: []const u8, is_path: bool) ![]const u8 {
    var list = std.ArrayList(u8).empty;
    defer list.deinit(arena);

    for (str) |ch| {
        if (is_path and ch == '/') {
            try list.append(arena, '/');
        } else if (isRfc3986Unreserved(ch)) {
            try list.append(arena, ch);
        } else {
            var hex_buf: [3]u8 = undefined;
            const hex = std.fmt.bufPrint(&hex_buf, "%{x:0>2}", .{ch}) catch "%00";
            try list.appendSlice(arena, hex);
        }
    }
    return list.toOwnedSlice(arena);
}

pub fn getAbsoluteUri(arena: std.mem.Allocator, path: []const u8) ![]const u8 {
    var host_buf: [256]u8 = undefined;
    var host_str: []const u8 = "";
    if (c.gethostname(&host_buf, host_buf.len) == 0) {
        host_str = std.mem.span(@as([*:0]const u8, @ptrCast(&host_buf)));
    }
    const escaped_host = try fileEscape(arena, host_str, false);

    var abs_path: []const u8 = path;
    var real_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path_z = try arena.dupeZ(u8, path);
    if (c.realpath(path_z.ptr, &real_buf)) |res| {
        abs_path = try arena.dupe(u8, std.mem.span(res));
    } else {
        if (!std.fs.path.isAbsolute(path)) {
            var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
            if (c.getcwd(&cwd_buf, cwd_buf.len)) |cwd_ptr| {
                const cwd_str = std.mem.span(cwd_ptr);
                abs_path = try std.fs.path.join(arena, &[_][]const u8{ cwd_str, path });
            }
        }
    }

    const escaped_path = try fileEscape(arena, abs_path, true);
    const leading_slash = if (escaped_path.len > 0 and escaped_path[0] == '/') "" else "/";
    return std.fmt.allocPrint(arena, "file://{s}{s}{s}", .{ escaped_host, leading_slash, escaped_path });
}

pub fn printHyperlinkStart(writer: anytype, uri: []const u8) !void {
    try writer.print("\x1b]8;;{s}\x1b\\", .{uri});
}

pub fn printHyperlinkEnd(writer: anytype) !void {
    try writer.writeAll("\x1b]8;;\x1b\\");
}
