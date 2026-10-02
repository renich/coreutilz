const std = @import("std");
const types = @import("types.zig");

const named_chars = [_][]const u8{
    "nul", "soh", "stx", "etx", "eot", "enq", "ack", "bel",
    "bs",  "ht",  "nl",  "vt",  "ff",  "cr",  "so",  "si",
    "dle", "dc1", "dc2", "dc3", "dc4", "nak", "syn", "etb",
    "can", "em",  "sub", "esc", "fs",  "gs",  "rs",  "us",
    "sp",
};

pub fn printAddress(writer: anytype, addr: u64, radix: types.AddressRadix) !void {
    switch (radix) {
        .none => {},
        .octal => try writer.print("{o:0>7}", .{addr}),
        .decimal => try writer.print("{d:0>7}", .{addr}),
        .hex => try writer.print("{x:0>6}", .{addr}),
    }
}

pub fn printChunk(writer: anytype, chunk: []const u8, spec: types.FormatSpec) !void {
    switch (spec.kind) {
        .char => {
            for (chunk) |b| {
                switch (b) {
                    0 => try writer.writeAll("  \\0"),
                    '\x07' => try writer.writeAll("  \\a"),
                    '\x08' => try writer.writeAll("  \\b"),
                    '\t' => try writer.writeAll("  \\t"),
                    '\n' => try writer.writeAll("  \\n"),
                    '\x0b' => try writer.writeAll("  \\v"),
                    '\x0c' => try writer.writeAll("  \\f"),
                    '\r' => try writer.writeAll("  \\r"),
                    32...126 => try writer.print("   {c}", .{b}),
                    else => try writer.print(" {o:0>3}", .{b}),
                }
            }
        },
        .named_char => {
            for (chunk) |b| {
                const b7 = b & 0x7F;
                if (b7 <= 32) {
                    try writer.print("{s:>4}", .{named_chars[b7]});
                } else if (b7 == 127) {
                    try writer.writeAll(" del");
                } else {
                    try writer.print("   {c}", .{b7});
                }
            }
        },
        .octal => {
            var i: usize = 0;
            while (i < chunk.len) : (i += spec.size) {
                const sz = @min(spec.size, chunk.len - i);
                const val = readUint(chunk[i .. i + sz]);
                switch (spec.size) {
                    1 => try writer.print(" {o:0>3}", .{val}),
                    2 => try writer.print(" {o:0>6}", .{val}),
                    4 => try writer.print(" {o:0>11}", .{val}),
                    8 => try writer.print(" {o:0>22}", .{val}),
                    else => {},
                }
            }
        },
        .hex => {
            var i: usize = 0;
            while (i < chunk.len) : (i += spec.size) {
                const sz = @min(spec.size, chunk.len - i);
                const val = readUint(chunk[i .. i + sz]);
                switch (spec.size) {
                    1 => try writer.print("  {x:0>2}", .{val}),
                    2 => try writer.print("   {x:0>4}", .{val}),
                    4 => try writer.print("       {x:0>8}", .{val}),
                    8 => try writer.print("               {x:0>16}", .{val}),
                    else => {},
                }
            }
        },
        .decimal_unsigned => {
            var i: usize = 0;
            while (i < chunk.len) : (i += spec.size) {
                const sz = @min(spec.size, chunk.len - i);
                const val = readUint(chunk[i .. i + sz]);
                switch (spec.size) {
                    1 => try writer.print(" {d:>3}", .{val}),
                    2 => try writer.print(" {d:>5}", .{val}),
                    4 => try writer.print(" {d:>10}", .{val}),
                    8 => try writer.print(" {d:>20}", .{val}),
                    else => {},
                }
            }
        },
        .decimal_signed => {
            var i: usize = 0;
            while (i < chunk.len) : (i += spec.size) {
                const sz = @min(spec.size, chunk.len - i);
                const val = readInt(chunk[i .. i + sz]);
                switch (spec.size) {
                    1 => try writer.print(" {d:>4}", .{val}),
                    2 => try writer.print(" {d:>6}", .{val}),
                    4 => try writer.print(" {d:>11}", .{val}),
                    8 => try writer.print(" {d:>20}", .{val}),
                    else => {},
                }
            }
        },
        .float => {
            var i: usize = 0;
            while (i < chunk.len) : (i += spec.size) {
                const sz = @min(spec.size, chunk.len - i);
                if (spec.size == 4 and sz == 4) {
                    const u = @as(u32, @truncate(readUint(chunk[i .. i + 4])));
                    const f: f32 = @bitCast(u);
                    try writer.print(" {e:>14}", .{f});
                } else if (spec.size == 8 and sz == 8) {
                    const u = readUint(chunk[i .. i + 8]);
                    const f: f64 = @bitCast(u);
                    try writer.print(" {e:>21}", .{f});
                }
            }
        },
    }
}

fn readUint(bytes: []const u8) u64 {
    var val: u64 = 0;
    for (bytes, 0..) |b, i| {
        val |= @as(u64, b) << @as(u6, @intCast(i * 8));
    }
    return val;
}

fn readInt(bytes: []const u8) i64 {
    const u = readUint(bytes);
    switch (bytes.len) {
        1 => return @as(i8, @bitCast(@as(u8, @truncate(u)))),
        2 => return @as(i16, @bitCast(@as(u16, @truncate(u)))),
        4 => return @as(i32, @bitCast(@as(u32, @truncate(u)))),
        8 => return @as(i64, @bitCast(u)),
        else => return @as(i64, @intCast(u)),
    }
}
