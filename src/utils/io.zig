const std = @import("std");

/// Copy data from reader to writer with buffer
pub fn copyBuffered(reader: anytype, writer: anytype, buffer: []u8) !void {
    while (true) {
        const bytes_read = try reader.read(buffer);
        if (bytes_read == 0) break;
        try writer.writeAll(buffer[0..bytes_read]);
    }
}

/// Read entire file into memory
pub fn readFile(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    const file = try std.fs.cwd().openFile(path, .{});
    defer file.close();
    return try file.readToEndAlloc(allocator, std.math.maxInt(usize));
}

/// Write data to file atomically
pub fn writeFileAtomic(path: []const u8, data: []const u8) !void {
    const tmp_path = try std.fmt.allocPrint(std.heap.page_allocator, "{s}.tmp", .{path});
    defer std.heap.page_allocator.free(tmp_path);

    {
        const file = try std.fs.cwd().createFile(tmp_path, .{});
        defer file.close();
        try file.writeAll(data);
    }

    try std.fs.cwd().rename(tmp_path, path);
}

/// Buffered line reader for efficient line-by-line processing
pub const LineReader = struct {
    reader: std.io.BufferedReader(4096, std.fs.File.Reader),
    buffer: [4096]u8,
    allocator: std.mem.Allocator,

    pub fn init(file: std.fs.File, allocator: std.mem.Allocator) LineReader {
        return .{
            .reader = std.io.bufferedReader(file.reader()),
            .buffer = undefined,
            .allocator = allocator,
        };
    }

    pub fn readLine(self: *LineReader, allocator: std.mem.Allocator) !?[]u8 {
        var line = std.ArrayList(u8).init(allocator);
        defer line.deinit();

        while (true) {
            const byte = self.reader.reader().readByte() catch |err| switch (err) {
                error.EndOfStream => {
                    if (line.items.len == 0) return null;
                    return try line.toOwnedSlice();
                },
                else => return err,
            };

            if (byte == '\n') {
                return try line.toOwnedSlice();
            }
            try line.append(byte);
        }
    }
};
