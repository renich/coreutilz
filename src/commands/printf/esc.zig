const std = @import("std");
const c = @import("../../compat/c.zig").c;

fn printUnicodeChar(val: u32, esc_char: u8, stdout: anytype, stderr: anytype) !void {
    if (val >= 0xd800 and val <= 0xdfff) {
        const width: usize = if (esc_char == 'u') 4 else 8;
        if (width == 4) {
            stderr.print("printf: invalid universal character name \\{c}{x:0>4}\n", .{ esc_char, val }) catch {};
        } else {
            stderr.print("printf: invalid universal character name \\{c}{x:0>8}\n", .{ esc_char, val }) catch {};
        }
        return error.InvalidEscape;
    }
    var buf: [4]u8 = undefined;
    const len = std.unicode.utf8Encode(@intCast(val), &buf) catch {
        stderr.print("printf: invalid universal character name \\{c}{x}\n", .{ esc_char, val }) catch {};
        return error.InvalidEscape;
    };
    try stdout.writeAll(buf[0..len]);
}

fn parseHexUnicode(p: []const u8, len: usize, esc_char: u8, stdout: anytype, stderr: anytype) !usize {
    var val: u32 = 0;
    var i: usize = 0;
    while (i < len) : (i += 1) {
        if (i >= p.len or !std.ascii.isHex(p[i])) {
            stderr.print("printf: missing hexadecimal number in escape\n", .{}) catch {};
            return error.InvalidEscape;
        }
        const digit = std.fmt.charToDigit(p[i], 16) catch unreachable;
        val = (val << 4) | digit;
    }
    try printUnicodeChar(val, esc_char, stdout, stderr);
    return len;
}

fn parseHexEscape(p: []const u8, stdout: anytype, stderr: anytype) !usize {
    var len: usize = 0;
    var val: u8 = 0;
    while (1 + len < p.len and len < 2 and std.ascii.isHex(p[1 + len])) : (len += 1) {
        const digit = std.fmt.charToDigit(p[1 + len], 16) catch unreachable;
        val = (val << 4) | digit;
    }
    if (len == 0) {
        stderr.print("printf: missing hexadecimal number in escape\n", .{}) catch {};
        return error.InvalidEscape;
    }
    try stdout.writeByte(val);
    return 1 + len;
}

fn parseOctalEscape(p: []const u8, octal_0: bool, ch: u8, stdout: anytype) !usize {
    var idx: usize = if (octal_0 and ch == '0') 1 else 0;
    var val: u8 = 0;
    var count: usize = 0;
    while (idx < p.len and count < 3 and p[idx] >= '0' and p[idx] <= '7') : ({
        idx += 1;
        count += 1;
    }) {
        val = (val << 3) | (p[idx] - '0');
    }
    try stdout.writeByte(val);
    return idx;
}

pub fn printEsc(escstart: []const u8, octal_0: bool, stdout: anytype, stderr: anytype) !struct { usize, bool } {
    if (escstart.len <= 1) {
        try stdout.writeByte('\\');
        return .{ 0, true };
    }
    const p = escstart[1..];
    const ch = p[0];
    if (ch == 'c') return .{ 1, false };
    if (ch == 'x') return .{ try parseHexEscape(p, stdout, stderr), true };
    if (ch >= '0' and ch <= '7') return .{ try parseOctalEscape(p, octal_0, ch, stdout), true };
    if (ch == 'u' or ch == 'U') {
        const ulen: usize = if (ch == 'u') 4 else 8;
        const used = try parseHexUnicode(p[1..], ulen, ch, stdout, stderr);
        return .{ 1 + used, true };
    }
    switch (ch) {
        'a' => try stdout.writeByte(0x07),
        'b' => try stdout.writeByte(0x08),
        'e' => try stdout.writeByte(0x1B),
        'f' => try stdout.writeByte(0x0C),
        'n' => try stdout.writeByte('\n'),
        'r' => try stdout.writeByte('\r'),
        't' => try stdout.writeByte('\t'),
        'v' => try stdout.writeByte(0x0B),
        '\\', '\'', '"' => try stdout.writeByte(ch),
        else => {
            try stdout.writeByte('\\');
            try stdout.writeByte(ch);
        },
    }
    return .{ 1, true };
}

pub fn printEscString(str: []const u8, stdout: anytype, stderr: anytype) !bool {
    var i: usize = 0;
    while (i < str.len) {
        if (str[i] == '\\') {
            const res = printEsc(str[i..], true, stdout, stderr) catch return false;
            if (!res[1]) return false;
            i += 1 + res[0];
        } else {
            try stdout.writeByte(str[i]);
            i += 1;
        }
    }
    return true;
}

fn isShellSpecial(ch: u8) bool {
    return switch (ch) {
        ' ',
        '\t',
        '\n',
        '\r',
        0x0B,
        0x0C,
        '!',
        '"',
        '#',
        '$',
        '&',
        '\'',
        '(',
        ')',
        '*',
        ';',
        '<',
        '=',
        '>',
        '?',
        '[',
        '\\',
        ']',
        '^',
        '`',
        '{',
        '|',
        '}',
        => true,
        else => false,
    };
}

