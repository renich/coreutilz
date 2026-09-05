const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "rm";
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

    var recursive = false;
    var force = false;
    var verbose = false;
    var dir_flag = false;
    var files_start: usize = args.len;
    var end_of_opts = false;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (end_of_opts or !std.mem.startsWith(u8, arg, "-") or arg.len == 1) {
            files_start = i;
            break;
        }
        if (std.mem.eql(u8, arg, "--")) {
            end_of_opts = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--help")) {
            try printHelp(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try printVersion(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "-R") or std.mem.eql(u8, arg, "--recursive")) {
            recursive = true;
        } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--force")) {
            force = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--dir")) {
            dir_flag = true;
        } else if (arg[0] == '-') {
            var j: usize = 1;
            while (j < arg.len) : (j += 1) {
                const c = arg[j];
                switch (c) {
                    'r', 'R' => recursive = true,
                    'f' => force = true,
                    'v' => verbose = true,
                    'd' => dir_flag = true,
                    'i', 'I' => {},
                    else => {
                        const msg = try std.fmt.allocPrint(allocator, "invalid option -- '{c}'", .{c});
                        defer allocator.free(msg);
                        try errors.printError(stderr, name, msg);
                        return 1;
                    },
                }
            }
        }
    }

    if (files_start >= args.len) {
        if (!force) {
            try errors.printError(stderr, name, "missing operand");
            return 1;
        }
        return 0;
    }

    var exit_status: u8 = 0;

    for (args[files_start..]) |file_path| {
        const stat = std.Io.Dir.cwd().statFile(std.Options.debug_io, file_path, .{ .follow_symlinks = false }) catch |err| {
            if (force and err == error.FileNotFound) continue;
            try errors.printErrorWithArg(stderr, name, file_path, err);
            exit_status = 1;
            continue;
        };

        if (stat.kind == .directory) {
            if (recursive) {
                const ok = try removeTree(allocator, file_path, force, verbose, stdout, stderr);
                if (!ok) exit_status = 1;
            } else if (dir_flag) {
                std.Io.Dir.cwd().deleteDir(std.Options.debug_io, file_path) catch |err| {
                    if (!force) {
                        try errors.printErrorWithArg(stderr, name, file_path, err);
                        exit_status = 1;
                    }
                    continue;
                };
                if (verbose) {
                    try stdout.print("removed directory '{s}'\n", .{file_path});
                }
            } else {
                if (!force) {
                    const msg = try std.fmt.allocPrint(allocator, "cannot remove '{s}': Is a directory", .{file_path});
                    defer allocator.free(msg);
                    try errors.printError(stderr, name, msg);
                    exit_status = 1;
                }
            }
        } else {
            std.Io.Dir.cwd().deleteFile(std.Options.debug_io, file_path) catch |err| {
                if (!force) {
                    try errors.printErrorWithArg(stderr, name, file_path, err);
                    exit_status = 1;
                }
                continue;
            };
            if (verbose) {
                try stdout.print("removed '{s}'\n", .{file_path});
            }
        }
    }

    return exit_status;
}

fn removeTree(
    allocator: std.mem.Allocator,
    dir_path: []const u8,
    force: bool,
    verbose: bool,
    stdout: anytype,
    stderr: anytype,
) anyerror!bool {
    var dir = std.Io.Dir.cwd().openDir(std.Options.debug_io, dir_path, .{ .iterate = true }) catch |err| {
        if (!force) {
            try errors.printErrorWithArg(stderr, name, dir_path, err);
        }
        return false;
    };
    defer dir.close(std.Options.debug_io);

    var ok = true;
    var it = dir.iterate();
    while (it.next(std.Options.debug_io) catch null) |entry| {
        const sub_path = try std.fs.path.join(allocator, &[_][]const u8{ dir_path, entry.name });
        defer allocator.free(sub_path);

        if (entry.kind == .directory) {
            const sub_ok = try removeTree(allocator, sub_path, force, verbose, stdout, stderr);
            if (!sub_ok) ok = false;
        } else {
            std.Io.Dir.cwd().deleteFile(std.Options.debug_io, sub_path) catch |err| {
                if (!force) {
                    try errors.printErrorWithArg(stderr, name, sub_path, err);
                }
                ok = false;
                continue;
            };
            if (verbose) {
                try stdout.print("removed '{s}'\n", .{sub_path});
            }
        }
    }

    std.Io.Dir.cwd().deleteDir(std.Options.debug_io, dir_path) catch |err| {
        if (!force) {
            try errors.printErrorWithArg(stderr, name, dir_path, err);
        }
        return false;
    };
    if (verbose) {
        try stdout.print("removed directory '{s}'\n", .{dir_path});
    }
    return ok;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: rm [OPTION]... [FILE]...
        \\Remove (unlink) the FILE(s).
        \\
        \\  -f, --force           ignore nonexistent files and arguments, never prompt
        \\  -i                    prompt before every removal
        \\  -I                    prompt once before removing more than three files, or
        \\                        when removing recursively; less intrusive than -i,
        \\                        while still giving protection against most mistakes
        \\  -d, --dir             remove empty directories
        \\  -r, -R, --recursive   remove directories and their contents recursively
        \\  -v, --verbose         explain what is being done
        \\      --help            display this help and exit
        \\      --version         output version information and exit
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
