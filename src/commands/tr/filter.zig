const std = @import("std");
const c = @import("../../compat/c.zig").c;

pub const Tables = struct {
    map: [256]u8,
    delete: [256]bool,
    squeeze: [256]bool,

    pub fn init() Tables {
        var t: Tables = undefined;
        for (0..256) |i| {
            t.map[i] = @intCast(i);
            t.delete[i] = false;
            t.squeeze[i] = false;
        }
        return t;
    }
};

pub fn translateStream(tables: *const Tables, stdout: anytype) !void {
    var inbuf: [65536]u8 = undefined;
    var outbuf: [65536]u8 = undefined;
    while (true) {
        const n = c.read(std.posix.STDIN_FILENO, &inbuf, inbuf.len);
        if (n < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            return error.ReadError;
        }
        if (n == 0) break;
        const len: usize = @intCast(n);
        for (0..len) |i| {
            outbuf[i] = tables.map[inbuf[i]];
        }
        try stdout.writeAll(outbuf[0..len]);
    }
}

pub fn deleteStream(tables: *const Tables, stdout: anytype) !void {
    var inbuf: [65536]u8 = undefined;
    var outbuf: [65536]u8 = undefined;
    while (true) {
        const n = c.read(std.posix.STDIN_FILENO, &inbuf, inbuf.len);
        if (n < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            return error.ReadError;
        }
        if (n == 0) break;
        const len: usize = @intCast(n);
        var out_len: usize = 0;
        for (0..len) |i| {
            const b = inbuf[i];
            if (!tables.delete[b]) {
                outbuf[out_len] = b;
                out_len += 1;
            }
        }
        if (out_len > 0) {
            try stdout.writeAll(outbuf[0..out_len]);
        }
    }
}

pub fn squeezeStream(tables: *const Tables, stdout: anytype) !void {
    var inbuf: [65536]u8 = undefined;
    var outbuf: [65536]u8 = undefined;
    var last_char: ?u8 = null;
    while (true) {
        const n = c.read(std.posix.STDIN_FILENO, &inbuf, inbuf.len);
        if (n < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            return error.ReadError;
        }
        if (n == 0) break;
        const len: usize = @intCast(n);
        var out_len: usize = 0;
        for (0..len) |i| {
            const b = inbuf[i];
            if (tables.squeeze[b]) {
                if (last_char != null and last_char.? == b) continue;
            }
            outbuf[out_len] = b;
            out_len += 1;
            last_char = b;
        }
        if (out_len > 0) {
            try stdout.writeAll(outbuf[0..out_len]);
        }
    }
}

pub fn deleteAndSqueezeStream(tables: *const Tables, stdout: anytype) !void {
    var inbuf: [65536]u8 = undefined;
    var outbuf: [65536]u8 = undefined;
    var last_char: ?u8 = null;
    while (true) {
        const n = c.read(std.posix.STDIN_FILENO, &inbuf, inbuf.len);
        if (n < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            return error.ReadError;
        }
        if (n == 0) break;
        const len: usize = @intCast(n);
        var out_len: usize = 0;
        for (0..len) |i| {
            const b = inbuf[i];
            if (tables.delete[b]) continue;
            if (tables.squeeze[b]) {
                if (last_char != null and last_char.? == b) continue;
            }
            outbuf[out_len] = b;
            out_len += 1;
            last_char = b;
        }
        if (out_len > 0) {
            try stdout.writeAll(outbuf[0..out_len]);
        }
    }
}

pub fn translateAndSqueezeStream(tables: *const Tables, stdout: anytype) !void {
    var inbuf: [65536]u8 = undefined;
    var outbuf: [65536]u8 = undefined;
    var last_char: ?u8 = null;
    while (true) {
        const n = c.read(std.posix.STDIN_FILENO, &inbuf, inbuf.len);
        if (n < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            return error.ReadError;
        }
        if (n == 0) break;
        const len: usize = @intCast(n);
        var out_len: usize = 0;
        for (0..len) |i| {
            const m = tables.map[inbuf[i]];
            if (tables.squeeze[m]) {
                if (last_char != null and last_char.? == m) continue;
            }
            outbuf[out_len] = m;
            out_len += 1;
            last_char = m;
        }
        if (out_len > 0) {
            try stdout.writeAll(outbuf[0..out_len]);
        }
    }
}
