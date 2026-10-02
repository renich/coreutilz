const std = @import("std");
const types = @import("types.zig");
const format = @import("format.zig");

pub const OutField = types.OutField;
pub const CheckOrder = types.CheckOrder;
pub const JoinOptions = types.JoinOptions;
pub const OrderTracker = types.OrderTracker;
pub const splitFields = types.splitFields;
pub const getField = types.getField;
pub const compareKey = types.compareKey;
pub const outputLine = format.outputLine;
pub const handleHeader = format.handleHeader;
pub const joinCartesian = format.joinCartesian;

pub fn findSpan(
    lines: [][]const u8,
    start: usize,
    field: usize,
    key: []const u8,
    file_idx: usize,
    trk: *OrderTracker,
    opts: *const JoinOptions,
    alloc: std.mem.Allocator,
    stderr: anytype,
) !?usize {
    var end = start;
    while (end < lines.len) : (end += 1) {
        const fields = try splitFields(lines[end], opts.separator, alloc);
        defer alloc.free(fields);
        const k = getField(fields, field);
        if (compareKey(key, k, opts.ignore_case) == .gt) {
            if (!try trk.checkOrder(key, k, lines[end], file_idx, end + 1, opts, stderr)) return null;
        }
        if (compareKey(k, key, opts.ignore_case) != .eq) break;
    }
    return end;
}

pub fn drain1(
    l1: [][]const u8,
    start: usize,
    prev: ?[]const u8,
    has_other: bool,
    opts: *const JoinOptions,
    a1: usize,
    a2: usize,
    delim: u8,
    trk: *OrderTracker,
    alloc: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) !bool {
    if (has_other) trk.seen_unpairable = true;
    var prev_k = prev;
    var i = start;
    while (i < l1.len) : (i += 1) {
        const f1 = try splitFields(l1[i], opts.separator, alloc);
        defer alloc.free(f1);
        const k1 = getField(f1, opts.field1);
        if (!try trk.checkOrder(prev_k, k1, l1[i], 0, i + 1, opts, stderr)) return false;
        prev_k = k1;
        if (opts.print_unpairable1) try outputLine(f1, null, opts, a1, a2, delim, stdout);
        if (has_other) trk.seen_unpairable = true;
    }
    return true;
}

pub fn drain2(
    l2: [][]const u8,
    start: usize,
    prev: ?[]const u8,
    has_other: bool,
    opts: *const JoinOptions,
    a1: usize,
    a2: usize,
    delim: u8,
    trk: *OrderTracker,
    alloc: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) !bool {
    if (has_other) trk.seen_unpairable = true;
    var prev_k = prev;
    var i = start;
    while (i < l2.len) : (i += 1) {
        const f2 = try splitFields(l2[i], opts.separator, alloc);
        defer alloc.free(f2);
        const k2 = getField(f2, opts.field2);
        if (!try trk.checkOrder(prev_k, k2, l2[i], 1, i + 1, opts, stderr)) return false;
        prev_k = k2;
        if (opts.print_unpairable2) try outputLine(null, f2, opts, a1, a2, delim, stdout);
        if (has_other) trk.seen_unpairable = true;
    }
    return true;
}

fn getAutoCounts(l1: [][]const u8, l2: [][]const u8, sep: ?[]const u8, alloc: std.mem.Allocator) !struct { a1: usize, a2: usize } {
    var a1: usize = 0;
    var a2: usize = 0;
    if (l1.len > 0) {
        const f = try splitFields(l1[0], sep, alloc);
        a1 = f.len;
        alloc.free(f);
    }
    if (l2.len > 0) {
        const f = try splitFields(l2[0], sep, alloc);
        a2 = f.len;
        alloc.free(f);
    }
    return .{ .a1 = a1, .a2 = a2 };
}

fn handleMatch(
    l1: [][]const u8,
    l2: [][]const u8,
    idx1: *usize,
    idx2: *usize,
    k1: []const u8,
    k2: []const u8,
    trk: *OrderTracker,
    opts: *const JoinOptions,
    a1: usize,
    a2: usize,
    delim: u8,
    alloc: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) !bool {
    const end1 = (try findSpan(l1, idx1.*, opts.field1, k1, 0, trk, opts, alloc, stderr)) orelse return false;
    const end2 = (try findSpan(l2, idx2.*, opts.field2, k2, 1, trk, opts, alloc, stderr)) orelse return false;
    try joinCartesian(l1[idx1.*..end1], l2[idx2.*..end2], opts, a1, a2, delim, alloc, stdout);
    idx1.* = end1;
    idx2.* = end2;
    return true;
}

