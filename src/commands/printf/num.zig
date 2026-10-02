const std = @import("std");
const c = @import("../../compat/c.zig").c;

fn mbCurMax() usize {
    return c.__ctype_get_mb_cur_max();
}

pub fn vstrtoimax(s: []const u8, ok_ptr: *bool, stderr: anytype, alloc: std.mem.Allocator) i64 {
    if (s.len >= 2 and (s[0] == '\'' or s[0] == '"')) {
        const char_part = s[1..];
        var wc: c.wchar_t = 0;
        var mbstate: c.mbstate_t = std.mem.zeroes(c.mbstate_t);
        var val: i64 = char_part[0];
        var consumed: usize = 1;
        if (mbCurMax() > 1 and char_part.len > 1) {
            const bytes = c.mbrtowc(&wc, char_part.ptr, char_part.len, &mbstate);
            if (@as(isize, @bitCast(bytes)) > 0) {
                val = @intCast(wc);
                consumed = bytes;
            }
        }
        if (1 + consumed < s.len and c.getenv("POSIXLY_CORRECT") == null) {
            stderr.print("printf: warning: {s}: character(s) following character constant have been ignored\n", .{s[1 + consumed ..]}) catch {};
        }
        return val;
    }
    const sz = alloc.dupeZ(u8, s) catch return 0;
    defer alloc.free(sz);
    var end: [*c]u8 = undefined;
    c.__errno_location().* = 0;
    const val = c.strtoimax(sz.ptr, &end, 0);
    if (c.__errno_location().* != 0) {
        stderr.print("printf: '{s}': Numerical result out of range\n", .{s}) catch {};
        ok_ptr.* = false;
    } else if (end.* != 0 and end != sz.ptr) {
        stderr.print("printf: '{s}': value not completely converted\n", .{s}) catch {};
        ok_ptr.* = false;
    } else if (end == sz.ptr) {
        stderr.print("printf: '{s}': expected a numeric value\n", .{s}) catch {};
        ok_ptr.* = false;
    }
    return val;
}

pub fn vstrtoumax(s: []const u8, ok_ptr: *bool, stderr: anytype, alloc: std.mem.Allocator) u64 {
    if (s.len >= 2 and (s[0] == '\'' or s[0] == '"')) {
        return @bitCast(vstrtoimax(s, ok_ptr, stderr, alloc));
    }
    const sz = alloc.dupeZ(u8, s) catch return 0;
    defer alloc.free(sz);
    var end: [*c]u8 = undefined;
    c.__errno_location().* = 0;
    const val = c.strtoumax(sz.ptr, &end, 0);
    if (c.__errno_location().* != 0) {
        stderr.print("printf: '{s}': Numerical result out of range\n", .{s}) catch {};
        ok_ptr.* = false;
    } else if (end.* != 0 and end != sz.ptr) {
        stderr.print("printf: '{s}': value not completely converted\n", .{s}) catch {};
        ok_ptr.* = false;
    } else if (end == sz.ptr) {
        stderr.print("printf: '{s}': expected a numeric value\n", .{s}) catch {};
        ok_ptr.* = false;
    }
    return val;
}

pub fn vstrtold(s: []const u8, ok_ptr: *bool, stderr: anytype, alloc: std.mem.Allocator) f128 {
    if (s.len >= 2 and (s[0] == '\'' or s[0] == '"')) {
        return @floatFromInt(vstrtoimax(s, ok_ptr, stderr, alloc));
    }
    const sz = alloc.dupeZ(u8, s) catch return 0;
    defer alloc.free(sz);
    var end: [*c]u8 = undefined;
    c.__errno_location().* = 0;
    const val = c.strtold(sz.ptr, &end);
    if (c.__errno_location().* != 0) {
        stderr.print("printf: '{s}': Numerical result out of range\n", .{s}) catch {};
        ok_ptr.* = false;
    } else if (end.* != 0 and end != sz.ptr) {
        stderr.print("printf: '{s}': value not completely converted\n", .{s}) catch {};
        ok_ptr.* = false;
    } else if (end == sz.ptr) {
        stderr.print("printf: '{s}': expected a numeric value\n", .{s}) catch {};
        ok_ptr.* = false;
    }
    return @floatCast(val);
}
