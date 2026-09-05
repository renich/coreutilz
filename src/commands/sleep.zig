const std = @import("std");
const errors = @import("../utils/errors.zig");

const c = @cImport({
    @cInclude("stdlib.h");
});

pub const name: []const u8 = "sleep";
pub const version: []const u8 = "0.1.0";

fn applySuffix(val: *f64, suffix: u8) bool {
    const mult: f64 = switch (suffix) {
        0, 's' => 1.0,
        'm' => 60.0,
        'h' => 3600.0,
        'd' => 86400.0,
        else => return false,
    };
    val.* *= mult;
    return true;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buffer: [4096]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .init(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    if (args.len < 2) {
        try errors.printError(stderr, name, "missing operand");
        return 1;
    }

    var arg_start: usize = 1;
    while (arg_start < args.len) : (arg_start += 1) {
        const arg = args[arg_start];
        if (std.mem.eql(u8, arg, "--help")) {
            try printHelp(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try printVersion(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "--")) {
            arg_start += 1;
            break;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            try errors.printError(stderr, name, try std.fmt.allocPrint(allocator, "unrecognized option '{s}'", .{arg}));
            return 1;
        } else {
            break;
        }
    }

    if (arg_start >= args.len) {
        try errors.printError(stderr, name, "missing operand");
        return 1;
    }

    var total_seconds: f64 = 0;
    var ok = true;

    for (args[arg_start..]) |arg| {
        const arg_z = try allocator.dupeZ(u8, arg);
        defer allocator.free(arg_z);

        var endptr: [*c]u8 = undefined;
        const val = c.strtod(arg_z.ptr, &endptr);

        if (endptr == arg_z.ptr or std.math.isNan(val) or val < 0) {
            try errors.printError(stderr, name, try std.fmt.allocPrint(allocator, "invalid time interval '{s}'", .{arg}));
            ok = false;
            continue;
        }

        var s = val;
        const suffix = endptr[0];
        if (suffix != 0 and endptr[1] != 0) {
            try errors.printError(stderr, name, try std.fmt.allocPrint(allocator, "invalid time interval '{s}'", .{arg}));
            ok = false;
            continue;
        }

        if (!applySuffix(&s, suffix)) {
            try errors.printError(stderr, name, try std.fmt.allocPrint(allocator, "invalid time interval '{s}'", .{arg}));
            ok = false;
            continue;
        }

        total_seconds += s;
    }

    if (!ok) return 1;

    if (total_seconds <= 0) return 0;

    const total_nanos = @as(i96, @intFromFloat(total_seconds * @as(f64, @floatFromInt(std.time.ns_per_s))));
    const duration = std.Io.Duration.fromNanoseconds(total_nanos);
    std.Options.debug_io.sleep(duration, .awake) catch {};

    return 0;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: sleep NUMBER[SUFFIX]...
        \\  or:  sleep OPTION
        \\Pause for NUMBER seconds.  SUFFIX may be 's' for seconds (the default),
        \\'m' for minutes, 'h' for hours or 'd' for days.  NUMBER need not be an
        \\integer.  Multiple NUMBERs are cumulative.
        \\
        \\      --help     display this help and exit
        \\      --version  output version information and exit
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
