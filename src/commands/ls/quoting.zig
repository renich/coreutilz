const std = @import("std");
const c = @import("../../compat/c.zig").c;
const types = @import("types.zig");
const FileEntry = types.FileEntry;
const Options = types.Options;
const QuotingStyle = types.QuotingStyle;

pub fn getIndicatorChar(entry: *const FileEntry, options: *const Options) ?u8 {
    if (options.indicator == .none) return null;
    if (entry.is_dir) return '/';
    if (options.indicator == .slash) return null;

    if (entry.is_symlink) return '@';
    const mode_val: u32 = @intCast(entry.stat.st_mode);
    switch (mode_val & c.S_IFMT) {
        c.S_IFIFO => return '|',
        c.S_IFSOCK => return '=',
        else => {},
    }
    if (options.indicator == .file_type) return null;
    if ((mode_val & 0o111) != 0) return '*';
    return null;
}

pub fn isControlChar(ch: u8) bool {
    return ch < 32 or ch >= 127;
}

pub fn isSpecialShellChar(ch: u8) bool {
    if (std.ascii.isWhitespace(ch)) return true;
    const specials = "'\"\\$`*?[]();<>|&!^~#=:";
    return std.mem.indexOfScalar(u8, specials, ch) != null;
}

pub fn needsQuoting(str: []const u8, style: QuotingStyle) bool {
    return switch (style) {
        .literal => false,
        .c_style, .clocale, .shell_always, .locale => true,
        .shell => blk: {
            for (str) |ch| {
                if (isSpecialShellChar(ch)) break :blk true;
            }
            break :blk false;
        },
        .shell_escape => blk: {
            for (str) |ch| {
                if (isSpecialShellChar(ch) or isControlChar(ch)) break :blk true;
            }
            break :blk false;
        },
        .escape => false,
    };
}

fn getShortEscape(ch: u8) ?u8 {
    return switch (ch) {
        7 => 'a',
        8 => 'b',
        9 => 't',
        10 => 'n',
        11 => 'v',
        12 => 'f',
        13 => 'r',
        else => null,
    };
}

fn appendEscapedChar(buf: []u8, cur: *usize, ch: u8) void {
    if (cur.* + 4 > buf.len) return;
    if (getShortEscape(ch)) |esc| {
        buf[cur.*] = '\\';
        buf[cur.* + 1] = esc;
        cur.* += 2;
    } else {
        buf[cur.*] = '\\';
        buf[cur.* + 1] = '0' + ((ch >> 6) & 7);
        buf[cur.* + 2] = '0' + ((ch >> 3) & 7);
        buf[cur.* + 3] = '0' + (ch & 7);
        cur.* += 4;
    }
}

fn quoteCStyle(str: []const u8, buf: []u8) []const u8 {
    if (buf.len < str.len * 4 + 2) return str;
    buf[0] = '"';
    var cur: usize = 1;
    for (str) |ch| {
        if (ch == '"' or ch == '\\') {
            buf[cur] = '\\';
            buf[cur + 1] = ch;
            cur += 2;
        } else if (isControlChar(ch)) {
            appendEscapedChar(buf, &cur, ch);
        } else {
            buf[cur] = ch;
            cur += 1;
        }
    }
    buf[cur] = '"';
    return buf[0 .. cur + 1];
}

fn quoteLocale(str: []const u8, buf: []u8) []const u8 {
    if (buf.len < str.len * 4 + 2) return str;
    buf[0] = '\'';
    var cur: usize = 1;
    for (str) |ch| {
        if (ch == '\'' or ch == '\\') {
            buf[cur] = '\\';
            buf[cur + 1] = ch;
            cur += 2;
        } else if (isControlChar(ch)) {
            appendEscapedChar(buf, &cur, ch);
        } else {
            buf[cur] = ch;
            cur += 1;
        }
    }
    buf[cur] = '\'';
    return buf[0 .. cur + 1];
}

