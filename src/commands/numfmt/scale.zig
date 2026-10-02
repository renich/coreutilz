const std = @import("std");
const types = @import("types.zig");

const suffixes = "KMGTPEZYRQ";

pub fn parseNumber(str: []const u8, scale: types.Scale) !f64 {
    var s = std.mem.trim(u8, str, " \t\r\n");
    if (s.len == 0) return error.EmptyNumber;

    if (scale == .none) {
        return std.fmt.parseFloat(f64, s);
    }

    var mult: f64 = 1.0;
    const base_si: f64 = 1000.0;
    const base_iec: f64 = 1024.0;

    if (s.len > 1 and (s[s.len - 1] == 'i' or s[s.len - 1] == 'I')) {
        if (s.len > 2 and (scale == .auto or scale == .iec_i)) {
            const unit_c = s[s.len - 2];
            if (getUnitPower(unit_c)) |p| {
                mult = std.math.pow(f64, base_iec, @as(f64, @floatFromInt(p)));
                s = s[0 .. s.len - 2];
            } else return error.InvalidSuffix;
        } else return error.InvalidSuffix;
    } else if (s.len > 1 and !std.ascii.isDigit(s[s.len - 1])) {
        const unit_c = s[s.len - 1];
        if (getUnitPower(unit_c)) |p| {
            const base = switch (scale) {
                .si => base_si,
                .iec => base_iec,
                .auto => if (unit_c == 'k') base_si else base_si,
                else => base_si,
            };
            mult = std.math.pow(f64, base, @as(f64, @floatFromInt(p)));
            s = s[0 .. s.len - 1];
        } else return error.InvalidSuffix;
    }

    const val = try std.fmt.parseFloat(f64, s);
    return val * mult;
}

fn getUnitPower(c: u8) ?usize {
    const uc = std.ascii.toUpper(c);
    for (suffixes, 0..) |s, i| {
        if (s == uc) return i + 1;
    }
    return null;
}

pub fn formatNumber(
    buf: []u8,
    val_in: f64,
    scale: types.Scale,
    round: types.RoundMethod,
    suffix: ?[]const u8,
) ![]const u8 {
    if (scale == .none) {
        const rounded = applyRound(val_in, round);
        if (@round(rounded) == rounded) {
            return std.fmt.bufPrint(buf, "{d}{s}", .{ @as(i64, @intFromFloat(rounded)), suffix orelse "" });
        }
        return std.fmt.bufPrint(buf, "{d:.1}{s}", .{ rounded, suffix orelse "" });
    }

    const base: f64 = if (scale == .si) 1000.0 else 1024.0;
    var val = val_in;
    var power: usize = 0;

    while (@abs(val) >= base and power < suffixes.len) {
        val /= base;
        power += 1;
    }

    const show_decimal = (@abs(val) < 10.0 and power > 0);
    const power_adjust: f64 = if (show_decimal) 10.0 else 1.0;
    val = applyRound(val * power_adjust, round) / power_adjust;

    if (@abs(val) >= base and power < suffixes.len) {
        val /= base;
        power += 1;
    }

    var unit_str: [4]u8 = undefined;
    var unit_len: usize = 0;
    if (power > 0) {
        if (power == 1 and scale == .si) {
            unit_str[0] = 'k';
        } else {
            unit_str[0] = suffixes[power - 1];
        }
        unit_len = 1;
        if (scale == .iec_i) {
            unit_str[1] = 'i';
            unit_len = 2;
        }
    }

    const u_slice = unit_str[0..unit_len];
    const s_str = suffix orelse "";

    if (show_decimal and @abs(val) < 10.0 and power > 0) {
        return std.fmt.bufPrint(buf, "{d:.1}{s}{s}", .{ val, u_slice, s_str });
    } else {
        const int_val = @as(i64, @intFromFloat(val));
        return std.fmt.bufPrint(buf, "{d}{s}{s}", .{ int_val, u_slice, s_str });
    }
}

fn applyRound(val: f64, method: types.RoundMethod) f64 {
    return switch (method) {
        .up => @ceil(val),
        .down => @floor(val),
        .from_zero => if (val >= 0) @ceil(val) else @floor(val),
        .towards_zero => @trunc(val),
        .nearest => @round(val),
    };
}
