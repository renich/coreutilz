const std = @import("std");
const c = @import("../../compat/c.zig").c;

pub const Regex = struct {
    bytes: [128]u8 align(8) = undefined,

    pub fn ptr(self: *Regex) *c.regex_t {
        return @ptrCast(&self.bytes);
    }
};

pub const PatternType = enum {
    line_number,
    regex,
};

pub const Pattern = struct {
    pattern_type: PatternType,
    line_number: usize = 0,
    regex_compiled: ?Regex = null,
    offset: i64 = 0,
    ignore: bool = false,
    repeat: usize = 0,
    repeat_forever: bool = false,
    raw_arg: []const u8 = "",

    pub fn deinit(self: *Pattern) void {
        if (self.regex_compiled) |*reg| {
            c.regfree(reg.ptr());
            self.regex_compiled = null;
        }
    }

    pub fn matchRegex(self: *Pattern, line: []const u8, buf: *[8192]u8, allocator: std.mem.Allocator) !bool {
        var len = line.len;
        if (len > 0 and line[len - 1] == '\n') len -= 1;
        const line_content = line[0..len];

        const reg = if (self.regex_compiled) |*r| r.ptr() else return false;
        if (line_content.len < buf.len) {
            @memcpy(buf[0..line_content.len], line_content);
            buf[line_content.len] = 0;
            const res = c.regexec(reg, buf, 0, null, 0);
            return res == 0;
        }
        const heap_buf = try allocator.allocSentinel(u8, line_content.len, 0);
        defer allocator.free(heap_buf);
        @memcpy(heap_buf, line_content);
        const res = c.regexec(reg, heap_buf.ptr, 0, null, 0);
        return res == 0;
    }
};

pub fn parsePatterns(
    allocator: std.mem.Allocator,
    raw_patterns: [][]const u8,
    stderr: anytype,
) ![]Pattern {
    var list: std.ArrayList(Pattern) = .empty;
    errdefer {
        for (list.items) |*p| p.deinit();
        list.deinit(allocator);
    }
    var last_val: usize = 0;
    var i: usize = 0;
    while (i < raw_patterns.len) : (i += 1) {
        const token = raw_patterns[i];
        var pat = try parseSinglePattern(allocator, token, &last_val, stderr);
        if (i + 1 < raw_patterns.len and std.mem.startsWith(u8, raw_patterns[i + 1], "{")) {
            i += 1;
            try parseRepeatCount(raw_patterns[i], &pat, stderr);
        }
        try list.append(allocator, pat);
    }
    return list.toOwnedSlice(allocator);
}

fn parseSinglePattern(
    allocator: std.mem.Allocator,
    token: []const u8,
    last_val: *usize,
    stderr: anytype,
) !Pattern {
    if (token.len > 0 and (token[0] == '/' or token[0] == '%')) {
        return parseRegexPattern(allocator, token, stderr);
    }
    return parseLineNumberPattern(token, last_val, stderr);
}

fn parseLineNumberPattern(
    token: []const u8,
    last_val: *usize,
    stderr: anytype,
) !Pattern {
    const val = std.fmt.parseInt(usize, token, 10) catch {
        try stderr.print("csplit: '{s}': invalid pattern\n", .{token});
        return error.InvalidPattern;
    };
    if (val == 0) {
        try stderr.print("csplit: {s}: line number must be greater than zero\n", .{token});
        return error.InvalidPattern;
    }
    if (val < last_val.*) {
        try stderr.print("csplit: line number '{s}' is smaller than preceding line number, {d}\n", .{ token, last_val.* });
        return error.InvalidPattern;
    }
    if (val == last_val.*) {
        try stderr.print("csplit: warning: line number '{s}' is the same as preceding line number\n", .{token});
    }
    last_val.* = val;
    return Pattern{
        .pattern_type = .line_number,
        .line_number = val,
        .raw_arg = token,
    };
}

fn parseRegexPattern(
    allocator: std.mem.Allocator,
    token: []const u8,
    stderr: anytype,
) !Pattern {
    const delim = token[0];
    const ignore = (delim == '%');
    const last_delim_idx = std.mem.lastIndexOfScalar(u8, token[1..], delim);
    if (last_delim_idx == null) {
        try stderr.print("csplit: {s}: closing delimiter '{c}' missing\n", .{ token, delim });
        return error.MissingDelimiter;
    }
    const closing_idx = 1 + last_delim_idx.?;
    const regex_part = token[1..closing_idx];
    const offset_part = token[closing_idx + 1 ..];

    var offset: i64 = 0;
    if (offset_part.len > 0) {
        offset = std.fmt.parseInt(i64, offset_part, 10) catch {
            try stderr.print("csplit: '{s}': integer expected after delimiter\n", .{token});
            return error.InvalidOffset;
        };
    }

    const reg = try compileRegex(allocator, regex_part, token, stderr);
    return Pattern{
        .pattern_type = .regex,
        .regex_compiled = reg,
        .offset = offset,
        .ignore = ignore,
        .raw_arg = token,
    };
}

fn compileRegex(
    allocator: std.mem.Allocator,
    regex_part: []const u8,
    full_token: []const u8,
    stderr: anytype,
) !Regex {
    const reg_z = try allocator.dupeZ(u8, regex_part);
    defer allocator.free(reg_z);
    var reg = Regex{};
    const res = c.regcomp(reg.ptr(), reg_z.ptr, 0);
    if (res != 0) {
        var err_buf: [256]u8 = undefined;
        _ = c.regerror(res, reg.ptr(), &err_buf, err_buf.len);
        const err_len = std.mem.sliceTo(&err_buf, 0).len;
        try stderr.print("csplit: '{s}': invalid regular expression: {s}\n", .{ full_token, err_buf[0..err_len] });
        return error.InvalidRegex;
    }
    return reg;
}

fn parseRepeatCount(
    token: []const u8,
    pat: *Pattern,
    stderr: anytype,
) !void {
    if (!std.mem.endsWith(u8, token, "}")) {
        try stderr.print("csplit: '{s}': '}}' is required in repeat count\n", .{token});
        return error.InvalidRepeat;
    }
    const inner = token[1 .. token.len - 1];
    if (std.mem.eql(u8, inner, "*")) {
        pat.repeat_forever = true;
        return;
    }
    const count = std.fmt.parseInt(usize, inner, 10) catch {
        try stderr.print("csplit: '{s}': integer required between '{{' and '}}'\n", .{token});
        return error.InvalidRepeat;
    };
    pat.repeat = count;
}
