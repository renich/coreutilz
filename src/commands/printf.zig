const std = @import("std");
const c = @import("../compat/c.zig").c;
const format = @import("printf/format.zig");

pub const name: []const u8 = "printf";
pub const version: []const u8 = "0.1.0";

fn checkSpecialArgs(args: [][]const u8, stdout: anytype) ?u8 {
    if (args.len == 2) {
        if (std.mem.eql(u8, args[1], "--help")) {
            stdout.print("Usage: printf FORMAT [ARGUMENT]...\nPrint ARGUMENT(s) according to FORMAT.\n", .{}) catch return 1;
            return 0;
        } else if (std.mem.eql(u8, args[1], "--version")) {
            stdout.print("printf (coreutilz) {s}\n", .{version}) catch return 1;
            return 0;
        }
    }
    return null;
}

fn loopFormat(fmt: []const u8, args_in: [][]const u8, ok: *bool, stdout: anytype, stderr: anytype, alloc: std.mem.Allocator) ![][]const u8 {
    var rest = args_in;
    while (true) {
        var ac = format.ArgCursor{ .f_idx = 0 };
        const keep_going = try format.printFormatted(fmt, rest, &ac, ok, stdout, stderr, alloc);
        if (!keep_going) break;
        const args_used: usize = if (ac.end_arg >= 0) @min(rest.len, @as(usize, @intCast(ac.end_arg + 1))) else 0;
        rest = rest[args_used..];
        if (args_used == 0 or rest.len == 0) break;
    }
    return rest;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    _ = c.setlocale(c.LC_ALL, "");

    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &out_w.interface;
    const stderr = &err_w.interface;

    if (checkSpecialArgs(args, stdout)) |rc| {
        stdout.flush() catch return 1;
        return rc;
    }

    var arg_idx: usize = 1;
    if (arg_idx < args.len and std.mem.eql(u8, args[arg_idx], "--")) arg_idx += 1;
    if (arg_idx >= args.len) {
        stderr.print("printf: missing operand\nTry 'printf --help' for more information.\n", .{}) catch {};
        stderr.flush() catch {};
        return 1;
    }

    const fmt = args[arg_idx];
    var ok = true;
    const rest = loopFormat(fmt, args[arg_idx + 1 ..], &ok, stdout, stderr, allocator) catch {
        stdout.flush() catch {};
        stderr.flush() catch {};
        return 1;
    };

    if (rest.len > 0) {
        stderr.print("printf: warning: ignoring excess arguments, starting with '{s}'\n", .{rest[0]}) catch {};
    }

    stdout.flush() catch return 1;
    stderr.flush() catch {};
    return if (ok) 0 else 1;
}
