const std = @import("std");
const types = @import("types.zig");

pub const JoinOptions = types.JoinOptions;
pub const splitFields = types.splitFields;

fn prfield(idx_0: usize, fields: ?[][]const u8, empty_filler: ?[]const u8, stdout: anytype) !void {
    if (fields) |fl| {
        if (idx_0 < fl.len) {
            const val = fl[idx_0];
            if (val.len > 0) {
                try stdout.print("{s}", .{val});
            } else if (empty_filler) |ef| {
                try stdout.print("{s}", .{ef});
            }
            return;
        }
    }
    if (empty_filler) |ef| {
        try stdout.print("{s}", .{ef});
    }
}

fn prfields(fields: ?[][]const u8, join_field_0: usize, autocount: usize, opts: *const JoinOptions, stdout: anytype) !void {
    const nfields = if (opts.autoformat) autocount else if (fields) |fl| fl.len else 0;
    var i: usize = 0;
    while (i < nfields) : (i += 1) {
        if (i == join_field_0) continue;
        try stdout.print("{s}", .{opts.output_sep});
        try prfield(i, fields, opts.empty_filler, stdout);
    }
}

pub fn outputLine(
    f1: ?[][]const u8,
    f2: ?[][]const u8,
    opts: *const JoinOptions,
    auto1: usize,
    auto2: usize,
    out_delim: u8,
    stdout: anytype,
) !void {
    if (opts.outlist) |olist| {
        for (olist, 0..) |o, idx| {
            if (idx > 0) try stdout.print("{s}", .{opts.output_sep});
            if (o.file == 0) {
                const jfield = if (f1 != null) opts.field1 - 1 else opts.field2 - 1;
                const fl = if (f1 != null) f1 else f2;
                try prfield(jfield, fl, opts.empty_filler, stdout);
            } else {
                const fl = if (o.file == 1) f1 else f2;
                try prfield(o.field - 1, fl, opts.empty_filler, stdout);
            }
        }
    } else {
        const jfield = if (f1 != null) opts.field1 - 1 else opts.field2 - 1;
        const fl = if (f1 != null) f1 else f2;
        try prfield(jfield, fl, opts.empty_filler, stdout);
        try prfields(f1, opts.field1 - 1, auto1, opts, stdout);
        try prfields(f2, opts.field2 - 1, auto2, opts, stdout);
    }
    try stdout.writeByte(out_delim);
}

pub fn handleHeader(
    l1: [][]const u8,
    l2: [][]const u8,
    opts: *const JoinOptions,
    a1: usize,
    a2: usize,
    delim: u8,
    alloc: std.mem.Allocator,
    stdout: anytype,
) !struct { idx1: usize, idx2: usize } {
    if (!opts.header or (l1.len == 0 and l2.len == 0)) return .{ .idx1 = 0, .idx2 = 0 };
    const h1 = if (l1.len > 0) try splitFields(l1[0], opts.separator, alloc) else null;
    defer if (h1) |f| alloc.free(f);
    const h2 = if (l2.len > 0) try splitFields(l2[0], opts.separator, alloc) else null;
    defer if (h2) |f| alloc.free(f);
    try outputLine(h1, h2, opts, a1, a2, delim, stdout);
    return .{ .idx1 = if (l1.len > 0) 1 else 0, .idx2 = if (l2.len > 0) 1 else 0 };
}

pub fn joinCartesian(
    l1_s: [][]const u8,
    l2_s: [][]const u8,
    opts: *const JoinOptions,
    a1: usize,
    a2: usize,
    delim: u8,
    alloc: std.mem.Allocator,
    stdout: anytype,
) !void {
    for (l1_s) |l1| {
        const f1 = try splitFields(l1, opts.separator, alloc);
        defer alloc.free(f1);
        for (l2_s) |l2| {
            const f2 = try splitFields(l2, opts.separator, alloc);
            defer alloc.free(f2);
            if (!opts.suppress_paired) try outputLine(f1, f2, opts, a1, a2, delim, stdout);
        }
    }
}
