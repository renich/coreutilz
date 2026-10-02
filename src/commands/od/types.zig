const std = @import("std");

pub const AddressRadix = enum { octal, decimal, hex, none };

pub const FormatKind = enum {
    char,
    named_char,
    octal,
    decimal_signed,
    decimal_unsigned,
    hex,
    float,
};

pub const FormatSpec = struct {
    kind: FormatKind,
    size: usize, // 1, 2, 4, 8
};

pub const OdConfig = struct {
    radix: AddressRadix = .octal,
    skip_bytes: u64 = 0,
    has_read_limit: bool = false,
    read_limit: u64 = 0,
    line_bytes: usize = 16,
    output_duplicates: bool = false,
    formats: std.ArrayList(FormatSpec) = .empty,

    pub fn deinit(self: *OdConfig, allocator: std.mem.Allocator) void {
        self.formats.deinit(allocator);
    }
};

pub fn parseFormat(cfg: *OdConfig, s: []const u8, allocator: std.mem.Allocator) !void {
    var i: usize = 0;
    while (i < s.len) {
        const c = s[i];
        i += 1;
        switch (c) {
            'a' => try cfg.formats.append(allocator, .{ .kind = .named_char, .size = 1 }),
            'c' => try cfg.formats.append(allocator, .{ .kind = .char, .size = 1 }),
            'o', 'd', 'u', 'x' => {
                var size: usize = 4;
                if (i < s.len) {
                    switch (s[i]) {
                        '1', 'C' => {
                            size = 1;
                            i += 1;
                        },
                        '2', 'S' => {
                            size = 2;
                            i += 1;
                        },
                        '4', 'I' => {
                            size = 4;
                            i += 1;
                        },
                        '8', 'L' => {
                            size = 8;
                            i += 1;
                        },
                        else => {},
                    }
                }
                const kind: FormatKind = switch (c) {
                    'o' => .octal,
                    'd' => .decimal_signed,
                    'u' => .decimal_unsigned,
                    'x' => .hex,
                    else => unreachable,
                };
                try cfg.formats.append(allocator, .{ .kind = kind, .size = size });
            },
            'f' => {
                var size: usize = 4;
                if (i < s.len) {
                    switch (s[i]) {
                        '4', 'F' => {
                            size = 4;
                            i += 1;
                        },
                        '8', 'D' => {
                            size = 8;
                            i += 1;
                        },
                        else => {},
                    }
                }
                try cfg.formats.append(allocator, .{ .kind = .float, .size = size });
            },
            else => return error.InvalidFormat,
        }
    }
}
