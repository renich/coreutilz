const std = @import("std");
const common = @import("common.zig");
const WrapWriter = common.WrapWriter;
const c = @import("../../compat/c.zig").c;

const b58_alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz";

fn writeLeadingOnes(zeros_count: usize, ones_buf: []const u8, wrap: *WrapWriter) !void {
    var zeros_left = zeros_count;
    while (zeros_left > 0) {
        const to_write = @min(zeros_left, ones_buf.len);
        try wrap.writeChunk(ones_buf[0..to_write]);
        zeros_left -= to_write;
    }
}

pub fn encodeStream(
    file: std.Io.File,
    wrap: *WrapWriter,
    allocator: std.mem.Allocator,
) !void {
    var in_buf: [16384]u8 = undefined;
    var ones_buf: [4096]u8 = undefined;
    @memset(&ones_buf, '1');

    var non_zeros: std.ArrayList(u8) = .empty;
    defer non_zeros.deinit(allocator);

    var reading_zeros = true;
    while (true) {
        const n_read = c.read(file.handle, &in_buf, in_buf.len);
        if (n_read < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            return error.ReadError;
        }
        if (n_read == 0) break;
        const chunk = in_buf[0..@intCast(n_read)];

        if (reading_zeros) {
            var i: usize = 0;
            while (i < chunk.len and chunk[i] == 0) : (i += 1) {}
            try writeLeadingOnes(i, &ones_buf, wrap);
            if (i < chunk.len) {
                reading_zeros = false;
                try non_zeros.appendSlice(allocator, chunk[i..]);
            }
        } else {
            try non_zeros.appendSlice(allocator, chunk);
        }
    }

    if (non_zeros.items.len > 0) try encodeNonZeros(non_zeros.items, wrap, allocator);
    try wrap.finish();
}

fn encodeNonZeros(
    data: []const u8,
    wrap: *WrapWriter,
    allocator: std.mem.Allocator,
) !void {
    var digits: std.ArrayList(u8) = .empty;
    defer digits.deinit(allocator);

    for (data) |byte| {
        var carry: u32 = byte;
        for (digits.items) |*d| {
            const acc: u32 = carry + (@as(u32, d.*) << 8);
            d.* = @as(u8, @truncate(acc % 58));
            carry = acc / 58;
        }
        while (carry > 0) {
            try digits.append(allocator, @as(u8, @truncate(carry % 58)));
            carry /= 58;
        }
    }

    var out_buf: [4096]u8 = undefined;
    var out_idx: usize = 0;
    var i: usize = digits.items.len;
    while (i > 0) {
        i -= 1;
        out_buf[out_idx] = b58_alphabet[digits.items[i]];
        out_idx += 1;
        if (out_idx == out_buf.len) {
            try wrap.writeChunk(out_buf[0..out_idx]);
            out_idx = 0;
        }
    }
    if (out_idx > 0) {
        try wrap.writeChunk(out_buf[0..out_idx]);
    }
}

fn processDecodeChunk(
    chunk: []const u8,
    reading_ones: *bool,
    digits: *std.ArrayList(u8),
    out_writer: *std.Io.Writer,
    ignore_garbage: bool,
    allocator: std.mem.Allocator,
) !void {
    for (chunk) |byte| {
        if (byte == '\n' or byte == '\r') continue;
        const val = decodeChar(byte);
        if (val == 0xFF) {
            if (ignore_garbage) continue;
            return error.InvalidInput;
        }
        if (reading_ones.* and val == 0) {
            try out_writer.writeByte(0);
        } else {
            reading_ones.* = false;
            try digits.append(allocator, val);
        }
    }
}

pub fn decodeStream(
    file: std.Io.File,
    out_writer: *std.Io.Writer,
    ignore_garbage: bool,
    allocator: std.mem.Allocator,
) !void {
    var in_buf: [16384]u8 = undefined;
    var digits: std.ArrayList(u8) = .empty;
    defer digits.deinit(allocator);

    var reading_ones = true;
    while (true) {
        const n_read = c.read(file.handle, &in_buf, in_buf.len);
        if (n_read < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            return error.ReadError;
        }
        if (n_read == 0) break;
        try processDecodeChunk(in_buf[0..@intCast(n_read)], &reading_ones, &digits, out_writer, ignore_garbage, allocator);
    }

    if (digits.items.len > 0) {
        try decodeDigits(digits.items, out_writer, allocator);
    }
}

fn decodeDigits(
    digits: []const u8,
    out_writer: *std.Io.Writer,
    allocator: std.mem.Allocator,
) !void {
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(allocator);

    for (digits) |digit| {
        var carry: u32 = digit;
        for (bytes.items) |*b| {
            const acc: u32 = carry + @as(u32, b.*) * 58;
            b.* = @as(u8, @truncate(acc & 0xFF));
            carry = acc >> 8;
        }
        while (carry > 0) {
            try bytes.append(allocator, @as(u8, @truncate(carry & 0xFF)));
            carry >>= 8;
        }
    }

    var i: usize = bytes.items.len;
    while (i > 0) {
        i -= 1;
        try out_writer.writeByte(bytes.items[i]);
    }
}

fn decodeChar(b: u8) u8 {
    for (b58_alphabet, 0..) |ch, i| {
        if (b == ch) return @intCast(i);
    }
    return 0xFF;
}
