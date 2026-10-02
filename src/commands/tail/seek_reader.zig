const std = @import("std");
const c = @import("../../compat/c.zig").c;
const ring_buffer = @import("ring_buffer.zig");

pub fn isSeekable(file: std.Io.File) bool {
    const cur = c.lseek(file.handle, 0, c.SEEK_CUR);
    if (cur < 0) return false;
    var st: c.struct_stat = undefined;
    if (c.fstat(file.handle, &st) == 0) {
        if ((st.st_mode & c.S_IFMT) == c.S_IFIFO or (st.st_mode & c.S_IFMT) == c.S_IFSOCK) {
            return false;
        }
    }
    return true;
}

pub fn tailSeekBytes(
    file: std.Io.File,
    count: usize,
    from_start: bool,
    allocator: std.mem.Allocator,
    stdout: anytype,
) !void {
    if (from_start) {
        if (count >= std.math.maxInt(c.off_t)) return;
        _ = c.lseek(file.handle, @intCast(count), c.SEEK_SET);
        try ring_buffer.copyToEof(file, stdout);
        return;
    }
    if (count == 0) return;

    var st: c.struct_stat = undefined;
    const is_chr = (c.fstat(file.handle, &st) == 0 and (st.st_mode & c.S_IFMT) == c.S_IFCHR);
    if (is_chr) {
        var remaining = count;
        var inbuf: [8192]u8 = undefined;
        while (remaining > 0) {
            const to_read = @min(inbuf.len, remaining);
            const n = c.read(file.handle, &inbuf, to_read);
            if (n <= 0) break;
            try stdout.writeAll(inbuf[0..@intCast(n)]);
            remaining -= @intCast(n);
        }
        return;
    }

    const cur_pos = c.lseek(file.handle, 0, c.SEEK_CUR);
    const initial_pos: usize = if (cur_pos > 0) @intCast(cur_pos) else 0;
    const has_usable_size = (c.fstat(file.handle, &st) == 0 and
        (st.st_mode & c.S_IFMT) == c.S_IFREG and
        st.st_size > st.st_blksize);

    if (!has_usable_size) {
        _ = c.lseek(file.handle, @intCast(initial_pos), c.SEEK_SET);
        try ring_buffer.bufferLastBytes(file, count, allocator, stdout);
        return;
    }

    const size = c.lseek(file.handle, 0, c.SEEK_END);
    if (size <= 0 or @as(usize, @intCast(size)) <= initial_pos) return;
    const u_size: usize = @intCast(size);
    const available = u_size - initial_pos;
    const start_pos = if (available > count) u_size - count else initial_pos;
    _ = c.lseek(file.handle, @intCast(start_pos), c.SEEK_SET);
    try ring_buffer.copyToEof(file, stdout);
}

pub fn tailSeekLines(
    file: std.Io.File,
    count: usize,
    delim: u8,
    from_start: bool,
    allocator: std.mem.Allocator,
    stdout: anytype,
) !void {
    if (from_start) {
        if (count >= std.math.maxInt(c.off_t)) return;
        _ = c.lseek(file.handle, 0, c.SEEK_SET);
        try ring_buffer.streamLinesForward(file, count, delim, stdout);
        return;
    }
    if (count == 0) return;

    var st: c.struct_stat = undefined;
    const has_usable_size = (c.fstat(file.handle, &st) == 0 and
        (st.st_mode & c.S_IFMT) == c.S_IFREG and
        st.st_size > st.st_blksize);

    const cur_pos = c.lseek(file.handle, 0, c.SEEK_CUR);
    const initial_pos: usize = if (cur_pos > 0) @intCast(cur_pos) else 0;

    if (!has_usable_size) {
        _ = c.lseek(file.handle, @intCast(initial_pos), c.SEEK_SET);
        try ring_buffer.bufferLastLines(file, count, delim, allocator, stdout);
        return;
    }

    const size = c.lseek(file.handle, 0, c.SEEK_END);
    if (size <= 0 or @as(usize, @intCast(size)) <= initial_pos) return;

    var pos = size;
    var lines_found: usize = 0;
    var target_offset: usize = initial_pos;
    var buf: [8192]u8 = undefined;

    outer: while (pos > @as(c.off_t, @intCast(initial_pos))) {
        const remaining: usize = @intCast(pos - @as(c.off_t, @intCast(initial_pos)));
        const to_read: usize = if (remaining >= buf.len) buf.len else remaining;
        const read_start: i64 = pos - @as(i64, @intCast(to_read));
        _ = c.lseek(file.handle, read_start, c.SEEK_SET);
        const n = c.read(file.handle, &buf, to_read);
        if (n <= 0) break;
        const len: usize = @intCast(n);

        var idx: usize = len;
        while (idx > 0) {
            idx -= 1;
            const global_idx = @as(usize, @intCast(read_start)) + idx;
            if (buf[idx] == delim) {
                if (global_idx + 1 == @as(usize, @intCast(size))) {
                    continue;
                }
                lines_found += 1;
                if (lines_found == count) {
                    target_offset = global_idx + 1;
                    break :outer;
                }
            }
        }
        pos = read_start;
    }

    _ = c.lseek(file.handle, @intCast(target_offset), c.SEEK_SET);
    try ring_buffer.copyToEof(file, stdout);
}
