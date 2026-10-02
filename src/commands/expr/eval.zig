const std = @import("std");
const c = @import("../../compat/c.zig").c;

pub const Val = struct {
    str: []const u8,

    pub fn isZeroOrNull(s: []const u8) bool {
        if (s.len == 0 or std.mem.eql(u8, s, "0") or std.mem.eql(u8, s, "-0")) return true;
        var i: usize = 0;
        if (s[i] == '-' or s[i] == '+') i += 1;
        while (i < s.len and s[i] == '0') : (i += 1) {}
        return i == s.len;
    }
};

const RePatternBuffer = extern struct {
    __buffer: ?*anyopaque = null,
    __allocated: usize = 0,
    __used: usize = 0,
    __syntax: c_ulong = 0,
    __fastmap: ?[*]u8 = null,
    __translate: ?[*]u8 = null,
    re_nsub: usize = 0,
    __can_be_null: c_uint = 0,
    __regs_allocated: c_uint = 0,
    __fastmap_accurate: c_uint = 0,
    __no_sub: c_uint = 0,
    __not_bol: c_uint = 0,
    __not_eol: c_uint = 0,
    __newline_anchor: c_uint = 0,
};

const ReRegisters = extern struct {
    num_regs: c_uint = 0,
    __pad: u32 = 0,
    start: ?[*]c_int = null,
    end: ?[*]c_int = null,
};

extern "c" var re_syntax_options: c_ulong;
extern "c" fn re_compile_pattern(pattern: [*]const u8, length: usize, buffer: *RePatternBuffer) ?[*:0]const u8;
extern "c" fn re_match(buffer: *RePatternBuffer, string: [*]const u8, length: usize, start: c_int, regs: *ReRegisters) c_int;
extern "c" fn regfree(buffer: *RePatternBuffer) void;

pub fn cleanIntStr(s: []const u8) []const u8 {
    if (s.len > 1 and s[0] == '+') return s[1..];
    return s;
}

pub fn isIntegerStr(s: []const u8) bool {
    if (s.len == 0) return false;
    var idx: usize = 0;
    if (s[0] == '-' or s[0] == '+') idx += 1;
    if (idx >= s.len) return false;
    for (s[idx..]) |ch| {
        if (ch < '0' or ch > '9') return false;
    }
    return true;
}

pub fn toBigInt(s: []const u8, alloc: std.mem.Allocator) !std.math.big.int.Managed {
    if (!isIntegerStr(s)) return error.InvalidCharacter;
    var bi = try std.math.big.int.Managed.init(alloc);
    errdefer bi.deinit();
    const clean = cleanIntStr(s);
    try bi.setString(10, clean);
    return bi;
}

fn divOrMod(op: []const u8, res: *std.math.big.int.Managed, a: *const std.math.big.int.Managed, b: *const std.math.big.int.Managed, alloc: std.mem.Allocator, stderr: anytype) !void {
    if (b.eqlZero()) {
        stderr.print("expr: division by zero\n", .{}) catch {};
        return error.Handled;
    }
    if (std.mem.eql(u8, op, "/")) {
        var rem = try std.math.big.int.Managed.init(alloc);
        defer rem.deinit();
        try res.divTrunc(&rem, a, b);
    } else {
        var quot = try std.math.big.int.Managed.init(alloc);
        defer quot.deinit();
        try quot.divTrunc(res, a, b);
    }
}

pub fn evalArith(op: []const u8, l: []const u8, r: []const u8, alloc: std.mem.Allocator, stderr: anytype) anyerror!Val {
    var a = toBigInt(l, alloc) catch {
        stderr.print("expr: non-integer argument\n", .{}) catch {};
        return error.Handled;
    };
    defer a.deinit();
    var b = toBigInt(r, alloc) catch {
        stderr.print("expr: non-integer argument\n", .{}) catch {};
        return error.Handled;
    };
    defer b.deinit();

    var res = try std.math.big.int.Managed.init(alloc);
    defer res.deinit();

    if (std.mem.eql(u8, op, "+")) {
        try res.add(&a, &b);
    } else if (std.mem.eql(u8, op, "-")) {
        try res.sub(&a, &b);
    } else if (std.mem.eql(u8, op, "*")) {
        try res.mul(&a, &b);
    } else if (std.mem.eql(u8, op, "/") or std.mem.eql(u8, op, "%")) {
        try divOrMod(op, &res, &a, &b, alloc, stderr);
    } else return error.SyntaxError;

    const str = try res.toString(alloc, 10, .lower);
    return Val{ .str = str };
}

pub fn evalRel(op: []const u8, l: []const u8, r: []const u8, alloc: std.mem.Allocator) !Val {
    var is_num = false;
    var ord: std.math.Order = undefined;
    if (toBigInt(l, alloc)) |a_in| {
        var a = a_in;
        defer a.deinit();
        if (toBigInt(r, alloc)) |b_in| {
            var b = b_in;
            defer b.deinit();
            ord = a.order(b);
            is_num = true;
        } else |_| {}
    } else |_| {}

    if (!is_num) {
        ord = std.mem.order(u8, l, r);
    }

    var cond = false;
    if (std.mem.eql(u8, op, "=") or std.mem.eql(u8, op, "==")) cond = ord == .eq;
    if (std.mem.eql(u8, op, "!=")) cond = ord != .eq;
    if (std.mem.eql(u8, op, "<")) cond = ord == .lt;
    if (std.mem.eql(u8, op, "<=")) cond = ord == .lt or ord == .eq;
    if (std.mem.eql(u8, op, ">")) cond = ord == .gt;
    if (std.mem.eql(u8, op, ">=")) cond = ord == .gt or ord == .eq;

    return Val{ .str = if (cond) "1" else "0" };
}

pub fn matchRegex(target: []const u8, pattern: []const u8, alloc: std.mem.Allocator, stderr: anytype) anyerror!Val {
    re_syntax_options = 0x2c6;
    var re_buffer: RePatternBuffer = .{};
    if (re_compile_pattern(pattern.ptr, pattern.len, &re_buffer)) |errmsg| {
        stderr.print("expr: {s}\n", .{std.mem.span(errmsg)}) catch {};
        return error.Handled;
    }
    defer regfree(&re_buffer);

    // re_buffer.newline_anchor = 0;
    const buf_bytes: [*]u8 = @ptrCast(&re_buffer);
    buf_bytes[56] &= ~@as(u8, 0x80);

    var re_regs: ReRegisters = .{};
    defer {
        if (re_regs.start) |s| c.free(s);
        if (re_regs.end) |e| c.free(e);
    }

    const matchlen = re_match(&re_buffer, target.ptr, target.len, 0, &re_regs);
    if (matchlen >= 0) {
        if (re_buffer.re_nsub > 0) {
            if (re_regs.end != null and re_regs.end.?[1] < 0) {
                return Val{ .str = "" };
            }
            if (re_regs.start != null and re_regs.end != null and re_regs.start.?[1] >= 0) {
                const s: usize = @intCast(re_regs.start.?[1]);
                const e: usize = @intCast(re_regs.end.?[1]);
                return Val{ .str = target[s..e] };
            }
            return Val{ .str = "" };
        }
        return Val{ .str = try std.fmt.allocPrint(alloc, "{d}", .{matchlen}) };
    }
    return Val{ .str = if (re_buffer.re_nsub > 0) "" else "0" };
}