fn advance1(
    l1: [][]const u8,
    idx1: *usize,
    f1: [][]const u8,
    prev_k1: *?[]const u8,
    trk: *OrderTracker,
    opts: *const JoinOptions,
    a1: usize,
    a2: usize,
    delim: u8,
    alloc: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) !bool {
    if (opts.print_unpairable1) try outputLine(f1, null, opts, a1, a2, delim, stdout);
    const k1 = getField(f1, opts.field1);
    prev_k1.* = k1;
    idx1.* += 1;
    if (idx1.* < l1.len) {
        const nf1 = try splitFields(l1[idx1.*], opts.separator, alloc);
        defer alloc.free(nf1);
        const nk1 = getField(nf1, opts.field1);
        if (!try trk.checkOrder(prev_k1.*, nk1, l1[idx1.*], 0, idx1.* + 1, opts, stderr)) return false;
    }
    trk.seen_unpairable = true;
    return true;
}

fn advance2(
    l2: [][]const u8,
    idx2: *usize,
    f2: [][]const u8,
    prev_k2: *?[]const u8,
    trk: *OrderTracker,
    opts: *const JoinOptions,
    a1: usize,
    a2: usize,
    delim: u8,
    alloc: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) !bool {
    if (opts.print_unpairable2) try outputLine(null, f2, opts, a1, a2, delim, stdout);
    const k2 = getField(f2, opts.field2);
    prev_k2.* = k2;
    idx2.* += 1;
    if (idx2.* < l2.len) {
        const nf2 = try splitFields(l2[idx2.*], opts.separator, alloc);
        defer alloc.free(nf2);
        const nk2 = getField(nf2, opts.field2);
        if (!try trk.checkOrder(prev_k2.*, nk2, l2[idx2.*], 1, idx2.* + 1, opts, stderr)) return false;
    }
    trk.seen_unpairable = true;
    return true;
}

pub fn executeJoin(
    lines1: [][]const u8,
    lines2: [][]const u8,
    opts: *const JoinOptions,
    alloc: std.mem.Allocator,
    stdout: anytype,
    stderr: anytype,
) !u8 {
    const delim: u8 = if (opts.zero_terminated) 0 else '\n';
    const counts = try getAutoCounts(lines1, lines2, opts.separator, alloc);
    var trk = OrderTracker{};
    const init_idx = try handleHeader(lines1, lines2, opts, counts.a1, counts.a2, delim, alloc, stdout);
    var idx1 = init_idx.idx1;
    var idx2 = init_idx.idx2;
    var prev_k1: ?[]const u8 = null;
    var prev_k2: ?[]const u8 = null;

    while (idx1 < lines1.len and idx2 < lines2.len) {
        const f1 = try splitFields(lines1[idx1], opts.separator, alloc);
        defer alloc.free(f1);
        const f2 = try splitFields(lines2[idx2], opts.separator, alloc);
        defer alloc.free(f2);
        const k1 = getField(f1, opts.field1);
        const k2 = getField(f2, opts.field2);

        const ord = compareKey(k1, k2, opts.ignore_case);
        if (ord == .eq) {
            if (!try handleMatch(lines1, lines2, &idx1, &idx2, k1, k2, &trk, opts, counts.a1, counts.a2, delim, alloc, stdout, stderr)) return 1;
            prev_k1 = k1;
            prev_k2 = k2;
        } else if (ord == .lt) {
            if (!try advance1(lines1, &idx1, f1, &prev_k1, &trk, opts, counts.a1, counts.a2, delim, alloc, stdout, stderr)) return 1;
        } else {
            if (!try advance2(lines2, &idx2, f2, &prev_k2, &trk, opts, counts.a1, counts.a2, delim, alloc, stdout, stderr)) return 1;
        }
    }

    const has_other1 = lines2.len > 0;
    const has_other2 = lines1.len > 0;
    if (!try drain1(lines1, idx1, prev_k1, has_other1, opts, counts.a1, counts.a2, delim, &trk, alloc, stdout, stderr)) return 1;
    if (!try drain2(lines2, idx2, prev_k2, has_other2, opts, counts.a1, counts.a2, delim, &trk, alloc, stdout, stderr)) return 1;
    if (trk.issued_warning[0] or trk.issued_warning[1]) {
        try stderr.print("join: input is not in sorted order\n", .{});
        return 1;
    }
    return 0;
}
