const std = @import("std");
const Algorithm = @import("algorithm.zig").Algorithm;

const base64_chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

pub fn needsEscaping(filename: []const u8) bool {
    for (filename) |b| {
        if (b == '\n' or b == '\r' or b == '\\') return true;
    }
    return false;
}

pub fn writeEscapedFilename(writer: *std.Io.Writer, filename: []const u8) !void {
    for (filename) |b| {
        switch (b) {
            '\\' => try writer.writeAll("\\\\"),
            '\n' => try writer.writeAll("\\n"),
            '\r' => try writer.writeAll("\\r"),
            else => try writer.writeByte(b),
        }
    }
}

pub fn unescapeFilename(allocator: std.mem.Allocator, raw: []const u8) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);

    var i: usize = 0;
    while (i < raw.len) {
        if (raw[i] == '\\' and i + 1 < raw.len) {
            switch (raw[i + 1]) {
                '\\' => {
                    try list.append(allocator, '\\');
                    i += 2;
                },
                'n' => {
                    try list.append(allocator, '\n');
                    i += 2;
                },
                'r' => {
                    try list.append(allocator, '\r');
                    i += 2;
                },
                else => {
                    try list.append(allocator, raw[i]);
                    i += 1;
                },
            }
        } else {
            try list.append(allocator, raw[i]);
            i += 1;
        }
    }
    return list.toOwnedSlice(allocator);
}

pub fn toBase64(digest: []const u8, out: []u8) usize {
    var in_idx: usize = 0;
    var out_idx: usize = 0;
    while (in_idx + 3 <= digest.len) : (in_idx += 3) {
        const b0 = digest[in_idx];
        const b1 = digest[in_idx + 1];
        const b2 = digest[in_idx + 2];
        out[out_idx] = base64_chars[b0 >> 2];
        out[out_idx + 1] = base64_chars[((b0 & 0x03) << 4) | (b1 >> 4)];
        out[out_idx + 2] = base64_chars[((b1 & 0x0F) << 2) | (b2 >> 6)];
        out[out_idx + 3] = base64_chars[b2 & 0x3F];
        out_idx += 4;
    }
    const rem = digest.len - in_idx;
    if (rem == 1) {
        const b0 = digest[in_idx];
        out[out_idx] = base64_chars[b0 >> 2];
        out[out_idx + 1] = base64_chars[(b0 & 0x03) << 4];
        out[out_idx + 2] = '=';
        out[out_idx + 3] = '=';
        out_idx += 4;
    } else if (rem == 2) {
        const b0 = digest[in_idx];
        const b1 = digest[in_idx + 1];
        out[out_idx] = base64_chars[b0 >> 2];
        out[out_idx + 1] = base64_chars[((b0 & 0x03) << 4) | (b1 >> 4)];
        out[out_idx + 2] = base64_chars[(b1 & 0x0F) << 2];
        out[out_idx + 3] = '=';
        out_idx += 4;
    }
    return out_idx;
}

pub fn printUntagged(
    writer: *std.Io.Writer,
    digest_str: []const u8,
    filename: []const u8,
    is_binary: bool,
    zero: bool,
) !void {
    const esc = !zero and needsEscaping(filename);
    if (esc) try writer.writeByte('\\');
    try writer.writeAll(digest_str);
    try writer.writeByte(' ');
    try writer.writeByte(if (is_binary) '*' else ' ');
    if (esc) {
        try writeEscapedFilename(writer, filename);
    } else {
        try writer.writeAll(filename);
    }
    try writer.writeByte(if (zero) 0 else '\n');
}

pub fn printTagged(
    writer: *std.Io.Writer,
    tag: []const u8,
    digest_str: []const u8,
    filename: []const u8,
    zero: bool,
) !void {
    const esc = !zero and needsEscaping(filename);
    if (esc) try writer.writeByte('\\');
    try writer.print("{s} (", .{tag});
    if (esc) {
        try writeEscapedFilename(writer, filename);
    } else {
        try writer.writeAll(filename);
    }
    try writer.print(") = {s}", .{digest_str});
    try writer.writeByte(if (zero) 0 else '\n');
}

pub fn printCrc(
    writer: *std.Io.Writer,
    crc_val: u32,
    bytes: u64,
    filename: ?[]const u8,
    zero: bool,
) !void {
    try writer.print("{d} {d}", .{ crc_val, bytes });
    if (filename) |f| {
        try writer.print(" {s}", .{f});
    }
    try writer.writeByte(if (zero) 0 else '\n');
}

pub fn printBsd(
    writer: *std.Io.Writer,
    checksum: u16,
    blocks: u64,
    filename: ?[]const u8,
    zero: bool,
) !void {
    try writer.print("{d:0>5} {d:>5}", .{ checksum, blocks });
    if (filename) |f| {
        try writer.print(" {s}", .{f});
    }
    try writer.writeByte(if (zero) 0 else '\n');
}

pub fn printSysv(
    writer: *std.Io.Writer,
    checksum: u16,
    blocks: u64,
    filename: ?[]const u8,
    zero: bool,
) !void {
    try writer.print("{d} {d}", .{ checksum, blocks });
    if (filename) |f| {
        try writer.print(" {s}", .{f});
    }
    try writer.writeByte(if (zero) 0 else '\n');
}
