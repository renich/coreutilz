const std = @import("std");
const errors = @import("../utils/errors.zig");
const c = @import("../compat/c.zig").c;

fn getErrno() c_int {
    return c.__errno_location().*;
}

fn setErrno(err: c_int) void {
    c.__errno_location().* = err;
}

fn errnoStr(err: c_int) []const u8 {
    return std.mem.span(c.strerror(err));
}

fn getNanoseconds() i128 {
    var ts: c.struct_timespec = undefined;
    _ = c.clock_gettime(c.CLOCK_MONOTONIC, &ts);
    return @as(i128, ts.tv_sec) * 1_000_000_000 + @as(i128, ts.tv_nsec);
}

pub const name: []const u8 = "dd";
pub const version: []const u8 = "0.1.0";

// Conversion flags
const C_ASCII: u32 = 0x0001;
const C_EBCDIC: u32 = 0x0002;
const C_IBM: u32 = 0x0004;
const C_BLOCK: u32 = 0x0008;
const C_UNBLOCK: u32 = 0x0010;
const C_LCASE: u32 = 0x0020;
const C_UCASE: u32 = 0x0040;
const C_SPARSE: u32 = 0x0080;
const C_SWAB: u32 = 0x0100;
const C_NOERROR: u32 = 0x0200;
const C_NOCREAT: u32 = 0x0400;
const C_EXCL: u32 = 0x0800;
const C_NOTRUNC: u32 = 0x1000;
const C_SYNC: u32 = 0x2000;
const C_FDATASYNC: u32 = 0x4000;
const C_FSYNC: u32 = 0x8000;
const C_TWOBUFS: u32 = 0x10000;

// Input/output flags
const O_FULLBLOCK: u32 = 0x0001;
const O_NOCACHE: u32 = 0x0002;
const O_COUNT_BYTES: u32 = 0x0004;
const O_SKIP_BYTES: u32 = 0x0008;
const O_SEEK_BYTES: u32 = 0x0010;
const O_DIRECT_FLAG: u32 = 0x0020;
const O_NOATIME_FLAG: u32 = 0x0040;
const O_NOFOLLOW_FLAG: u32 = 0x0080;
const O_NONBLOCK_FLAG: u32 = 0x0100;
const O_SYNC_FLAG: u32 = 0x0200;
const O_DSYNC_FLAG: u32 = 0x0400;
const O_DIRECTORY_FLAG: u32 = 0x0800;
const O_APPEND_FLAG: u32 = 0x1000;
const O_NOLINKS_FLAG: u32 = 0x2000;

const StatusLevel = enum {
    default,
    none,
    noxfer,
    progress,
};

const ascii_to_ebcdic = [256]u8{
    0x00, 0x01, 0x02, 0x03, 0x37, 0x2d, 0x2e, 0x2f, 0x16, 0x05, 0x25, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
    0x10, 0x11, 0x12, 0x13, 0x3c, 0x3d, 0x32, 0x26, 0x18, 0x19, 0x3f, 0x27, 0x1c, 0x1d, 0x1e, 0x1f,
    0x40, 0x5a, 0x7f, 0x7b, 0x5b, 0x6c, 0x50, 0x7d, 0x4d, 0x5d, 0x5c, 0x4e, 0x6b, 0x60, 0x4b, 0x61,
    0xf0, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9, 0x7a, 0x5e, 0x4c, 0x7e, 0x6e, 0x6f,
    0x7c, 0xc1, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xd1, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6,
    0xd7, 0xd8, 0xd9, 0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xad, 0xe0, 0xbd, 0x9a, 0x6d,
    0x79, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96,
    0x97, 0x98, 0x99, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xc0, 0x4f, 0xd0, 0x5f, 0x07,
    0x20, 0x21, 0x22, 0x23, 0x24, 0x15, 0x06, 0x17, 0x28, 0x29, 0x2a, 0x2b, 0x2c, 0x09, 0x0a, 0x1b,
    0x30, 0x31, 0x1a, 0x33, 0x34, 0x35, 0x36, 0x08, 0x38, 0x39, 0x3a, 0x3b, 0x04, 0x14, 0x3e, 0xe1,
    0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57,
    0x58, 0x59, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75,
    0x76, 0x77, 0x78, 0x80, 0x8a, 0x8b, 0x8c, 0x8d, 0x8e, 0x8f, 0x90, 0x6a, 0x9b, 0x9c, 0x9d, 0x9e,
    0x9f, 0xa0, 0xaa, 0xab, 0xac, 0x4a, 0xae, 0xaf, 0xb0, 0xb1, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7,
    0xb8, 0xb9, 0xba, 0xbb, 0xbc, 0xa1, 0xbe, 0xbf, 0xca, 0xcb, 0xcc, 0xcd, 0xce, 0xcf, 0xda, 0xdb,
    0xdc, 0xdd, 0xde, 0xdf, 0xea, 0xeb, 0xec, 0xed, 0xee, 0xef, 0xfa, 0xfb, 0xfc, 0xfd, 0xfe, 0xff,
};

const ascii_to_ibm = [256]u8{
    0x00, 0x01, 0x02, 0x03, 0x37, 0x2d, 0x2e, 0x2f, 0x16, 0x05, 0x25, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
    0x10, 0x11, 0x12, 0x13, 0x3c, 0x3d, 0x32, 0x26, 0x18, 0x19, 0x3f, 0x27, 0x1c, 0x1d, 0x1e, 0x1f,
    0x40, 0x5a, 0x7f, 0x7b, 0x5b, 0x6c, 0x50, 0x7d, 0x4d, 0x5d, 0x5c, 0x4e, 0x6b, 0x60, 0x4b, 0x61,
    0xf0, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9, 0x7a, 0x5e, 0x4c, 0x7e, 0x6e, 0x6f,
    0x7c, 0xc1, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9, 0xd1, 0xd2, 0xd3, 0xd4, 0xd5, 0xd6,
    0xd7, 0xd8, 0xd9, 0xe2, 0xe3, 0xe4, 0xe5, 0xe6, 0xe7, 0xe8, 0xe9, 0xad, 0xe0, 0xbd, 0x5f, 0x6d,
    0x79, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x91, 0x92, 0x93, 0x94, 0x95, 0x96,
    0x97, 0x98, 0x99, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xc0, 0x4f, 0xd0, 0xa1, 0x07,
    0x20, 0x21, 0x22, 0x23, 0x24, 0x15, 0x06, 0x17, 0x28, 0x29, 0x2a, 0x2b, 0x2c, 0x09, 0x0a, 0x1b,
    0x30, 0x31, 0x1a, 0x33, 0x34, 0x35, 0x36, 0x08, 0x38, 0x39, 0x3a, 0x3b, 0x04, 0x14, 0x3e, 0xe1,
    0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0x51, 0x52, 0x53, 0x54, 0x55, 0x56, 0x57,
    0x58, 0x59, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75,
    0x76, 0x77, 0x78, 0x80, 0x8a, 0x8b, 0x8c, 0x8d, 0x8e, 0x8f, 0x90, 0x9a, 0x9b, 0x9c, 0x9d, 0x9e,
    0x9f, 0xa0, 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf, 0xb0, 0xb1, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7,
    0xb8, 0xb9, 0xba, 0xbb, 0xbc, 0xbd, 0xbe, 0xbf, 0xca, 0xcb, 0xcc, 0xcd, 0xce, 0xcf, 0xda, 0xdb,
    0xdc, 0xdd, 0xde, 0xdf, 0xea, 0xeb, 0xec, 0xed, 0xee, 0xef, 0xfa, 0xfb, 0xfc, 0xfd, 0xfe, 0xff,
};

const ebcdic_to_ascii = [256]u8{
    0x00, 0x01, 0x02, 0x03, 0x9c, 0x09, 0x86, 0x7f, 0x97, 0x8d, 0x8e, 0x0b, 0x0c, 0x0d, 0x0e, 0x0f,
    0x10, 0x11, 0x12, 0x13, 0x9d, 0x85, 0x08, 0x87, 0x18, 0x19, 0x92, 0x8f, 0x1c, 0x1d, 0x1e, 0x1f,
    0x80, 0x81, 0x82, 0x83, 0x84, 0x0a, 0x17, 0x1b, 0x88, 0x89, 0x8a, 0x8b, 0x8c, 0x05, 0x06, 0x07,
    0x90, 0x91, 0x16, 0x93, 0x94, 0x95, 0x96, 0x04, 0x98, 0x99, 0x9a, 0x9b, 0x14, 0x15, 0x9e, 0x1a,
    0x20, 0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xd5, 0x2e, 0x3c, 0x28, 0x2b, 0x7c,
    0x26, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf, 0xb0, 0xb1, 0x21, 0x24, 0x2a, 0x29, 0x3b, 0x7e,
    0x2d, 0x2f, 0xb2, 0xb3, 0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xcb, 0x2c, 0x25, 0x5f, 0x3e, 0x3f,
    0xba, 0xbb, 0xbc, 0xbd, 0xbe, 0xbf, 0xc0, 0xc1, 0xc2, 0x60, 0x3a, 0x23, 0x40, 0x27, 0x3d, 0x22,
    0xc3, 0x61, 0x62, 0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0xc4, 0xc5, 0xc6, 0xc7, 0xc8, 0xc9,
    0xca, 0x6a, 0x6b, 0x6c, 0x6d, 0x6e, 0x6f, 0x70, 0x71, 0x72, 0x5e, 0xcc, 0xcd, 0xce, 0xcf, 0xd0,
    0xd1, 0xe5, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7a, 0xd2, 0xd3, 0xd4, 0x5b, 0xd6, 0xd7,
    0xd8, 0xd9, 0xda, 0xdb, 0xdc, 0xdd, 0xde, 0xdf, 0xe0, 0xe1, 0xe2, 0xe3, 0xe4, 0x5d, 0xe6, 0xe7,
    0x7b, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46, 0x47, 0x48, 0x49, 0xe8, 0xe9, 0xea, 0xeb, 0xec, 0xed,
    0x7d, 0x4a, 0x4b, 0x4c, 0x4d, 0x4e, 0x4f, 0x50, 0x51, 0x52, 0xee, 0xef, 0xf0, 0xf1, 0xf2, 0xf3,
    0x5c, 0x9f, 0x53, 0x54, 0x55, 0x56, 0x57, 0x58, 0x59, 0x5a, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9,
    0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0xfa, 0xfb, 0xfc, 0xfd, 0xfe, 0xff,
};

