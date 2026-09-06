const std = @import("std");
const errors = @import("../utils/errors.zig");
const args_mod = @import("../utils/args.zig");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "ln";
pub const version: []const u8 = "0.1.0";

const ln_long_opts = &[_][]const u8{
    "--help",
    "--version",
    "--symbolic",
    "--force",
    "--verbose",
    "--no-dereference",
    "--no-target-directory",
    "--target-directory",
    "--backup",
    "--suffix",
    "--logical",
    "--physical",
    "--relative",
    "--directory",
};

fn isDirectory(path: [:0]const u8, dereference: bool) bool {
    var st: c.struct_stat = undefined;
    const rc = if (dereference) c.stat(path.ptr, &st) else c.lstat(path.ptr, &st);
    if (rc != 0) return false;
    return (st.st_mode & c.S_IFMT) == c.S_IFDIR;
}

fn pathExists(path: [:0]const u8) bool {
    var st: c.struct_stat = undefined;
    return c.lstat(path.ptr, &st) == 0;
}

fn areSameFile(source: [:0]const u8, dest: [:0]const u8) bool {
    var src_st: c.struct_stat = undefined;
    var dst_st: c.struct_stat = undefined;
    if (c.stat(source.ptr, &src_st) != 0) return false;
    if (c.lstat(dest.ptr, &dst_st) != 0) return false;
    if (src_st.st_dev != dst_st.st_dev or src_st.st_ino != dst_st.st_ino) return false;

    if (src_st.st_nlink == 1) return true;

    var buf1: [std.fs.max_path_bytes]u8 = undefined;
    var buf2: [std.fs.max_path_bytes]u8 = undefined;
    const r1 = c.realpath(source.ptr, &buf1);
    const r2 = c.realpath(dest.ptr, &buf2);
    if (r1 != null and r2 != null) {
        return std.mem.eql(u8, std.mem.span(r1), std.mem.span(r2));
    }
    return std.mem.eql(u8, source, dest);
}

fn resolveCanonical(allocator: std.mem.Allocator, initial_path: []const u8) ![]u8 {
    var cur_path = try allocator.dupe(u8, initial_path);
    defer allocator.free(cur_path);

    var loop_count: usize = 0;
    while (loop_count < 40) : (loop_count += 1) {
        const cur_z = try allocator.dupeZ(u8, cur_path);
        defer allocator.free(cur_z);

        var link_buf: [std.fs.max_path_bytes]u8 = undefined;
        const len = c.readlink(cur_z.ptr, &link_buf, link_buf.len - 1);
        if (len <= 0) break;
        link_buf[@intCast(len)] = 0;
        const target = link_buf[0..@intCast(len)];

        const next_path = if (std.fs.path.isAbsolute(target))
            try allocator.dupe(u8, target)
        else blk: {
            const dir = std.fs.path.dirname(cur_path) orelse ".";
            break :blk try std.fs.path.join(allocator, &[_][]const u8{ dir, target });
        };
        allocator.free(cur_path);
        cur_path = next_path;
    }

    var cwd_buf: [std.fs.max_path_bytes]u8 = undefined;
    const cwd = if (c.getcwd(&cwd_buf, cwd_buf.len)) |ptr| std.mem.span(ptr) else ".";
    return std.fs.path.resolve(allocator, &[_][]const u8{ cwd, cur_path });
}

