const std = @import("std");

fn isDigit(ch: u8) bool {
    return ch >= '0' and ch <= '9';
}

pub fn unitOrder(ch: u8) i32 {
    return switch (ch) {
        'k', 'K' => 1,
        'M' => 2,
        'G' => 3,
        'T' => 4,
        'P' => 5,
        'E' => 6,
        'Z' => 7,
        'Y' => 8,
        'R' => 9,
        'Q' => 10,
        else => 0,
    };
}

pub fn findUnitOrder(str: []const u8, dec: u8, sep: ?u8) i32 {
    var s = std.mem.trimStart(u8, str, " \t");
    if (s.len == 0) return 0;
    const minus = (s[0] == '-');
    if (minus) s = s[1..];
    var max_digit: u8 = 0;
    var i: usize = 0;
    while (i < s.len and (isDigit(s[i]) or (sep != null and s[i] == sep.?))) : (i += 1) {
        if (isDigit(s[i]) and s[i] > max_digit) max_digit = s[i];
    }
    if (i < s.len and s[i] == dec) {
        i += 1;
        while (i < s.len and (isDigit(s[i]) or (sep != null and s[i] == sep.?))) : (i += 1) {
            if (isDigit(s[i]) and s[i] > max_digit) max_digit = s[i];
        }
    }
    if (max_digit > '0' and i < s.len) {
        const order = unitOrder(s[i]);
        return if (minus) -order else order;
    }
    return 0;
}

pub fn fraccompare(a_in: []const u8, b_in: []const u8, decimal_point: u8) i32 {
    var a = a_in;
    var b = b_in;
    if (a.len > 0 and b.len > 0 and a[0] == decimal_point and b[0] == decimal_point) {
        a = a[1..];
        b = b[1..];
        while (a.len > 0 and b.len > 0 and a[0] == b[0]) {
            if (!isDigit(a[0])) return 0;
            a = a[1..];
            b = b[1..];
        }
        if (a.len > 0 and b.len > 0 and isDigit(a[0]) and isDigit(b[0])) {
            return @as(i32, a[0]) - @as(i32, b[0]);
        }
        if (a.len > 0 and isDigit(a[0])) {
            while (a.len > 0 and a[0] == '0') a = a[1..];
            return if (a.len > 0 and isDigit(a[0])) 1 else 0;
        }
        if (b.len > 0 and isDigit(b[0])) {
            while (b.len > 0 and b[0] == '0') b = b[1..];
            return if (b.len > 0 and isDigit(b[0])) -1 else 0;
        }
        return 0;
    } else if (a.len > 0 and a[0] == decimal_point) {
        a = a[1..];
        while (a.len > 0 and a[0] == '0') a = a[1..];
        return if (a.len > 0 and isDigit(a[0])) 1 else 0;
    } else if (b.len > 0 and b[0] == decimal_point) {
        b = b[1..];
        while (b.len > 0 and b[0] == '0') b = b[1..];
        return if (b.len > 0 and isDigit(b[0])) -1 else 0;
    }
    return 0;
}

fn skipZeros(s: []const u8, sep: ?u8) []const u8 {
    var cur = s;
    while (cur.len > 0 and (cur[0] == '0' or (sep != null and cur[0] == sep.?))) {
        cur = cur[1..];
    }
    return cur;
}

fn compareDigitsDiff(a_in: []const u8, b_in: []const u8, sep: ?u8) struct { diff: i32, a: []const u8, b: []const u8 } {
    var a = a_in;
    var b = b_in;
    while (a.len > 0 and b.len > 0 and a[0] == b[0] and isDigit(a[0])) {
        a = a[1..];
        while (sep != null and a.len > 0 and a[0] == sep.?) a = a[1..];
        b = b[1..];
        while (sep != null and b.len > 0 and b[0] == sep.?) b = b[1..];
    }
    return .{ .diff = 0, .a = a, .b = b };
}

fn countDigits(s_in: []const u8, sep: ?u8) struct { count: usize, rest: []const u8 } {
    var s = s_in;
    var cnt: usize = 0;
    while (s.len > 0 and isDigit(s[0])) {
        cnt += 1;
        s = s[1..];
        while (sep != null and s.len > 0 and s[0] == sep.?) s = s[1..];
    }
    return .{ .count = cnt, .rest = s };
}

fn comparePositive(a_in: []const u8, b_in: []const u8, dec: u8, sep: ?u8) i32 {
    const a0 = skipZeros(a_in, sep);
    const b0 = skipZeros(b_in, sep);
    const step = compareDigitsDiff(a0, b0, sep);
    const a = step.a;
    const b = step.b;
    const a_is_dec_b_not_dig = (a.len > 0 and a[0] == dec and (b.len == 0 or !isDigit(b[0])));
    const b_is_dec_a_not_dig = (b.len > 0 and b[0] == dec and (a.len == 0 or !isDigit(a[0])));
    if (a_is_dec_b_not_dig or b_is_dec_a_not_dig) {
        return fraccompare(a, b, dec);
    }
    const ca = if (a.len > 0) @as(i32, a[0]) else 0;
    const cb = if (b.len > 0) @as(i32, b[0]) else 0;
    const tmp = ca - cb;
    const res_a = countDigits(a, sep);
    const res_b = countDigits(b, sep);
    if (res_a.count != res_b.count) {
        return if (res_a.count < res_b.count) -1 else 1;
    }
    if (res_a.count == 0) return 0;
    return tmp;
}

pub fn numcompare(a_in: []const u8, b_in: []const u8, dec: u8, sep: ?u8) i32 {
    const a_trimmed = std.mem.trimStart(u8, a_in, " \t");
    const b_trimmed = std.mem.trimStart(u8, b_in, " \t");
    const a_neg = (a_trimmed.len > 0 and a_trimmed[0] == '-');
    const b_neg = (b_trimmed.len > 0 and b_trimmed[0] == '-');
    const a_body = if (a_neg) a_trimmed[1..] else a_trimmed;
    const b_body = if (b_neg) b_trimmed[1..] else b_trimmed;

    if (a_neg and !b_neg) {
        const a_val = skipZeros(a_body, sep);
        const a_has_digits = (a_val.len > 0 and (isDigit(a_val[0]) or (a_val[0] == dec and skipZeros(a_val[1..], sep).len > 0 and isDigit(skipZeros(a_val[1..], sep)[0]))));
        if (a_has_digits) return -1;
        const b_val = skipZeros(b_body, sep);
        const b_has_digits = (b_val.len > 0 and (isDigit(b_val[0]) or (b_val[0] == dec and skipZeros(b_val[1..], sep).len > 0 and isDigit(skipZeros(b_val[1..], sep)[0]))));
        return if (b_has_digits) -1 else 0;
    } else if (!a_neg and b_neg) {
        const b_val = skipZeros(b_body, sep);
        const b_has_digits = (b_val.len > 0 and (isDigit(b_val[0]) or (b_val[0] == dec and skipZeros(b_val[1..], sep).len > 0 and isDigit(skipZeros(b_val[1..], sep)[0]))));
        if (b_has_digits) return 1;
        const a_val = skipZeros(a_body, sep);
        const a_has_digits = (a_val.len > 0 and (isDigit(a_val[0]) or (a_val[0] == dec and skipZeros(a_val[1..], sep).len > 0 and isDigit(skipZeros(a_val[1..], sep)[0]))));
        return if (a_has_digits) 1 else 0;
    } else if (a_neg and b_neg) {
        return -comparePositive(a_body, b_body, dec, sep);
    } else {
        return comparePositive(a_body, b_body, dec, sep);
    }
}
