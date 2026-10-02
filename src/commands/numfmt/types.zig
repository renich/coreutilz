const std = @import("std");

pub const Scale = enum { none, auto, si, iec, iec_i };
pub const RoundMethod = enum { up, down, from_zero, towards_zero, nearest };
pub const InvalidMode = enum { abort, fail, warn, ignore };

pub const NumfmtConfig = struct {
    scale_from: Scale = .none,
    scale_to: Scale = .none,
    round: RoundMethod = .nearest,
    invalid: InvalidMode = .abort,
    field: usize = 1,
    header: usize = 0,
    delimiter: ?u8 = null,
    padding: i32 = 0,
    suffix: ?[]const u8 = null,
};

pub fn parseScale(s: []const u8) !Scale {
    if (std.mem.eql(u8, s, "none")) return .none;
    if (std.mem.eql(u8, s, "auto")) return .auto;
    if (std.mem.eql(u8, s, "si")) return .si;
    if (std.mem.eql(u8, s, "iec")) return .iec;
    if (std.mem.eql(u8, s, "iec-i")) return .iec_i;
    return error.InvalidScale;
}

pub fn parseRound(s: []const u8) !RoundMethod {
    if (std.mem.eql(u8, s, "up")) return .up;
    if (std.mem.eql(u8, s, "down")) return .down;
    if (std.mem.eql(u8, s, "from-zero")) return .from_zero;
    if (std.mem.eql(u8, s, "towards-zero")) return .towards_zero;
    if (std.mem.eql(u8, s, "nearest")) return .nearest;
    return error.InvalidRound;
}

pub fn parseInvalid(s: []const u8) !InvalidMode {
    if (std.mem.eql(u8, s, "abort")) return .abort;
    if (std.mem.eql(u8, s, "fail")) return .fail;
    if (std.mem.eql(u8, s, "warn")) return .warn;
    if (std.mem.eql(u8, s, "ignore")) return .ignore;
    return error.InvalidMode;
}
