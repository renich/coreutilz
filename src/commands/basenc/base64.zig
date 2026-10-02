const std = @import("std");
const common = @import("common.zig");
const WrapWriter = common.WrapWriter;
const c = @import("../../compat/c.zig").c;

const std_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
const url_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";

pub fn encodeStream(
    file: std.Io.File,
    wrap: *WrapWriter,
    is_url: bool,
) !void {
    const alphabet = if (is_url) url_alphabet else std_alphabet;
    var in_buf: [12288]u8 = undefined;
    var out_buf: [16384]u8 = undefined;
    var carry: [3]u8 = undefined;
    var carry_len: usize = 0;

    while (true) {
        const n_read = c.read(file.handle, &in_buf, in_buf.len);
        if (n_read < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            return error.ReadError;
        }
        if (n_read == 0) break;
        const chunk = in_buf[0..@intCast(n_read)];
        try processEncodeChunk(chunk, &carry, &carry_len, &out_buf, wrap, alphabet);
    }

    try finalizeEncode(&carry, carry_len, &out_buf, wrap, alphabet);
    try wrap.finish();
}

fn processEncodeChunk(
    chunk: []const u8,
    carry: *[3]u8,
    carry_len: *usize,
    out_buf: []u8,
    wrap: *WrapWriter,
    alphabet: *const [64]u8,
) !void {
    var in_idx: usize = 0;
    while (carry_len.* > 0 and carry_len.* < 3 and in_idx < chunk.len) {
        carry[carry_len.*] = chunk[in_idx];
        carry_len.* += 1;
        in_idx += 1;
        if (carry_len.* == 3) {
            encodeTriple(carry[0..3], out_buf[0..4], alphabet);
            try wrap.writeChunk(out_buf[0..4]);
            carry_len.* = 0;
        }
    }

    var out_idx: usize = 0;
    while (in_idx + 3 <= chunk.len) : (in_idx += 3) {
        encodeTriple(chunk[in_idx .. in_idx + 3], out_buf[out_idx .. out_idx + 4], alphabet);
        out_idx += 4;
        if (out_idx + 4 > out_buf.len) {
            try wrap.writeChunk(out_buf[0..out_idx]);
            out_idx = 0;
        }
    }
    if (out_idx > 0) {
        try wrap.writeChunk(out_buf[0..out_idx]);
    }

    while (in_idx < chunk.len) : (in_idx += 1) {
        carry[carry_len.*] = chunk[in_idx];
        carry_len.* += 1;
    }
}

fn encodeTriple(in: []const u8, out: []u8, alphabet: *const [64]u8) void {
    const b0 = in[0];
    const b1 = in[1];
    const b2 = in[2];
    out[0] = alphabet[b0 >> 2];
    out[1] = alphabet[((b0 & 0x03) << 4) | (b1 >> 4)];
    out[2] = alphabet[((b1 & 0x0F) << 2) | (b2 >> 6)];
    out[3] = alphabet[b2 & 0x3F];
}

fn finalizeEncode(
    carry: *[3]u8,
    carry_len: usize,
    out_buf: []u8,
    wrap: *WrapWriter,
    alphabet: *const [64]u8,
) !void {
    if (carry_len == 1) {
        const b0 = carry[0];
        out_buf[0] = alphabet[b0 >> 2];
        out_buf[1] = alphabet[(b0 & 0x03) << 4];
        out_buf[2] = '=';
        out_buf[3] = '=';
        try wrap.writeChunk(out_buf[0..4]);
    } else if (carry_len == 2) {
        const b0 = carry[0];
        const b1 = carry[1];
        out_buf[0] = alphabet[b0 >> 2];
        out_buf[1] = alphabet[((b0 & 0x03) << 4) | (b1 >> 4)];
        out_buf[2] = alphabet[(b1 & 0x0F) << 2];
        out_buf[3] = '=';
        try wrap.writeChunk(out_buf[0..4]);
    }
}

pub fn decodeStream(
    file: std.Io.File,
    out_writer: *std.Io.Writer,
    is_url: bool,
    ignore_garbage: bool,
) !void {
    var in_buf: [16384]u8 = undefined;
    var out_buf: [12288]u8 = undefined;
    var quad: [4]u8 = undefined;
    var quad_len: usize = 0;
    var pad_seen: bool = false;

    while (true) {
        const n_read = c.read(file.handle, &in_buf, in_buf.len);
        if (n_read < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            return error.ReadError;
        }
        if (n_read == 0) break;
        const chunk = in_buf[0..@intCast(n_read)];
        try decodeChunk(chunk, &quad, &quad_len, &pad_seen, &out_buf, out_writer, is_url, ignore_garbage);
    }

    try finalizeDecode(quad[0..quad_len], out_writer, is_url);
}

fn flushQuad(
    quad: *[4]u8,
    quad_len: *usize,
    pad_seen: *bool,
    out_buf: []u8,
    out_idx: *usize,
    out_writer: *std.Io.Writer,
    is_url: bool,
) !void {
    const res = try decodeQuad(quad, out_buf[out_idx.*..], is_url);
    out_idx.* += res.count;
    quad_len.* = 0;
    pad_seen.* = false;
    try out_writer.writeAll(out_buf[0..out_idx.*]);
    out_idx.* = 0;
    if (res.invalid) return error.InvalidInput;
}