fn isShellSafe(str: []const u8) bool {
    if (str.len == 0) return false;
    var i: usize = 0;
    while (i < str.len) {
        if (i == 0 and str[0] == '~') return false;
        var mb_len: usize = 1;
        if (!isCharPrintable(str, i, &mb_len)) return false;
        if (mb_len == 1) {
            if (isShellSpecial(str[i])) return false;
        } else {
            var wc: c.wchar_t = 0;
            var mbstate: c.mbstate_t = std.mem.zeroes(c.mbstate_t);
            _ = c.mbrtowc(&wc, str[i..].ptr, mb_len, &mbstate);
            if (c.iswspace(@as(c.wint_t, @bitCast(wc))) != 0) return false;
        }
        i += mb_len;
    }
    return true;
}

fn isCharPrintable(str: []const u8, offset: usize, mb_len: *usize) bool {
    const pz = str[offset..];
    var wc: c.wchar_t = 0;
    var mbstate: c.mbstate_t = std.mem.zeroes(c.mbstate_t);
    const n = c.mbrtowc(&wc, pz.ptr, pz.len, &mbstate);
    if (@as(isize, @bitCast(n)) > 0) {
        mb_len.* = n;
        return c.iswprint(@as(c.wint_t, @bitCast(wc))) != 0;
    }
    mb_len.* = 1;
    return false;
}

fn printAnsiEscape(ch: u8, stdout: anytype) !void {
    switch (ch) {
        0x07 => try stdout.writeAll("\\a"),
        0x08 => try stdout.writeAll("\\b"),
        0x1B => try stdout.writeAll("\\e"),
        0x0C => try stdout.writeAll("\\f"),
        '\n' => try stdout.writeAll("\\n"),
        '\r' => try stdout.writeAll("\\r"),
        '\t' => try stdout.writeAll("\\t"),
        0x0B => try stdout.writeAll("\\v"),
        '\\' => try stdout.writeAll("\\\\"),
        else => {
            var oct_buf: [4]u8 = undefined;
            const oct = std.fmt.bufPrint(&oct_buf, "\\{o:0>3}", .{ch}) catch unreachable;
            try stdout.writeAll(oct);
        },
    }
}

fn printShellEscapeText(str: []const u8, stdout: anytype) !void {
    if (std.mem.indexOfScalar(u8, str, '\'') != null and
        std.mem.indexOfScalar(u8, str, '"') == null and
        std.mem.indexOfScalar(u8, str, '$') == null and
        std.mem.indexOfScalar(u8, str, '\\') == null and
        std.mem.indexOfScalar(u8, str, '`') == null)
    {
        try stdout.writeByte('"');
        try stdout.writeAll(str);
        try stdout.writeByte('"');
        return;
    }
    try stdout.writeByte('\'');
    for (str) |ch| {
        if (ch == '\'') try stdout.writeAll("'\\''") else try stdout.writeByte(ch);
    }
    try stdout.writeByte('\'');
}

const ShellPiece = enum { none, text, quote, ansi };

fn hasNonPrintable(str: []const u8) bool {
    var i: usize = 0;
    while (i < str.len) {
        var mb_len: usize = 1;
        if (!isCharPrintable(str, i, &mb_len)) return true;
        i += mb_len;
    }
    return false;
}

fn emitShellPiece(str: []const u8, i: *usize, prev_piece: *ShellPiece, stdout: anytype) !void {
    var mb_len: usize = 1;
    if (str[i.*] == '\'') {
        if (prev_piece.* == .ansi) try stdout.writeByte('\'');
        if (prev_piece.* == .none) try stdout.writeAll("''");
        try stdout.writeAll("\\'");
        prev_piece.* = .quote;
        i.* += 1;
    } else if (isCharPrintable(str, i.*, &mb_len)) {
        if (prev_piece.* == .ansi) try stdout.writeByte('\'');
        if (prev_piece.* != .text) try stdout.writeByte('\'');
        try stdout.writeAll(str[i.* .. i.* + mb_len]);
        prev_piece.* = .text;
        i.* += mb_len;
    } else {
        if (prev_piece.* == .text) {
            try stdout.writeAll("'$'");
        } else if (prev_piece.* != .ansi) {
            try stdout.writeAll("''$'");
        }
        try printAnsiEscape(str[i.*], stdout);
        prev_piece.* = .ansi;
        i.* += 1;
    }
}

pub fn printShellEscape(str: []const u8, stdout: anytype) !void {
    if (str.len == 0) return stdout.writeAll("''");
    if (isShellSafe(str)) return stdout.writeAll(str);
    if (!hasNonPrintable(str)) return printShellEscapeText(str, stdout);

    var prev_piece: ShellPiece = .none;
    var i: usize = 0;
    while (i < str.len) {
        try emitShellPiece(str, &i, &prev_piece, stdout);
    }
    if (prev_piece == .text or prev_piece == .ansi) {
        try stdout.writeByte('\'');
    } else if (prev_piece == .quote) {
        try stdout.writeAll("''");
    }
}
