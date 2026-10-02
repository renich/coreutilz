const std = @import("std");

pub const OutField = struct {
    file: u8,
    field: usize,
};

pub const CheckOrder = enum {
    default,
    disabled,
    enabled,
};

pub const JoinOptions = struct {
    field1: usize = 1,
    field2: usize = 1,
    separator: ?[]const u8 = null,
    output_sep: []const u8 = " ",
    ignore_case: bool = false,
    print_unpairable1: bool = false,
    print_unpairable2: bool = false,
    suppress_paired: bool = false,
    zero_terminated: bool = false,
    header: bool = false,
    check_order: CheckOrder = .default,
    empty_filler: ?[]const u8 = null,
    autoformat: bool = false,
    outlist: ?[]const OutField = null,
    file1_name: []const u8 = "",
    file2_name: []const u8 = "",
};

pub fn splitFields(line: []const u8, sep: ?[]const u8, alloc: std.mem.Allocator) ![][]const u8 {
    var list: std.ArrayListUnmanaged([]const u8) = .empty;
    if (sep) |s| {
        if (s.len == 0) {
            try list.append(alloc, line);
        } else {
            var it = std.mem.splitSequence(u8, line, s);
            while (it.next()) |f| try list.append(alloc, f);
        }
    } else {
        var it = std.mem.tokenizeAny(u8, line, " \t\r\n");
        while (it.next()) |f| try list.append(alloc, f);
    }
    return list.toOwnedSlice(alloc);
}

pub fn getField(fields: [][]const u8, idx_1: usize) []const u8 {
    if (idx_1 == 0 or idx_1 > fields.len) return "";
    return fields[idx_1 - 1];
}

pub fn compareKey(k1: []const u8, k2: []const u8, ignore_case: bool) std.math.Order {
    if (ignore_case) {
        var i: usize = 0;
        while (i < k1.len and i < k2.len) : (i += 1) {
            const c1 = std.ascii.toLower(k1[i]);
            const c2 = std.ascii.toLower(k2[i]);
            if (c1 < c2) return .lt;
            if (c1 > c2) return .gt;
        }
        return std.math.order(k1.len, k2.len);
    }
    return std.mem.order(u8, k1, k2);
}

pub const OrderTracker = struct {
    issued_warning: [2]bool = .{ false, false },
    seen_unpairable: bool = false,

    pub fn checkOrder(
        self: *OrderTracker,
        prev_key: ?[]const u8,
        curr_key: []const u8,
        curr_line: []const u8,
        file_idx: usize,
        line_num: usize,
        opts: *const JoinOptions,
        stderr: anytype,
    ) !bool {
        if (opts.check_order == .disabled) return true;
        const prev = prev_key orelse return true;
        if (compareKey(prev, curr_key, opts.ignore_case) == .gt) {
            if (opts.check_order == .enabled or self.seen_unpairable) {
                const fname = if (file_idx == 0) opts.file1_name else opts.file2_name;
                try stderr.print("join: {s}:{d}: is not sorted: {s}\n", .{ fname, line_num, curr_line });
                if (opts.check_order == .enabled) return false;
                self.issued_warning[file_idx] = true;
            }
        }
        return true;
    }
};
