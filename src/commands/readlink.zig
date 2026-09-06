const std = @import("std");
const errors = @import("../utils/errors.zig");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "readlink";
pub const version: []const u8 = "0.1.0";

const CanonMode = enum { normal, existing, missing };

fn canonicalize(allocator: std.mem.Allocator, path: []const u8, mode: CanonMode) !?[]const u8 {
    if (path.len == 0) return null;

    if (mode == .existing) {
        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);
        const res_c = c.realpath(path_z.ptr, null) orelse return null;
        defer c.free(res_c);
        return try allocator.dupe(u8, std.mem.span(res_c));
    }

    // Try realpath first
    {
        const path_z = try allocator.dupeZ(u8, path);
        defer allocator.free(path_z);
        if (c.realpath(path_z.ptr, null)) |res_c| {
            defer c.free(res_c);
            return try allocator.dupe(u8, std.mem.span(res_c));
        }
    }

    // Make absolute path
    const abs_path = if (std.fs.path.isAbsolute(path))
        try allocator.dupe(u8, path)
    else blk: {
        const cwd_c = c.getcwd(null, 0) orelse return null;
        defer c.free(cwd_c);
        const cwd = std.mem.span(cwd_c);
        break :blk try std.fs.path.join(allocator, &.{ cwd, path });
    };
    defer allocator.free(abs_path);

    var remaining: std.ArrayList([]const u8) = .empty;
    defer remaining.deinit(allocator);

    var it = std.mem.splitScalar(u8, abs_path, '/');
    while (it.next()) |part| {
        if (part.len > 0) {
            try remaining.append(allocator, part);
        }
    }

    var resolved: std.ArrayList([]const u8) = .empty;
    defer resolved.deinit(allocator);

    const has_trailing_slash = path.len > 0 and path[path.len - 1] == '/';

    var loop_count: usize = 0;
    const max_links: usize = 40;

    var i: usize = 0;
    while (i < remaining.items.len) {
        const part = remaining.items[i];
        i += 1;

        if (std.mem.eql(u8, part, ".")) {
            continue;
        }
        if (std.mem.eql(u8, part, "..")) {
            if (resolved.items.len > 0) {
                _ = resolved.pop();
            }
            continue;
        }

        try resolved.append(allocator, part);

        // Build current path
        var current: std.ArrayList(u8) = .empty;
        defer current.deinit(allocator);
        try current.append(allocator, '/');
        for (resolved.items, 0..) |item, idx| {
            if (idx > 0) try current.append(allocator, '/');
            try current.appendSlice(allocator, item);
        }
        const cur_z = try allocator.dupeZ(u8, current.items);
        defer allocator.free(cur_z);

        var st: c.struct_stat = undefined;
        if (c.lstat(cur_z.ptr, &st) == 0) {
            if (c.S_ISLNK(st.st_mode)) {
                loop_count += 1;
                if (loop_count > max_links) return null; // ELOOP

                var link_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
                const link_len = c.readlink(cur_z.ptr, &link_buf, link_buf.len);
                if (link_len < 0) return null;
                const target = link_buf[0..@intCast(link_len)];

                _ = resolved.pop();

                // Target components
                var target_parts: std.ArrayList([]const u8) = .empty;
                defer target_parts.deinit(allocator);

                if (target.len > 0 and target[0] == '/') {
                    // Absolute target: clear resolved
                    resolved.clearRetainingCapacity();
                }

                var target_it = std.mem.splitScalar(u8, target, '/');
                while (target_it.next()) |tp| {
                    if (tp.len > 0) {
                        try target_parts.append(allocator, try allocator.dupe(u8, tp));
                    }
                }

                // Insert target parts before remaining items
                const rest = try allocator.dupe([]const u8, remaining.items[i..]);
                defer allocator.free(rest);

                remaining.clearRetainingCapacity();
                for (target_parts.items) |tp| {
                    try remaining.append(allocator, tp);
                }
                for (rest) |r| {
                    try remaining.append(allocator, r);
                }
                i = 0;
            } else if (mode != .missing and !c.S_ISDIR(st.st_mode)) {
                if (i < remaining.items.len or has_trailing_slash) {
                    // Not a directory, but more components or trailing slash follow!
                    return null;
                }
            }
        } else {
            // Does not exist
            if (mode == .normal) {
                // For -f, only the last component can be missing!
                if (i < remaining.items.len) {
                    return null;
                }
            } else if (mode == .missing) {
                // Continue
            }
        }
    }

    var result: std.ArrayList(u8) = .empty;
    defer result.deinit(allocator);
    try result.append(allocator, '/');
    for (resolved.items, 0..) |item, idx| {
        if (idx > 0) try result.append(allocator, '/');
        try result.appendSlice(allocator, item);
    }
    return try allocator.dupe(u8, result.items);
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

    var canonicalize_mode: ?CanonMode = null;
    var no_newline = false;
    var verbose: bool = (std.c.getenv("POSIXLY_CORRECT") != null);
    var use_nuls = false;
    var files_start: usize = args.len;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            printHelp(stdout) catch return 1;
            stdout.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            printVersion(stdout) catch return 1;
            stdout.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--canonicalize")) {
            canonicalize_mode = .normal;
        } else if (std.mem.eql(u8, arg, "--canonicalize-existing")) {
            canonicalize_mode = .existing;
        } else if (std.mem.eql(u8, arg, "--canonicalize-missing")) {
            canonicalize_mode = .missing;
        } else if (std.mem.eql(u8, arg, "--no-newline")) {
            no_newline = true;
        } else if (std.mem.eql(u8, arg, "--quiet") or std.mem.eql(u8, arg, "--silent")) {
            verbose = false;
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "--zero")) {
            use_nuls = true;
        } else if (std.mem.eql(u8, arg, "--")) {
            files_start = i + 1;
            break;
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1 and arg[1] != '-') {
            for (arg[1..]) |ch| {
                switch (ch) {
                    'f' => canonicalize_mode = .normal,
                    'e' => canonicalize_mode = .existing,
                    'm' => canonicalize_mode = .missing,
                    'n' => no_newline = true,
                    'q', 's' => verbose = false,
                    'v' => verbose = true,
                    'z' => use_nuls = true,
                    else => {
                        try errors.printInvalidOption(stderr, name, ch);
                        return 1;
                    },
                }
            }
        } else {
            files_start = i;
            break;
        }
    }

    if (files_start >= args.len) {
        try errors.printMissingOperand(stderr, name);
        return 1;
    }

    if (args.len - files_start > 1) {
        if (no_newline) {
            try errors.printError(stderr, name, "ignoring --no-newline with multiple arguments");
            no_newline = false;
        }
    }

    const delimiter: u8 = if (use_nuls) 0 else '\n';
    var status: u8 = 0;

    for (args[files_start..]) |file| {
        if (canonicalize_mode == null) {
            const file_z = try allocator.dupeZ(u8, file);
            defer allocator.free(file_z);

            var link_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
            const res = c.readlink(file_z.ptr, &link_buf, link_buf.len);
            if (res < 0) {
                status = 1;
                if (verbose) {
                    const err = c.__errno_location().*;
                    const msg = std.mem.span(c.strerror(err));
                    try stderr.print("{s}: {s}: {s}\n", .{ name, file, msg });
                }
                continue;
            }
            try stdout.writeAll(link_buf[0..@intCast(res)]);
        } else {
            const canon = try canonicalize(allocator, file, canonicalize_mode.?);
            if (canon) |c_path| {
                defer allocator.free(c_path);
                try stdout.writeAll(c_path);
            } else {
                status = 1;
                if (verbose) {
                    const err = c.__errno_location().*;
                    const msg = std.mem.span(c.strerror(err));
                    try stderr.print("{s}: {s}: {s}\n", .{ name, file, msg });
                }
                continue;
            }
        }

        if (!no_newline) {
            try stdout.writeByte(delimiter);
        }
    }

    return status;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: readlink [OPTION]... FILE...
        \\Print value of a symbolic link or canonical file name
        \\
        \\  -f, --canonicalize            canonicalize by following every symlink in
        \\                                every component of the given name recursively;
        \\                                all but the last component must exist
        \\  -e, --canonicalize-existing   canonicalize by following every symlink in
        \\                                every component of the given name recursively,
        \\                                all components must exist
        \\  -m, --canonicalize-missing    canonicalize by following every symlink in
        \\                                every component of the given name recursively,
        \\                                without requirements on components existence
        \\  -n, --no-newline              do not output the trailing newline
        \\  -q, -s, --silent, --quiet     suppress most error messages
        \\  -v, --verbose                 report error messages
        \\  -z, --zero                    end each output line with NUL, not newline
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
