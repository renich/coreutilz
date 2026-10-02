const std = @import("std");
const c = @import("../../compat/c.zig").c;
const chunk_writer = @import("chunk_writer.zig");
const file_namer = @import("file_namer.zig");
const args_mod = @import("args.zig");

pub fn splitLines(
    file: std.Io.File,
    lines_per_file: usize,
    sep: u8,
    writer: *chunk_writer.ChunkWriter,
    namer: *file_namer.FileNamer,
    stdout: anytype,
    stderr: anytype,
) !void {
    var inbuf: [65536]u8 = undefined;
    var lines_in_file: usize = 0;

    while (true) {
        const n = c.read(file.handle, &inbuf, inbuf.len);
        if (n <= 0) break;
        const len: usize = @intCast(n);
        var start: usize = 0;

        for (inbuf[0..len], 0..) |b, idx| {
            if (b == sep) {
                lines_in_file += 1;
                if (lines_in_file == lines_per_file) {
                    if (!writer.has_opened) try writer.openNew(namer, stdout, stderr);
                    writer.writeAll(inbuf[start .. idx + 1], stderr) catch |err| switch (err) {
                        error.BrokenPipe => {},
                        else => return err,
                    };
                    try writer.closeCurrent();
                    writer.has_opened = false;
                    lines_in_file = 0;
                    start = idx + 1;
                }
            }
        }
        if (start < len) {
            if (!writer.has_opened) try writer.openNew(namer, stdout, stderr);
            writer.writeAll(inbuf[start..len], stderr) catch |err| switch (err) {
                error.BrokenPipe => {},
                else => return err,
            };
        }
    }
    if (writer.has_opened) {
        try writer.closeCurrent();
        writer.has_opened = false;
    }
}

pub fn splitBytes(
    file: std.Io.File,
    bytes_per_file: usize,
    writer: *chunk_writer.ChunkWriter,
    namer: *file_namer.FileNamer,
    stdout: anytype,
    stderr: anytype,
) !void {
    var inbuf: [65536]u8 = undefined;
    var bytes_in_file: usize = 0;

    while (true) {
        const n = c.read(file.handle, &inbuf, inbuf.len);
        if (n <= 0) break;
        const len: usize = @intCast(n);
        var start: usize = 0;

        while (start < len) {
            if (!writer.has_opened) try writer.openNew(namer, stdout, stderr);
            const needed = bytes_per_file - bytes_in_file;
            const to_write = @min(needed, len - start);
            writer.writeAll(inbuf[start .. start + to_write], stderr) catch |err| switch (err) {
                error.BrokenPipe => {},
                else => return err,
            };
            bytes_in_file += to_write;
            start += to_write;

            if (bytes_in_file == bytes_per_file) {
                try writer.closeCurrent();
                writer.has_opened = false;
                bytes_in_file = 0;
            }
        }
    }
    if (writer.has_opened) {
        try writer.closeCurrent();
        writer.has_opened = false;
    }
}

fn drainLineBytesChunk(
    buf: *std.ArrayList(u8),
    write_len: usize,
    writer: *chunk_writer.ChunkWriter,
    namer: *file_namer.FileNamer,
    stdout: anytype,
    stderr: anytype,
) !void {
    try writer.openNew(namer, stdout, stderr);
    try writer.writeAll(buf.items[0..write_len], stderr);
    try writer.closeCurrent();
    writer.has_opened = false;

    const remaining = buf.items.len - write_len;
    std.mem.copyForwards(u8, buf.items[0..remaining], buf.items[write_len..]);
    buf.items.len = remaining;
}

pub fn splitLineBytes(
    allocator: std.mem.Allocator,
    file: std.Io.File,
    max_bytes: usize,
    sep: u8,
    writer: *chunk_writer.ChunkWriter,
    namer: *file_namer.FileNamer,
    stdout: anytype,
    stderr: anytype,
) !void {
    var buf: std.ArrayList(u8) = .empty;
    defer buf.deinit(allocator);

    var inbuf: [65536]u8 = undefined;
    while (true) {
        const n = c.read(file.handle, &inbuf, inbuf.len);
        if (n < 0) return error.ReadFailed;
        if (n == 0) break;
        try buf.appendSlice(allocator, inbuf[0..@intCast(n)]);

        while (buf.items.len >= max_bytes) {
            const window = buf.items[0..max_bytes];
            const last_sep = std.mem.lastIndexOfScalar(u8, window, sep);
            const write_len = if (last_sep) |idx| idx + 1 else max_bytes;
            try drainLineBytesChunk(&buf, write_len, writer, namer, stdout, stderr);
        }
    }

    while (buf.items.len > 0) {
        const write_len = @min(buf.items.len, max_bytes);
        try drainLineBytesChunk(&buf, write_len, writer, namer, stdout, stderr);
    }
}
