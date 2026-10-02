const std = @import("std");
const common = @import("common.zig");
const WrapWriter = common.WrapWriter;
const c = @import("../../compat/c.zig").c;

const z85_alphabet = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ.-:+=^!/*?&<>()[]{}@%$#";

pub fn encodeStream(file: std.Io.File, wrap: *WrapWriter) !void {
    var in_buf: [8192]u8 = undefined;
    var out_buf: [20480]u8 = undefined;
    var carry: [4]u8 = undefined;
    var carry_len: usize = 0;
    var pending_len: usize = 0;

    while (true) {
        const n_read = c.read(file.handle, &in_buf, in_buf.len);
        if (n_read < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            return error.ReadError;
        }
        if (n_read == 0) {
            if (carry_len != 0) return error.InvalidInput;
            if (pending_len > 0) try wrap.writeChunk(out_buf[0..pending_len]);
            break;
        }
        if (pending_len > 0) {
            try wrap.writeChunk(out_buf[0..pending_len]);
            pending_len = 0;
        }
        try processEncodeChunk(in_buf[0..@intCast(n_read)], &carry, &carry_len, &out_buf, &pending_len, wrap);
    }
    try wrap.finish();
}

fn processEncodeChunk(
    chunk: []const u8,
    carry: *[4]u8,
    carry_len: *usize,
    out_buf: []u8,
    pending_len: *usize,
    wrap: *WrapWriter,
) !void {
    var in_idx: usize = 0;
    if (carry_len.* > 0) {
        while (carry_len.* < 4 and in_idx < chunk.len) {
            carry[carry_len.*] = chunk[in_idx];
            carry_len.* += 1;
            in_idx += 1;
        }
        if (carry_len.* == 4) {
            encodeQuad(carry[0..4], out_buf[pending_len.* .. pending_len.* + 5]);
            pending_len.* += 5;
            carry_len.* = 0;
        }
    }
    while (in_idx + 4 <= chunk.len) : (in_idx += 4) {
        encodeQuad(chunk[in_idx .. in_idx + 4], out_buf[pending_len.* .. pending_len.* + 5]);
        pending_len.* += 5;
        if (pending_len.* + 5 > out_buf.len) {
            try wrap.writeChunk(out_buf[0..pending_len.*]);
            pending_len.* = 0;
        }
    }
    while (in_idx < chunk.len) : (in_idx += 1) {
        carry[carry_len.*] = chunk[in_idx];
        carry_len.* += 1;
    }
}

fn encodeQuad(in: []const u8, out: []u8) void {
    var val: u32 = (@as(u32, in[0]) << 24) | (@as(u32, in[1]) << 16) | (@as(u32, in[2]) << 8) | @as(u32, in[3]);
    var i: usize = 5;
    while (i > 0) {
        i -= 1;
        out[i] = z85_alphabet[@as(usize, val % 85)];
        val /= 85;
    }
}

pub fn decodeStream(
    file: std.Io.File,
    out_writer: *std.Io.Writer,
    ignore_garbage: bool,
) !void {
    var in_buf: [16384]u8 = undefined;
    var out_buf: [8192]u8 = undefined;
    var quint: [5]u8 = undefined;
    var quint_len: usize = 0;

    while (true) {
        const n_read = c.read(file.handle, &in_buf, in_buf.len);
        if (n_read < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            return error.ReadError;
        }
        if (n_read == 0) break;
        const chunk = in_buf[0..@intCast(n_read)];
        try decodeChunk(chunk, &quint, &quint_len, &out_buf, out_writer, ignore_garbage);
    }
    if (quint_len != 0) return error.InvalidInput;
}

fn decodeChunk(
    chunk: []const u8,
    quint: *[5]u8,
    quint_len: *usize,
    out_buf: []u8,
    out_writer: *std.Io.Writer,
    ignore_garbage: bool,
) !void {
    var out_idx: usize = 0;
    for (chunk) |byte| {
        if (!ignore_garbage and (byte == '\n' or byte == '\r')) continue;
        const digit = decodeChar(byte);
        if (digit == 0xFF) {
            if (ignore_garbage) continue;
            return error.InvalidInput;
        }
        quint[quint_len.*] = digit;
        quint_len.* += 1;
        if (quint_len.* == 5) {
            try decodeQuint(quint, out_buf[out_idx .. out_idx + 4]);
            out_idx += 4;
            quint_len.* = 0;
            try out_writer.writeAll(out_buf[0..out_idx]);
            out_idx = 0;
        }
    }
    if (out_idx > 0) try out_writer.writeAll(out_buf[0..out_idx]);
}

fn decodeQuint(in: *const [5]u8, out: []u8) !void {
    var val: u64 = 0;
    for (in) |d| {
        val = val * 85 + d;
    }
    if (val > 0xFFFFFFFF) return error.InvalidInput;
    out[0] = @as(u8, @truncate(val >> 24));
    out[1] = @as(u8, @truncate(val >> 16));
    out[2] = @as(u8, @truncate(val >> 8));
    out[3] = @as(u8, @truncate(val));
}

fn decodeChar(b: u8) u8 {
    for (z85_alphabet, 0..) |ch, i| {
        if (b == ch) return @intCast(i);
    }
    return 0xFF;
}
