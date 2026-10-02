const std = @import("std");
const c = @import("../../compat/c.zig").c;
const chunk_writer = @import("chunk_writer.zig");
const file_namer = @import("file_namer.zig");
const args_mod = @import("args.zig");

pub fn splitNumberedBytes(
    file: std.Io.File,
    total_size: usize,
    spec: args_mod.NumberSpec,
    elide_empty: bool,
    writer: *chunk_writer.ChunkWriter,
    namer: *file_namer.FileNamer,
    stdout: anytype,
    stderr: anytype,
) !void {
    var inbuf: [65536]u8 = undefined;
    const base_chunk = total_size / spec.n;
    const rem = total_size % spec.n;

    for (0..spec.n) |idx| {
        const start = idx * base_chunk + @min(idx, rem);
        const end = (idx + 1) * base_chunk + @min(idx + 1, rem);
        const chunk_len = end - start;

        if (spec.mode == .bytes_stdout) {
            if (idx + 1 == spec.k) {
                var remaining = chunk_len;
                _ = c.lseek(file.handle, @intCast(start), c.SEEK_SET);
                while (remaining > 0) {
                    const to_read = @min(inbuf.len, remaining);
                    const n = c.read(file.handle, &inbuf, to_read);
                    if (n <= 0) break;
                    try stdout.writeAll(inbuf[0..@intCast(n)]);
                    remaining -= @intCast(n);
                }
                return;
            }
        } else {
            if (elide_empty and chunk_len == 0) continue;
            try writer.openNew(namer, stdout, stderr);
            var remaining = chunk_len;
            _ = c.lseek(file.handle, @intCast(start), c.SEEK_SET);
            while (remaining > 0) {
                const to_read = @min(inbuf.len, remaining);
                const n = c.read(file.handle, &inbuf, to_read);
                if (n <= 0) break;
                try writer.writeAll(inbuf[0..@intCast(n)], stderr);
                remaining -= @intCast(n);
            }
            try writer.closeCurrent();
            writer.has_opened = false;
        }
    }
}

pub fn splitNumberedLines(
    file: std.Io.File,
    total_size: usize,
    spec: args_mod.NumberSpec,
    sep: u8,
    elide_empty: bool,
    writer: *chunk_writer.ChunkWriter,
    namer: *file_namer.FileNamer,
    stdout: anytype,
    stderr: anytype,
) !void {
    if (total_size == 0) {
        if (!elide_empty and spec.mode == .lines) {
            for (0..spec.n) |_| {
                try writer.openNew(namer, stdout, stderr);
                try writer.closeCurrent();
                writer.has_opened = false;
            }
        }
        return;
    }

    const n = spec.n;
    const chunk_size = total_size / n;
    const rem_bytes = total_size % n;
    var chunk_no: usize = 1;
    var chunk_end = chunk_size + (if (rem_bytes > 0) @as(usize, 1) else 0);
    var n_written: usize = 0;

    _ = c.lseek(file.handle, 0, c.SEEK_SET);
    var inbuf: [65536]u8 = undefined;

    while (n_written < total_size) {
        const to_read = @min(inbuf.len, total_size - n_written);
        const nr = c.read(file.handle, &inbuf, to_read);
        if (nr <= 0) break;
        const n_read: usize = @intCast(nr);
        var bp: usize = 0;

        while (bp < n_read) {
            var next_chunk = false;
            const skip = if (chunk_end > 1 + n_written)
                @min(n_read - bp, chunk_end - 1 - n_written)
            else
                0;

            var bp_out = n_read;
            if (std.mem.indexOfScalar(u8, inbuf[bp + skip .. n_read], sep)) |pos| {
                bp_out = bp + skip + pos + 1;
                next_chunk = true;
            }

            const to_write = bp_out - bp;
            if (spec.mode == .lines_stdout and spec.k == chunk_no) {
                try stdout.writeAll(inbuf[bp .. bp + to_write]);
            } else if (spec.mode == .lines) {
                if (!writer.has_opened) try writer.openNew(namer, stdout, stderr);
                try writer.writeAll(inbuf[bp .. bp + to_write], stderr);
            }

            n_written += to_write;
            bp += to_write;

            while (next_chunk or chunk_end <= n_written) {
                if (spec.mode == .lines_stdout and spec.k == chunk_no) return;
                if (spec.mode == .lines and writer.has_opened) {
                    try writer.closeCurrent();
                    writer.has_opened = false;
                }
                chunk_end += chunk_size + (if (chunk_no < rem_bytes) @as(usize, 1) else 0);
                chunk_no += 1;
                if (chunk_end <= n_written) {
                    if (spec.mode == .lines and !elide_empty) {
                        try writer.openNew(namer, stdout, stderr);
                        try writer.closeCurrent();
                        writer.has_opened = false;
                    }
                } else {
                    next_chunk = false;
                }
            }
        }
    }

    if (spec.mode == .lines) {
        if (writer.has_opened) {
            try writer.closeCurrent();
            writer.has_opened = false;
        }
        if (!elide_empty) {
            while (chunk_no <= n) : (chunk_no += 1) {
                try writer.openNew(namer, stdout, stderr);
                try writer.closeCurrent();
                writer.has_opened = false;
            }
        }
    }
}

fn splitRoundRobinStdout(
    allocator: std.mem.Allocator,
    file: std.Io.File,
    spec: args_mod.NumberSpec,
    sep: u8,
    stdout: anytype,
) !void {
    var inbuf: [65536]u8 = undefined;
    var line_buf = std.ArrayList(u8).empty;
    defer line_buf.deinit(allocator);
    var cur_k: usize = 1;
    while (true) {
        const n = c.read(file.handle, &inbuf, inbuf.len);
        if (n <= 0) break;
        for (inbuf[0..@intCast(n)]) |b| {
            try line_buf.append(allocator, b);
            if (b == sep) {
                if (cur_k == spec.k) try stdout.writeAll(line_buf.items);
                line_buf.clearRetainingCapacity();
                cur_k = if (cur_k == spec.n) 1 else cur_k + 1;
            }
        }
    }
    if (line_buf.items.len > 0 and cur_k == spec.k) {
        try stdout.writeAll(line_buf.items);
    }
}

