const std = @import("std");
const c = @import("../../compat/c.zig").c;
const num = @import("num.zig");

fn formatInt(p: [:0]const u8, conv: u8, have_w: bool, w: c_int, have_p: bool, pr: c_int, arg: ?[]const u8, ok: *bool, err: anytype, alloc: std.mem.Allocator, out: []u8) c_int {
    if (conv == 'd' or conv == 'i') {
        const val = if (arg) |a| num.vstrtoimax(a, ok, err, alloc) else 0;
        return if (!have_w)
            (if (!have_p) c.snprintf(out.ptr, out.len, p.ptr, val) else c.snprintf(out.ptr, out.len, p.ptr, pr, val))
        else
            (if (!have_p) c.snprintf(out.ptr, out.len, p.ptr, w, val) else c.snprintf(out.ptr, out.len, p.ptr, w, pr, val));
    }
    const val = if (arg) |a| num.vstrtoumax(a, ok, err, alloc) else 0;
    return if (!have_w)
        (if (!have_p) c.snprintf(out.ptr, out.len, p.ptr, val) else c.snprintf(out.ptr, out.len, p.ptr, pr, val))
    else
        (if (!have_p) c.snprintf(out.ptr, out.len, p.ptr, w, val) else c.snprintf(out.ptr, out.len, p.ptr, w, pr, val));
}

fn formatFloat(p: [:0]const u8, have_w: bool, w: c_int, have_p: bool, pr: c_int, arg: ?[]const u8, ok: *bool, err: anytype, alloc: std.mem.Allocator, out: []u8) c_int {
    const val: c_longdouble = if (arg) |a| @floatCast(num.vstrtold(a, ok, err, alloc)) else 0;
    return if (!have_w)
        (if (!have_p) c.snprintf(out.ptr, out.len, p.ptr, val) else c.snprintf(out.ptr, out.len, p.ptr, pr, val))
    else
        (if (!have_p) c.snprintf(out.ptr, out.len, p.ptr, w, val) else c.snprintf(out.ptr, out.len, p.ptr, w, pr, val));
}

fn formatStrOrChar(p: [:0]const u8, conv: u8, have_w: bool, w: c_int, have_p: bool, pr: c_int, arg: ?[]const u8, alloc: std.mem.Allocator, out: []u8) c_int {
    if (conv == 'c') {
        const ch: c_int = if (arg) |a| (if (a.len > 0) a[0] else 0) else 0;
        return if (!have_w) c.snprintf(out.ptr, out.len, p.ptr, ch) else c.snprintf(out.ptr, out.len, p.ptr, w, ch);
    }
    const s_val = arg orelse "";
    const sz = alloc.dupeZ(u8, s_val) catch return 0;
    defer alloc.free(sz);
    return if (!have_w)
        (if (!have_p) c.snprintf(out.ptr, out.len, p.ptr, sz.ptr) else c.snprintf(out.ptr, out.len, p.ptr, pr, sz.ptr))
    else
        (if (!have_p) c.snprintf(out.ptr, out.len, p.ptr, w, sz.ptr) else c.snprintf(out.ptr, out.len, p.ptr, w, pr, sz.ptr));
}

pub fn executeCFormat(
    p: [:0]const u8,
    conversion: u8,
    have_width: bool,
    width: c_int,
    have_prec: bool,
    prec: c_int,
    raw_arg: ?[]const u8,
    ok_ptr: *bool,
    stdout: anytype,
    stderr: anytype,
    alloc: std.mem.Allocator,
) !void {
    var out: [4096]u8 = undefined;
    var n: c_int = 0;
    switch (conversion) {
        'd', 'i', 'o', 'u', 'x', 'X' => {
            n = formatInt(p, conversion, have_width, width, have_prec, prec, raw_arg, ok_ptr, stderr, alloc, &out);
        },
        'a', 'A', 'e', 'E', 'f', 'F', 'g', 'G' => {
            n = formatFloat(p, have_width, width, have_prec, prec, raw_arg, ok_ptr, stderr, alloc, &out);
        },
        'c', 's' => {
            n = formatStrOrChar(p, conversion, have_width, width, have_prec, prec, raw_arg, alloc, &out);
        },
        else => {},
    }
    if (n > 0) try stdout.writeAll(out[0..@min(out.len, @as(usize, @intCast(n)))]);
}

pub fn printDirec(
    pdirec: []const u8,
    conversion: u8,
    have_width: bool,
    width: c_int,
    have_prec: bool,
    prec: c_int,
    raw_arg: ?[]const u8,
    ok_ptr: *bool,
    stdout: anytype,
    stderr: anytype,
    alloc: std.mem.Allocator,
) !void {
    var p_buf: [136:0]u8 = undefined;
    var q: usize = 0;
    for (pdirec) |b| {
        p_buf[q] = b;
        q += 1;
    }
    switch (conversion) {
        'd', 'i', 'o', 'u', 'x', 'X' => {
            p_buf[q] = 'j';
            q += 1;
        },
        'a', 'A', 'e', 'E', 'f', 'F', 'g', 'G' => {
            p_buf[q] = 'L';
            q += 1;
        },
        else => {},
    }
    p_buf[q] = conversion;
    q += 1;
    p_buf[q] = 0;
    try executeCFormat(p_buf[0..q :0], conversion, have_width, width, have_prec, prec, raw_arg, ok_ptr, stdout, stderr, alloc);
}
