const std = @import("std");
const common = @import("common.zig");
const WrapWriter = common.WrapWriter;
const c = @import("../../compat/c.zig").c;

const std32_alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
const hex32_alphabet = "0123456789ABCDEFGHIJKLMNOPQRSTUV";

pub fn encodeStream(
    file: std.Io.File,
    wrap: *WrapWriter,
    is_hex: bool,
) !void {
    const alphabet = if (is_hex) hex32_alphabet else std32_alphabet;
    var in_buf: [10240]u8 = undefined;
    var out_buf: [16384]u8 = undefined;
    var carry: [5]u8 = undefined;
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
    carry: *[5]u8,
    carry_len: *usize,
    out_buf: []u8,
    wrap: *WrapWriter,
    alphabet: *const [32]u8,
) !void {
    var in_idx: usize = 0;
    while (carry_len.* > 0 and carry_len.* < 5 and in_idx < chunk.len) {
        carry[carry_len.*] = chunk[in_idx];
        carry_len.* += 1;
        in_idx += 1;
        if (carry_len.* == 5) {
            encodeFive(carry[0..5], out_buf[0..8], alphabet);
            try wrap.writeChunk(out_buf[0..8]);
            carry_len.* = 0;
        }
    }

    var out_idx: usize = 0;
    while (in_idx + 5 <= chunk.len) : (in_idx += 5) {
        encodeFive(chunk[in_idx .. in_idx + 5], out_buf[out_idx .. out_idx + 8], alphabet);
        out_idx += 8;
        if (out_idx + 8 > out_buf.len) {
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

fn encodeFive(in: []const u8, out: []u8, alphabet: *const [32]u8) void {
    const b0 = in[0];
    const b1 = in[1];
    const b2 = in[2];
    const b3 = in[3];
    const b4 = in[4];
    out[0] = alphabet[b0 >> 3];
    out[1] = alphabet[((b0 & 0x07) << 2) | (b1 >> 6)];
    out[2] = alphabet[(b1 >> 1) & 0x1F];
    out[3] = alphabet[((b1 & 0x01) << 4) | (b2 >> 4)];
    out[4] = alphabet[((b2 & 0x0F) << 1) | (b3 >> 7)];
    out[5] = alphabet[(b3 >> 2) & 0x1F];
    out[6] = alphabet[((b3 & 0x03) << 3) | (b4 >> 5)];
    out[7] = alphabet[b4 & 0x1F];
}

fn finalizeEncode(
    carry: *[5]u8,
    carry_len: usize,
    out: []u8,
    wrap: *WrapWriter,
    alphabet: *const [32]u8,
) !void {
    if (carry_len == 0) return;
    @memset(out[0..8], '=');
    const b0 = carry[0];
    out[0] = alphabet[b0 >> 3];
    if (carry_len == 1) {
        out[1] = alphabet[(b0 & 0x07) << 2];
    } else {
        const b1 = carry[1];
        out[1] = alphabet[((b0 & 0x07) << 2) | (b1 >> 6)];
        out[2] = alphabet[(b1 >> 1) & 0x1F];
        if (carry_len == 2) {
            out[3] = alphabet[(b1 & 0x01) << 4];
        } else {
            const b2 = carry[2];
            out[3] = alphabet[((b1 & 0x01) << 4) | (b2 >> 4)];
            if (carry_len == 3) {
                out[4] = alphabet[(b2 & 0x0F) << 1];
            } else {
                const b3 = carry[3];
                out[4] = alphabet[((b2 & 0x0F) << 1) | (b3 >> 7)];
                out[5] = alphabet[(b3 >> 2) & 0x1F];
                out[6] = alphabet[(b3 & 0x03) << 3];
            }
        }
    }
    try wrap.writeChunk(out[0..8]);
}

pub fn decodeStream(
    file: std.Io.File,
    out_writer: *std.Io.Writer,
    is_hex: bool,
    ignore_garbage: bool,
) !void {
    var in_buf: [16384]u8 = undefined;
    var out_buf: [10240]u8 = undefined;
    var octet: [8]u8 = undefined;
    var octet_len: usize = 0;
    var pad_seen: bool = false;

    while (true) {
        const n_read = c.read(file.handle, &in_buf, in_buf.len);
        if (n_read < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            return error.ReadError;
        }
        if (n_read == 0) break;
        const chunk = in_buf[0..@intCast(n_read)];
        try decodeChunk(chunk, &octet, &octet_len, &pad_seen, &out_buf, out_writer, is_hex, ignore_garbage);
    }

    try finalizeDecode(octet[0..octet_len], out_writer, is_hex);
}

fn flushOctet(
    octet: *[8]u8,
    octet_len: *usize,
    pad_seen: *bool,
    out_buf: []u8,
    out_idx: *usize,
    out_writer: *std.Io.Writer,
    is_hex: bool,
) !void {
    out_idx.* += try decodeOctet(octet, out_buf[out_idx.*..], is_hex);
    octet_len.* = 0;
    pad_seen.* = false;
    try out_writer.writeAll(out_buf[0..out_idx.*]);
    out_idx.* = 0;
}

fn decodeChunk(
    chunk: []const u8,
    octet: *[8]u8,
    octet_len: *usize,
    pad_seen: *bool,
    out_buf: []u8,
    out_writer: *std.Io.Writer,
    is_hex: bool,
    ignore_garbage: bool,
) !void {
    var out_idx: usize = 0;
    for (chunk) |byte| {
        if (!ignore_garbage and (byte == '\n' or byte == '\r')) continue;
        if (byte == '=') {
            if (octet_len.* < 2) return error.InvalidInput;
            pad_seen.* = true;
            octet[octet_len.*] = byte;
            octet_len.* += 1;
            if (octet_len.* == 8) {
                try flushOctet(octet, octet_len, pad_seen, out_buf, &out_idx, out_writer, is_hex);
            }
            continue;
        }
        if (pad_seen.* and !ignore_garbage) return error.InvalidInput;
        const val = decodeChar(byte, is_hex);
        if (val == 0xFF) {
            if (ignore_garbage) continue;
            return error.InvalidInput;
        }
        if (pad_seen.*) pad_seen.* = false;
        octet[octet_len.*] = byte;
        octet_len.* += 1;
        if (octet_len.* == 8) {
            try flushOctet(octet, octet_len, pad_seen, out_buf, &out_idx, out_writer, is_hex);
        }
    }
    if (out_idx > 0) try out_writer.writeAll(out_buf[0..out_idx]);
}

fn decodeOctet(oct: *const [8]u8, out: []u8, is_hex: bool) !usize {
    var vals: [8]u8 = undefined;
    var pad_count: usize = 0;
    for (oct, 0..) |ch, i| {
        if (ch == '=') {
            pad_count += 1;
            vals[i] = 0;
        } else {
            if (pad_count > 0) return error.InvalidInput;
            const v = decodeChar(ch, is_hex);
            if (v == 0xFF) return error.InvalidInput;
            vals[i] = v;
        }
    }
    return unpackVals(&vals, pad_count, out);
}

fn unpackVals(vals: *const [8]u8, pad_count: usize, out: []u8) !usize {
    switch (pad_count) {
        0 => {
            out[0] = (vals[0] << 3) | (vals[1] >> 2);
            out[1] = (vals[1] << 6) | (vals[2] << 1) | (vals[3] >> 4);
            out[2] = (vals[3] << 4) | (vals[4] >> 1);
            out[3] = (vals[4] << 7) | (vals[5] << 2) | (vals[6] >> 3);
            out[4] = (vals[6] << 5) | vals[7];
            return 5;
        },
        1 => {
            if ((vals[6] & 0x07) != 0) return error.InvalidInput;
            out[0] = (vals[0] << 3) | (vals[1] >> 2);
            out[1] = (vals[1] << 6) | (vals[2] << 1) | (vals[3] >> 4);
            out[2] = (vals[3] << 4) | (vals[4] >> 1);
            out[3] = (vals[4] << 7) | (vals[5] << 2) | (vals[6] >> 3);
            return 4;
        },
        3 => {
            if ((vals[4] & 0x01) != 0) return error.InvalidInput;
            out[0] = (vals[0] << 3) | (vals[1] >> 2);
            out[1] = (vals[1] << 6) | (vals[2] << 1) | (vals[3] >> 4);
            out[2] = (vals[3] << 4) | (vals[4] >> 1);
            return 3;
        },
        4 => {
            if ((vals[3] & 0x0F) != 0) return error.InvalidInput;
            out[0] = (vals[0] << 3) | (vals[1] >> 2);
            out[1] = (vals[1] << 6) | (vals[2] << 1) | (vals[3] >> 4);
            return 2;
        },
        6 => {
            if ((vals[1] & 0x03) != 0) return error.InvalidInput;
            out[0] = (vals[0] << 3) | (vals[1] >> 2);
            return 1;
        },
        else => return error.InvalidInput,
    }
}

fn finalizeDecode(rem: []const u8, out_writer: *std.Io.Writer, is_hex: bool) !void {
    if (rem.len == 0) return;
    var vals: [8]u8 = [_]u8{0} ** 8;
    for (rem, 0..) |ch, i| {
        if (ch == '=') return error.InvalidInput;
        const v = decodeChar(ch, is_hex);
        if (v == 0xFF) return error.InvalidInput;
        vals[i] = v;
    }
    const pad = 8 - rem.len;
    var out: [5]u8 = undefined;
    const n = try unpackVals(&vals, pad, &out);
    try out_writer.writeAll(out[0..n]);
}

fn decodeChar(b: u8, is_hex: bool) u8 {
    if (is_hex) {
        if (b >= '0' and b <= '9') return b - '0';
        if (b >= 'A' and b <= 'V') return b - 'A' + 10;
        if (b >= 'a' and b <= 'v') return b - 'a' + 10;
        return 0xFF;
    } else {
        if (b >= 'A' and b <= 'Z') return b - 'A';
        if (b >= 'a' and b <= 'z') return b - 'a';
        if (b >= '2' and b <= '7') return b - '2' + 26;
        return 0xFF;
    }
}
