const std = @import("std");
const errors = @import("errors.zig");
const signals = @import("signals.zig");
const args_mod = @import("args.zig");

/// Standard entrypoint runner for standalone command binaries.
/// Restores Unix signals, parses CLI arguments, invokes the command run function,
/// handles fatal runtime errors without panicking or dumping compiler traces,
/// and exits with the returned exit code.
pub fn runWrapper(
    comptime cmd_name: []const u8,
    comptime runFn: anytype,
    init: std.process.Init.Minimal,
) u8 {
    signals.restoreDefaultSignals();
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = args_mod.getArgs(init.args, allocator) catch |err| {
        handleError(cmd_name, err);
        return 1;
    };
    const exit_code = runFn(args, allocator) catch |err| {
        handleError(cmd_name, err);
        return 1;
    };
    return exit_code;
}

fn handleError(command: []const u8, err: anyerror) void {
    var stderr_buf: [256]u8 = undefined;
    var stderr_writer = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stderr = &stderr_writer.interface;
    switch (err) {
        error.OutOfMemory => {
            stderr.print("{s}: memory exhausted\n", .{command}) catch {};
        },
        error.BrokenPipe => {
            stderr.print("{s}: write error: Broken pipe\n", .{command}) catch {};
        },
        error.WriteFailed, error.DiskFull, error.NoSpaceLeft => {
            stderr.print("{s}: write error: {s}\n", .{ command, errors.errorDescription(err) }) catch {};
        },
        else => {
            stderr.print("{s}: {s}\n", .{ command, errors.errorDescription(err) }) catch {};
        },
    }
    stderr.flush() catch {};
}