fn splitRoundRobinFilter(
    allocator: std.mem.Allocator,
    file: std.Io.File,
    spec: args_mod.NumberSpec,
    sep: u8,
    filter_cmd: []const u8,
    verbose: bool,
    namer: *file_namer.FileNamer,
    stdout: anytype,
    stderr: anytype,
) !void {
    const writers = try allocator.alloc(chunk_writer.ChunkWriter, spec.n);
    defer {
        for (writers) |*w| w.deinit();
        allocator.free(writers);
    }
    const closed = try allocator.alloc(bool, spec.n);
    defer allocator.free(closed);
    for (writers, 0..) |*w, i| {
        w.* = chunk_writer.ChunkWriter.init(allocator, filter_cmd, verbose, null);
        closed[i] = false;
    }

    var active_filters: usize = spec.n;
    var inbuf: [65536]u8 = undefined;
    var line_buf = std.ArrayList(u8).empty;
    defer line_buf.deinit(allocator);
    var line_idx: usize = 0;

    read_loop: while (active_filters > 0) {
        const n = c.read(file.handle, &inbuf, inbuf.len);
        if (n <= 0) break;
        for (inbuf[0..@intCast(n)]) |b| {
            try line_buf.append(allocator, b);
            if (b == sep) {
                const target = line_idx % spec.n;
                if (!closed[target]) {
                    if (!writers[target].has_opened) {
                        try writers[target].openNew(namer, stdout, stderr);
                    }
                    writers[target].writeAll(line_buf.items, stderr) catch {
                        closed[target] = true;
                        active_filters -= 1;
                        if (active_filters == 0) break :read_loop;
                    };
                }
                line_buf.clearRetainingCapacity();
                line_idx += 1;
            }
        }
    }

    for (writers) |*w| w.closeCurrent() catch {};
}

fn writeDynamicLine(name: []const u8, data: []const u8) void {
    var name_buf: [4096]u8 = undefined;
    if (name.len >= name_buf.len) return;
    @memcpy(name_buf[0..name.len], name);
    name_buf[name.len] = 0;
    const fd = c.open(&name_buf, c.O_WRONLY | c.O_CREAT | c.O_APPEND, @as(c_uint, 0o666));
    if (fd >= 0) {
        _ = c.write(fd, data.ptr, data.len);
        _ = c.close(fd);
    }
}

pub fn splitRoundRobin(
    allocator: std.mem.Allocator,
    file: std.Io.File,
    spec: args_mod.NumberSpec,
    sep: u8,
    filter_cmd: ?[]const u8,
    verbose: bool,
    elide_empty: bool,
    namer: *file_namer.FileNamer,
    stdout: anytype,
    stderr: anytype,
) !void {
    if (spec.mode == .round_robin_stdout) {
        return splitRoundRobinStdout(allocator, file, spec, sep, stdout);
    }
    if (filter_cmd) |cmd| {
        return splitRoundRobinFilter(allocator, file, spec, sep, cmd, verbose, namer, stdout, stderr);
    }

    const filenames = try allocator.alloc([]u8, spec.n);
    defer {
        for (filenames) |f| allocator.free(f);
        allocator.free(filenames);
    }
    var name_tmp = std.ArrayList(u8).empty;
    defer name_tmp.deinit(allocator);
    for (filenames) |*slot| {
        try namer.next(&name_tmp);
        slot.* = try allocator.dupe(u8, name_tmp.items);
    }

    const fds = try allocator.alloc(c_int, spec.n);
    defer allocator.free(fds);
    @memset(fds, -1);
    var file_limit = false;

    var inbuf: [65536]u8 = undefined;
    var line_buf = std.ArrayList(u8).empty;
    defer line_buf.deinit(allocator);
    var line_idx: usize = 0;

    while (true) {
        const n = c.read(file.handle, &inbuf, inbuf.len);
        if (n <= 0) break;
        for (inbuf[0..@intCast(n)]) |b| {
            try line_buf.append(allocator, b);
            if (b == sep) {
                const target = line_idx % spec.n;
                if (file_limit) {
                    writeDynamicLine(filenames[target], line_buf.items);
                } else if (fds[target] >= 0) {
                    _ = c.write(fds[target], line_buf.items.ptr, line_buf.items.len);
                } else {
                    var nb: [4096]u8 = undefined;
                    @memcpy(nb[0..filenames[target].len], filenames[target]);
                    nb[filenames[target].len] = 0;
                    const fd = c.open(&nb, c.O_WRONLY | c.O_CREAT | c.O_TRUNC, @as(c_uint, 0o666));
                    if (fd < 0) {
                        file_limit = true;
                        for (fds) |*open_fd| {
                            if (open_fd.* >= 0) {
                                _ = c.close(open_fd.*);
                                open_fd.* = -1;
                            }
                        }
                        writeDynamicLine(filenames[target], line_buf.items);
                    } else {
                        fds[target] = fd;
                        _ = c.write(fd, line_buf.items.ptr, line_buf.items.len);
                    }
                }
                line_buf.clearRetainingCapacity();
                line_idx += 1;
            }
        }
    }

    for (fds, 0..) |fd, i| {
        if (fd >= 0) _ = c.close(fd);
        if (!elide_empty and (line_idx <= i)) {
            writeDynamicLine(filenames[i], "");
        }
    }
}
