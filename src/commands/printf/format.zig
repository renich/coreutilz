const std = @import("std");
const esc = @import("esc.zig");
const num = @import("num.zig");
const c_format = @import("c_format.zig");

pub const ArgCursor = struct {
    f_idx: usize,
    curr_arg: isize = -1,
    curr_s_arg: isize = -1,
    end_arg: isize = -1,
    direc_arg: isize = -1,
};

pub fn getCurrArg(pos: u8, ac: *ArgCursor, fmt: []const u8) void {
    var arg: isize = 0;
    var f = ac.f_idx;
    if (pos < 3 and f < fmt.len and std.ascii.isDigit(fmt[f])) {
        var a: isize = @intCast(fmt[f] - '0');
        f += 1;
        var overflow = false;
        while (f < fmt.len and std.ascii.isDigit(fmt[f])) : (f += 1) {
            const digit: isize = @intCast(fmt[f] - '0');
            const mul = @mulWithOverflow(a, 10);
            if (mul[1] != 0) overflow = true else {
                const add = @addWithOverflow(mul[0], digit);
                if (add[1] != 0) overflow = true else a = add[0];
            }
        }
        if (f < fmt.len and fmt[f] == '$') {
            arg = if (overflow) std.math.maxInt(c_int) else a;
            f += 1;
            ac.f_idx = f;
        }
    }
    if (arg > 0) {
        arg -= 1;
        if (pos == 0) ac.direc_arg = arg;
    } else {
        arg = if (pos == 0) blk: {
            ac.direc_arg = -1;
            break :blk -1;
        } else if (pos < 3 or ac.direc_arg < 0) blk: {
            ac.curr_s_arg += 1;
            break :blk ac.curr_s_arg;
        } else ac.direc_arg;
    }
    if (arg >= 0) {
        ac.curr_arg = arg;
        ac.end_arg = @max(ac.end_arg, arg);
    }
}

fn parseFlags(fmt: []const u8, ac: *ArgCursor, pdirec: *[128]u8, plen: *usize, ok: *[256]bool) void {
    while (ac.f_idx < fmt.len) : (ac.f_idx += 1) {
        const ch = fmt[ac.f_idx];
        switch (ch) {
            'I', '\'' => {
                ok['a'] = false;
                ok['A'] = false;
                ok['c'] = false;
                ok['e'] = false;
                ok['E'] = false;
                ok['o'] = false;
                ok['s'] = false;
                ok['x'] = false;
                ok['X'] = false;
            },
            '-', '+', ' ' => {},
            '#' => {
                ok['c'] = false;
                ok['d'] = false;
                ok['i'] = false;
                ok['s'] = false;
                ok['u'] = false;
            },
            '0' => {
                ok['c'] = false;
                ok['s'] = false;
            },
            else => break,
        }
        if (plen.* < pdirec.len - 4) {
            pdirec[plen.*] = ch;
            plen.* += 1;
        }
    }
}

fn parseWidth(fmt: []const u8, ac: *ArgCursor, pdirec: *[128]u8, plen: *usize, args: [][]const u8, ok_ptr: *bool, stderr: anytype, alloc: std.mem.Allocator) !struct { bool, c_int } {
    if (ac.f_idx < fmt.len and fmt[ac.f_idx] == '*') {
        if (plen.* < pdirec.len - 4) {
            pdirec[plen.*] = '*';
            plen.* += 1;
        }
        ac.f_idx += 1;
        getCurrArg(1, ac, fmt);
        var width: c_int = 0;
        if (ac.curr_arg >= 0 and ac.curr_arg < args.len) {
            const arg_str = args[@intCast(ac.curr_arg)];
            const w = num.vstrtoimax(arg_str, ok_ptr, stderr, alloc);
            if (w < std.math.minInt(c_int) or w > std.math.maxInt(c_int)) {
                stderr.print("printf: invalid field width: '{s}'\n", .{arg_str}) catch {};
                ok_ptr.* = false;
                return error.InvalidWidth;
            }
            width = @intCast(w);
        }
        return .{ true, width };
    }
    while (ac.f_idx < fmt.len and std.ascii.isDigit(fmt[ac.f_idx])) : (ac.f_idx += 1) {
        if (plen.* < pdirec.len - 4) {
            pdirec[plen.*] = fmt[ac.f_idx];
            plen.* += 1;
        }
    }
    return .{ false, 0 };
}

fn parsePrec(fmt: []const u8, ac: *ArgCursor, pdirec: *[128]u8, plen: *usize, ok: *[256]bool, args: [][]const u8, ok_ptr: *bool, stderr: anytype, alloc: std.mem.Allocator) !struct { bool, c_int } {
    if (ac.f_idx < fmt.len and fmt[ac.f_idx] == '.') {
        if (plen.* < pdirec.len - 4) {
            pdirec[plen.*] = '.';
            plen.* += 1;
        }
        ac.f_idx += 1;
        ok['c'] = false;
        if (ac.f_idx < fmt.len and fmt[ac.f_idx] == '*') {
            if (plen.* < pdirec.len - 4) {
                pdirec[plen.*] = '*';
                plen.* += 1;
            }
            ac.f_idx += 1;
            getCurrArg(2, ac, fmt);
            var precision: c_int = 0;
            if (ac.curr_arg >= 0 and ac.curr_arg < args.len) {
                const arg_str = args[@intCast(ac.curr_arg)];
                const p = num.vstrtoimax(arg_str, ok_ptr, stderr, alloc);
                if (p < 0) {
                    precision = -1;
                } else if (p > std.math.maxInt(c_int)) {
                    stderr.print("printf: invalid precision: '{s}'\n", .{arg_str}) catch {};
                    ok_ptr.* = false;
                    return error.InvalidPrecision;
                } else {
                    precision = @intCast(p);
                }
            }
            return .{ true, precision };
        }
        while (ac.f_idx < fmt.len and std.ascii.isDigit(fmt[ac.f_idx])) : (ac.f_idx += 1) {
            if (plen.* < pdirec.len - 4) {
                pdirec[plen.*] = fmt[ac.f_idx];
                plen.* += 1;
            }
        }
    }
    return .{ false, 0 };
}

