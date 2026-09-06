const std = @import("std");
const errors = @import("../utils/errors.zig");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "nproc";
pub const version: []const u8 = "0.1.0";

fn getOmpNumThreads() ?u32 {
    const val = c.getenv("OMP_NUM_THREADS") orelse return null;
    const s = std.mem.span(val);
    if (s.len == 0) return null;
    const first_token = if (std.mem.indexOfScalar(u8, s, ',')) |idx| s[0..idx] else s;
    const num = std.fmt.parseInt(u32, first_token, 10) catch return null;
    if (num == 0) return null;
    return num;
}

fn getOmpThreadLimit() ?u32 {
    const val = c.getenv("OMP_THREAD_LIMIT") orelse return null;
    const s = std.mem.span(val);
    if (s.len == 0) return null;
    const num = std.fmt.parseInt(u32, s, 10) catch return null;
    if (num == 0) return null;
    return num;
}

fn parseIgnore(str: []const u8) ?u32 {
    var s = std.mem.trimStart(u8, str, " \t\r\n");
    if (s.len > 0 and s[0] == '+') {
        s = s[1..];
    }
    if (s.len == 0) return null;
    for (s) |ch| {
        if (!std.ascii.isDigit(ch)) return null;
    }
    return std.fmt.parseInt(u32, s, 10) catch null;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buffer: [4096]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var all_cpus = false;
    var ignore_count: u32 = 0;

    var idx: usize = 1;
    while (idx < args.len) : (idx += 1) {
        const arg = args[idx];
        if (std.mem.eql(u8, arg, "--help")) {
            printHelp(stdout) catch return 1;
            stdout.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            printVersion(stdout) catch return 1;
            stdout.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--all")) {
            all_cpus = true;
        } else if (std.mem.startsWith(u8, arg, "--ignore=")) {
            const num_str = arg["--ignore=".len..];
            if (parseIgnore(num_str)) |val| {
                ignore_count = val;
            } else {
                try errors.printError(stderr, name, try std.fmt.allocPrint(allocator, "invalid number '{s}'", .{num_str}));
                return 1;
            }
        } else if (std.mem.eql(u8, arg, "--ignore")) {
            idx += 1;
            if (idx >= args.len) {
                try errors.printError(stderr, name, "option '--ignore' requires an argument");
                return 1;
            }
            const num_str = args[idx];
            if (parseIgnore(num_str)) |val| {
                ignore_count = val;
            } else {
                try errors.printError(stderr, name, try std.fmt.allocPrint(allocator, "invalid number '{s}'", .{num_str}));
                return 1;
            }
        } else if (std.mem.startsWith(u8, arg, "-")) {
            try errors.printError(stderr, name, try std.fmt.allocPrint(allocator, "unrecognized option '{s}'", .{arg}));
            return 1;
        } else {
            try errors.printExtraOperand(stderr, name, arg);
            return 1;
        }
    }

    const conf = if (all_cpus) c._SC_NPROCESSORS_CONF else c._SC_NPROCESSORS_ONLN;
    var cpu_count = c.sysconf(conf);
    if (cpu_count < 1) {
        // Fallback to 1 if sysconf fails
        cpu_count = 1;
    }

    var result: u32 = @as(u32, @intCast(cpu_count));
    if (!all_cpus) {
        if (getOmpNumThreads()) |omp_threads| {
            result = omp_threads;
        }
        if (getOmpThreadLimit()) |omp_limit| {
            result = @min(result, omp_limit);
        }
    }

    if (result > ignore_count) {
        result -= ignore_count;
    } else {
        result = 1;
    }

    stdout.print("{d}\n", .{result}) catch return 1;
    stdout.flush() catch return 1;
    return 0;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: nproc [OPTION]...
        \\Print the number of processing units available.
        \\
        \\      --all       print the number of installed CPUs
        \\      --ignore=N  if possible, exclude N processing units
        \\      --help      display this help and exit
        \\      --version   output version information and exit
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