fn quoteEscape(str: []const u8, buf: []u8) []const u8 {
    if (buf.len < str.len * 4) return str;
    var cur: usize = 0;
    for (str) |ch| {
        if (ch == '\\' or ch == ' ') {
            buf[cur] = '\\';
            buf[cur + 1] = ch;
            cur += 2;
        } else if (isControlChar(ch)) {
            appendEscapedChar(buf, &cur, ch);
        } else {
            buf[cur] = ch;
            cur += 1;
        }
    }
    return buf[0..cur];
}

fn quoteShell(str: []const u8, buf: []u8) []const u8 {
    if (buf.len < str.len * 4 + 2) return str;
    buf[0] = '\'';
    var cur: usize = 1;
    for (str) |ch| {
        if (ch == '\'') {
            @memcpy(buf[cur .. cur + 4], "'\\''");
            cur += 4;
        } else {
            buf[cur] = ch;
            cur += 1;
        }
    }
    buf[cur] = '\'';
    return buf[0 .. cur + 1];
}

fn quoteShellEscape(str: []const u8, buf: []u8) []const u8 {
    var has_ctrl = false;
    for (str) |ch| {
        if (isControlChar(ch)) {
            has_ctrl = true;
            break;
        }
    }
    if (!has_ctrl) return quoteShell(str, buf);

    buf[0] = '\'';
    var cur: usize = 1;
    var in_ansi = false;
    for (str) |ch| {
        if (isControlChar(ch)) {
            if (!in_ansi) {
                @memcpy(buf[cur .. cur + 3], "'$'");
                cur += 3;
                in_ansi = true;
            }
            appendEscapedChar(buf, &cur, ch);
        } else {
            if (in_ansi) {
                @memcpy(buf[cur .. cur + 2], "''");
                cur += 2;
                in_ansi = false;
            }
            if (ch == '\'') {
                @memcpy(buf[cur .. cur + 4], "'\\''");
                cur += 4;
            } else {
                buf[cur] = ch;
                cur += 1;
            }
        }
    }
    buf[cur] = '\'';
    return buf[0 .. cur + 1];
}

fn sanitizeNongraphic(str: []const u8, buf: []u8) []const u8 {
    var has_funny = false;
    for (str) |ch| {
        if (isControlChar(ch)) {
            has_funny = true;
            break;
        }
    }
    if (!has_funny) return str;

    const out = buf[0..str.len];
    for (str, 0..) |ch, idx| {
        out[idx] = if (isControlChar(ch)) '?' else ch;
    }
    return out;
}

pub fn formatQuotedName(str: []const u8, style: QuotingStyle, hide_ctrl: bool, buf: []u8) []const u8 {
    const raw = switch (style) {
        .literal => str,
        .c_style, .clocale => quoteCStyle(str, buf),
        .locale => quoteLocale(str, buf),
        .shell_always => quoteShell(str, buf),
        .shell => if (needsQuoting(str, .shell)) quoteShell(str, buf) else str,
        .shell_escape => if (needsQuoting(str, .shell_escape)) quoteShellEscape(str, buf) else str,
        .escape => quoteEscape(str, buf),
    };

    if (hide_ctrl and (style == .literal or style == .shell or style == .shell_always)) {
        return sanitizeNongraphic(raw, buf);
    }
    return raw;
}

pub fn shouldAlignVariableQuotes(options: *const Options) bool {
    const is_active_format = switch (options.format) {
        .long => true,
        .columns, .across => options.term_width != 0,
        else => false,
    };
    if (!is_active_format) return false;
    return switch (options.quoting_style) {
        .shell, .shell_escape, .shell_always, .c_style => true,
        else => false,
    };
}

pub fn hasQuotedEntry(entries: []const FileEntry, style: QuotingStyle) bool {
    for (entries) |*e| {
        if (needsQuoting(e.name, style)) return true;
    }
    return false;
}