fn handleGeneralDirective(
    fmt: []const u8,
    direc_start: usize,
    ac: *ArgCursor,
    args: [][]const u8,
    ok_ptr: *bool,
    stdout: anytype,
    stderr: anytype,
    alloc: std.mem.Allocator,
) !void {
    var ok = [_]bool{false} ** 256;
    ok['a'] = true;
    ok['A'] = true;
    ok['c'] = true;
    ok['d'] = true;
    ok['e'] = true;
    ok['E'] = true;
    ok['f'] = true;
    ok['F'] = true;
    ok['g'] = true;
    ok['G'] = true;
    ok['i'] = true;
    ok['o'] = true;
    ok['s'] = true;
    ok['u'] = true;
    ok['x'] = true;
    ok['X'] = true;
    var pdirec: [128]u8 = undefined;
    var plen: usize = 1;
    pdirec[0] = '%';
    parseFlags(fmt, ac, &pdirec, &plen, &ok);
    const w_res = try parseWidth(fmt, ac, &pdirec, &plen, args, ok_ptr, stderr, alloc);
    const p_res = try parsePrec(fmt, ac, &pdirec, &plen, &ok, args, ok_ptr, stderr, alloc);
    while (ac.f_idx < fmt.len and (fmt[ac.f_idx] == 'l' or fmt[ac.f_idx] == 'L' or fmt[ac.f_idx] == 'h' or fmt[ac.f_idx] == 'j' or fmt[ac.f_idx] == 't' or fmt[ac.f_idx] == 'z')) : (ac.f_idx += 1) {}
    if (ac.f_idx >= fmt.len or !ok[fmt[ac.f_idx]]) {
        const speclen = if (ac.f_idx < fmt.len) ac.f_idx + 1 - direc_start else fmt.len - direc_start;
        stderr.print("printf: {s}: invalid conversion specification\n", .{fmt[direc_start .. direc_start + speclen]}) catch {};
        ok_ptr.* = false;
        return error.InvalidConversion;
    }
    const conv = fmt[ac.f_idx];
    ac.f_idx += 1;
    getCurrArg(3, ac, fmt);
    const raw_arg = if (ac.curr_arg >= 0 and ac.curr_arg < args.len) args[@intCast(ac.curr_arg)] else null;
    try c_format.printDirec(pdirec[0..plen], conv, w_res[0], w_res[1], p_res[0], p_res[1], raw_arg, ok_ptr, stdout, stderr, alloc);
}

fn handlePercent(
    fmt: []const u8,
    ac: *ArgCursor,
    args: [][]const u8,
    ok_ptr: *bool,
    stdout: anytype,
    stderr: anytype,
    alloc: std.mem.Allocator,
) !bool {
    const direc_start = ac.f_idx;
    ac.f_idx += 1;
    if (ac.f_idx < fmt.len and fmt[ac.f_idx] == '%') {
        try stdout.writeByte('%');
        ac.f_idx += 1;
        return true;
    }
    getCurrArg(0, ac, fmt);
    if (ac.f_idx < fmt.len and fmt[ac.f_idx] == 'b') {
        ac.f_idx += 1;
        getCurrArg(3, ac, fmt);
        if (ac.curr_arg >= 0 and ac.curr_arg < args.len) {
            return esc.printEscString(args[@intCast(ac.curr_arg)], stdout, stderr);
        }
        return true;
    }
    if (ac.f_idx < fmt.len and fmt[ac.f_idx] == 'q') {
        ac.f_idx += 1;
        getCurrArg(3, ac, fmt);
        if (ac.curr_arg >= 0 and ac.curr_arg < args.len) {
            try esc.printShellEscape(args[@intCast(ac.curr_arg)], stdout);
        }
        return true;
    }
    try handleGeneralDirective(fmt, direc_start, ac, args, ok_ptr, stdout, stderr, alloc);
    return true;
}

pub fn printFormatted(
    fmt: []const u8,
    args: [][]const u8,
    ac: *ArgCursor,
    ok_ptr: *bool,
    stdout: anytype,
    stderr: anytype,
    alloc: std.mem.Allocator,
) !bool {
    while (ac.f_idx < fmt.len) {
        const ch = fmt[ac.f_idx];
        if (ch == '%') {
            if (!try handlePercent(fmt, ac, args, ok_ptr, stdout, stderr, alloc)) return false;
        } else if (ch == '\\') {
            const res = esc.printEsc(fmt[ac.f_idx..], false, stdout, stderr) catch {
                ok_ptr.* = false;
                return false;
            };
            if (!res[1]) return false;
            ac.f_idx += 1 + res[0];
        } else {
            try stdout.writeByte(ch);
            ac.f_idx += 1;
        }
    }
    return true;
}