// Global telemetry and signal state
var info_signals: std.atomic.Value(usize) = std.atomic.Value(usize).init(0);
var interrupt_signal: std.atomic.Value(c_int) = std.atomic.Value(c_int).init(0);

fn siginfoHandler(_: c_int) callconv(.c) void {
    _ = info_signals.fetchAdd(1, .monotonic);
}

fn interruptHandler(sig: c_int) callconv(.c) void {
    interrupt_signal.store(sig, .monotonic);
}

fn installSignals() void {
    var act: c.struct_sigaction = std.mem.zeroes(c.struct_sigaction);
    act.__sigaction_handler.sa_handler = siginfoHandler;
    _ = c.sigemptyset(&act.sa_mask);
    _ = c.sigaction(c.SIGUSR1, &act, null);

    var int_act: c.struct_sigaction = std.mem.zeroes(c.struct_sigaction);
    int_act.__sigaction_handler.sa_handler = interruptHandler;
    _ = c.sigemptyset(&int_act.sa_mask);
    int_act.sa_flags = @bitCast(@as(u32, c.SA_NODEFER) | @as(u32, c.SA_RESETHAND));
    _ = c.sigaction(c.SIGINT, &int_act, null);
}

const IO_BUFSIZE: i64 = 128 * 1024;

fn openRetry(path: [*:0]const u8, flags: c_int, mode: ?c.mode_t) c_int {
    while (true) {
        const res = if (mode) |m| c.open(path, flags, m) else c.open(path, flags);
        if (res >= 0) return res;
        if (getErrno() != c.EINTR) return res;
    }
}

fn formatHuman(val: f64, buf: []u8, base: f64, units: []const []const u8) ![]const u8 {
    var v = val;
    var idx: usize = 0;
    while (v >= base and idx + 1 < units.len) {
        v /= base;
        idx += 1;
    }
    if (idx == 0) return std.fmt.bufPrint(buf, "{d:.0} {s}", .{ v, units[0] });
    if (v < 9.95) return std.fmt.bufPrint(buf, "{d:.1} {s}", .{ v, units[idx] });
    return std.fmt.bufPrint(buf, "{d:.0} {s}", .{ @round(v), units[idx] });
}

fn formatTimeStr(buf: []u8, elapsed_s: f64, is_progress: bool) ![]const u8 {
    if (is_progress) return std.fmt.bufPrint(buf, "{d:.0} s", .{elapsed_s});
    if (elapsed_s == 0) return "0 s";
    if (elapsed_s < 0.001) return std.fmt.bufPrint(buf, "{e:.4} s", .{elapsed_s});
    return std.fmt.bufPrint(buf, "{d:.6} s", .{elapsed_s});
}

fn swabBuffer(buf: []u8, nread: *usize, saved_byte: *?u8) []u8 {
    var cur_buf = buf;
    var nr = nread.*;
    if (saved_byte.*) |sb| {
        var j = nr;
        while (j > 0) : (j -= 1) cur_buf[j] = cur_buf[j - 1];
        cur_buf[0] = sb;
        nr += 1;
        saved_byte.* = null;
    }
    if (nr % 2 == 1) {
        nr -= 1;
        saved_byte.* = cur_buf[nr];
    }
    var i: usize = 0;
    while (i < nr) : (i += 2) {
        const tmp = cur_buf[i];
        cur_buf[i] = cur_buf[i + 1];
        cur_buf[i + 1] = tmp;
    }
    nread.* = nr;
    return cur_buf[0..nr];
}

const SizeResult = struct {
    val: u64,
    has_B: bool,
};

fn parseSuffix(suffix: []const u8) !struct { mult: u64, has_B: bool } {
    if (suffix.len == 0) return .{ .mult = 1, .has_B = false };
    if (std.mem.eql(u8, suffix, "B")) return .{ .mult = 1, .has_B = true };
    if (std.mem.eql(u8, suffix, "c")) return .{ .mult = 1, .has_B = false };
    if (std.mem.eql(u8, suffix, "w")) return .{ .mult = 2, .has_B = false };
    if (std.mem.eql(u8, suffix, "b")) return .{ .mult = 512, .has_B = false };
    const SuffixEntry = struct { name: []const u8, mult: u64 };
    const table = [_]SuffixEntry{
        .{ .name = "k", .mult = 1024 },
        .{ .name = "kb", .mult = 1000 },
        .{ .name = "kib", .mult = 1024 },
        .{ .name = "m", .mult = 1024 * 1024 },
        .{ .name = "mb", .mult = 1000 * 1000 },
        .{ .name = "mib", .mult = 1024 * 1024 },
        .{ .name = "g", .mult = 1024 * 1024 * 1024 },
        .{ .name = "gb", .mult = 1000 * 1000 * 1000 },
        .{ .name = "gib", .mult = 1024 * 1024 * 1024 },
        .{ .name = "t", .mult = 1024 * 1024 * 1024 * 1024 },
        .{ .name = "tb", .mult = 1000 * 1000 * 1000 * 1000 },
        .{ .name = "tib", .mult = 1024 * 1024 * 1024 * 1024 },
        .{ .name = "p", .mult = 1024 * 1024 * 1024 * 1024 * 1024 },
        .{ .name = "pb", .mult = 1000 * 1000 * 1000 * 1000 * 1000 },
        .{ .name = "pib", .mult = 1024 * 1024 * 1024 * 1024 * 1024 },
        .{ .name = "e", .mult = 1024 * 1024 * 1024 * 1024 * 1024 * 1024 },
        .{ .name = "eb", .mult = 1000 * 1000 * 1000 * 1000 * 1000 * 1000 },
        .{ .name = "eib", .mult = 1024 * 1024 * 1024 * 1024 * 1024 * 1024 },
    };
    for (table) |entry| {
        if (std.ascii.eqlIgnoreCase(suffix, entry.name)) return .{ .mult = entry.mult, .has_B = false };
    }
    return error.InvalidNumber;
}

fn parseSingleNumber(token: []const u8) !struct { val: u64, has_B: bool, overflow: bool } {
    if (token.len == 0) return error.InvalidNumber;
    var digit_end: usize = 0;
    while (digit_end < token.len and token[digit_end] >= '0' and token[digit_end] <= '9') {
        digit_end += 1;
    }
    if (digit_end == 0) return error.InvalidNumber;
    const digits_str = token[0..digit_end];
    const s_res = try parseSuffix(token[digit_end..]);

    var base_val: u64 = 0;
    var base_overflow = false;
    for (digits_str) |ch| {
        const mul_res = @mulWithOverflow(base_val, 10);
        const add_res = @addWithOverflow(mul_res[0], ch - '0');
        if (mul_res[1] != 0 or add_res[1] != 0) {
            base_overflow = true;
            break;
        }
        base_val = add_res[0];
    }

    if (base_overflow or base_val > std.math.maxInt(i64)) return .{ .val = 0, .has_B = s_res.has_B, .overflow = true };
    const res = @mulWithOverflow(base_val, s_res.mult);
    if (res[1] != 0 or res[0] > std.math.maxInt(i64)) return .{ .val = 0, .has_B = s_res.has_B, .overflow = true };
    return .{ .val = res[0], .has_B = s_res.has_B, .overflow = false };
}

fn parseSize(str: []const u8, stderr: anytype) !SizeResult {
    if (str.len == 0 or str[0] == 'x' or str[str.len - 1] == 'x') return error.InvalidNumber;
    const warn_0x = std.mem.startsWith(u8, str, "0x");
    var it = std.mem.splitScalar(u8, str, 'x');
    var product: u64 = 1;
    var any_overflow = false;
    var has_b = false;
    var has_zero = false;

    while (it.next()) |token| {
        if (token.len == 0) return error.InvalidNumber;
        const res = try parseSingleNumber(token);
        if (res.has_B) has_b = true;
        if (res.overflow) any_overflow = true;
        if (res.val == 0 and !res.overflow) {
            has_zero = true;
            product = 0;
        } else if (!has_zero) {
            const mul_res = @mulWithOverflow(product, res.val);
            if (mul_res[1] != 0 or mul_res[0] > std.math.maxInt(i64)) any_overflow = true else product = mul_res[0];
        }
    }

    if (has_zero) {
        if (warn_0x) {
            try stderr.print("dd: warning: '0x' is a zero multiplier; use '00x' if that is intended\n", .{});
            try stderr.flush();
        }
        return .{ .val = 0, .has_B = has_b };
    }
    if (any_overflow) return error.Overflow;
    return .{ .val = product, .has_B = has_b };
}

