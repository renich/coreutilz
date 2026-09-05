const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "rmdir";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buffer: [4096]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .init(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var parents = false;
    var verbose = false;
    var ignore_non_empty = false;
    var files_start: usize = args.len;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            try printHelp(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try printVersion(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--parents")) {
            parents = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "--ignore-fail-on-non-empty")) {
            ignore_non_empty = true;
        } else if (std.mem.eql(u8, arg, "--")) {
            files_start = i + 1;
            break;
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1 and arg[1] != '-') {
            for (arg[1..]) |c| {
                switch (c) {
                    'p' => parents = true,
                    'v' => verbose = true,
                    else => {
                        const msg = try std.fmt.allocPrint(allocator, "invalid option -- '{c}'", .{c});
                        defer allocator.free(msg);
                        try errors.printError(stderr, name, msg);
                        return 1;
                    },
                }
            }
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            const msg = try std.fmt.allocPrint(allocator, "unrecognized option '{s}'", .{arg});
            defer allocator.free(msg);
            try errors.printError(stderr, name, msg);
            return 1;
        } else {
            files_start = i;
            break;
        }
    }

    if (files_start >= args.len) {
        try errors.printError(stderr, name, "missing operand");
        return 1;
    }

    var exit_status: u8 = 0;

    for (args[files_start..]) |dir_name| {
        if (verbose) {
            try stdout.print("{s}: removing directory, '{s}'\n", .{ name, dir_name });
        }

        var failed = false;
        std.Io.Dir.cwd().deleteDir(std.Options.debug_io, dir_name) catch |err| {
            if (ignore_non_empty and (err == error.DirNotEmpty or err == error.PathAlreadyExists)) {
                // Ignore failure on non-empty
            } else {
                try errors.printErrorWithArg(stderr, name, dir_name, err);
                exit_status = 1;
                failed = true;
            }
        };

        if (failed) continue;

        if (parents) {
            var path_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
            if (dir_name.len > path_buf.len) {
                exit_status = 1;
                continue;
            }
            @memcpy(path_buf[0..dir_name.len], dir_name);
            var path: []const u8 = path_buf[0..dir_name.len];

            // Strip trailing slashes
            while (path.len > 1 and path[path.len - 1] == '/') {
                path = path[0 .. path.len - 1];
            }

            while (true) {
                const last_slash = std.mem.lastIndexOfScalar(u8, path, '/') orelse break;
                var end = last_slash;
                while (end > 0 and path[end - 1] == '/') : (end -= 1) {}
                if (end == 0) {
                    break;
                }
                path = path[0..end];

                if (verbose) {
                    try stdout.print("{s}: removing directory, '{s}'\n", .{ name, path });
                }

                var parent_failed = false;
                std.Io.Dir.cwd().deleteDir(std.Options.debug_io, path) catch |err| {
                    if (ignore_non_empty and (err == error.DirNotEmpty or err == error.PathAlreadyExists)) {
                        parent_failed = true;
                        break;
                    } else {
                        try errors.printErrorWithArg(stderr, name, path, err);
                        exit_status = 1;
                        parent_failed = true;
                        break;
                    }
                };
                if (parent_failed) break;
            }
        }
    }

    return exit_status;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: rmdir [OPTION]... DIRECTORY...
        \\Remove the DIRECTORY(ies), if they are empty.
        \\
        \\      --ignore-fail-on-non-empty
        \\                  ignore each failure that is solely because a directory
        \\                  is non-empty
        \\  -p, --parents   remove DIRECTORY and its ancestors; e.g., 'rmdir -p a/b/c' is
        \\                  similar to 'rmdir a/b/c a/b a'
        \\  -v, --verbose   output a diagnostic for every directory processed
        \\      --help      display this help and exit
        \\      --version   output version information and exit
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
