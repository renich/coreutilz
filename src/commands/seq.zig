const std = @import("std");
const errors = @import("../utils/errors.zig");

const c = @cImport({
    @cDefine("_GNU_SOURCE", "1");
    @cInclude("errno.h");
    @cInclude("stdlib.h");
    @cInclude("stdio.h");
    @cInclude("string.h");
    @cInclude("locale.h");
    @cInclude("unistd.h");
});

pub const name: []const u8 = "seq";
pub const version: []const u8 = "0.1.0";

const Layout = struct {
    prefix_len: usize = 0,
    suffix_len: usize = 0,
};

const Operand = struct {
    value: c_longdouble,
    width: usize,
    precision: c_int,
};

fn fullWrite(fd: c_int, bytes: []const u8) bool {
    var written: usize = 0;
    while (written < bytes.len) {
        const count = bytes.len - written;
        const res = c.write(fd, bytes[written..].ptr, count);
        if (res <= 0) {
            return false;
        }
        written += @intCast(res);
    }
    return true;
}

fn writeError() void {
    const err = c.__errno_location().*;
    const msg = std.mem.span(c.strerror(err));
    std.debug.print("seq: write error: {s}\n", .{msg});
}

fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: seq [OPTION]... LAST
        \\  or:  seq [OPTION]... FIRST LAST
        \\  or:  seq [OPTION]... FIRST INCREMENT LAST
        \\Print numbers from FIRST to LAST, in steps of INCREMENT.
        \\
        \\Mandatory arguments to long options are mandatory for short options too.
        \\  -f, --format=FORMAT      use printf style floating-point FORMAT
        \\  -s, --separator=STRING   use STRING to separate numbers (default: \n)
        \\  -w, --equal-width        equalize width by padding with leading zeroes
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
        \\If FIRST or INCREMENT is omitted, it defaults to 1.  That is, an
        \\omitted INCREMENT defaults to 1 even when LAST is smaller than FIRST.
        \\The sequence of numbers ends when the sum of the current number and
        \\INCREMENT would become greater than LAST.
        \\FIRST, INCREMENT, and LAST are interpreted as floating point values.
        \\INCREMENT is usually positive if FIRST is smaller than LAST, and
        \\INCREMENT is usually negative if FIRST is greater than LAST.
        \\INCREMENT must not be 0; none of FIRST, INCREMENT and LAST may be NaN.
        \\FORMAT must be suitable for printing one argument of type 'double';
        \\it defaults to %.PRECf if FIRST, INCREMENT, and LAST are all fixed point
        \\decimal numbers with maximum precision PREC, and to %g otherwise.
        \\
    );
}

fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}

fn allDigits(s: []const u8) bool {
    if (s.len == 0) return false;
    for (s) |b| {
        if (!std.ascii.isDigit(b)) return false;
    }
    return true;
}

fn trimLeadingZeros(s: []const u8) []const u8 {
    var i: usize = 0;
    while (i < s.len and s[i] == '0') : (i += 1) {}
    if (i == s.len and s.len > 0) {
        return s[s.len - 1 ..];
    }
    return s[i..];
}

fn cmpDigits(a: []const u8, b: []const u8) i32 {
    if (a.len != b.len) {
        return if (a.len < b.len) -1 else 1;
    }
    return switch (std.mem.order(u8, a, b)) {
        .lt => -1,
        .eq => 0,
        .gt => 1,
    };
}

fn incrGrows(buf: []u8, p: *usize, endp: usize) bool {
    var cur = endp;
    while (cur > p.*) {
        cur -= 1;
        if (buf[cur] < '9') {
            buf[cur] += 1;
            return false;
        }
        buf[cur] = '0';
    }
    p.* -= 1;
    buf[p.*] = '1';
    return true;
}