fn parseSizeOperand(val: []const u8, non_zero: bool, stderr: anytype) !SizeResult {
    const res = parseSize(val, stderr) catch |err| {
        if (err == error.Overflow) {
            try stderr.print("dd: invalid number: '{s}': Value too large for defined data type\n", .{val});
        } else {
            try stderr.print("dd: invalid number: '{s}'\n", .{val});
        }
        return error.Fatal;
    };
    if (non_zero and res.val == 0) {
        try stderr.print("dd: invalid number: '{s}'\n", .{val});
        return error.Fatal;
    }
    return res;
}

const FlagEntry = struct { name: []const u8, flag: u32 };
const flag_table = [_]FlagEntry{
    .{ .name = "append", .flag = O_APPEND_FLAG },
    .{ .name = "direct", .flag = O_DIRECT_FLAG },
    .{ .name = "directory", .flag = O_DIRECTORY_FLAG },
    .{ .name = "dsync", .flag = O_DSYNC_FLAG },
    .{ .name = "sync", .flag = O_SYNC_FLAG },
    .{ .name = "nonblock", .flag = O_NONBLOCK_FLAG },
    .{ .name = "noatime", .flag = O_NOATIME_FLAG },
    .{ .name = "nocache", .flag = O_NOCACHE },
    .{ .name = "nofollow", .flag = O_NOFOLLOW_FLAG },
    .{ .name = "count_bytes", .flag = O_COUNT_BYTES },
    .{ .name = "skip_bytes", .flag = O_SKIP_BYTES },
    .{ .name = "seek_bytes", .flag = O_SEEK_BYTES },
    .{ .name = "binary", .flag = 0 },
    .{ .name = "text", .flag = 0 },
    .{ .name = "cio", .flag = 0 },
    .{ .name = "noctty", .flag = 0 },
};

fn parseSingleFlag(flag: []const u8, is_input: bool, stderr: anytype) !u32 {
    if (std.mem.eql(u8, flag, "fullblock")) {
        if (!is_input) {
            try stderr.print("dd: invalid output flag: 'fullblock'\nTry 'dd --help' for more information.\n", .{});
            return error.InvalidFlag;
        }
        return O_FULLBLOCK;
    }
    for (flag_table) |entry| {
        if (std.mem.eql(u8, flag, entry.name)) return entry.flag;
    }
    const flag_type = if (is_input) "input" else "output";
    try stderr.print("dd: invalid {s} flag: '{s}'\nTry 'dd --help' for more information.\n", .{ flag_type, flag });
    return error.InvalidFlag;
}

fn parseFlags(val: []const u8, is_input: bool, stderr: anytype) !u32 {
    var flags: u32 = 0;
    var it = std.mem.splitScalar(u8, val, ',');
    while (it.next()) |flag| {
        if (flag.len == 0) continue;
        flags |= try parseSingleFlag(flag, is_input, stderr);
    }
    return flags;
}

const ConvEntry = struct { name: []const u8, mask: u32 };
const conv_table = [_]ConvEntry{
    .{ .name = "ascii", .mask = C_ASCII | C_UNBLOCK | C_TWOBUFS },
    .{ .name = "ebcdic", .mask = C_EBCDIC | C_BLOCK | C_TWOBUFS },
    .{ .name = "ibm", .mask = C_IBM | C_BLOCK | C_TWOBUFS },
    .{ .name = "block", .mask = C_BLOCK | C_TWOBUFS },
    .{ .name = "unblock", .mask = C_UNBLOCK | C_TWOBUFS },
    .{ .name = "lcase", .mask = C_LCASE | C_TWOBUFS },
    .{ .name = "ucase", .mask = C_UCASE | C_TWOBUFS },
    .{ .name = "sparse", .mask = C_SPARSE },
    .{ .name = "swab", .mask = C_SWAB | C_TWOBUFS },
    .{ .name = "noerror", .mask = C_NOERROR },
    .{ .name = "nocreat", .mask = C_NOCREAT },
    .{ .name = "excl", .mask = C_EXCL },
    .{ .name = "notrunc", .mask = C_NOTRUNC },
    .{ .name = "sync", .mask = C_SYNC },
    .{ .name = "fdatasync", .mask = C_FDATASYNC },
    .{ .name = "fsync", .mask = C_FSYNC },
};

fn parseConversions(val: []const u8, stderr: anytype) !u32 {
    var mask: u32 = 0;
    var it = std.mem.splitScalar(u8, val, ',');
    while (it.next()) |conv| {
        if (conv.len == 0) continue;
        var found = false;
        for (conv_table) |entry| {
            if (std.mem.eql(u8, conv, entry.name)) {
                mask |= entry.mask;
                found = true;
                break;
            }
        }
        if (!found) {
            try stderr.print("dd: invalid conversion: '{s}'\nTry 'dd --help' for more information.\n", .{conv});
            return error.InvalidConversion;
        }
    }
    return mask;
}

fn setFdFlags(fd: c_int, flags: u32, target_name: []const u8, stderr: anytype) !void {
    if (flags & O_DIRECTORY_FLAG != 0) {
        var st: c.struct_stat = undefined;
        if (c.fstat(fd, &st) != 0 or (st.st_mode & c.S_IFMT) != c.S_IFDIR) {
            try stderr.print("dd: setting flags for '{s}': Not a directory\n", .{target_name});
            return error.Fatal;
        }
    }
    var add_flags: c_int = 0;
    if (flags & O_APPEND_FLAG != 0) add_flags |= c.O_APPEND;
    if (flags & O_NONBLOCK_FLAG != 0) add_flags |= c.O_NONBLOCK;
    if (flags & O_SYNC_FLAG != 0) add_flags |= c.O_SYNC;
    if (flags & O_DSYNC_FLAG != 0) add_flags |= c.O_DSYNC;
    if (add_flags != 0) {
        const old_flags = c.fcntl(fd, c.F_GETFL);
        if (old_flags >= 0) _ = c.fcntl(fd, c.F_SETFL, old_flags | add_flags);
    }
}

const DdConfig = struct {
    if_path: ?[]const u8 = null,
    of_path: ?[]const u8 = null,
    ibs_val: usize = 512,
    obs_val: usize = 512,
    bs_opt: ?usize = null,
    cbs_val: ?usize = null,
    count_val: ?u64 = null,
    skip_val: u64 = 0,
    seek_val: u64 = 0,
    skip_has_B: bool = false,
    seek_has_B: bool = false,
    count_has_B: bool = false,
    conv_mask: u32 = 0,
    iflag_mask: u32 = 0,
    oflag_mask: u32 = 0,
};

fn parseBasicOperand(key: []const u8, val: []const u8, cfg: *DdConfig, stderr: anytype) !bool {
    if (std.mem.eql(u8, key, "if")) {
        cfg.if_path = val;
    } else if (std.mem.eql(u8, key, "of")) {
        cfg.of_path = val;
    } else if (std.mem.eql(u8, key, "bs")) {
        cfg.bs_opt = @intCast((try parseSizeOperand(val, true, stderr)).val);
    } else if (std.mem.eql(u8, key, "ibs")) {
        cfg.ibs_val = @intCast((try parseSizeOperand(val, true, stderr)).val);
    } else if (std.mem.eql(u8, key, "obs")) {
        cfg.obs_val = @intCast((try parseSizeOperand(val, true, stderr)).val);
    } else if (std.mem.eql(u8, key, "cbs")) {
        cfg.cbs_val = @intCast((try parseSizeOperand(val, true, stderr)).val);
    } else {
        return false;
    }
    return true;
}

fn validateCombinations(conv_mask: u32, iflag_mask: u32, oflag_mask: u32, stderr: anytype) !void {
    if ((iflag_mask & O_DIRECT_FLAG != 0 and iflag_mask & O_NOCACHE != 0) or
        (oflag_mask & O_DIRECT_FLAG != 0 and oflag_mask & O_NOCACHE != 0))
    {
        try stderr.print("dd: cannot combine direct and nocache\n", .{});
        return error.Fatal;
    }
    if (@popCount(conv_mask & (C_ASCII | C_EBCDIC | C_IBM)) > 1) {
        try stderr.print("dd: cannot combine any two of {{ascii,ebcdic,ibm}}\n", .{});
        return error.Fatal;
    }
    if (@popCount(conv_mask & (C_BLOCK | C_UNBLOCK)) > 1) {
        try stderr.print("dd: cannot combine block and unblock\n", .{});
        return error.Fatal;
    }
    if (@popCount(conv_mask & (C_LCASE | C_UCASE)) > 1) {
        try stderr.print("dd: cannot combine lcase and ucase\n", .{});
        return error.Fatal;
    }
    if (@popCount(conv_mask & (C_EXCL | C_NOCREAT)) > 1) {
        try stderr.print("dd: cannot combine excl and nocreat\n", .{});
        return error.Fatal;
    }
}