fn makeRelative(allocator: std.mem.Allocator, target: []const u8, dest: []const u8) ![]u8 {
    const dest_dir = std.fs.path.dirname(dest) orelse ".";
    const canon_dest_dir = try resolveCanonical(allocator, dest_dir);
    defer allocator.free(canon_dest_dir);
    const canon_target = try resolveCanonical(allocator, target);
    defer allocator.free(canon_target);
    return std.fs.path.relative(allocator, "/", null, canon_dest_dir, canon_target);
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var symbolic = false;
    var force = false;
    var verbose = false;
    var no_dereference = false;
    var logical = false;
    var relative = false;
    var backup = false;
    var custom_suffix: ?[]const u8 = null;
    var target_dir: ?[]const u8 = null;
    var no_target_dir = false;
    var file_start: usize = args.len;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--")) {
            file_start = i + 1;
            break;
        }
        if (!std.mem.startsWith(u8, arg, "-") or arg.len == 1) {
            file_start = i;
            break;
        }

        if (std.mem.startsWith(u8, arg, "--")) {
            const opt_eq = std.mem.indexOfScalar(u8, arg, '=');
            const opt_name = if (opt_eq) |idx| arg[0..idx] else arg;
            const opt_val = if (opt_eq) |idx| arg[idx + 1 ..] else null;

            const matched = args_mod.matchLongOption(opt_name, ln_long_opts);
            const opt = switch (matched) {
                .found => |canonical| canonical,
                .ambiguous => {
                    try errors.printAmbiguousOption(stderr, name, arg);
                    return 1;
                },
                .none => {
                    try errors.printUnrecognizedOption(stderr, name, arg);
                    return 1;
                },
            };

            if (std.mem.eql(u8, opt, "--help")) {
                printHelp(stdout) catch return 1;
                stdout.flush() catch return 1;
                return 0;
            } else if (std.mem.eql(u8, opt, "--version")) {
                printVersion(stdout) catch return 1;
                stdout.flush() catch return 1;
                return 0;
            } else if (std.mem.eql(u8, opt, "--symbolic")) {
                symbolic = true;
            } else if (std.mem.eql(u8, opt, "--force")) {
                force = true;
            } else if (std.mem.eql(u8, opt, "--verbose")) {
                verbose = true;
            } else if (std.mem.eql(u8, opt, "--no-dereference")) {
                no_dereference = true;
            } else if (std.mem.eql(u8, opt, "--no-target-directory")) {
                no_target_dir = true;
            } else if (std.mem.eql(u8, opt, "--target-directory")) {
                if (opt_val) |val| {
                    target_dir = val;
                } else {
                    i += 1;
                    if (i >= args.len) {
                        try errors.printError(stderr, name, "option '--target-directory' requires an argument");
                        return 1;
                    }
                    target_dir = args[i];
                }
            } else if (std.mem.eql(u8, opt, "--backup")) {
                backup = true;
            } else if (std.mem.eql(u8, opt, "--suffix")) {
                if (opt_val) |val| {
                    custom_suffix = val;
                } else {
                    i += 1;
                    if (i >= args.len) {
                        try errors.printError(stderr, name, "option '--suffix' requires an argument");
                        return 1;
                    }
                    custom_suffix = args[i];
                }
            } else if (std.mem.eql(u8, opt, "--logical")) {
                logical = true;
            } else if (std.mem.eql(u8, opt, "--physical")) {
                logical = false;
            } else if (std.mem.eql(u8, opt, "--relative")) {
                relative = true;
            } else if (std.mem.eql(u8, opt, "--directory")) {
                // -F / -d ignored
            }
        } else {
            // Short options
            var j: usize = 1;
            while (j < arg.len) : (j += 1) {
                const ch = arg[j];
                switch (ch) {
                    's' => symbolic = true,
                    'f' => force = true,
                    'v' => verbose = true,
                    'n' => no_dereference = true,
                    'T' => no_target_dir = true,
                    'b' => backup = true,
                    'L' => logical = true,
                    'P' => logical = false,
                    'r' => relative = true,
                    'F', 'd' => {},
                    'S' => {
                        if (j + 1 < arg.len) {
                            custom_suffix = arg[j + 1 ..];
                            break;
                        } else {
                            i += 1;
                            if (i >= args.len) {
                                try errors.printError(stderr, name, "option requires an argument -- 'S'");
                                return 1;
                            }
                            custom_suffix = args[i];
                            break;
                        }
                    },
                    't' => {
                        if (j + 1 < arg.len) {
                            target_dir = arg[j + 1 ..];
                            break;
                        } else {
                            i += 1;
                            if (i >= args.len) {
                                try errors.printError(stderr, name, "option requires an argument -- 't'");
                                return 1;
                            }
                            target_dir = args[i];
                            break;
                        }
                    },
                    else => {
                        try errors.printInvalidOption(stderr, name, ch);
                        return 1;
                    },
                }
            }
        }
    }

    if (file_start >= args.len) {
        try errors.printError(stderr, name, "missing file operand");
        return 1;
    }

    const files = args[file_start..];
    const env_suffix = if (c.getenv("SIMPLE_BACKUP_SUFFIX")) |ptr| std.mem.span(ptr) else null;
    const backup_suffix = custom_suffix orelse env_suffix orelse "~";

    var created_dest_files = std.StringHashMap(void).init(allocator);
    defer {
        var it = created_dest_files.keyIterator();
        while (it.next()) |k| allocator.free(k.*);
        created_dest_files.deinit();
    }

    if (target_dir) |td| {
        const td_z = try allocator.dupeZ(u8, td);
        defer allocator.free(td_z);
        if (!isDirectory(td_z, true)) {
            const msg = try std.fmt.allocPrint(allocator, "target '{s}' is not a directory", .{td});
            defer allocator.free(msg);
            try errors.printError(stderr, name, msg);
            return 1;
        }

        var exit_code: u8 = 0;
        for (files) |target| {
            const rc = createLink(allocator, target, td, true, symbolic, force, verbose, no_dereference, logical, relative, backup, backup_suffix, &created_dest_files, stdout, stderr);
            if (rc != 0) exit_code = 1;
        }
        return exit_code;
    }

    if (files.len == 1) {
        const target = files[0];
        const base = std.fs.path.basename(target);
        return createLink(allocator, target, base, false, symbolic, force, verbose, no_dereference, logical, relative, backup, backup_suffix, &created_dest_files, stdout, stderr);
    }

    if (!no_target_dir and files.len >= 2) {
        const last_dest = files[files.len - 1];
        const last_dest_z = try allocator.dupeZ(u8, last_dest);
        defer allocator.free(last_dest_z);

        const is_dir = isDirectory(last_dest_z, !no_dereference);

        if (is_dir) {
            var exit_code: u8 = 0;
            for (files[0 .. files.len - 1]) |target| {
                const rc = createLink(allocator, target, last_dest, true, symbolic, force, verbose, no_dereference, logical, relative, backup, backup_suffix, &created_dest_files, stdout, stderr);
                if (rc != 0) exit_code = 1;
            }
            return exit_code;
        } else if (files.len > 2) {
            const msg = try std.fmt.allocPrint(allocator, "target '{s}' is not a directory", .{last_dest});
            defer allocator.free(msg);
            try errors.printError(stderr, name, msg);
            return 1;
        }
    }

    if (no_target_dir and files.len > 2) {
        const msg = try std.fmt.allocPrint(allocator, "extra operand '{s}'", .{files[2]});
        defer allocator.free(msg);
        try errors.printError(stderr, name, msg);
        return 1;
    }

    return createLink(allocator, files[0], files[1], false, symbolic, force, verbose, no_dereference, logical, relative, backup, backup_suffix, &created_dest_files, stdout, stderr);
}

