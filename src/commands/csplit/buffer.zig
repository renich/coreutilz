const std = @import("std");
const c = @import("../../compat/c.zig").c;
const FileManager = @import("file_manager.zig").FileManager;

pub const Line = struct {
    num: usize,
    data: []u8,
};

pub const LineBuffer = struct {
    allocator: std.mem.Allocator,
    fd: c_int,
    io_buf: [65536]u8 = undefined,
    io_start: usize = 0,
    io_end: usize = 0,
    eof_reached: bool = false,

    pending: std.ArrayList(Line),
    total_read: usize = 0,

    pub fn init(allocator: std.mem.Allocator, fd: c_int) LineBuffer {
        return .{
            .allocator = allocator,
            .fd = fd,
            .pending = .empty,
        };
    }

    pub fn deinit(self: *LineBuffer) void {
        for (self.pending.items) |item| {
            self.allocator.free(item.data);
        }
        self.pending.deinit(self.allocator);
    }

    fn refillIo(self: *LineBuffer) !bool {
        if (self.eof_reached) return false;
        if (self.io_start < self.io_end) {
            const rem = self.io_end - self.io_start;
            std.mem.copyForwards(u8, self.io_buf[0..rem], self.io_buf[self.io_start..self.io_end]);
            self.io_start = 0;
            self.io_end = rem;
        } else {
            self.io_start = 0;
            self.io_end = 0;
        }
        const to_read = self.io_buf.len - self.io_end;
        const n = c.read(self.fd, self.io_buf[self.io_end..].ptr, to_read);
        if (n <= 0) {
            self.eof_reached = true;
            return (self.io_start < self.io_end);
        }
        self.io_end += @intCast(n);
        return true;
    }

    fn readNextRawLine(self: *LineBuffer) !?[]u8 {
        var line_builder: std.ArrayList(u8) = .empty;
        errdefer line_builder.deinit(self.allocator);

        while (true) {
            if (self.io_start >= self.io_end) {
                if (!try self.refillIo()) {
                    if (line_builder.items.len == 0) {
                        line_builder.deinit(self.allocator);
                        return null;
                    }
                    return try line_builder.toOwnedSlice(self.allocator);
                }
            }
            const chunk = self.io_buf[self.io_start..self.io_end];
            if (std.mem.indexOfScalar(u8, chunk, '\n')) |newline_pos| {
                const take_len = newline_pos + 1;
                try line_builder.appendSlice(self.allocator, chunk[0..take_len]);
                self.io_start += take_len;
                return try line_builder.toOwnedSlice(self.allocator);
            }
            try line_builder.appendSlice(self.allocator, chunk);
            self.io_start = self.io_end;
        }
    }

    pub fn peek(self: *LineBuffer, k: usize) !?Line {
        while (self.pending.items.len <= k) {
            const raw = try self.readNextRawLine();
            if (raw == null) return null;
            self.total_read += 1;
            try self.pending.append(self.allocator, .{
                .num = self.total_read,
                .data = raw.?,
            });
        }
        return self.pending.items[k];
    }

    pub fn pop(self: *LineBuffer) !Line {
        if (self.pending.items.len == 0) {
            _ = try self.peek(0);
        }
        if (self.pending.items.len == 0) return error.PrematureEOF;
        return self.pending.orderedRemove(0);
    }

    pub fn discardFirst(self: *LineBuffer) void {
        if (self.pending.items.len == 0) {
            _ = self.peek(0) catch null;
        }
        if (self.pending.items.len > 0) {
            const item = self.pending.orderedRemove(0);
            self.allocator.free(item.data);
        }
    }

    pub fn dumpRest(
        self: *LineBuffer,
        fm: *FileManager,
        stderr: anytype,
    ) !void {
        while (self.pending.items.len > 0) {
            const item = self.pending.orderedRemove(0);
            defer self.allocator.free(item.data);
            try fm.writeLine(item.data, stderr);
        }
        while (try self.readNextRawLine()) |raw| {
            defer self.allocator.free(raw);
            try fm.writeLine(raw, stderr);
        }
    }
};