fn decodeChunk(
    chunk: []const u8,
    quad: *[4]u8,
    quad_len: *usize,
    pad_seen: *bool,
    out_buf: []u8,
    out_writer: *std.Io.Writer,
    is_url: bool,
    ignore_garbage: bool,
) !void {
    var out_idx: usize = 0;
    for (chunk) |byte| {
        if (!ignore_garbage and (byte == '\n' or byte == '\r')) continue;
        if (byte == '=') {
            if (quad_len.* < 2) return error.InvalidInput;
            pad_seen.* = true;
            quad[quad_len.*] = byte;
            quad_len.* += 1;
            if (quad_len.* == 4) {
                try flushQuad(quad, quad_len, pad_seen, out_buf, &out_idx, out_writer, is_url);
            }
            continue;
        }
        if (pad_seen.* and !ignore_garbage) return error.InvalidInput;
        const val = decodeChar(byte, is_url);
        if (val == 0xFF) {
            if (ignore_garbage) continue;
            return error.InvalidInput;
        }
        if (pad_seen.*) pad_seen.* = false;
        quad[quad_len.*] = byte;
        quad_len.* += 1;
        if (quad_len.* == 4) {
            try flushQuad(quad, quad_len, pad_seen, out_buf, &out_idx, out_writer, is_url);
        }
    }
    if (out_idx > 0) try out_writer.writeAll(out_buf[0..out_idx]);
}

const DecodeResult = struct {
    count: usize,
    invalid: bool,
};

fn decodeQuad(quad: *const [4]u8, out: []u8, is_url: bool) !DecodeResult {
    const c0 = decodeChar(quad[0], is_url);
    const c1 = decodeChar(quad[1], is_url);
    if (c0 == 0xFF or c1 == 0xFF) return error.InvalidInput;

    if (quad[2] == '=') {
        if (quad[3] != '=') return error.InvalidInput;
        out[0] = (c0 << 2) | (c1 >> 4);
        const bad_pad = (c1 & 0x0F) != 0;
        return .{ .count = 1, .invalid = bad_pad };
    }

    const c2 = decodeChar(quad[2], is_url);
    if (c2 == 0xFF) return error.InvalidInput;

    if (quad[3] == '=') {
        out[0] = (c0 << 2) | (c1 >> 4);
        out[1] = ((c1 & 0x0F) << 4) | (c2 >> 2);
        const bad_pad = (c2 & 0x03) != 0;
        return .{ .count = 2, .invalid = bad_pad };
    }

    const c3 = decodeChar(quad[3], is_url);
    if (c3 == 0xFF) return error.InvalidInput;
    out[0] = (c0 << 2) | (c1 >> 4);
    out[1] = ((c1 & 0x0F) << 4) | (c2 >> 2);
    out[2] = ((c2 & 0x03) << 6) | c3;
    return .{ .count = 3, .invalid = false };
}

fn finalizeDecode(rem: []const u8, out_writer: *std.Io.Writer, is_url: bool) !void {
    if (rem.len == 0) return;
    if (rem.len == 1) return error.InvalidInput;
    var out: [3]u8 = undefined;
    if (rem.len == 2) {
        if (rem[0] == '=' or rem[1] == '=') return error.InvalidInput;
        const c0 = decodeChar(rem[0], is_url);
        const c1 = decodeChar(rem[1], is_url);
        if (c0 == 0xFF or c1 == 0xFF) return error.InvalidInput;
        out[0] = (c0 << 2) | (c1 >> 4);
        try out_writer.writeAll(out[0..1]);
    } else if (rem.len == 3) {
        if (rem[0] == '=' or rem[1] == '=') return error.InvalidInput;
        const c0 = decodeChar(rem[0], is_url);
        const c1 = decodeChar(rem[1], is_url);
        if (c0 == 0xFF or c1 == 0xFF) return error.InvalidInput;
        if (rem[2] == '=') {
            out[0] = (c0 << 2) | (c1 >> 4);
            try out_writer.writeAll(out[0..1]);
            return error.InvalidInput;
        }
        const c2 = decodeChar(rem[2], is_url);
        if (c2 == 0xFF) return error.InvalidInput;
        out[0] = (c0 << 2) | (c1 >> 4);
        out[1] = ((c1 & 0x0F) << 4) | (c2 >> 2);
        try out_writer.writeAll(out[0..2]);
    }
}

fn decodeChar(b: u8, is_url: bool) u8 {
    if (b >= 'A' and b <= 'Z') return b - 'A';
    if (b >= 'a' and b <= 'z') return b - 'a' + 26;
    if (b >= '0' and b <= '9') return b - '0' + 52;
    if (is_url) {
        if (b == '-') return 62;
        if (b == '_') return 63;
        return 0xFF;
    } else {
        if (b == '+') return 62;
        if (b == '/') return 63;
        return 0xFF;
    }
}
