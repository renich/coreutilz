const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "link";
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

    // Parse options
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            try printHelp(stdout);
            try stdout.flush();
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try printVersion(stdout);
            try stdout.flush();
            return 0;
        } else if (std.mem.startsWith(u8, arg, "-")) {
            try errors.printError(stderr, name, try std.fmt.allocPrint(std.heap.page_allocator, "invalid option -- '{s}'", .{arg}));
            return 1;
        } else {
            break;
        }
    }

    // Need exactly 2 arguments: FILE1 FILE2
    if (i + 2 < args.len) {
        try errors.printError(stderr, name, try std.fmt.allocPrint(std.heap.page_allocator, "extra operand '{s}'", .{args[i + 2]}));
        return 1;
    }
    if (i + 2 > args.len) {
        try errors.printError(stderr, name, "missing operand");
        return 1;
    }

    const file1 = args[i];
    const file2 = args[i + 1];

    // Create hard link
    std.Io.Dir.cwd().hardLink(file1, std.Io.Dir.cwd(), file2, std.Options.debug_io, .{}) catch |err| {
        try errors.printErrorWithArg(stderr, name, file2, err);
        return 1;
    };

    return 0;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: link FILE1 FILE2
        \\Call the link function to create a link named FILE2 to an existing FILE1.
        \\
        \\      --help     display this help and exit
        \\      --version  output version information and exit
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
