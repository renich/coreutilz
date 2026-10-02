const std = @import("std");
const c = @import("../compat/c.zig").c;
const algo = @import("factor/algo.zig");

pub const name: []const u8 = "factor";
pub const version: []const u8 = "0.1.0";

const PIPE_BUF: usize = 4096;

pub const LineBuffer = struct {
    buf: [PIPE_BUF * 2]u8 = undefined,
    len: usize = 0,
    is_tty: bool,

    pub fn init() LineBuffer {
        return .{
            .is_tty = c.isatty(c.STDOUT_FILENO) != 0,
        };
    }

    pub fn flush(self: *LineBuffer) !void {
        if (self.len == 0) return;
        var written: usize = 0;
        while (written < self.len) {
            const nw = c.write(c.STDOUT_FILENO, self.buf[written..self.len].ptr, self.len - written);
            if (nw <= 0) {
                if (c.__errno_location().* == c.EINTR) continue;
                return error.WriteFailed;
            }
            written += @intCast(nw);
        }
        self.len = 0;
    }

    fn halfFlush(self: *LineBuffer) !void {
        const check_len = @min(self.len, PIPE_BUF);
        const nl = std.mem.lastIndexOfScalar(u8, self.buf[0..check_len], '\n');
        const prefix_len = if (nl) |pos| pos + 1 else check_len;
        var written: usize = 0;
        while (written < prefix_len) {
            const nw = c.write(c.STDOUT_FILENO, self.buf[written..prefix_len].ptr, prefix_len - written);
            if (nw <= 0) {
                if (c.__errno_location().* == c.EINTR) continue;
                return error.WriteFailed;
            }
            written += @intCast(nw);
        }
        const suffix_len = self.len - prefix_len;
        if (suffix_len > 0) {
            std.mem.copyForwards(u8, self.buf[0..suffix_len], self.buf[prefix_len..self.len]);
        }
        self.len = suffix_len;
    }

    pub fn writeAll(self: *LineBuffer, bytes: []const u8) !void {
        var src = bytes;
        while (src.len > 0) {
            const avail = self.buf.len - self.len;
            const to_copy = @min(src.len, avail);
            @memcpy(self.buf[self.len .. self.len + to_copy], src[0..to_copy]);
            self.len += to_copy;
            src = src[to_copy..];
            if (self.len >= PIPE_BUF) {
                if (self.is_tty) {
                    try self.flush();
                } else {
                    try self.halfFlush();
                }
            }
        }
    }
};

fn formatExponents(factors: []const u512, buf: []u8, start_pos: usize) usize {
    var pos = start_pos;
    var i: usize = 0;
    while (i < factors.len) {
        const f = factors[i];
        var count: usize = 0;
        while (i < factors.len and factors[i] == f) : (i += 1) {
            count += 1;
        }
        const part = if (count == 1)
            std.fmt.bufPrint(buf[pos..], " {d}", .{f}) catch return pos
        else
            std.fmt.bufPrint(buf[pos..], " {d}^{d}", .{ f, count }) catch return pos;
        pos += part.len;
    }
    return pos;
}

fn printFactors(num_str: []const u8, factors: []const u512, exponents: bool, lbuf: *LineBuffer) !void {
    var line_buf: [4096]u8 = undefined;
    var pos: usize = 0;
    const prefix = std.fmt.bufPrint(line_buf[pos..], "{s}:", .{num_str}) catch return;
    pos += prefix.len;

    if (factors.len == 0) {
        line_buf[pos] = '\n';
        pos += 1;
        try lbuf.writeAll(line_buf[0..pos]);
        return;
    }

    if (!exponents) {
        for (factors) |f| {
            const part = std.fmt.bufPrint(line_buf[pos..], " {d}", .{f}) catch break;
            pos += part.len;
        }
    } else {
        pos = formatExponents(factors, &line_buf, pos);
    }
    line_buf[pos] = '\n';
    pos += 1;
    try lbuf.writeAll(line_buf[0..pos]);
}