fn openInputFile(if_path: ?[]const u8, iflag_mask: u32, stderr: anytype) !struct { fd: c_int, needs_close: bool } {
    if (if_path) |path| {
        var open_flags: c_int = c.O_RDONLY;
        if (iflag_mask & O_DIRECT_FLAG != 0) open_flags |= c.O_DIRECT;
        if (iflag_mask & O_NOATIME_FLAG != 0) open_flags |= c.O_NOATIME;
        if (iflag_mask & O_NOFOLLOW_FLAG != 0) open_flags |= c.O_NOFOLLOW;
        if (iflag_mask & O_NONBLOCK_FLAG != 0) open_flags |= c.O_NONBLOCK;
        if (iflag_mask & O_DIRECTORY_FLAG != 0) open_flags |= c.O_DIRECTORY;
        const path_c = try std.posix.toPosixPath(path);
        const fd = openRetry(&path_c, open_flags, null);
        if (fd < 0) {
            try stderr.print("dd: failed to open '{s}': {s}\n", .{ path, errnoStr(getErrno()) });
            return error.Fatal;
        }
        return .{ .fd = fd, .needs_close = true };
    }
    try setFdFlags(c.STDIN_FILENO, iflag_mask, "standard input", stderr);
    return .{ .fd = c.STDIN_FILENO, .needs_close = false };
}

fn openOutputFile(of_path: ?[]const u8, oflag_mask: u32, conv_mask: u32, will_seek: bool, stderr: anytype) !struct { fd: c_int, needs_close: bool } {
    if (of_path) |path| {
        var open_flags: c_int = 0;
        if (oflag_mask & O_APPEND_FLAG != 0) open_flags |= c.O_APPEND;
        if (oflag_mask & O_DIRECT_FLAG != 0) open_flags |= c.O_DIRECT;
        if (oflag_mask & O_NONBLOCK_FLAG != 0) open_flags |= c.O_NONBLOCK;
        if (oflag_mask & O_SYNC_FLAG != 0) open_flags |= c.O_SYNC;
        if (oflag_mask & O_DSYNC_FLAG != 0) open_flags |= c.O_DSYNC;
        if (conv_mask & C_NOCREAT == 0) open_flags |= c.O_CREAT;
        if (conv_mask & C_EXCL != 0) open_flags |= c.O_EXCL;
        if (!will_seek and (conv_mask & C_NOTRUNC == 0)) open_flags |= c.O_TRUNC;

        const path_c = try std.posix.toPosixPath(path);
        var fd: c_int = -1;
        if (will_seek) {
            fd = openRetry(&path_c, c.O_RDWR | open_flags, @as(c.mode_t, 0o666));
            if (fd < 0) fd = openRetry(&path_c, c.O_WRONLY | open_flags, @as(c.mode_t, 0o666));
        } else {
            fd = openRetry(&path_c, c.O_WRONLY | open_flags, @as(c.mode_t, 0o666));
        }
        if (fd < 0) {
            try stderr.print("dd: failed to open '{s}': {s}\n", .{ path, errnoStr(getErrno()) });
            return error.Fatal;
        }
        return .{ .fd = fd, .needs_close = true };
    }
    try setFdFlags(c.STDOUT_FILENO, oflag_mask, "standard output", stderr);
    return .{ .fd = c.STDOUT_FILENO, .needs_close = false };
}

const PrepResult = struct {
    cur_in_seekable: bool,
    input_offset: i64,
    max_r: ?u64,
    max_b: u64,
};

