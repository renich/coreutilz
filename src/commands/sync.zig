const std = @import("std");
const errors = @import("../utils/errors.zig");

const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "sync";
pub const version: []const u8 = "0.1.0";

const Mode = enum {
    file,
    data,
    file_system,
    sync_all,
};

fn syncArg(mode: Mode, file_path: []const u8, allocator: std.mem.Allocator, stderr: anytype) bool {
    var path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const path_z: [*:0]const u8 = if (file_path.len < path_buf.len) blk: {
        @memcpy(path_buf[0..file_path.len], file_path);
        path_buf[file_path.len] = 0;
        break :blk @ptrCast(&path_buf);
    } else blk: {
        const allocated = allocator.dupeZ(u8, file_path) catch {
            stderr.print("sync: error opening '{s}': Out of memory\n", .{file_path}) catch {};
            return false;
        };
        break :blk allocated.ptr;
    };
    defer {
        if (file_path.len >= path_buf.len) {
            allocator.free(std.mem.span(path_z));
        }
    }

    const open_flags: c_int = c.O_RDONLY | c.O_NONBLOCK;

    var fd = c.open(path_z, open_flags);
    if (fd < 0) {
        const rd_errno = c.__errno_location().*;
        if (open_flags != (c.O_WRONLY | c.O_NONBLOCK)) {
            fd = c.open(path_z, c.O_WRONLY | c.O_NONBLOCK);
        }
        if (fd < 0) {
            const err_str = std.mem.span(c.strerror(rd_errno));
            stderr.print("sync: error opening '{s}': {s}\n", .{ file_path, err_str }) catch {};
            return false;
        }
    }

    var ret = true;
    const fdflags = c.fcntl(fd, c.F_GETFL);
    if (fdflags == -1 or c.fcntl(fd, c.F_SETFL, fdflags & ~c.O_NONBLOCK) < 0) {
        const err_str = std.mem.span(c.strerror(c.__errno_location().*));
        stderr.print("sync: couldn't reset non-blocking mode '{s}': {s}\n", .{ file_path, err_str }) catch {};
        ret = false;
    }

    if (ret) {
        var sync_status: c_int = -1;
        switch (mode) {
            .data => {
                sync_status = c.fdatasync(fd);
            },
            .file => {
                sync_status = c.fsync(fd);
            },
            .file_system => {
                sync_status = c.syncfs(fd);
            },
            .sync_all => unreachable,
        }

        if (sync_status < 0) {
            const err_str = std.mem.span(c.strerror(c.__errno_location().*));
            stderr.print("sync: error syncing '{s}': {s}\n", .{ file_path, err_str }) catch {};
            ret = false;
        }
    }

    if (c.close(fd) < 0) {
        const err_str = std.mem.span(c.strerror(c.__errno_location().*));
        stderr.print("sync: failed to close '{s}': {s}\n", .{ file_path, err_str }) catch {};
        ret = false;
    }

    return ret;
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

    var arg_data = false;
    var arg_file_system = false;
    var parse_options = true;

    var files: std.ArrayListUnmanaged([]const u8) = .empty;
    defer files.deinit(allocator);

    if (args.len > 1) {
        for (args[1..]) |arg| {
            if (parse_options and std.mem.eql(u8, arg, "--")) {
                parse_options = false;
                continue;
            }

            if (parse_options and std.mem.startsWith(u8, arg, "--") and arg.len > 2) {
                if (std.mem.eql(u8, arg, "--data")) {
                    arg_data = true;
                } else if (std.mem.eql(u8, arg, "--file-system")) {
                    arg_file_system = true;
                } else if (std.mem.eql(u8, arg, "--help")) {
                    printHelp(stdout) catch return 1;
                    stdout.flush() catch return 1;
                    return 0;
                } else if (std.mem.eql(u8, arg, "--version")) {
                    printVersion(stdout) catch return 1;
                    stdout.flush() catch return 1;
                    return 0;
                } else {
                    try errors.printUnrecognizedOption(stderr, name, arg);
                    return 1;
                }
            } else if (parse_options and std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
                for (arg[1..]) |ch| {
                    switch (ch) {
                        'd' => arg_data = true,
                        'f' => arg_file_system = true,
                        else => {
                            try errors.printInvalidOption(stderr, name, ch);
                            return 1;
                        },
                    }
                }
            } else {
                try files.append(allocator, arg);
            }
        }
    }

    if (arg_data and arg_file_system) {
        try stderr.print("sync: cannot specify both --data and --file-system\n", .{});
        return 1;
    }

    if (files.items.len == 0 and arg_data) {
        try stderr.print("sync: --data needs at least one argument\n", .{});
        return 1;
    }

    const mode: Mode = if (files.items.len == 0)
        .sync_all
    else if (arg_file_system)
        .file_system
    else if (!arg_data)
        .file
    else
        .data;

    var ok = true;
    if (mode == .sync_all) {
        c.sync();
    } else {
        for (files.items) |file| {
            if (!syncArg(mode, file, allocator, stderr)) {
                ok = false;
            }
        }
    }

    return if (ok) 0 else 1;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: sync [OPTION] [FILE]...
        \\Synchronize cached writes to persistent storage
        \\
        \\If one or more files are specified, sync only them,
        \\or their containing file systems.
        \\
        \\  -d, --data             sync only file data, no unneeded metadata
        \\  -f, --file-system      sync the file systems that contain the files
        \\      --help     display this help and exit
        \\      --version  output version information and exit
        \\
        \\GNU coreutils online help: <https://www.gnu.org/software/coreutils/>
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