fn processToken(tok: []const u8, exponents: bool, lbuf: *LineBuffer, stderr: anytype, alloc: std.mem.Allocator, seed: *u64) !bool {
    var s = tok;
    while (s.len > 0 and (s[0] == ' ' or s[0] == '\t' or s[0] == '\r' or s[0] == '\n')) : (s = s[1..]) {}
    if (s.len > 0 and s[0] == '+') s = s[1..];
    if (s.len == 0) {
        stderr.print("factor: '{s}' is not a valid positive integer\n", .{tok}) catch {};
        return false;
    }
    for (s) |ch| {
        if (!std.ascii.isDigit(ch)) {
            stderr.print("factor: '{s}' is not a valid positive integer\n", .{tok}) catch {};
            return false;
        }
    }
    const val = std.fmt.parseInt(u512, s, 10) catch {
        stderr.print("factor: '{s}' is not a valid positive integer\n", .{tok}) catch {};
        return false;
    };
    var factors: std.ArrayListUnmanaged(u512) = .empty;
    defer factors.deinit(alloc);
    try algo.factorNumber(val, &factors, alloc, seed);
    try printFactors(s, factors.items, exponents, lbuf);
    return true;
}

fn runStdin(exponents: bool, lbuf: *LineBuffer, stderr: anytype, alloc: std.mem.Allocator, seed: *u64) !u8 {
    var buf: [65536]u8 = undefined;
    var start: usize = 0;
    var ok = true;
    while (true) {
        const n = c.read(0, buf[start..].ptr, buf.len - start);
        if (n < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            return 1;
        }
        const total = start + @as(usize, @intCast(n));
        if (total == 0) break;
        var i: usize = 0;
        var partial = false;
        while (i < total) {
            while (i < total and (buf[i] == ' ' or buf[i] == '\t' or buf[i] == '\n' or buf[i] == '\r')) : (i += 1) {}
            if (i >= total) break;
            const tok_start = i;
            while (i < total and !(buf[i] == ' ' or buf[i] == '\t' or buf[i] == '\n' or buf[i] == '\r')) : (i += 1) {}
            if (i >= total and n > 0) {
                std.mem.copyForwards(u8, buf[0 .. total - tok_start], buf[tok_start..total]);
                start = total - tok_start;
                partial = true;
                break;
            }
            if (!try processToken(buf[tok_start..i], exponents, lbuf, stderr, alloc, seed)) ok = false;
        }
        if (n == 0) break;
        if (!partial) start = 0;
    }
    return if (ok) 0 else 1;
}

fn parseArgs(args: [][]const u8, operands: *std.ArrayListUnmanaged([]const u8), exponents: *bool, lbuf: *LineBuffer, stderr: anytype, alloc: std.mem.Allocator) !?u8 {
    var past = false;
    for (args[1..]) |arg| {
        if (past or !std.mem.startsWith(u8, arg, "-") or std.mem.eql(u8, arg, "-")) {
            try operands.append(alloc, arg);
        } else if (std.mem.eql(u8, arg, "--")) {
            past = true;
        } else if (std.mem.eql(u8, arg, "--help")) {
            try lbuf.writeAll("Usage: factor [OPTION] [NUMBER]...\nPrint the prime factors of each specified integer NUMBER.\n");
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try lbuf.writeAll("factor (coreutilz) " ++ version ++ "\n");
            return 0;
        } else if (std.mem.eql(u8, arg, "--exponents") or std.mem.eql(u8, arg, "-h")) {
            exponents.* = true;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            stderr.print("factor: unrecognized option '{s}'\nTry 'factor --help' for more information.\n", .{arg}) catch {};
            return 1;
        } else {
            for (arg[1..]) |ch| {
                if (ch == 'h') {
                    exponents.* = true;
                } else {
                    stderr.print("factor: invalid option -- '{c}'\nTry 'factor --help' for more information.\n", .{ch}) catch {};
                    return 1;
                }
            }
        }
    }
    return null;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stderr_buf: [4096]u8 = undefined;
    var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stderr = &err_w.interface;

    var operands: std.ArrayListUnmanaged([]const u8) = .empty;
    defer operands.deinit(allocator);
    var exponents = false;
    var lbuf = LineBuffer.init();

    if (try parseArgs(args, &operands, &exponents, &lbuf, stderr, allocator)) |rc| {
        lbuf.flush() catch return 1;
        stderr.flush() catch {};
        return rc;
    }

    var seed: u64 = 0x9e3779b97f4a7c15;
    var ok = true;
    if (operands.items.len == 0) {
        const rc = try runStdin(exponents, &lbuf, stderr, allocator, &seed);
        lbuf.flush() catch return 1;
        stderr.flush() catch {};
        return rc;
    }
    for (operands.items) |op| {
        if (!try processToken(op, exponents, &lbuf, stderr, allocator, &seed)) ok = false;
    }
    lbuf.flush() catch return 1;
    stderr.flush() catch {};
    return if (ok) 0 else 1;
}
