const std = @import("std");
const c = @import("../../compat/c.zig").c;

pub const ByteChunk = struct {
    data: [8192]u8,
    len: usize,
    next: ?*ByteChunk,
};

pub const LineChunk = struct {
    data: [8192]u8,
    len: usize,
    lines: usize,
    next: ?*LineChunk,
};

pub fn copyToEof(file: std.Io.File, stdout: anytype) !void {
    var inbuf: [65536]u8 = undefined;
    while (true) {
        const n = c.read(file.handle, &inbuf, inbuf.len);
        if (n <= 0) break;
        try stdout.writeAll(inbuf[0..@intCast(n)]);
    }
}

pub fn streamLinesForward(file: std.Io.File, skip_lines: usize, delim: u8, stdout: anytype) !void {
    if (skip_lines == 0) {
        try copyToEof(file, stdout);
        return;
    }
    var lines_skipped: usize = 0;
    var inbuf: [65536]u8 = undefined;
    while (true) {
        const n = c.read(file.handle, &inbuf, inbuf.len);
        if (n <= 0) break;
        const len: usize = @intCast(n);
        var idx: usize = 0;
        while (idx < len and lines_skipped < skip_lines) : (idx += 1) {
            if (inbuf[idx] == delim) {
                lines_skipped += 1;
                if (lines_skipped == skip_lines) {
                    idx += 1;
                    break;
                }
            }
        }
        if (lines_skipped >= skip_lines and idx < len) {
            try stdout.writeAll(inbuf[idx..len]);
            try copyToEof(file, stdout);
            return;
        }
    }
}

pub fn streamBytesForward(file: std.Io.File, skip_bytes: usize, stdout: anytype) !void {
    if (skip_bytes == 0) {
        try copyToEof(file, stdout);
        return;
    }
    var remaining = skip_bytes;
    var inbuf: [65536]u8 = undefined;
    while (remaining > 0) {
        const to_read = @min(inbuf.len, remaining);
        const n = c.read(file.handle, &inbuf, to_read);
        if (n <= 0) return;
        remaining -= @intCast(n);
    }
    try copyToEof(file, stdout);
}

pub fn bufferLastBytes(file: std.Io.File, count: usize, allocator: std.mem.Allocator, stdout: anytype) !void {
    if (count == 0) return;

    var first: ?*ByteChunk = null;
    var last: ?*ByteChunk = null;
    var total_bytes: usize = 0;

    defer {
        var curr = first;
        while (curr) |c_ptr| {
            const nxt = c_ptr.next;
            allocator.destroy(c_ptr);
            curr = nxt;
        }
    }

    while (true) {
        const chunk = try allocator.create(ByteChunk);
        chunk.len = 0;
        chunk.next = null;

        const n = c.read(file.handle, &chunk.data, chunk.data.len);
        if (n <= 0) {
            allocator.destroy(chunk);
            break;
        }
        chunk.len = @intCast(n);
        total_bytes += chunk.len;

        if (last) |l| {
            l.next = chunk;
            last = chunk;
        } else {
            first = chunk;
            last = chunk;
        }

        while (first) |f| {
            if (total_bytes - f.len >= count) {
                total_bytes -= f.len;
                first = f.next;
                if (first == null) last = null;
                allocator.destroy(f);
            } else {
                break;
            }
        }
    }

    if (total_bytes == 0) return;

    var skip = if (total_bytes > count) total_bytes - count else 0;
    var curr = first;
    while (curr) |c_ptr| : (curr = c_ptr.next) {
        if (skip >= c_ptr.len) {
            skip -= c_ptr.len;
        } else {
            const start = skip;
            skip = 0;
            try stdout.writeAll(c_ptr.data[start..c_ptr.len]);
        }
    }
}

pub fn bufferLastLines(file: std.Io.File, count: usize, delim: u8, allocator: std.mem.Allocator, stdout: anytype) !void {
    if (count == 0) return;

    var first: ?*LineChunk = null;
    var last: ?*LineChunk = null;
    var total_lines: usize = 0;

    defer {
        var curr = first;
        while (curr) |c_ptr| {
            const nxt = c_ptr.next;
            allocator.destroy(c_ptr);
            curr = nxt;
        }
    }

    while (true) {
        const chunk = try allocator.create(LineChunk);
        chunk.len = 0;
        chunk.lines = 0;
        chunk.next = null;

        const n = c.read(file.handle, &chunk.data, chunk.data.len);
        if (n <= 0) {
            allocator.destroy(chunk);
            break;
        }
        chunk.len = @intCast(n);
        for (chunk.data[0..chunk.len]) |b| {
            if (b == delim) chunk.lines += 1;
        }
        total_lines += chunk.lines;

        if (last) |l| {
            l.next = chunk;
            last = chunk;
        } else {
            first = chunk;
            last = chunk;
        }

        while (first) |f| {
            if (total_lines - f.lines > count) {
                total_lines -= f.lines;
                first = f.next;
                if (first == null) last = null;
                allocator.destroy(f);
            } else {
                break;
            }
        }
    }

    const l = last orelse return;
    if (l.len == 0) return;

    if (l.data[l.len - 1] != delim) {
        l.lines += 1;
        total_lines += 1;
    }

    while (first) |f| {
        if (total_lines - f.lines >= count) {
            total_lines -= f.lines;
            first = f.next;
        } else {
            break;
        }
    }

    const target_first = first orelse return;
    const curr_lines = total_lines;
    var start_idx: usize = 0;
    if (curr_lines > count) {
        const to_skip = curr_lines - count;
        var skipped: usize = 0;
        for (target_first.data[0..target_first.len], 0..) |b, idx| {
            if (b == delim) {
                skipped += 1;
                if (skipped == to_skip) {
                    start_idx = idx + 1;
                    break;
                }
            }
        }
    }

    try stdout.writeAll(target_first.data[start_idx..target_first.len]);
    var c_curr = target_first.next;
    while (c_curr) |c_ptr| : (c_curr = c_ptr.next) {
        try stdout.writeAll(c_ptr.data[0..c_ptr.len]);
    }
}