pub const Dd = struct {
    allocator: std.mem.Allocator,
    w_bytes: u64 = 0,
    r_full: u64 = 0,
    r_partial: u64 = 0,
    w_full: u64 = 0,
    w_partial: u64 = 0,
    r_truncate: u64 = 0,
    start_time_ns: i128 = 0,
    status_level: StatusLevel = .default,
    progress_len: usize = 0,
    trans_table: [256]u8 = undefined,
    translation_needed: bool = false,
    newline_char: u8 = '\n',
    space_char: u8 = ' ',
    ibuf: ?[]u8 = null,
    obuf: ?[]u8 = null,
    oc: usize = 0,
    ibs: usize = 512,
    obs: usize = 512,
    conv_sparse_active: bool = false,
    final_op_was_seek: bool = false,
    conv_mask: u32 = 0,
    oflag_mask: u32 = 0,
    o_nocache_eof: bool = false,
    i_pending: i64 = 0,
    o_pending: i64 = 0,
    output_offset_tracker: i64 = -2,

    pub fn cleanupBuffers(self: *Dd) void {
        if (self.obuf != null and (self.ibuf == null or self.obuf.?.ptr != self.ibuf.?.ptr)) {
            self.allocator.free(self.obuf.?);
        }
        if (self.ibuf) |buf| {
            self.allocator.free(buf);
        }
        self.ibuf = null;
        self.obuf = null;
    }

    fn cacheRound(self: *Dd, is_input: bool, len: i64) i64 {
        const pending_ptr = if (is_input) &self.i_pending else &self.o_pending;
        if (len != 0) {
            const c_pending = pending_ptr.* + len;
            pending_ptr.* = @mod(c_pending, IO_BUFSIZE);
            return if (c_pending > pending_ptr.*) c_pending - pending_ptr.* else 0;
        }
        return pending_ptr.*;
    }

    fn getInvalidateOffset(self: *Dd, fd: c_int, is_input: bool, input_seekable: bool, input_offset: i64, add_len: i64) i64 {
        if (is_input) {
            if (!input_seekable) {
                setErrno(c.ESPIPE);
                return -1;
            }
            return input_offset;
        }
        if (self.output_offset_tracker != -1) {
            if (self.output_offset_tracker < 0) {
                self.output_offset_tracker = c.lseek(fd, 0, c.SEEK_CUR);
            } else if (add_len != 0) {
                self.output_offset_tracker += add_len;
            }
        }
        return self.output_offset_tracker;
    }

    fn invalidateCache(self: *Dd, fd: c_int, len: i64, is_input: bool, nocache_eof: bool, input_seekable: bool, input_offset: i64) bool {
        const clen = self.cacheRound(is_input, len);
        if (len != 0 and clen == 0) return true;
        if (len == 0 and clen == 0 and !nocache_eof) return true;
        const pending = if (len != 0) self.cacheRound(is_input, 0) else 0;

        const offset = self.getInvalidateOffset(fd, is_input, input_seekable, input_offset, clen + pending);
        if (offset < 0) return false;

        var eff_clen = clen;
        var eff_pending = pending;
        if (len == 0 and clen != 0 and nocache_eof) {
            eff_pending = clen;
            eff_clen = 0;
        }
        var adv_offset = offset - eff_clen - eff_pending;
        if (eff_clen == 0) {
            const page_size: i64 = @intCast(std.heap.pageSize());
            adv_offset -= @mod(adv_offset, page_size);
        }
        const ret = c.posix_fadvise(fd, adv_offset, eff_clen, c.POSIX_FADV_DONTNEED);
        setErrno(ret);
        return ret == 0;
    }

    fn formatCopiedLine(self: *const Dd, buf: []u8, time_str: []const u8, rate_str: []const u8) ![]const u8 {
        var si_buf: [64]u8 = undefined;
        var iec_buf: [64]u8 = undefined;
        if (self.w_bytes == 1) {
            return std.fmt.bufPrint(buf, "1 byte copied, {s}, {s}", .{ time_str, rate_str });
        } else if (self.w_bytes < 1000) {
            return std.fmt.bufPrint(buf, "{d} bytes copied, {s}, {s}", .{ self.w_bytes, time_str, rate_str });
        } else if (self.w_bytes < 1024) {
            const si = try formatHuman(@floatFromInt(self.w_bytes), &si_buf, 1000.0, &[_][]const u8{ "B", "kB", "MB", "GB", "TB", "PB", "EB" });
            return std.fmt.bufPrint(buf, "{d} bytes ({s}) copied, {s}, {s}", .{ self.w_bytes, si, time_str, rate_str });
        } else {
            const si = try formatHuman(@floatFromInt(self.w_bytes), &si_buf, 1000.0, &[_][]const u8{ "B", "kB", "MB", "GB", "TB", "PB", "EB" });
            const iec = try formatHuman(@floatFromInt(self.w_bytes), &iec_buf, 1024.0, &[_][]const u8{ "B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB" });
            return std.fmt.bufPrint(buf, "{d} bytes ({s}, {s}) copied, {s}, {s}", .{ self.w_bytes, si, iec, time_str, rate_str });
        }
    }

    fn printXferStats(self: *Dd, is_progress: bool, stderr: anytype) !void {
        if (self.status_level == .none or self.status_level == .noxfer) return;
        const now_ns = getNanoseconds();
        const elapsed_ns = @max(0, now_ns - self.start_time_ns);
        const elapsed_s = @as(f64, @floatFromInt(elapsed_ns)) / 1_000_000_000.0;
        var rate_num_buf: [64]u8 = undefined;
        var rate_buf: [64]u8 = undefined;
        var time_buf: [64]u8 = undefined;
        const time_str = try formatTimeStr(&time_buf, elapsed_s, is_progress);

        const rate_str = if (elapsed_s <= 0) "Infinity B/s" else blk: {
            const rate_val = @as(f64, @floatFromInt(self.w_bytes)) / elapsed_s;
            const h = try formatHuman(rate_val, &rate_num_buf, 1000.0, &[_][]const u8{ "B", "kB", "MB", "GB", "TB", "PB", "EB" });
            break :blk try std.fmt.bufPrint(&rate_buf, "{s}/s", .{h});
        };

        var line_buf: [256]u8 = undefined;
        const line = try self.formatCopiedLine(&line_buf, time_str, rate_str);
        if (is_progress) {
            try stderr.print("\r{s}", .{line});
            if (line.len < self.progress_len) {
                for (0..(self.progress_len - line.len)) |_| try stderr.print(" ", .{});
            }
            self.progress_len = line.len;
            try stderr.flush();
        } else {
            if (self.progress_len > 0) {
                try stderr.print("\n", .{});
                self.progress_len = 0;
            }
            try stderr.print("{s}\n", .{line});
            try stderr.flush();
        }
    }

    fn printStats(self: *Dd, stderr: anytype) !void {
        if (self.status_level == .none) return;
        if (self.progress_len > 0) {
            try stderr.print("\n", .{});
            self.progress_len = 0;
        }
        try stderr.print("{d}+{d} records in\n", .{ self.r_full, self.r_partial });
        try stderr.print("{d}+{d} records out\n", .{ self.w_full, self.w_partial });
        if (self.r_truncate > 0) {
            if (self.r_truncate == 1) {
                try stderr.print("1 truncated record\n", .{});
            } else {
                try stderr.print("{d} truncated records\n", .{self.r_truncate});
            }
        }
        if (self.status_level != .noxfer) {
            try self.printXferStats(false, stderr);
        }
        try stderr.flush();
    }

    fn processSignals(self: *Dd, stderr: anytype) void {
        while (info_signals.load(.monotonic) > 0) {
            _ = info_signals.fetchSub(1, .monotonic);
            self.printStats(stderr) catch {};
        }
        const sig = interrupt_signal.load(.monotonic);
        if (sig != 0) {
            self.printStats(stderr) catch {};
            _ = c.signal(sig, c.SIG_DFL);
            _ = c.raise(sig);
        }
    }

    fn rawRead(self: *Dd, fd: c_int, buf: []u8, stderr: anytype) !usize {
        while (true) {
            self.processSignals(stderr);
            const ret = c.read(fd, buf.ptr, buf.len);
            if (ret >= 0) return @intCast(ret);
            const err = getErrno();
            if (err == c.EINTR) continue;
            return error.ReadError;
        }
    }

    fn rawReadFullBlock(self: *Dd, fd: c_int, buf: []u8, stderr: anytype) !usize {
        var total: usize = 0;
        while (total < buf.len) {
            const n = try self.rawRead(fd, buf[total..], stderr);
            if (n == 0) break;
            total += n;
        }
        return total;
    }

    fn rawWriteAll(self: *Dd, fd: c_int, buf: []const u8, stderr: anytype) !void {
        var written: usize = 0;
        while (written < buf.len) {
            self.processSignals(stderr);
            const ret = c.write(fd, buf.ptr + written, buf.len - written);
            if (ret > 0) {
                written += @intCast(ret);
            } else if (ret == 0) {
                return error.WriteError;
            } else {
                const err = getErrno();
                if (err == c.EINTR) continue;
                return error.WriteError;
            }
        }
    }

    fn handlePartialDirectWrite(self: *Dd, of_fd: c_int, size: usize) void {
        if (self.oflag_mask & O_DIRECT_FLAG != 0 and size < self.obs) {
            const old_flags = c.fcntl(of_fd, c.F_GETFL);
            if (old_flags >= 0) {
                _ = c.fcntl(of_fd, c.F_SETFL, old_flags & ~c.O_DIRECT);
            }
            self.o_nocache_eof = true;
            _ = self.invalidateCache(of_fd, 0, false, true, true, 0);
            self.conv_mask |= C_FSYNC;
        }
    }

    fn writeBufferInternal(self: *Dd, of_fd: c_int, buf: []const u8, is_partial: bool, o_nocache: bool, stderr: anytype) !void {
        if (buf.len == 0) return;
        self.handlePartialDirectWrite(of_fd, buf.len);
        var is_all_zero = false;
        if (self.conv_sparse_active) {
            is_all_zero = std.mem.allEqual(u8, buf, 0);
        }

        self.final_op_was_seek = false;
        if (self.conv_sparse_active and is_all_zero) {
            if (c.lseek(of_fd, @intCast(buf.len), c.SEEK_CUR) >= 0) {
                self.final_op_was_seek = true;
                self.w_bytes += buf.len;
                if (is_partial) self.w_partial += 1 else self.w_full += 1;
                if (o_nocache) _ = self.invalidateCache(of_fd, @intCast(buf.len), false, false, true, 0);
                return;
            } else {
                self.conv_sparse_active = false;
            }
        }

        try self.rawWriteAll(of_fd, buf, stderr);
        self.w_bytes += buf.len;
        if (is_partial) self.w_partial += 1 else self.w_full += 1;
        if (o_nocache) _ = self.invalidateCache(of_fd, @intCast(buf.len), false, false, true, 0);
    }

    fn writeOutput(self: *Dd, of_fd: c_int, is_partial: bool, o_nocache: bool, stderr: anytype) !void {
        if (self.oc == 0) return;
        const to_write = self.oc;
        self.oc = 0;
        try self.writeBufferInternal(of_fd, self.obuf.?[0..to_write], is_partial, o_nocache, stderr);
    }

    fn writeSingleBuffer(self: *Dd, of_fd: c_int, buf: []const u8, o_nocache: bool, stderr: anytype) !void {
        try self.writeBufferInternal(of_fd, buf, buf.len != self.obs, o_nocache, stderr);
    }

    fn outputChar(self: *Dd, c_val: u8, of_fd: c_int, o_nocache: bool, stderr: anytype) !void {
        self.obuf.?[self.oc] = c_val;
        self.oc += 1;
        if (self.oc >= self.obs) {
            try self.writeOutput(of_fd, false, o_nocache, stderr);
        }
    }

    fn padBlockSpaces(self: *Dd, cbs_val: usize, col: *usize, of_fd: c_int, o_nocache: bool, stderr: anytype) !void {
        while (col.* < cbs_val) : (col.* += 1) {
            try self.outputChar(self.space_char, of_fd, o_nocache, stderr);
        }
    }

    fn copyWithBlock(self: *Dd, buf: []const u8, cbs_val: usize, col: *usize, of_fd: c_int, o_nocache: bool, stderr: anytype) !void {
        for (buf) |b| {
            if (b == self.newline_char) {
                try self.padBlockSpaces(cbs_val, col, of_fd, o_nocache, stderr);
                col.* = 0;
            } else {
                if (col.* == cbs_val) {
                    self.r_truncate += 1;
                } else if (col.* < cbs_val) {
                    try self.outputChar(b, of_fd, o_nocache, stderr);
                }
                col.* += 1;
            }
        }
    }

    fn copyWithUnblock(self: *Dd, buf: []const u8, cbs_val: usize, col: *usize, pending_spaces: *usize, of_fd: c_int, o_nocache: bool, stderr: anytype) !void {
        var i: usize = 0;
        while (i < buf.len) : (i += 1) {
            const b = buf[i];
            if (col.* >= cbs_val) {
                col.* = 0;
                pending_spaces.* = 0;
                try self.outputChar(self.newline_char, of_fd, o_nocache, stderr);
                col.* = 0;
                if (b == self.space_char) {
                    pending_spaces.* += 1;
                    col.* += 1;
                } else {
                    try self.outputChar(b, of_fd, o_nocache, stderr);
                    col.* += 1;
                }
            } else if (b == self.space_char) {
                pending_spaces.* += 1;
                col.* += 1;
            } else {
                while (pending_spaces.* > 0) : (pending_spaces.* -= 1) {
                    try self.outputChar(self.space_char, of_fd, o_nocache, stderr);
                }
                try self.outputChar(b, of_fd, o_nocache, stderr);
                col.* += 1;
            }
        }
    }

    fn copySimple(self: *Dd, buf: []const u8, of_fd: c_int, o_nocache: bool, stderr: anytype) !void {
        var start: usize = 0;
        var nread = buf.len;
        while (nread > 0) {
            const nfree = @min(nread, self.obs - self.oc);
            @memcpy(self.obuf.?[self.oc .. self.oc + nfree], buf[start .. start + nfree]);
            nread -= nfree;
            start += nfree;
            self.oc += nfree;
            if (self.oc >= self.obs) {
                try self.writeOutput(of_fd, false, o_nocache, stderr);
            }
        }
    }

    fn ensureIbuf(self: *Dd, conv_mask: u32, stderr: anytype) !void {
        if (self.ibuf != null) return;
        const extra: usize = if (conv_mask & C_SWAB != 0) 1 else 0;
        self.ibuf = self.allocator.alloc(u8, self.ibs + extra) catch {
            var hbuf: [64]u8 = undefined;
            const h = formatHuman(@floatFromInt(self.ibs), &hbuf, 1024.0, &[_][]const u8{ "B", "KiB", "MiB", "GiB", "TiB" }) catch "";
            try stderr.print("dd: memory exhausted by input buffer of size {d} bytes ({s})\n", .{ self.ibs, h });
            try stderr.flush();
            return error.OutOfMemory;
        };
    }

    fn ensureObuf(self: *Dd, conv_mask: u32, stderr: anytype) !void {
        if (self.obuf != null) return;
        if (conv_mask & C_TWOBUFS != 0) {
            self.obuf = self.allocator.alloc(u8, self.obs) catch {
                var hbuf: [64]u8 = undefined;
                const h = formatHuman(@floatFromInt(self.obs), &hbuf, 1024.0, &[_][]const u8{ "B", "KiB", "MiB", "GiB", "TiB" }) catch "";
                try stderr.print("dd: memory exhausted by output buffer of size {d} bytes ({s})\n", .{ self.obs, h });
                try stderr.flush();
                return error.OutOfMemory;
            };
        } else {
            try self.ensureIbuf(conv_mask, stderr);
            self.obuf = self.ibuf;
        }
    }

    fn checkSkipPastEof(self: *const Dd, if_fd: c_int, total_skip: u64, cur_off: i64, if_path: ?[]const u8, stderr: anytype) !void {
        var st: c.struct_stat = undefined;
        if (c.fstat(if_fd, &st) == 0 and ((st.st_mode & c.S_IFMT) == c.S_IFREG)) {
            const file_size: u64 = if (st.st_size > 0) @intCast(st.st_size) else 0;
            const start_off: u64 = if (cur_off > 0) @intCast(cur_off) else 0;
            if (start_off + total_skip > file_size) {
                _ = c.lseek(if_fd, 0, c.SEEK_END);
                if (self.status_level != .none) {
                    try stderr.print("dd: '{s}': cannot skip to specified offset\n", .{if_path orelse "standard input"});
                }
            }
        }
    }

    fn skipInputRead(self: *Dd, if_fd: c_int, total_skip: u64, conv_mask: u32, if_path: ?[]const u8, stderr: anytype) !void {
        try self.ensureIbuf(conv_mask, stderr);
        var remaining = total_skip;
        while (remaining > 0) {
            const to_read: usize = @intCast(@min(remaining, self.ibs));
            const n = self.rawRead(if_fd, self.ibuf.?[0..to_read], stderr) catch |err| {
                if (conv_mask & C_NOERROR != 0) break;
                return err;
            };
            if (n == 0) {
                if (self.status_level != .none) {
                    try stderr.print("dd: '{s}': cannot skip to specified offset\n", .{if_path orelse "standard input"});
                }
                break;
            }
            remaining -= n;
        }
    }

    fn skipInput(self: *Dd, if_fd: c_int, total_skip: u64, conv_mask: u32, if_path: ?[]const u8, stderr: anytype) !void {
        if (total_skip == 0) return;
        if (total_skip > std.math.maxInt(i64)) {
            if (c.lseek(if_fd, 0, c.SEEK_END) >= 0) {
                try stderr.print("dd: '{s}': cannot skip: Value too large for defined data type\n", .{if_path orelse "standard input"});
                return error.Fatal;
            }
        } else {
            const off: i64 = @intCast(total_skip);
            const cur_off = c.lseek(if_fd, 0, c.SEEK_CUR);
            if (c.lseek(if_fd, off, c.SEEK_CUR) >= 0) {
                try self.checkSkipPastEof(if_fd, total_skip, cur_off, if_path, stderr);
                return;
            } else if (c.lseek(if_fd, 0, c.SEEK_END) >= 0) {
                try stderr.print("dd: '{s}': cannot skip: {s}\n", .{ if_path orelse "standard input", errnoStr(getErrno()) });
                return error.Fatal;
            }
        }
        try self.skipInputRead(if_fd, total_skip, conv_mask, if_path, stderr);
    }

    fn seekOutputWrite(self: *Dd, of_fd: c_int, total_seek: u64, conv_mask: u32, stderr: anytype) !void {
        try self.ensureObuf(conv_mask, stderr);
        @memset(self.obuf.?[0..self.obs], 0);
        var remaining = total_seek;
        while (remaining > 0) {
            const to_write = @min(remaining, self.obs);
            try self.rawWriteAll(of_fd, self.obuf.?[0..to_write], stderr);
            remaining -= to_write;
        }
    }

    fn seekOutput(self: *Dd, of_fd: c_int, total_seek: u64, conv_mask: u32, of_path: ?[]const u8, stderr: anytype) !void {
        if (total_seek == 0) return;
        if (total_seek > std.math.maxInt(i64)) {
            if (c.lseek(of_fd, 0, c.SEEK_END) >= 0) {
                try stderr.print("dd: '{s}': cannot seek: Value too large for defined data type\n", .{of_path orelse "standard output"});
                return error.Fatal;
            }
        } else {
            const off: i64 = @intCast(total_seek);
            if (conv_mask & C_NOTRUNC == 0) _ = c.ftruncate(of_fd, off);
            if (c.lseek(of_fd, off, c.SEEK_CUR) >= 0) return;
            if (c.lseek(of_fd, 0, c.SEEK_END) >= 0) {
                try stderr.print("dd: '{s}': cannot seek: {s}\n", .{ of_path orelse "standard output", errnoStr(getErrno()) });
                return error.Fatal;
            }
        }
        try self.seekOutputWrite(of_fd, total_seek, conv_mask, stderr);
    }

    fn parseStatusLevel(self: *Dd, val: []const u8, stderr: anytype) !void {
        var it = std.mem.splitScalar(u8, val, ',');
        while (it.next()) |st| {
            if (st.len == 0) continue;
            if (std.mem.eql(u8, st, "none")) {
                self.status_level = .none;
            } else if (std.mem.eql(u8, st, "noxfer")) {
                self.status_level = .noxfer;
            } else if (std.mem.eql(u8, st, "progress")) {
                self.status_level = .progress;
            } else {
                try stderr.print("dd: invalid status level: '{s}'\nTry 'dd --help' for more information.\n", .{st});
                return error.Fatal;
            }
        }
    }

    fn parseControlOperand(self: *Dd, key: []const u8, val: []const u8, cfg: *DdConfig, stderr: anytype) !bool {
        if (std.mem.eql(u8, key, "count")) {
            const res = try parseSizeOperand(val, false, stderr);
            cfg.count_val = res.val;
            if (res.has_B) cfg.count_has_B = true;
        } else if (std.mem.eql(u8, key, "skip") or std.mem.eql(u8, key, "iseek")) {
            const res = try parseSizeOperand(val, false, stderr);
            cfg.skip_val = res.val;
            if (res.has_B) cfg.skip_has_B = true;
        } else if (std.mem.eql(u8, key, "seek") or std.mem.eql(u8, key, "oseek")) {
            const res = try parseSizeOperand(val, false, stderr);
            cfg.seek_val = res.val;
            if (res.has_B) cfg.seek_has_B = true;
        } else if (std.mem.eql(u8, key, "conv")) {
            cfg.conv_mask |= try parseConversions(val, stderr);
        } else if (std.mem.eql(u8, key, "iflag")) {
            cfg.iflag_mask |= try parseFlags(val, true, stderr);
        } else if (std.mem.eql(u8, key, "oflag")) {
            cfg.oflag_mask |= try parseFlags(val, false, stderr);
        } else if (std.mem.eql(u8, key, "status")) {
            try self.parseStatusLevel(val, stderr);
        } else {
            return false;
        }
        return true;
    }

    fn parseOperand(self: *Dd, arg: []const u8, cfg: *DdConfig, stderr: anytype) !void {
        const eq_pos = std.mem.indexOfScalar(u8, arg, '=') orelse {
            try stderr.print("dd: unrecognized operand '{s}'\nTry 'dd --help' for more information.\n", .{arg});
            return error.Fatal;
        };
        const key = arg[0..eq_pos];
        const val = arg[eq_pos + 1 ..];
        if (try parseBasicOperand(key, val, cfg, stderr)) return;
        if (try self.parseControlOperand(key, val, cfg, stderr)) return;
        try stderr.print("dd: unrecognized operand '{s}'\nTry 'dd --help' for more information.\n", .{arg});
        return error.Fatal;
    }

    fn parseAllArgs(self: *Dd, args: [][]const u8, cfg: *DdConfig, stderr: anytype) !bool {
        for (args[1..]) |arg| {
            if (std.mem.eql(u8, arg, "--")) break;
            if (std.mem.eql(u8, arg, "--help")) {
                var stdout_buf: [4096]u8 = undefined;
                var stdout_writer: std.Io.File.Writer = .init(.stdout(), std.Options.debug_io, &stdout_buf);
                try printHelp(&stdout_writer.interface);
                try stdout_writer.interface.flush();
                return true;
            } else if (std.mem.eql(u8, arg, "--version")) {
                var stdout_buf: [4096]u8 = undefined;
                var stdout_writer: std.Io.File.Writer = .init(.stdout(), std.Options.debug_io, &stdout_buf);
                try printVersion(&stdout_writer.interface);
                try stdout_writer.interface.flush();
                return true;
            }
        }
        for (args[1..]) |arg| {
            if (std.mem.eql(u8, arg, "--")) continue;
            try self.parseOperand(arg, cfg, stderr);
        }
        return false;
    }

    fn postProcessConfig(self: *Dd, cfg: *DdConfig) void {
        if (cfg.bs_opt) |b| {
            cfg.ibs_val = b;
            cfg.obs_val = b;
        } else {
            cfg.conv_mask |= C_TWOBUFS;
        }
        self.ibs = cfg.ibs_val;
        self.obs = cfg.obs_val;
        if (cfg.cbs_val == null) {
            cfg.conv_mask &= ~(C_BLOCK | C_UNBLOCK);
        }
        if (cfg.skip_has_B) cfg.iflag_mask |= O_SKIP_BYTES;
        if (cfg.count_has_B) cfg.iflag_mask |= O_COUNT_BYTES;
        if (cfg.seek_has_B) cfg.oflag_mask |= O_SEEK_BYTES;
    }

    fn setupTranslations(self: *Dd, conv_mask: u32) void {
        for (0..256) |i| self.trans_table[i] = @intCast(i);
        if (conv_mask & C_ASCII != 0) {
            for (0..256) |i| self.trans_table[i] = ebcdic_to_ascii[self.trans_table[i]];
            self.translation_needed = true;
        }
        if (conv_mask & C_UCASE != 0) {
            _ = c.setlocale(c.LC_ALL, "");
            for (0..256) |i| self.trans_table[i] = @intCast(c.toupper(@intCast(self.trans_table[i])));
            self.translation_needed = true;
        } else if (conv_mask & C_LCASE != 0) {
            _ = c.setlocale(c.LC_ALL, "");
            for (0..256) |i| self.trans_table[i] = @intCast(c.tolower(@intCast(self.trans_table[i])));
            self.translation_needed = true;
        }
        if (conv_mask & C_EBCDIC != 0) {
            for (0..256) |i| self.trans_table[i] = ascii_to_ebcdic[self.trans_table[i]];
            self.newline_char = ascii_to_ebcdic['\n'];
            self.space_char = ascii_to_ebcdic[' '];
            self.translation_needed = true;
        } else if (conv_mask & C_IBM != 0) {
            for (0..256) |i| self.trans_table[i] = ascii_to_ibm[self.trans_table[i]];
            self.newline_char = ascii_to_ibm['\n'];
            self.space_char = ascii_to_ibm[' '];
            self.translation_needed = true;
        }
    }

    fn handleCountZero(
        self: *Dd,
        max_records: ?u64,
        max_bytes: u64,
        cfg: DdConfig,
        if_fd: c_int,
        of_fd: c_int,
        input_seekable: bool,
        input_offset: i64,
        stderr: anytype,
    ) !bool {
        if (max_records == null or max_records.? != 0 or max_bytes != 0) return false;
        if (cfg.iflag_mask & O_NOCACHE != 0) {
            if (!self.invalidateCache(if_fd, 0, true, true, input_seekable, input_offset)) {
                try stderr.print("dd: failed to discard cache for: {s}: {s}\n", .{ cfg.if_path orelse "standard input", errnoStr(getErrno()) });
                return error.Fatal;
            }
        }
        if (cfg.oflag_mask & O_NOCACHE != 0) {
            if (!self.invalidateCache(of_fd, 0, false, true, true, 0)) {
                try stderr.print("dd: failed to discard cache for: {s}: {s}\n", .{ cfg.of_path orelse "standard output", errnoStr(getErrno()) });
                return error.Fatal;
            }
        }
        try self.printStats(stderr);
        return true;
    }

    fn readNextBlock(
        self: *Dd,
        if_fd: c_int,
        is_fullblock: bool,
        read_target: usize,
        conv_mask: u32,
        if_path: ?[]const u8,
        stderr: anytype,
    ) !?usize {
        const res = if (is_fullblock)
            self.rawReadFullBlock(if_fd, self.ibuf.?[0..read_target], stderr)
        else
            self.rawRead(if_fd, self.ibuf.?[0..read_target], stderr);

        return res catch |err| {
            if (conv_mask & C_NOERROR != 0) {
                self.printStats(stderr) catch {};
                return null;
            }
            try stderr.print("dd: error reading '{s}': {s}\n", .{ if_path orelse "standard input", @errorName(err) });
            return error.Fatal;
        };
    }

    fn processAndWriteBlock(
        self: *Dd,
        buf: []u8,
        cbs_val: ?usize,
        col_ptr: *usize,
        spaces_ptr: *usize,
        of_fd: c_int,
        o_nocache: bool,
        two_bufs: bool,
        stderr: anytype,
    ) !void {
        if (self.conv_mask & C_BLOCK != 0) {
            try self.copyWithBlock(buf, cbs_val.?, col_ptr, of_fd, o_nocache, stderr);
        } else if (self.conv_mask & C_UNBLOCK != 0) {
            try self.copyWithUnblock(buf, cbs_val.?, col_ptr, spaces_ptr, of_fd, o_nocache, stderr);
        } else if (two_bufs) {
            try self.copySimple(buf, of_fd, o_nocache, stderr);
        } else {
            try self.writeSingleBuffer(of_fd, buf, o_nocache, stderr);
        }
    }

    fn flushTrailingData(
        self: *Dd,
        saved_byte: ?u8,
        cbs_val: ?usize,
        col_val: usize,
        two_bufs: bool,
        of_fd: c_int,
        o_nocache: bool,
        stderr: anytype,
    ) !void {
        if (saved_byte) |sb| {
            const sb_val = if (self.translation_needed) self.trans_table[sb] else sb;
            if (self.conv_mask & C_BLOCK != 0) {
                var c_col = col_val;
                try self.copyWithBlock(&[_]u8{sb_val}, cbs_val.?, &c_col, of_fd, o_nocache, stderr);
            } else if (self.conv_mask & C_UNBLOCK != 0) {
                var c_col = col_val;
                var ps: usize = 0;
                try self.copyWithUnblock(&[_]u8{sb_val}, cbs_val.?, &c_col, &ps, of_fd, o_nocache, stderr);
            } else if (two_bufs) {
                try self.outputChar(sb_val, of_fd, o_nocache, stderr);
            } else {
                try self.writeSingleBuffer(of_fd, &[_]u8{sb_val}, o_nocache, stderr);
            }
        }
        if (self.conv_mask & C_BLOCK != 0 and col_val > 0) {
            var c_col = col_val;
            try self.padBlockSpaces(cbs_val.?, &c_col, of_fd, o_nocache, stderr);
        }
        if (self.conv_mask & C_UNBLOCK != 0 and col_val > 0) try self.outputChar(self.newline_char, of_fd, o_nocache, stderr);
        if (two_bufs and self.oc > 0) try self.writeOutput(of_fd, true, o_nocache, stderr);
    }

    fn finishOutputSync(
        self: *Dd,
        of_fd: c_int,
        if_fd: c_int,
        i_nocache: bool,
        o_nocache: bool,
        i_nocache_eof: bool,
        input_seekable: bool,
        input_offset: i64,
    ) void {
        if (self.final_op_was_seek) {
            var st: c.struct_stat = undefined;
            if (c.fstat(of_fd, &st) == 0 and ((st.st_mode & c.S_IFMT) == c.S_IFREG)) {
                const cur_off = c.lseek(of_fd, 0, c.SEEK_CUR);
                if (cur_off >= 0 and cur_off > st.st_size) _ = c.ftruncate(of_fd, cur_off);
            }
        }
        if (self.conv_mask & C_FSYNC != 0) {
            _ = c.fsync(of_fd);
        } else if (self.conv_mask & C_FDATASYNC != 0) {
            _ = c.fdatasync(of_fd);
        }
        if (i_nocache or i_nocache_eof) {
            _ = self.invalidateCache(if_fd, 0, true, i_nocache_eof, input_seekable, input_offset);
        }
        if (o_nocache or self.o_nocache_eof) {
            _ = self.invalidateCache(of_fd, 0, false, self.o_nocache_eof, true, 0);
        }
    }

    fn checkProgressStats(self: *Dd, stderr: anytype, next_prog: *i128) !void {
        if (self.status_level == .progress and getNanoseconds() >= next_prog.*) {
            try self.printXferStats(true, stderr);
            next_prog.* = getNanoseconds() + 1_000_000_000;
        }
    }

    fn transformInputBlock(self: *Dd, conv_mask: u32, nr_ptr: *usize, saved_byte: *?u8) []u8 {
        var nr = nr_ptr.*;
        if (conv_mask & C_SYNC != 0 and nr < self.ibs) {
            @memset(self.ibuf.?[nr..self.ibs], if (conv_mask & (C_BLOCK | C_UNBLOCK) != 0) @as(u8, ' ') else @as(u8, 0));
            nr = self.ibs;
            nr_ptr.* = nr;
        }
        var pbuf = self.ibuf.?[0..nr];
        if (conv_mask & C_SWAB != 0) pbuf = swabBuffer(self.ibuf.?[0 .. nr + 1], nr_ptr, saved_byte);
        if (self.translation_needed) for (pbuf) |*b| {
            b.* = self.trans_table[b.*];
        };
        return pbuf;
    }

    fn recordsLimitReached(self: *const Dd, max_records: ?u64, max_bytes: u64) bool {
        if (max_records) |mr| {
            const extra: u64 = if (max_bytes > 0) 1 else 0;
            return (self.r_full + self.r_partial >= mr + extra);
        }
        return false;
    }

    fn readTargetSize(self: *const Dd, max_records: ?u64, max_bytes: u64) usize {
        if (max_records != null and self.r_full + self.r_partial >= max_records.?) {
            return @intCast(max_bytes);
        }
        return self.ibs;
    }

    fn runMainLoop(
        self: *Dd,
        if_fd: c_int,
        of_fd: c_int,
        cfg: DdConfig,
        max_records: ?u64,
        max_bytes: u64,
        init_offset: i64,
        stderr: anytype,
    ) !u8 {
        try self.ensureIbuf(cfg.conv_mask, stderr);
        try self.ensureObuf(cfg.conv_mask, stderr);
        var input_offset = init_offset;
        const input_seekable = (input_offset >= 0);
        var saved_byte: ?u8 = null;
        var col: usize = 0;
        var spaces: usize = 0;
        var next_prog = self.start_time_ns + 1_000_000_000;
        var i_nocache_eof = false;

        while (!self.recordsLimitReached(max_records, max_bytes)) {
            try self.checkProgressStats(stderr, &next_prog);
            const target = self.readTargetSize(max_records, max_bytes);
            const opt_nr = try self.readNextBlock(if_fd, cfg.iflag_mask & O_FULLBLOCK != 0, target, cfg.conv_mask, cfg.if_path, stderr);
            if (opt_nr == null) break;
            var nr = opt_nr.?;
            if (nr == 0) {
                i_nocache_eof = (cfg.iflag_mask & O_NOCACHE != 0);
                self.o_nocache_eof = (cfg.oflag_mask & O_NOCACHE != 0) and (cfg.conv_mask & C_NOTRUNC == 0);
                break;
            }
            input_offset += @intCast(nr);
            if (cfg.iflag_mask & O_NOCACHE != 0) _ = self.invalidateCache(if_fd, @intCast(nr), true, false, input_seekable, input_offset);
            if (nr == self.ibs) self.r_full += 1 else self.r_partial += 1;
            const pbuf = self.transformInputBlock(cfg.conv_mask, &nr, &saved_byte);
            try self.processAndWriteBlock(pbuf, cfg.cbs_val, &col, &spaces, of_fd, cfg.oflag_mask & O_NOCACHE != 0, cfg.conv_mask & C_TWOBUFS != 0, stderr);
        }
        try self.flushTrailingData(saved_byte, cfg.cbs_val, col, cfg.conv_mask & C_TWOBUFS != 0, of_fd, cfg.oflag_mask & O_NOCACHE != 0, stderr);
        self.finishOutputSync(of_fd, if_fd, cfg.iflag_mask & O_NOCACHE != 0, cfg.oflag_mask & O_NOCACHE != 0, i_nocache_eof, input_seekable, input_offset);
        try self.printStats(stderr);
        return 0;
    }

    fn prepareOffsetsAndLimits(self: *Dd, in_fd: c_int, out_fd: c_int, cfg: DdConfig, stderr: anytype) !PrepResult {
        const t_skip: u64 = if (cfg.skip_val > 0) (if (cfg.iflag_mask & O_SKIP_BYTES != 0) cfg.skip_val else cfg.skip_val * self.ibs) else 0;
        const t_seek: u64 = if (cfg.seek_val > 0) (if (cfg.oflag_mask & O_SEEK_BYTES != 0) cfg.seek_val else cfg.seek_val * self.obs) else 0;
        try self.skipInput(in_fd, t_skip, cfg.conv_mask, cfg.if_path, stderr);
        const cur_in_off = c.lseek(in_fd, 0, c.SEEK_CUR);
        const input_offset: i64 = @max(0, cur_in_off);
        try self.seekOutput(out_fd, t_seek, cfg.conv_mask, cfg.of_path, stderr);

        const has_cb = (cfg.iflag_mask & O_COUNT_BYTES != 0 or cfg.oflag_mask & O_COUNT_BYTES != 0);
        const max_r = if (cfg.count_val) |c_cnt| (if (has_cb) c_cnt / self.ibs else c_cnt) else null;
        const max_b: u64 = if (cfg.count_val) |c_cnt| (if (has_cb) c_cnt % self.ibs else 0) else 0;
        return .{
            .cur_in_seekable = (cur_in_off >= 0),
            .input_offset = input_offset,
            .max_r = max_r,
            .max_b = max_b,
        };
    }

    pub fn execute(self: *Dd, args: [][]const u8) !u8 {
        var stderr_buf: [4096]u8 = undefined;
        var stderr_writer: std.Io.File.Writer = .init(.stderr(), std.Options.debug_io, &stderr_buf);
        const stderr = &stderr_writer.interface;
        defer stderr.flush() catch {};

        info_signals.store(0, .monotonic);
        interrupt_signal.store(0, .monotonic);
        installSignals();

        var cfg: DdConfig = .{};
        if (self.parseAllArgs(args, &cfg, stderr) catch return 1) return 0;
        self.postProcessConfig(&cfg);
        validateCombinations(cfg.conv_mask, cfg.iflag_mask, cfg.oflag_mask, stderr) catch return 1;
        self.setupTranslations(cfg.conv_mask);
        self.conv_sparse_active = (cfg.conv_mask & C_SPARSE != 0);

        const in_f = openInputFile(cfg.if_path, cfg.iflag_mask, stderr) catch return 1;
        defer if (in_f.needs_close) {
            _ = c.close(in_f.fd);
        };
        const out_f = openOutputFile(cfg.of_path, cfg.oflag_mask, cfg.conv_mask, cfg.seek_val > 0, stderr) catch return 1;
        defer if (out_f.needs_close) {
            _ = c.close(out_f.fd);
        };

        self.conv_mask = cfg.conv_mask;
        self.oflag_mask = cfg.oflag_mask;

        const prep = self.prepareOffsetsAndLimits(in_f.fd, out_f.fd, cfg, stderr) catch return 1;
        self.start_time_ns = getNanoseconds();
        if (self.handleCountZero(prep.max_r, prep.max_b, cfg, in_f.fd, out_f.fd, prep.cur_in_seekable, prep.input_offset, stderr) catch return 1) return 0;

        return self.runMainLoop(in_f.fd, out_f.fd, cfg, prep.max_r, prep.max_b, prep.input_offset, stderr);
    }
};

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var dd = Dd{ .allocator = allocator };
    defer dd.cleanupBuffers();
    return try dd.execute(args);
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: dd [OPERAND]...
        \\  or:  dd OPTION
        \\Copy a file, converting and formatting according to the operands.
        \\
        \\  bs=BYTES        read and write up to BYTES bytes at a time
        \\  cbs=BYTES       convert BYTES bytes at a time
        \\  conv=CONVS      convert the file as per the comma separated symbol list
        \\  count=N         copy only N input blocks
        \\  ibs=BYTES       read up to BYTES bytes at a time (default: 512)
        \\  if=FILE         read from FILE instead of stdin
        \\  iflag=FLAGS     read as per the comma separated symbol list
        \\  obs=BYTES       write BYTES bytes at a time (default: 512)
        \\  of=FILE         write to FILE instead of stdout
        \\  oflag=FLAGS     write as per the comma separated symbol list
        \\  seek=N          (or oseek=N) skip N obs-sized blocks at start of output
        \\  skip=N          (or iseek=N) skip N ibs-sized blocks at start of input
        \\  status=LEVEL    The LEVEL of information to print to stderr;
        \\                  'none' suppresses everything but error messages,
        \\                  'noxfer' suppresses the final transfer statistics,
        \\                  'progress' shows periodic transfer statistics
        \\      --help      display this help and exit
        \\      --version   output version information and exit
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}

