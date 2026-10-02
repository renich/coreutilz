const std = @import("std");
const args_mod = @import("args.zig");

pub const SuffixType = args_mod.SuffixType;

pub const FileNamer = struct {
    prefix_buf: std.ArrayList(u8),
    suffix_type: SuffixType,
    suffix_len: usize,
    auto_extend: bool,
    additional_suffix: []const u8,
    indices: std.ArrayList(usize),
    allocator: std.mem.Allocator,
    first: bool = true,
    exhausted: bool = false,

    const alpha_alphabet = "abcdefghijklmnopqrstuvwxyz";
    const numeric_alphabet = "0123456789";
    const hex_alphabet = "0123456789abcdef";

    pub fn init(allocator: std.mem.Allocator, opts: *const args_mod.Options) !FileNamer {
        var prefix_buf: std.ArrayList(u8) = .empty;
        try prefix_buf.appendSlice(allocator, opts.prefix);

        var indices: std.ArrayList(usize) = .empty;
        const len = @max(opts.suffix_len, 1);
        try indices.ensureTotalCapacity(allocator, len);

        const alphabet_len: usize = switch (opts.suffix_type) {
            .alpha => alpha_alphabet.len,
            .numeric => numeric_alphabet.len,
            .hex => hex_alphabet.len,
        };

        for (0..len) |_| {
            try indices.append(allocator, 0);
        }
        var val = opts.start_from;
        var i = len;
        while (i > 0) {
            i -= 1;
            indices.items[i] = val % alphabet_len;
            val /= alphabet_len;
        }

        return .{
            .prefix_buf = prefix_buf,
            .suffix_type = opts.suffix_type,
            .suffix_len = len,
            .auto_extend = opts.auto_extend,
            .additional_suffix = opts.additional_suffix,
            .indices = indices,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *FileNamer) void {
        self.prefix_buf.deinit(self.allocator);
        self.indices.deinit(self.allocator);
    }

    fn getAlphabet(self: *const FileNamer) []const u8 {
        return switch (self.suffix_type) {
            .alpha => alpha_alphabet,
            .numeric => numeric_alphabet,
            .hex => hex_alphabet,
        };
    }

    fn formatName(self: *const FileNamer, buf: *std.ArrayList(u8)) !void {
        buf.clearRetainingCapacity();
        try buf.appendSlice(self.allocator, self.prefix_buf.items);
        const alphabet = self.getAlphabet();
        for (self.indices.items) |idx| {
            try buf.append(self.allocator, alphabet[idx]);
        }
        try buf.appendSlice(self.allocator, self.additional_suffix);
    }

    pub fn next(self: *FileNamer, buf: *std.ArrayList(u8)) !void {
        if (self.exhausted) return error.SuffixesExhausted;
        if (self.first) {
            self.first = false;
            return self.formatName(buf);
        }

        const alphabet = self.getAlphabet();
        var i = self.indices.items.len;
        while (i > 0) {
            i -= 1;
            self.indices.items[i] += 1;
            if (self.auto_extend and i == 0 and self.indices.items[0] + 1 >= alphabet.len) {
                try self.prefix_buf.append(self.allocator, alphabet[self.indices.items[0]]);
                try self.indices.append(self.allocator, 0);
                for (self.indices.items) |*item| item.* = 0;
                return self.formatName(buf);
            }
            if (self.indices.items[i] < alphabet.len) {
                return self.formatName(buf);
            }
            self.indices.items[i] = 0;
        }

        self.exhausted = true;
        return error.SuffixesExhausted;
    }
};
