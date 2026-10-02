const std = @import("std");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "arch";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    _ = allocator;
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &out_w.interface;
    const stderr = &err_w.interface;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            try stdout.print("Usage: arch [OPTION]...\nPrint machine architecture.\n", .{});
            stdout.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try stdout.print("arch (coreutilz) {s}\n", .{version});
            stdout.flush() catch return 1;
            return 0;
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            try stderr.print("arch: unrecognized option '{s}'\nTry 'arch --help' for more information.\n", .{arg});
            stderr.flush() catch {};
            return 1;
        } else {
            try stderr.print("arch: extra operand '{s}'\nTry 'arch --help' for more information.\n", .{arg});
            stderr.flush() catch {};
            return 1;
        }
    }

    var uts: c.struct_utsname = undefined;
    if (c.uname(&uts) != 0) return 1;
    const m_name = std.mem.sliceTo(&uts.machine, 0);
    try stdout.print("{s}\n", .{m_name});

    stdout.flush() catch return 1;
    return 0;
}
