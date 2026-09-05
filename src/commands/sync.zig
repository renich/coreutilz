const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "sync";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, _: std.mem.Allocator) !u8 {
    var stdout_buffer: [4096]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .init(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var files_start: usize = args.len;

    // Parse options
    for (args[1..], 1..) |arg, i| {
        if (std.mem.eql(u8, arg, "--help")) {
            try printHelp(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try printVersion(stdout);
            return 0;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            try errors.printError(stderr, name, try std.fmt.allocPrint(std.heap.page_allocator, "invalid option -- '{s}'", .{arg}));
            return 1;
        } else {
            files_start = i;
            break;
        }
    }

    var ok = true;
    if (files_start < args.len) {
        for (args[files_start..]) |file_path| {
            const file = std.Io.Dir.cwd().openFile(std.Options.debug_io, file_path, .{}) catch blk: {
                break :blk std.Io.Dir.cwd().openFile(std.Options.debug_io, file_path, .{ .mode = .write_only }) catch |err| {
                    try errors.printErrorWithArg(stderr, name, file_path, err);
                    ok = false;
                    continue;
                };
            };
            defer file.close(std.Options.debug_io);
            file.sync(std.Options.debug_io) catch |err| {
                try errors.printErrorWithArg(stderr, name, file_path, err);
                ok = false;
                continue;
            };
        }
    } else {
        std.posix.sync();
    }

    return if (ok) 0 else 1;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: sync [OPTION] [FILE]...
        \\Force changed blocks to disk, update the super block.
        \\
        \\      --help     display this help and exit
        \\      --version  output version information and exit
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