test "dd parseSize multipliers and suffixes" {
    const dummy_stderr = std.io.null_writer;
    const res1 = try parseSize("512", dummy_stderr);
    try std.testing.expectEqual(@as(u64, 512), res1.bytes);
    try std.testing.expectEqual(false, res1.has_byte_suffix);

    const res2 = try parseSize("1K", dummy_stderr);
    try std.testing.expectEqual(@as(u64, 1024), res2.bytes);

    const res3 = try parseSize("2x512", dummy_stderr);
    try std.testing.expectEqual(@as(u64, 1024), res3.bytes);

    const res4 = try parseSize("14B", dummy_stderr);
    try std.testing.expectEqual(@as(u64, 14), res4.bytes);
    try std.testing.expectEqual(true, res4.has_byte_suffix);

    const res5 = try parseSize("1MiB", dummy_stderr);
    try std.testing.expectEqual(@as(u64, 1024 * 1024), res5.bytes);

    const res6 = try parseSize("1MB", dummy_stderr);
    try std.testing.expectEqual(@as(u64, 1000 * 1000), res6.bytes);
}

test "dd parseSize invalid numbers" {
    const dummy_stderr = std.io.null_writer;
    try std.testing.expectError(error.InvalidNumber, parseSize("B", dummy_stderr));
    try std.testing.expectError(error.InvalidNumber, parseSize("1x", dummy_stderr));
    try std.testing.expectError(error.InvalidNumber, parseSize("x1", dummy_stderr));
    try std.testing.expectError(error.InvalidNumber, parseSize("1xx1", dummy_stderr));
    try std.testing.expectError(error.InvalidNumber, parseSize("KBB", dummy_stderr));
}
