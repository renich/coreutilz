const std = @import("std");
const c = @import("../compat/c.zig").c;
const types = @import("numfmt/types.zig");
const scale = @import("numfmt/scale.zig");

pub const name: []const u8 = "numfmt";
pub const version: []const u8 = "0.1.0";

pub const Scale = types.Scale;
pub const RoundMethod = types.RoundMethod;
pub const InvalidMode = types.InvalidMode;
pub const NumfmtConfig = types.NumfmtConfig;

fn parseArgs(cfg: *NumfmtConfig, operands: *std.ArrayList([]const u8), args: [][]const u8, allocator: std.mem.Allocator) !?u8 {
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            var buf: [256]u8 = undefined;
            var w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &buf);
            try w.interface.print("Usage: numfmt [OPTION]... [NUMBER]...\nReformat NUMBER(s), or the numbers from standard input if none are specified.\n", .{});
            w.interface.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            var buf: [256]u8 = undefined;
            var w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &buf);
            try w.interface.print("numfmt (coreutilz) {s}\n", .{version});
            w.interface.flush() catch return 1;
            return 0;
        } else if (std.mem.startsWith(u8, arg, "--from=")) {
            cfg.scale_from = try types.parseScale(arg["--from=".len..]);
        } else if (std.mem.startsWith(u8, arg, "--to=")) {
            cfg.scale_to = try types.parseScale(arg["--to=".len..]);
        } else if (std.mem.startsWith(u8, arg, "--round=")) {
            cfg.round = try types.parseRound(arg["--round=".len..]);
        } else if (std.mem.startsWith(u8, arg, "--invalid=")) {
            cfg.invalid = try types.parseInvalid(arg["--invalid=".len..]);
        } else if (std.mem.startsWith(u8, arg, "--field=")) {
            cfg.field = try std.fmt.parseInt(usize, arg["--field=".len..], 10);
        } else if (std.mem.startsWith(u8, arg, "--padding=")) {
            cfg.padding = try std.fmt.parseInt(i32, arg["--padding=".len..], 10);
        } else if (std.mem.startsWith(u8, arg, "--suffix=")) {
            cfg.suffix = arg["--suffix=".len..];
        } else if (std.mem.startsWith(u8, arg, "-") and !std.mem.eql(u8, arg, "-")) {
            return 1;
        } else {
            try operands.append(allocator, arg);
        }
    }
    return null;
}

fn processOne(writer: anytype, input_str: []const u8, cfg: *const NumfmtConfig) !u8 {
    var num_buf: [128]u8 = undefined;
    const val = scale.parseNumber(input_str, cfg.scale_from) catch {
        switch (cfg.invalid) {
            .abort, .fail => {
                var err_buf: [256]u8 = undefined;
                var ew = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &err_buf);
                try ew.interface.print("numfmt: invalid number: '{s}'\n", .{input_str});
                ew.interface.flush() catch {};
                try writer.writeAll(input_str);
                return 2;
            },
            .warn => {
                var err_buf: [256]u8 = undefined;
                var ew = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &err_buf);
                try ew.interface.print("numfmt: invalid number: '{s}'\n", .{input_str});
                ew.interface.flush() catch {};
                try writer.writeAll(input_str);
                return 0;
            },
            .ignore => {
                try writer.writeAll(input_str);
                return 0;
            },
        }
    };

    const out_str = try scale.formatNumber(&num_buf, val, cfg.scale_to, cfg.round, cfg.suffix);
    if (cfg.padding > 0) {
        const p = @as(usize, @intCast(cfg.padding));
        if (out_str.len < p) {
            for (0..(p - out_str.len)) |_| try writer.writeByte(' ');
        }
    }
    try writer.writeAll(out_str);
    if (cfg.padding < 0) {
        const p = @as(usize, @intCast(-cfg.padding));
        if (out_str.len < p) {
            for (0..(p - out_str.len)) |_| try writer.writeByte(' ');
        }
    }
    return 0;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var cfg = NumfmtConfig{};
    var operands: std.ArrayList([]const u8) = .empty;
    defer operands.deinit(allocator);

    if (parseArgs(&cfg, &operands, args, allocator) catch return 1) |code| return code;

    var out_buf: [16384]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &out_buf);
    const writer = &out_w.interface;

    var max_rc: u8 = 0;

    if (operands.items.len > 0) {
        for (operands.items) |op| {
            const rc = processOne(writer, op, &cfg) catch return 1;
            if (rc > max_rc) max_rc = rc;
            try writer.writeByte('\n');
        }
    } else {
        var in_buf: [16384]u8 = undefined;
        var line_buf: std.ArrayList(u8) = .empty;
        defer line_buf.deinit(allocator);

        while (true) {
            const nr = c.read(c.STDIN_FILENO, &in_buf, in_buf.len);
            if (nr <= 0) break;
            for (in_buf[0..@as(usize, @intCast(nr))]) |b| {
                if (b == '\n') {
                    const rc = processOne(writer, line_buf.items, &cfg) catch return 1;
                    if (rc > max_rc) max_rc = rc;
                    try writer.writeByte('\n');
                    line_buf.clearRetainingCapacity();
                } else {
                    try line_buf.append(allocator, b);
                }
            }
        }
        if (line_buf.items.len > 0) {
            const rc = processOne(writer, line_buf.items, &cfg) catch return 1;
            if (rc > max_rc) max_rc = rc;
        }
    }

    out_w.interface.flush() catch return 1;
    return max_rc;
}
