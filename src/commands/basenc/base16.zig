const std = @import("std");
const common = @import("common.zig");
const WrapWriter = common.WrapWriter;
const c = @import("../../compat/c.zig").c;

const hex_alphabet = "0123456789ABCDEF";

pub fn encodeStream(file: std.Io.File, wrap: *WrapWriter) !void {
    var in_buf: [8192]u8 = undefined;
    var out_buf: [16384]u8 = undefined;

    while (true) {
        const n_read = c.read(file.handle, &in_buf, in_buf.len);
        if (n_read < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            return error.ReadError;
        }
        if (n_read == 0) break;
        const chunk = in_buf[0..@intCast(n_read)];
        var out_idx: usize = 0;
        for (chunk) |byte| {
            out_buf[out_idx] = hex_alphabet[byte >> 4];
            out_buf[out_idx + 1] = hex_alphabet[byte & 0x0F];
            out_idx += 2;
            if (out_idx + 2 > out_buf.len) {
                try wrap.writeChunk(out_buf[0..out_idx]);
                out_idx = 0;
            }
        }
        if (out_idx > 0) {
            try wrap.writeChunk(out_buf[0..out_idx]);
        }
    }
    try wrap.finish();
}

pub fn decodeStream(
    file: std.Io.File,
    out_writer: *std.Io.Writer,
    ignore_garbage: bool,
) !void {
    var in_buf: [16384]u8 = undefined;
    var carry_nibble: i16 = -1;

    while (true) {
        const n_read = c.read(file.handle, &in_buf, in_buf.len);
        if (n_read < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            return error.ReadError;
        }
        if (n_read == 0) break;
        const chunk = in_buf[0..@intCast(n_read)];
        try decodeChunk(chunk, &carry_nibble, out_writer, ignore_garbage);
    }

    if (carry_nibble >= 0) return error.InvalidInput;
}

fn decodeChunk(
    chunk: []const u8,
    carry: *i16,
    out_writer: *std.Io.Writer,
    ignore_garbage: bool,
) !void {
    for (chunk) |byte| {
        if (!ignore_garbage and (byte == '\n' or byte == '\r')) continue;
        const nibble = decodeNibble(byte);
        if (nibble == 0xFF) {
            if (ignore_garbage) continue;
            return error.InvalidInput;
        }
        if (carry.* < 0) {
            carry.* = nibble;
        } else {
            try out_writer.writeByte(@as(u8, @intCast(carry.* << 4)) | nibble);
            carry.* = -1;
        }
    }
}

fn decodeNibble(b: u8) u8 {
    if (b >= '0' and b <= '9') return b - '0';
    if (b >= 'a' and b <= 'f') return b - 'a' + 10;
    if (b >= 'A' and b <= 'F') return b - 'A' + 10;
    return 0xFF;
}