fn seqFast(
    allocator: std.mem.Allocator,
    a_raw: []const u8,
    b_raw: []const u8,
    step: usize,
    separator: u8,
    terminator: u8,
) u8 {
    const a = trimLeadingZeros(a_raw);
    const b = trimLeadingZeros(b_raw);

    const is_inf = std.mem.eql(u8, b, "inf");
    const p_len = a.len;
    const b_len = b.len;

    const initial_alloc_digits = 31;
    var inc_size = @max(@max(p_len + 1, b_len), initial_alloc_digits);

    var p0 = allocator.alloc(u8, inc_size) catch return 1;
    defer allocator.free(p0);

    var endp = inc_size;
    var p = endp - p_len;
    @memcpy(p0[p..endp], a);

    var out_buf: [16384]u8 = undefined;
    var out_len: usize = 0;

    const stdout_fd: c_int = 1;

    while (is_inf or cmpDigits(p0[p..endp], b) <= 0) {
        var pp = p;
        while (out_buf.len - out_len <= endp - pp) {
            const chunk = out_buf.len - out_len;
            @memcpy(out_buf[out_len..][0..chunk], p0[pp..][0..chunk]);
            pp += chunk;
            out_len += chunk;
            if (!fullWrite(stdout_fd, out_buf[0..out_len])) {
                writeError();
                return 1;
            }
            out_len = 0;
        }

        const rest_len = endp - pp;
        @memcpy(out_buf[out_len..][0..rest_len], p0[pp..][0..rest_len]);
        out_len += rest_len;
        out_buf[out_len] = separator;
        out_len += 1;

        if (p == 0) {
            const new_inc_size = inc_size * 2;
            const new_p0 = allocator.alloc(u8, new_inc_size) catch return 1;
            const saved_p_len = endp - p;
            const new_endp = new_inc_size;
            const new_p = new_endp - saved_p_len;
            @memcpy(new_p0[new_p..new_endp], p0[p..endp]);
            allocator.free(p0);
            p0 = new_p0;
            inc_size = new_inc_size;
            endp = new_endp;
            p = new_p;
        }

        var n_incr = step;
        while (n_incr > 0) : (n_incr -= 1) {
            _ = incrGrows(p0, &p, endp);
        }
    }

    if (out_len > 0) {
        out_buf[out_len - 1] = terminator;
        if (!fullWrite(stdout_fd, out_buf[0..out_len])) {
            writeError();
            return 1;
        }
    }

    return 0;
}

fn validateAndTransformFormat(
    allocator: std.mem.Allocator,
    fmt: []const u8,
    layout: *Layout,
    stderr: anytype,
) ![:0]const u8 {
    var i: usize = 0;
    var prefix_len: usize = 0;

    while (true) {
        if (i >= fmt.len) {
            try stderr.print("seq: format '{s}' has no % directive\n", .{fmt});
            try stderr.flush();
            return error.FormatError;
        }
        if (fmt[i] == '%') {
            if (i + 1 < fmt.len and fmt[i + 1] == '%') {
                prefix_len += 1;
                i += 2;
                continue;
            } else {
                break;
            }
        }
        prefix_len += 1;
        i += 1;
    }

    i += 1; // skip '%'

    while (i < fmt.len and (fmt[i] == '-' or fmt[i] == '+' or fmt[i] == '#' or fmt[i] == '0' or fmt[i] == ' ' or fmt[i] == '\'')) : (i += 1) {}

    while (i < fmt.len and std.ascii.isDigit(fmt[i])) : (i += 1) {}

    if (i < fmt.len and fmt[i] == '.') {
        i += 1;
        while (i < fmt.len and std.ascii.isDigit(fmt[i])) : (i += 1) {}
    }

    const length_modifier_offset = i;
    const has_L = if (i < fmt.len and fmt[i] == 'L') true else false;
    if (has_L) i += 1;

    if (i >= fmt.len) {
        try stderr.print("seq: format '{s}' ends in %\n", .{fmt});
        try stderr.flush();
        return error.FormatError;
    }

    const spec = fmt[i];
    if (std.mem.indexOfScalar(u8, "efgaEFGA", spec) == null) {
        try stderr.print("seq: format '{s}' has unknown %{c} directive\n", .{ fmt, spec });
        try stderr.flush();
        return error.FormatError;
    }

    i += 1; // skip specifier

    var suffix_len: usize = 0;
    while (i < fmt.len) {
        if (fmt[i] == '%') {
            if (i + 1 < fmt.len and fmt[i + 1] == '%') {
                suffix_len += 1;
                i += 2;
                continue;
            } else {
                try stderr.print("seq: format '{s}' has too many % directives\n", .{fmt});
                try stderr.flush();
                return error.FormatError;
            }
        }
        suffix_len += 1;
        i += 1;
    }

    layout.prefix_len = prefix_len;
    layout.suffix_len = suffix_len;

    if (has_L) {
        return try allocator.dupeZ(u8, fmt);
    } else {
        const out = try allocator.allocSentinel(u8, fmt.len + 1, 0);
        @memcpy(out[0..length_modifier_offset], fmt[0..length_modifier_offset]);
        out[length_modifier_offset] = 'L';
        @memcpy(out[length_modifier_offset + 1 ..], fmt[length_modifier_offset..]);
        return out;
    }
}

