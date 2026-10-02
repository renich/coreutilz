const std = @import("std");
const common = @import("common.zig");
const WrapWriter = common.WrapWriter;
const c = @import("../../compat/c.zig").c;

pub fn encodeStream(file: std.Io.File, wrap: *WrapWriter, is_msbf: bool) !void {
    var in_buf: [2048]u8 = undefined;
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
            var bit: usize = 0;
            while (bit < 8) : (bit += 1) {
                const shift: u3 = if (is_msbf) @intCast(7 - bit) else @intCast(bit);
                out_buf[out_idx] = '0' + @as(u8, @intCast((byte >> shift) & 1));
                out_idx += 1;
            }
            if (out_idx + 8 > out_buf.len) {
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
    is_msbf: bool,
    ignore_garbage: bool,
) !void {
    var in_buf: [16384]u8 = undefined;
    var accum: u8 = 0;
    var bit_count: usize = 0;

    while (true) {
        const n_read = c.read(file.handle, &in_buf, in_buf.len);
        if (n_read < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            return error.ReadError;
        }
        if (n_read == 0) break;
        const chunk = in_buf[0..@intCast(n_read)];
        try decodeChunk(chunk, &accum, &bit_count, out_writer, is_msbf, ignore_garbage);
    }

    if (bit_count != 0) return error.InvalidInput;
}

fn decodeChunk(
    chunk: []const u8,
    accum: *u8,
    bit_count: *usize,
    out_writer: *std.Io.Writer,
    is_msbf: bool,
    ignore_garbage: bool,
) !void {
    for (chunk) |byte| {
        if (!ignore_garbage and (byte == '\n' or byte == '\r')) continue;
        if (byte != '0' and byte != '1') {
            if (ignore_garbage) continue;
            return error.InvalidInput;
        }
        const bit: u1 = if (byte == '1') 1 else 0;
        if (is_msbf) {
            accum.* = (accum.* << 1) | bit;
        } else {
            accum.* |= @as(u8, bit) << @intCast(bit_count.*);
        }
        bit_count.* += 1;
        if (bit_count.* == 8) {
            try out_writer.writeByte(accum.*);
            accum.* = 0;
            bit_count.* = 0;
        }
    }
}
