const std = @import("std");
const errors = @import("../utils/errors.zig");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "rmdir";
pub const version: []const u8 = "0.1.0";

fn stripTrailingSlashes(path: []const u8) []const u8 {
    if (path.len <= 1) return path;
    var end = path.len;
    while (end > 1 and path[end - 1] == '/') {
        end -= 1;
    }
    return path[0..end];
}

fn isDirectoryNonEmpty(path: []const u8) bool {
    var dir = std.Io.Dir.cwd().openDir(std.Options.debug_io, path, .{ .iterate = true }) catch return false;
    defer dir.close(std.Options.debug_io);
    var it = dir.iterate();
    if (it.next(std.Options.debug_io) catch null) |_| {
        return true;
    }
    return false;
}

fn ignorableFailure(errnum: c_int, dir: []const u8, ignore_non_empty: bool) bool {
    if (!ignore_non_empty) return false;
    if (errnum == c.ENOTEMPTY or errnum == c.EEXIST) return true;
    if (errnum == c.EACCES or errnum == c.EPERM or errnum == c.EROFS or errnum == c.EBUSY) {
        return isDirectoryNonEmpty(dir);
    }
    return false;
}

fn isSymlink(path: []const u8, allocator: std.mem.Allocator) bool {
    const path_z = allocator.dupeZ(u8, path) catch return false;
    defer allocator.free(path_z);
    var st: c.struct_stat = undefined;
    if (c.lstat(path_z.ptr, &st) == 0) {
        return c.S_ISLNK(st.st_mode);
    }
    return false;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    _ = c.signal(c.SIGPIPE, c.SIG_DFL);

    var stdout_buffer: [4096]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var parents = false;
    var verbose = false;
    var ignore_non_empty = false;

    var dir_operands: std.ArrayList([]const u8) = .empty;
    defer dir_operands.deinit(allocator);

    var parsing_options = true;
    const posixly_correct = errors.isPosixlyCorrect();

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (parsing_options and std.mem.eql(u8, arg, "--")) {
            parsing_options = false;
            continue;
        }

        if (parsing_options and std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            if (std.mem.startsWith(u8, arg, "--")) {
                if (std.mem.eql(u8, arg, "--help")) {
                    printHelp(stdout) catch return 1;
                    stdout.flush() catch return 1;
                    return 0;
                } else if (std.mem.eql(u8, arg, "--version")) {
                    printVersion(stdout) catch return 1;
                    stdout.flush() catch return 1;
                    return 0;
                } else if (std.mem.eql(u8, arg, "--parents")) {
                    parents = true;
                } else if (std.mem.eql(u8, arg, "--verbose")) {
                    verbose = true;
                } else if (std.mem.eql(u8, arg, "--ignore-fail-on-non-empty")) {
                    ignore_non_empty = true;
                } else {
                    try errors.printUnrecognizedOption(stderr, name, arg);
                    return 1;
                }
            } else {
                for (arg[1..]) |ch| {
                    switch (ch) {
                        'p' => parents = true,
                        'v' => verbose = true,
                        else => {
                            try errors.printInvalidOption(stderr, name, ch);
                            return 1;
                        },
                    }
                }
            }
        } else {
            try dir_operands.append(allocator, arg);
            if (posixly_correct) {
                parsing_options = false;
            }
        }
    }

    if (dir_operands.items.len == 0) {
        try errors.printMissingOperand(stderr, name);
        return 1;
    }

    var exit_status: u8 = 0;

    for (dir_operands.items) |dir_name| {
        if (verbose) {
            try stdout.print("{s}: removing directory, '{s}'\n", .{ name, dir_name });
        }

        const dir_z = try allocator.dupeZ(u8, dir_name);
        defer allocator.free(dir_z);

        if (c.rmdir(dir_z.ptr) != 0) {
            const err = c.__errno_location().*;
            if (ignorableFailure(err, dir_name, ignore_non_empty)) {
                continue;
            }

            var custom_error = false;
            if (err == c.ENOTDIR and dir_name.len > 0 and dir_name[dir_name.len - 1] == '/') {
                var st: c.struct_stat = undefined;
                const ret = c.stat(dir_z.ptr, &st);
                const stat_err = c.__errno_location().*;
                if ((ret != 0 and stat_err != c.ENOTDIR) or (ret == 0 and c.S_ISDIR(st.st_mode))) {
                    const stripped = stripTrailingSlashes(dir_name);
                    if (isSymlink(stripped, allocator)) {
                        try stderr.print("{s}: failed to remove '{s}': Symbolic link not followed\n", .{ name, dir_name });
                        custom_error = true;
                    }
                }
            }

            if (!custom_error) {
                const msg = std.mem.span(c.strerror(err));
                try stderr.print("{s}: failed to remove '{s}': {s}\n", .{ name, dir_name, msg });
            }
            exit_status = 1;
        } else if (parents) {
            var current_parent = try allocator.dupe(u8, stripTrailingSlashes(dir_name));
            defer allocator.free(current_parent);

            while (true) {
                const last_slash = std.mem.lastIndexOfScalar(u8, current_parent, '/');
                if (last_slash == null) break;
                var slash_idx = last_slash.?;
                while (slash_idx > 0 and current_parent[slash_idx - 1] == '/') {
                    slash_idx -= 1;
                }
                if (slash_idx == 0) break;

                const parent_dir = current_parent[0..slash_idx];
                current_parent = try allocator.dupe(u8, parent_dir);

                if (verbose) {
                    try stdout.print("{s}: removing directory, '{s}'\n", .{ name, parent_dir });
                }

                const p_z = try allocator.dupeZ(u8, parent_dir);
                defer allocator.free(p_z);

                if (c.rmdir(p_z.ptr) != 0) {
                    const p_err = c.__errno_location().*;
                    if (ignorableFailure(p_err, parent_dir, ignore_non_empty)) {
                        // ignore
                    } else {
                        const msg = std.mem.span(c.strerror(p_err));
                        if (p_err != c.ENOTDIR) {
                            try stderr.print("{s}: failed to remove directory '{s}': {s}\n", .{ name, parent_dir, msg });
                        } else {
                            try stderr.print("{s}: failed to remove '{s}': {s}\n", .{ name, parent_dir, msg });
                        }
                        exit_status = 1;
                    }
                    break;
                }
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
        \\                     ignore each failure to remove a non-empty directory
        \\  -p, --parents      remove DIRECTORY and its ancestors; e.g., 'rmdir -p a/b'
        \\                     is similar to 'rmdir a/b a'
        \\  -v, --verbose      output a diagnostic for every directory processed
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
        \\GNU coreutils online help: <https://www.gnu.org/software/coreutils/>
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