fn scanArg(allocator: std.mem.Allocator, arg: []const u8, stderr: anytype) !Operand {
    const arg_z = try allocator.dupeZ(u8, arg);
    defer allocator.free(arg_z);

    var endptr: [*c]u8 = null;
    c.__errno_location().* = 0;
    const value: c_longdouble = c.strtold(arg_z.ptr, &endptr);

    if (endptr == arg_z.ptr or (endptr != null and endptr.* != 0)) {
        try stderr.print("seq: invalid floating point argument: '{s}'\nTry 'seq --help' for more information.\n", .{arg});
        try stderr.flush();
        return error.InvalidFloat;
    }

    if (value != value) {
        try stderr.print("seq: invalid 'not-a-number' argument: '{s}'\nTry 'seq --help' for more information.\n", .{arg});
        try stderr.flush();
        return error.NotANumber;
    }

    var s = arg;
    while (s.len > 0 and (std.ascii.isWhitespace(s[0]) or s[0] == '+')) {
        s = s[1..];
    }

    var width: usize = 0;
    var precision: c_int = std.math.maxInt(c_int);

    const decimal_point = std.mem.indexOfScalar(u8, s, '.');
    const has_p = std.mem.indexOfScalar(u8, s, 'p') != null or std.mem.indexOfScalar(u8, s, 'P') != null;

    if (decimal_point == null and !has_p) {
        precision = 0;
    }

    const has_hex = std.mem.indexOfScalar(u8, s, 'x') != null or std.mem.indexOfScalar(u8, s, 'X') != null;
    const is_finite = (value * 0.0 == 0.0);

    if (!has_hex and is_finite) {
        var fraction_len: usize = 0;
        width = s.len;

        if (decimal_point) |dp_idx| {
            const after_dp = s[dp_idx + 1 ..];
            var f_len: usize = 0;
            while (f_len < after_dp.len and after_dp[f_len] != 'e' and after_dp[f_len] != 'E') : (f_len += 1) {}
            fraction_len = f_len;

            if (fraction_len <= std.math.maxInt(c_int)) {
                precision = @intCast(fraction_len);
            }

            if (fraction_len == 0) {
                if (width > 0) width -= 1;
            } else if (dp_idx == 0 or !std.ascii.isDigit(s[dp_idx - 1])) {
                width += 1;
            }
        }

        const e_idx = std.mem.indexOfScalar(u8, s, 'e') orelse std.mem.indexOfScalar(u8, s, 'E');
        if (e_idx) |exp_pos| {
            const exp_str = try allocator.dupeZ(u8, s[exp_pos + 1 ..]);
            defer allocator.free(exp_str);
            var end_exp: [*c]u8 = null;
            var exponent: c_long = c.strtol(exp_str.ptr, &end_exp, 10);
            if (exponent < -std.math.maxInt(c_long)) {
                exponent = -std.math.maxInt(c_long);
            }

            if (exponent < 0) {
                const pos_exp: c_long = if (exponent <= -std.math.maxInt(c_long))
                    std.math.maxInt(c_long)
                else
                    -exponent;
                if (pos_exp >= std.math.maxInt(c_int) or @as(c_long, precision) + pos_exp >= std.math.maxInt(c_int)) {
                    precision = std.math.maxInt(c_int);
                } else {
                    precision += @intCast(pos_exp);
                }
            } else {
                precision -= @intCast(@min(precision, exponent));
            }

            if (width >= s.len - exp_pos) {
                width -= s.len - exp_pos;
            } else {
                width = 0;
            }

            if (exponent < 0) {
                if (decimal_point) |dp_idx| {
                    if (exp_pos == dp_idx + 1) {
                        width += 1;
                    }
                } else {
                    width += 1;
                }
                const pos_exp: c_long = if (exponent <= -std.math.maxInt(c_long))
                    std.math.maxInt(c_long)
                else
                    -exponent;
                if (pos_exp >= std.math.maxInt(c_int) or @as(c_long, @intCast(width)) + pos_exp >= std.math.maxInt(c_int)) {
                    width = std.math.maxInt(c_int);
                } else {
                    width += @intCast(pos_exp);
                }
            } else {
                if (decimal_point != null and precision == 0 and fraction_len != 0) {
                    if (width > 0) width -= 1;
                }
                exponent -= @intCast(@min(fraction_len, @as(usize, @intCast(exponent))));
                if (exponent >= std.math.maxInt(c_int) or @as(c_long, @intCast(width)) + exponent >= std.math.maxInt(c_int)) {
                    width = std.math.maxInt(c_int);
                } else {
                    width += @intCast(exponent);
                }
            }
        }
    }

    return Operand{
        .value = value,
        .width = width,
        .precision = precision,
    };
}