fn createLink(
    allocator: std.mem.Allocator,
    raw_target: []const u8,
    raw_dest: []const u8,
    dest_is_dir: bool,
    symbolic: bool,
    force: bool,
    verbose: bool,
    no_dereference: bool,
    logical: bool,
    relative: bool,
    backup: bool,
    backup_suffix: []const u8,
    created_dest_files: *std.StringHashMap(void),
    stdout: anytype,
    stderr: anytype,
) u8 {
    _ = no_dereference;

    var link_path: []const u8 = raw_dest;
    var allocated_link_path: ?[]u8 = null;
    defer if (allocated_link_path) |p| allocator.free(p);

    if (dest_is_dir) {
        const base = std.fs.path.basename(raw_target);
        const joined = std.fs.path.join(allocator, &[_][]const u8{ raw_dest, base }) catch return 1;
        allocated_link_path = joined;
        link_path = joined;
    }

    // Protection: will not overwrite just-created file
    if (created_dest_files.contains(link_path)) {
        stderr.print("ln: will not overwrite just-created '{s}' with '{s}'\n", .{ link_path, raw_target }) catch {};
        return 1;
    }

    const target_z = allocator.dupeZ(u8, raw_target) catch return 1;
    defer allocator.free(target_z);
    const link_path_z = allocator.dupeZ(u8, link_path) catch return 1;
    defer allocator.free(link_path_z);

    // Check same file
    if (!symbolic or force or backup) {
        if (areSameFile(target_z, link_path_z)) {
            stderr.print("ln: '{s}' and '{s}' are the same file\n", .{ raw_target, link_path }) catch {};
            return 1;
        }
    }

    var effective_target: []const u8 = raw_target;
    var allocated_effective: ?[]u8 = null;
    defer if (allocated_effective) |p| allocator.free(p);

    if (symbolic and relative) {
        if (raw_target.len == 0) {
            stderr.print("ln: failed to create symbolic link '{s}': No such file or directory\n", .{link_path}) catch {};
            return 1;
        }
        if (makeRelative(allocator, raw_target, link_path)) |rel_str| {
            allocated_effective = rel_str;
            effective_target = rel_str;
        } else |_| {}
    }

    const eff_target_z = allocator.dupeZ(u8, effective_target) catch return 1;
    defer allocator.free(eff_target_z);

    // If backup is requested and dest exists, move dest to backup name
    if (backup and pathExists(link_path_z)) {
        const backup_name = std.fmt.allocPrint(allocator, "{s}{s}", .{ link_path, backup_suffix }) catch return 1;
        defer allocator.free(backup_name);
        const backup_name_z = allocator.dupeZ(u8, backup_name) catch return 1;
        defer allocator.free(backup_name_z);
        if (c.rename(link_path_z.ptr, backup_name_z.ptr) != 0) {
            const errno = c.__errno_location().*;
            if (errno != c.ENOENT) {
                stderr.print("ln: cannot backup '{s}': {s}\n", .{ link_path, errors.errorDescription(error.Unexpected) }) catch {};
                return 1;
            }
        }
    } else if (force and pathExists(link_path_z)) {
        _ = c.unlink(link_path_z.ptr);
    }

    if (symbolic) {
        if (c.symlink(eff_target_z.ptr, link_path_z.ptr) != 0) {
            const errno = c.__errno_location().*;
            if (errno == c.EEXIST and force) {
                _ = c.unlink(link_path_z.ptr);
                if (c.symlink(eff_target_z.ptr, link_path_z.ptr) == 0) {
                    if (allocator.dupe(u8, link_path)) |duped| {
                        created_dest_files.put(duped, {}) catch {};
                    } else |_| {}
                    if (verbose) stdout.print("'{s}' -> '{s}'\n", .{ link_path, effective_target }) catch {};
                    return 0;
                }
            }
            stderr.print("ln: failed to create symbolic link '{s}': {s}\n", .{ link_path, std.mem.span(c.strerror(errno)) }) catch {};
            return 1;
        }
        if (allocator.dupe(u8, link_path)) |duped| {
            created_dest_files.put(duped, {}) catch {};
        } else |_| {}
        if (verbose) stdout.print("'{s}' -> '{s}'\n", .{ link_path, effective_target }) catch {};
        return 0;
    } else {
        // Hard link
        if (raw_target.len > 0 and raw_target[raw_target.len - 1] == '/') {
            stderr.print("ln: {s}: hard link not allowed for directory\n", .{raw_target}) catch {};
            return 1;
        }

        var st: c.struct_stat = undefined;
        const stat_rc = if (logical) c.stat(target_z.ptr, &st) else c.lstat(target_z.ptr, &st);
        if (stat_rc == 0 and (st.st_mode & c.S_IFMT) == c.S_IFDIR) {
            stderr.print("ln: {s}: hard link not allowed for directory\n", .{raw_target}) catch {};
            return 1;
        }
        if (logical and stat_rc != 0) {
            stderr.print("ln: failed to access '{s}': No such file or directory\n", .{raw_target}) catch {};
            return 1;
        }

        const flags: c_int = if (logical) c.AT_SYMLINK_FOLLOW else 0;
        if (c.linkat(c.AT_FDCWD, target_z.ptr, c.AT_FDCWD, link_path_z.ptr, flags) != 0) {
            const errno = c.__errno_location().*;
            if (errno == c.EEXIST and force) {
                _ = c.unlink(link_path_z.ptr);
                if (c.linkat(c.AT_FDCWD, target_z.ptr, c.AT_FDCWD, link_path_z.ptr, flags) == 0) {
                    if (allocator.dupe(u8, link_path)) |duped| {
                        created_dest_files.put(duped, {}) catch {};
                    } else |_| {}
                    if (verbose) stdout.print("'{s}' => '{s}'\n", .{ link_path, raw_target }) catch {};
                    return 0;
                }
            }
            stderr.print("ln: failed to create hard link '{s}' => '{s}': {s}\n", .{ link_path, raw_target, std.mem.span(c.strerror(errno)) }) catch {};
            return 1;
        }
        if (allocator.dupe(u8, link_path)) |duped| {
            created_dest_files.put(duped, {}) catch {};
        } else |_| {}
        if (verbose) stdout.print("'{s}' => '{s}'\n", .{ link_path, raw_target }) catch {};
        return 0;
    }
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: ln [OPTION]... TARGET [LINK_NAME]
        \\  or:  ln [OPTION]... TARGET... DIRECTORY
        \\Create a link to TARGET.
        \\
        \\  -s, --symbolic     make symbolic links instead of hard links
        \\  -f, --force        remove existing destination files
        \\  -v, --verbose      print name of each linked file
        \\      --help         display this help and exit
        \\      --version      output version information and exit
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
