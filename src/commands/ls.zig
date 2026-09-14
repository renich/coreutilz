const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const types = @import("ls/types.zig");
pub const collector = @import("ls/collector.zig");
pub const formatter = @import("ls/formatter.zig");
pub const args_mod = @import("ls/args.zig");
pub const traversal = @import("ls/traversal.zig");

const help_mod = @import("ls/help.zig");

pub const printHelp = help_mod.printHelp;
pub const name: []const u8 = "ls";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    return runProfile(args, allocator, .columns, name);
}

pub fn runProfile(
    args: [][]const u8,
    allocator: std.mem.Allocator,
    default_format: types.FormatMode,
    prog_name: []const u8,
) !u8 {
    var stdout_buf: [16384]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), std.Options.debug_io, &stdout_buf);
    var stderr_writer: std.Io.File.Writer = .init(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    const is_ls = std.mem.eql(u8, prog_name, "ls");
    const action = try args_mod.parseArgs(args, default_format, is_ls, prog_name, allocator, stderr);

    switch (action) {
        .help => {
            try printHelp(stdout, prog_name);
            stdout.flush() catch return 2;
            return 0;
        },
        .version => {
            try errors.printVersion(stdout, prog_name, version);
            stdout.flush() catch return 2;
            return 0;
        },
        .error_exit => |code| return code,
        .proceed => |data| {
            const rc = try traversal.executeListing(data.paths, &data.options, prog_name, allocator, stdout, stderr);
            stdout.flush() catch return 2;
            return rc;
        },
    }
}
