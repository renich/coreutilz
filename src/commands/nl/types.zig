const std = @import("std");
const c = @import("../../compat/c.zig").c;

pub const StyleType = enum { all, nonempty, none, regex };

pub const NumberingStyle = struct {
    type: StyleType,
    regex_buf: [64]u8 align(@alignOf(u64)) = [_]u8{0} ** 64,
    has_regex: bool = false,

    pub fn deinit(self: *NumberingStyle) void {
        if (self.has_regex) {
            c.regfree(@ptrCast(&self.regex_buf));
            self.has_regex = false;
        }
    }
};

pub const Format = enum { ln, rn, rz };

pub const Section = enum { header, body, footer };

pub const NlConfig = struct {
    body_style: NumberingStyle = .{ .type = .nonempty },
    header_style: NumberingStyle = .{ .type = .none },
    footer_style: NumberingStyle = .{ .type = .none },
    start_num: i64 = 1,
    increment: i64 = 1,
    format: Format = .rn,
    width: usize = 6,
    separator: []const u8 = "\t",
    renumber: bool = true,
    blank_join: usize = 1,
    delim: []const u8 = "\\:",
    delim_enabled: bool = true,

    pub fn deinit(self: *NlConfig) void {
        self.body_style.deinit();
        self.header_style.deinit();
        self.footer_style.deinit();
    }
};

pub fn parseStyle(s: []const u8) !NumberingStyle {
    if (s.len == 0) return error.InvalidStyle;
    switch (s[0]) {
        'a' => return .{ .type = .all },
        't' => return .{ .type = .nonempty },
        'n' => return .{ .type = .none },
        'p' => {
            var res: NumberingStyle = .{ .type = .regex };
            const pat = s[1..];
            var zpat: [256]u8 = undefined;
            if (pat.len >= zpat.len) return error.PatternTooLong;
            @memcpy(zpat[0..pat.len], pat);
            zpat[pat.len] = 0;
            if (c.regcomp(@ptrCast(&res.regex_buf), &zpat, c.REG_NOSUB) != 0) return error.RegexError;
            res.has_regex = true;
            return res;
        },
        else => return error.InvalidStyle,
    }
}
