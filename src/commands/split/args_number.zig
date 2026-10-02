const std = @import("std");

pub const ChunkMode = enum {
    bytes,
    bytes_stdout,
    lines,
    lines_stdout,
    round_robin,
    round_robin_stdout,
};

pub const NumberSpec = struct {
    mode: ChunkMode,
    k: usize,
    n: usize,
};

fn parseChunkUnit(str: []const u8) ?u128 {
    if (str.len == 0) return null;
    for (str) |ch| {
        if (!std.ascii.isDigit(ch)) return null;
    }
    return std.fmt.parseUnsigned(u128, str, 10) catch std.math.maxInt(u128);
}

pub fn parseNumberSpec(val: []const u8, stderr: anytype) ?NumberSpec {
    var raw = val;
    var is_r = false;
    var is_l = false;
    if (std.mem.startsWith(u8, raw, "r/")) {
        is_r = true;
        raw = raw[2..];
    } else if (std.mem.startsWith(u8, raw, "l/")) {
        is_l = true;
        raw = raw[2..];
    }

    if (std.mem.indexOfScalar(u8, raw, '/')) |slash| {
        const k_str = raw[0..slash];
        const n_str = raw[slash + 1 ..];
        const k_val = parseChunkUnit(k_str);
        const n_val = parseChunkUnit(n_str);

        if (n_val == null or n_val.? == 0) {
            stderr.print("split: invalid number of chunks: '{s}'\n", .{n_str}) catch {};
            return null;
        }
        if (k_val == null or k_val.? == 0 or k_val.? > n_val.?) {
            stderr.print("split: invalid chunk number: '{s}'\n", .{k_str}) catch {};
            return null;
        }

        const mode: ChunkMode = if (is_r) .round_robin_stdout else if (is_l) .lines_stdout else .bytes_stdout;
        const max_usize: u128 = @as(u128, std.math.maxInt(usize));
        return .{
            .mode = mode,
            .k = @intCast(@min(k_val.?, max_usize)),
            .n = @intCast(@min(n_val.?, max_usize)),
        };
    }

    const n_val = parseChunkUnit(raw);
    if (n_val == null or n_val.? == 0) {
        stderr.print("split: invalid number of chunks: '{s}'\n", .{raw}) catch {};
        return null;
    }

    const mode: ChunkMode = if (is_r) .round_robin else if (is_l) .lines else .bytes;
    const max_usize: u128 = @as(u128, std.math.maxInt(usize));
    return .{
        .mode = mode,
        .k = 1,
        .n = @intCast(@min(n_val.?, max_usize)),
    };
}