fn getDefaultFormat(
    allocator: std.mem.Allocator,
    first: Operand,
    step: Operand,
    last: Operand,
    equal_width: bool,
) ![:0]const u8 {
    const prec = @max(first.precision, step.precision);

    if (prec != std.math.maxInt(c_int) and last.precision != std.math.maxInt(c_int)) {
        if (equal_width) {
            const f_diff = prec - first.precision;
            const l_diff = prec - last.precision;
            const fw_signed = @as(isize, @intCast(first.width)) + f_diff;
            var first_width: usize = if (fw_signed > 0) @intCast(fw_signed) else 0;
            const lw_signed = @as(isize, @intCast(last.width)) + l_diff;
            var last_width: usize = if (lw_signed > 0) @intCast(lw_signed) else 0;

            if (last.precision != 0 and prec == 0 and last_width > 0) {
                last_width -= 1;
            }
            if (last.precision == 0 and prec != 0) {
                last_width += 1;
            }
            if (first.precision == 0 and prec != 0) {
                first_width += 1;
            }
            const width = @max(first_width, last_width);
            const s = try std.fmt.allocPrint(allocator, "%0{d}.{d}Lf", .{ width, prec });
            defer allocator.free(s);
            return try allocator.dupeZ(u8, s);
        } else {
            const s = try std.fmt.allocPrint(allocator, "%.{d}Lf", .{prec});
            defer allocator.free(s);
            return try allocator.dupeZ(u8, s);
        }
    }

    return try allocator.dupeZ(u8, "%Lg");
}

fn appendOut(buf: *[16384]u8, len: *usize, slice: []const u8) bool {
    var off: usize = 0;
    while (off < slice.len) {
        const avail = buf.len - len.*;
        const chunk = @min(avail, slice.len - off);
        @memcpy(buf[len.*..][0..chunk], slice[off..][0..chunk]);
        len.* += chunk;
        off += chunk;
        if (len.* == buf.len) {
            if (!fullWrite(1, buf[0..len.*])) return false;
            len.* = 0;
        }
    }
    return true;
}

fn printNumbers(
    allocator: std.mem.Allocator,
    fmt_z: [:0]const u8,
    layout: Layout,
    first: c_longdouble,
    step: c_longdouble,
    last: c_longdouble,
    separator: []const u8,
) u8 {
    var out_of_range = if (step < 0) first < last else last < first;

    if (!out_of_range) {
        var x = first;
        var i: c_longdouble = 1.0;

        var out_buf: [16384]u8 = undefined;
        var out_len: usize = 0;

        while (true) : (i += 1.0) {
            const x0 = x;

            var stack_num: [512]u8 = undefined;
            const n = c.snprintf(&stack_num, stack_num.len, fmt_z.ptr, x);
            if (n < 0) {
                writeError();
                return 1;
            }
            if (@as(usize, @intCast(n)) < stack_num.len) {
                if (!appendOut(&out_buf, &out_len, stack_num[0..@intCast(n)])) {
                    writeError();
                    return 1;
                }
            } else {
                const dyn_num = allocator.alloc(u8, @as(usize, @intCast(n)) + 1) catch return 1;
                defer allocator.free(dyn_num);
                _ = c.snprintf(dyn_num.ptr, dyn_num.len, fmt_z.ptr, x);
                if (!appendOut(&out_buf, &out_len, dyn_num[0..@intCast(n)])) {
                    writeError();
                    return 1;
                }
            }

            if (out_of_range) break;

            x = first + i * step;
            out_of_range = if (step < 0) x < last else last < x;

            if (out_of_range) {
                var print_extra_number = false;
                var x_str: [*c]u8 = null;
                const x_strlen = c.asprintf(&x_str, fmt_z.ptr, x);
                if (x_strlen >= 0 and x_str != null) {
                    defer c.free(x_str);
                    const x_len: usize = @intCast(x_strlen);
                    if (x_len >= layout.suffix_len) {
                        x_str[x_len - layout.suffix_len] = 0;
                        const parse_slice = x_str + layout.prefix_len;
                        var endptr: [*c]u8 = null;
                        c.__errno_location().* = 0;
                        const x_val = c.strtold(parse_slice, &endptr);
                        if (endptr != parse_slice and (endptr == null or endptr.* == 0) and x_val == last) {
                            var x0_str: [*c]u8 = null;
                            const x0_strlen = c.asprintf(&x0_str, fmt_z.ptr, x0);
                            if (x0_strlen >= 0 and x0_str != null) {
                                defer c.free(x0_str);
                                const x0_len: usize = @intCast(x0_strlen);
                                if (x0_len >= layout.suffix_len) {
                                    x0_str[x0_len - layout.suffix_len] = 0;
                                    if (c.strcmp(x0_str, x_str) != 0) {
                                        print_extra_number = true;
                                    }
                                }
                            }
                        }
                    }
                }

                if (!print_extra_number) break;
            }

            if (!appendOut(&out_buf, &out_len, separator)) {
                writeError();
                return 1;
            }
        }

        if (!appendOut(&out_buf, &out_len, "\n")) {
            writeError();
            return 1;
        }

        if (out_len > 0) {
            if (!fullWrite(1, out_buf[0..out_len])) {
                writeError();
                return 1;
            }
        }
    }

    return 0;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    _ = c.setlocale(c.LC_ALL, "");

    var stdout_buffer: [4096]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var format_str: ?[]const u8 = null;
    var separator: []const u8 = "\n";
    var equal_width: bool = false;

    var optind: usize = 1;
    while (optind < args.len) {
        const arg = args[optind];
        // Negative numbers look like '-' followed by digit or '.'
        if (arg.len >= 2 and arg[0] == '-' and (arg[1] == '.' or std.ascii.isDigit(arg[1]))) {
            break;
        }

        if (std.mem.eql(u8, arg, "--")) {
            optind += 1;
            break;
        }

        if (std.mem.startsWith(u8, arg, "--")) {
            const eq_pos = std.mem.indexOfScalar(u8, arg, '=');
            const opt_name = if (eq_pos) |pos| arg[0..pos] else arg;
            const val_in_opt = if (eq_pos) |pos| arg[pos + 1 ..] else null;

            if (std.mem.startsWith(u8, "--help", opt_name)) {
                try printHelp(stdout);
                try stdout.flush();
                return 0;
            } else if (std.mem.startsWith(u8, "--version", opt_name)) {
                try printVersion(stdout);
                try stdout.flush();
                return 0;
            } else if (std.mem.startsWith(u8, "--equal-width", opt_name)) {
                if (val_in_opt != null) {
                    try stderr.print("seq: option '{s}' doesn't allow an argument\nTry 'seq --help' for more information.\n", .{opt_name});
                    try stderr.flush();
                    return 1;
                }
                equal_width = true;
                optind += 1;
            } else if (std.mem.startsWith(u8, "--format", opt_name)) {
                const val = if (val_in_opt) |v| v else blk: {
                    optind += 1;
                    if (optind >= args.len) {
                        try stderr.print("seq: option '{s}' requires an argument\nTry 'seq --help' for more information.\n", .{opt_name});
                        try stderr.flush();
                        return 1;
                    }
                    break :blk args[optind];
                };
                format_str = val;
                optind += 1;
            } else if (std.mem.startsWith(u8, "--separator", opt_name)) {
                const val = if (val_in_opt) |v| v else blk: {
                    optind += 1;
                    if (optind >= args.len) {
                        try stderr.print("seq: option '{s}' requires an argument\nTry 'seq --help' for more information.\n", .{opt_name});
                        try stderr.flush();
                        return 1;
                    }
                    break :blk args[optind];
                };
                separator = val;
                optind += 1;
            } else {
                try stderr.print("seq: unrecognized option '{s}'\nTry 'seq --help' for more information.\n", .{arg});
                try stderr.flush();
                return 1;
            }
        } else if (arg.len >= 2 and arg[0] == '-') {
            var j: usize = 1;
            while (j < arg.len) : (j += 1) {
                const c_opt = arg[j];
                switch (c_opt) {
                    'w' => {
                        equal_width = true;
                    },
                    's' => {
                        if (j + 1 < arg.len) {
                            separator = arg[j + 1 ..];
                            j = arg.len;
                        } else {
                            optind += 1;
                            if (optind >= args.len) {
                                try stderr.print("seq: option requires an argument -- 's'\nTry 'seq --help' for more information.\n", .{});
                                try stderr.flush();
                                return 1;
                            }
                            separator = args[optind];
                        }
                    },
                    'f' => {
                        if (j + 1 < arg.len) {
                            format_str = arg[j + 1 ..];
                            j = arg.len;
                        } else {
                            optind += 1;
                            if (optind >= args.len) {
                                try stderr.print("seq: option requires an argument -- 'f'\nTry 'seq --help' for more information.\n", .{});
                                try stderr.flush();
                                return 1;
                            }
                            format_str = args[optind];
                        }
                    },
                    else => {
                        try stderr.print("seq: invalid option -- '{c}'\nTry 'seq --help' for more information.\n", .{c_opt});
                        try stderr.flush();
                        return 1;
                    },
                }
            }
            optind += 1;
        } else {
            break;
        }
    }

    const n_args = args.len - optind;
    if (n_args < 1) {
        try stderr.print("seq: missing operand\nTry 'seq --help' for more information.\n", .{});
        try stderr.flush();
        return 1;
    }
    if (n_args > 3) {
        try stderr.print("seq: extra operand '{s}'\nTry 'seq --help' for more information.\n", .{args[optind + 3]});
        try stderr.flush();
        return 1;
    }

    if (format_str != null and equal_width) {
        try stderr.print("seq: format string may not be specified when printing equal width strings\nTry 'seq --help' for more information.\n", .{});
        try stderr.flush();
        return 1;
    }

    var layout: Layout = .{};
    var transformed_fmt: ?[:0]const u8 = null;
    defer if (transformed_fmt) |tf| allocator.free(tf);

    if (format_str) |fs| {
        transformed_fmt = validateAndTransformFormat(allocator, fs, &layout, stderr) catch return 1;
    }

    const user_start = if (n_args == 1) "1" else args[optind];

    var fast_step_ok = false;
    var step_val: usize = 1;
    if (n_args != 3) {
        fast_step_ok = true;
    } else if (allDigits(args[optind + 1])) {
        if (std.fmt.parseInt(usize, args[optind + 1], 10)) |sv| {
            if (sv > 0 and sv <= 200) {
                step_val = sv;
                fast_step_ok = true;
            }
        } else |_| {}
    }

    if (allDigits(args[optind]) and
        (n_args == 1 or allDigits(args[optind + 1])) and
        (n_args < 3 or (fast_step_ok and allDigits(args[optind + 2]))) and
        !equal_width and format_str == null and separator.len == 1)
    {
        const s1 = user_start;
        const s2 = args[optind + (n_args - 1)];
        return seqFast(allocator, s1, s2, step_val, separator[0], '\n');
    }

    var first = Operand{ .value = 1.0, .width = 1, .precision = 0 };
    var step = Operand{ .value = 1.0, .width = 1, .precision = 0 };
    var last: Operand = undefined;

    last = scanArg(allocator, args[optind], stderr) catch return 1;
    optind += 1;

    if (optind < args.len) {
        first = last;
        last = scanArg(allocator, args[optind], stderr) catch return 1;
        optind += 1;

        if (optind < args.len) {
            step = last;
            if (step.value == 0) {
                try stderr.print("seq: invalid Zero increment value: '{s}'\nTry 'seq --help' for more information.\n", .{args[optind - 1]});
                try stderr.flush();
                return 1;
            }
            last = scanArg(allocator, args[optind], stderr) catch return 1;
            optind += 1;
        }
    }

    if (first.precision == 0 and step.precision == 0 and last.precision == 0 and
        (first.value * 0.0 == 0.0) and first.value >= 0 and last.value >= 0 and
        step.value > 0 and step.value <= 200 and
        !equal_width and format_str == null and separator.len == 1)
    {
        const step_int: usize = @intFromFloat(step.value);
        if (@as(c_longdouble, @floatFromInt(step_int)) == step.value) {
            const s1 = if (allDigits(user_start))
                try allocator.dupe(u8, user_start)
            else blk: {
                var buf: [128]u8 = undefined;
                const n = c.snprintf(&buf, buf.len, "%0.Lf", first.value);
                break :blk try allocator.dupe(u8, buf[0..@intCast(n)]);
            };
            defer allocator.free(s1);

            const is_last_finite = (last.value * 0.0 == 0.0);
            const s2 = if (!is_last_finite)
                try allocator.dupe(u8, "inf")
            else blk: {
                var buf: [128]u8 = undefined;
                const n = c.snprintf(&buf, buf.len, "%0.Lf", last.value);
                break :blk try allocator.dupe(u8, buf[0..@intCast(n)]);
            };
            defer allocator.free(s2);

            if (s1.len > 0 and s1[0] != '-' and s2.len > 0 and s2[0] != '-') {
                return seqFast(allocator, s1, s2, step_int, separator[0], '\n');
            }
        }
    }

    const effective_fmt = if (transformed_fmt) |tf|
        tf
    else
        try getDefaultFormat(allocator, first, step, last, equal_width);
    defer if (transformed_fmt == null) allocator.free(effective_fmt);

    return printNumbers(allocator, effective_fmt, layout, first.value, step.value, last.value, separator);
}
