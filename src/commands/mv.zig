const std = @import("std");
const errors = @import("../utils/errors.zig");
const args_mod = @import("../utils/args.zig");
const backup_mod = @import("../utils/backup.zig");
const mode_mod = @import("../utils/mode.zig");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "mv";
pub const version: []const u8 = "0.1.0";

const mv_long_opts = &[_][]const u8{
    "--help",
    "--version",
    "--verbose",
    "--force",
    "--interactive",
    "--no-clobber",
    "--no-target-directory",
    "--target-directory",
    "--backup",
    "--suffix",
    "--update",
    "--strip-trailing-slashes",
    "--no-copy",
    "--exchange",
};

const UpdateMode = enum {
    not_set,
    all,
    older,
    none,
    none_fail,
};

const PromptChoice = enum {
    unspecified,
    ask_user,
    always_yes,
    always_skip,
};

const DevIno = struct {
    dev: c.dev_t,
    ino: c.ino_t,
};

fn isSameEntry(allocator: std.mem.Allocator, path1: []const u8, path2: []const u8) bool {
    if (std.mem.eql(u8, path1, path2)) return true;

    var p1 = path1;
    while (p1.len > 1 and p1[p1.len - 1] == '/') p1 = p1[0 .. p1.len - 1];
    var p2 = path2;
    while (p2.len > 1 and p2[p2.len - 1] == '/') p2 = p2[0 .. p2.len - 1];

    if (std.mem.eql(u8, p1, p2)) return true;

    const base1 = std.fs.path.basename(p1);
    const base2 = std.fs.path.basename(p2);
    if (!std.mem.eql(u8, base1, base2)) return false;

    const dir1 = std.fs.path.dirname(p1) orelse ".";
    const dir2 = std.fs.path.dirname(p2) orelse ".";

    const dir1_z = allocator.dupeZ(u8, dir1) catch return false;
    defer allocator.free(dir1_z);
    const dir2_z = allocator.dupeZ(u8, dir2) catch return false;
    defer allocator.free(dir2_z);

    var st1: c.struct_stat = undefined;
    var st2: c.struct_stat = undefined;
    if (c.stat(dir1_z.ptr, &st1) != 0) return false;
    if (c.stat(dir2_z.ptr, &st2) != 0) return false;

    return st1.st_dev == st2.st_dev and st1.st_ino == st2.st_ino;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buf: [16384]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var verbose = false;
    var prompt_choice: PromptChoice = .unspecified;
    var backup_type: backup_mod.BackupType = .none;
    var custom_suffix: ?[]const u8 = null;
    var target_dir: ?[]const u8 = null;
    var no_target_dir = false;
    var update_mode: UpdateMode = .not_set;
    var no_copy = false;
    var exchange = false;
    var strip_trailing_slashes = false;
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

            const matched = args_mod.matchLongOption(opt_name, mv_long_opts);
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
            } else if (std.mem.eql(u8, opt, "--verbose")) {
                verbose = true;
            } else if (std.mem.eql(u8, opt, "--force")) {
                prompt_choice = .always_yes;
            } else if (std.mem.eql(u8, opt, "--interactive")) {
                prompt_choice = .ask_user;
            } else if (std.mem.eql(u8, opt, "--no-clobber")) {
                prompt_choice = .always_skip;
                update_mode = .none;
            } else if (std.mem.eql(u8, opt, "--no-target-directory")) {
                no_target_dir = true;
            } else if (std.mem.eql(u8, opt, "--strip-trailing-slashes")) {
                strip_trailing_slashes = true;
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
                if (opt_val) |val| {
                    backup_type = backup_mod.parseBackupType(val) orelse {
                        try errors.printError(stderr, name, "invalid backup type");
                        return 1;
                    };
                } else {
                    backup_type = backup_mod.getVersionControl();
                }
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
            } else if (std.mem.eql(u8, opt, "--update")) {
                if (opt_val) |val| {
                    if (std.mem.eql(u8, val, "all")) {
                        update_mode = .all;
                    } else if (std.mem.eql(u8, val, "older")) {
                        update_mode = .older;
                    } else if (std.mem.eql(u8, val, "none")) {
                        update_mode = .none;
                    } else if (std.mem.eql(u8, val, "none-fail")) {
                        update_mode = .none_fail;
                    } else {
                        try errors.printError(stderr, name, "invalid update mode");
                        return 1;
                    }
                } else {
                    update_mode = .older;
                }
            } else if (std.mem.eql(u8, opt, "--no-copy")) {
                no_copy = true;
            } else if (std.mem.eql(u8, opt, "--exchange")) {
                exchange = true;
            }
        } else {
            var j: usize = 1;
            while (j < arg.len) : (j += 1) {
                const c_opt = arg[j];
                switch (c_opt) {
                    'v' => verbose = true,
                    'f' => prompt_choice = .always_yes,
                    'i' => prompt_choice = .ask_user,
                    'n' => {
                        prompt_choice = .always_skip;
                        update_mode = .none;
                    },
                    'b' => {
                        backup_type = backup_mod.getVersionControl();
                    },
                    'u' => {
                        update_mode = .older;
                    },
                    'T' => no_target_dir = true,
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
                        try errors.printInvalidOption(stderr, name, c_opt);
                        return 1;
                    },
                }
            }
        }
    }

    if (backup_type != .none and (prompt_choice == .always_skip or update_mode == .none or update_mode == .none_fail)) {
        try errors.printError(stderr, name, "options --backup and --no-clobber are mutually exclusive");
        return 1;
    }

    if (target_dir != null and no_target_dir) {
        try errors.printError(stderr, name, "cannot combine --target-directory (-t) and --no-target-directory (-T)");
        return 1;
    }

    if (file_start >= args.len) {
        try errors.printErrorWithHelp(stderr, name, "missing file operand");
        return 1;
    }

    const backup_suffix = custom_suffix orelse backup_mod.getSimpleBackupSuffix();

    var sources: [][]const u8 = undefined;
    var dest: []const u8 = undefined;

    if (target_dir) |td| {
        sources = args[file_start..];
        dest = td;
    } else {
        if (args.len - file_start < 2) {
            const msg = try std.fmt.allocPrint(allocator, "missing destination file operand after '{s}'", .{args[file_start]});
            defer allocator.free(msg);
            try errors.printErrorWithHelp(stderr, name, msg);
            return 1;
        }
        sources = args[file_start .. args.len - 1];
        dest = args[args.len - 1];
    }

    if (exchange and sources.len != 1) {
        try errors.printError(stderr, name, "cannot combine --exchange with more than two arguments");
        return 1;
    }

    if (strip_trailing_slashes) {
        while (dest.len > 1 and dest[dest.len - 1] == '/') {
            dest = dest[0 .. dest.len - 1];
        }
    }

    const dest_z = try allocator.dupeZ(u8, dest);
    defer allocator.free(dest_z);

    var dest_stat: c.struct_stat = undefined;
    const dest_exists = (c.stat(dest_z.ptr, &dest_stat) == 0);
    const dest_stat_err = if (!dest_exists) c.__errno_location().* else 0;
    const dest_is_dir = if (no_target_dir) false else (dest_exists and (dest_stat.st_mode & c.S_IFMT) == c.S_IFDIR);

    if (target_dir != null and !dest_is_dir) {
        const msg = if (!dest_exists)
            try std.fmt.allocPrint(allocator, "target directory '{s}': {s}", .{ dest, c.strerror(dest_stat_err) })
        else
            try std.fmt.allocPrint(allocator, "target directory '{s}': Not a directory", .{dest});
        defer allocator.free(msg);
        try errors.printError(stderr, name, msg);
        return 1;
    }

    if (sources.len > 1 and !dest_is_dir) {
        const msg = if (!dest_exists)
            try std.fmt.allocPrint(allocator, "target '{s}': {s}", .{ dest, c.strerror(dest_stat_err) })
        else
            try std.fmt.allocPrint(allocator, "target '{s}': Not a directory", .{dest});
        defer allocator.free(msg);
        try errors.printError(stderr, name, msg);
        return 1;
    }

    if (no_target_dir and sources.len > 1) {
        const msg = try std.fmt.allocPrint(allocator, "extra operand '{s}'", .{sources[1]});
        defer allocator.free(msg);
        try errors.printError(stderr, name, msg);
        return 1;
    }

    var seen_sources = std.AutoHashMap(DevIno, void).init(allocator);
    defer seen_sources.deinit();

    var created_dest_files = std.StringHashMap(void).init(allocator);
    defer {
        var it = created_dest_files.keyIterator();
        while (it.next()) |k| {
            allocator.free(k.*);
        }
        created_dest_files.deinit();
    }

    var hard_links = std.AutoHashMap(DevIno, []const u8).init(allocator);
    defer {
        var it = hard_links.valueIterator();
        while (it.next()) |val| {
            allocator.free(val.*);
        }
        hard_links.deinit();
    }

    var exit_code: u8 = 0;
    for (sources) |source| {
        var clean_source = source;
        if (clean_source.len > 1 and clean_source[clean_source.len - 1] == '/') {
            clean_source = clean_source[0 .. clean_source.len - 1];
        }

        var dest_path = if (dest_is_dir)
            try std.fs.path.join(allocator, &[_][]const u8{ dest, std.fs.path.basename(clean_source) })
        else
            dest;
        defer if (dest_is_dir) allocator.free(dest_path);

        const src_z = try allocator.dupeZ(u8, source);
        defer allocator.free(src_z);

        if (exchange) {
            const cur_dest_z = try allocator.dupeZ(u8, dest_path);
            defer allocator.free(cur_dest_z);
            const res = std.os.linux.syscall5(
                .renameat2,
                @as(usize, @bitCast(@as(isize, c.AT_FDCWD))),
                @intFromPtr(src_z.ptr),
                @as(usize, @bitCast(@as(isize, c.AT_FDCWD))),
                @intFromPtr(cur_dest_z.ptr),
                2,
            );
            const err_enum = std.os.linux.errno(res);
            if (err_enum != .SUCCESS) {
                if (err_enum == .NOSYS or err_enum == .INVAL) {
                    try stderr.print("mv: --exchange not supported\n", .{});
                } else {
                    const err_int: c_int = @intCast(@intFromEnum(err_enum));
                    try stderr.print("mv: cannot exchange '{s}' and '{s}': {s}\n", .{ source, dest_path, c.strerror(err_int) });
                }
                return 1;
            }
            return 0;
        }

        var src_lst: c.struct_stat = undefined;
        const src_lst_ok = (c.lstat(src_z.ptr, &src_lst) == 0);
        if (!src_lst_ok) {
            const err = c.__errno_location().*;
            try stderr.print("mv: cannot stat '{s}': {s}\n", .{ source, c.strerror(err) });
            exit_code = 1;
            continue;
        }

        // Duplicate source directory detection
        if ((src_lst.st_mode & c.S_IFMT) == c.S_IFDIR) {
            const key = DevIno{ .dev = src_lst.st_dev, .ino = src_lst.st_ino };
            if (seen_sources.contains(key)) {
                try stderr.print("mv: warning: source directory '{s}' specified more than once\n", .{source});
                continue;
            }
            try seen_sources.put(key, {});
        }

        // Handle trailing slash on destination:
        // If dest_path ends with '/' and does not exist:
        // If source is a directory, strip trailing slash and proceed.
        // If source is not a directory, fail with "Not a directory".
        var cur_dest_z = try allocator.dupeZ(u8, dest_path);
        defer allocator.free(cur_dest_z);
        var dst_lst: c.struct_stat = undefined;
        var dst_lst_ok = (c.lstat(cur_dest_z.ptr, &dst_lst) == 0);

        if (std.mem.endsWith(u8, dest_path, "/") and !dst_lst_ok) {
            if ((src_lst.st_mode & c.S_IFMT) != c.S_IFDIR) {
                try stderr.print("mv: cannot move '{s}' to '{s}': Not a directory\n", .{ source, dest_path });
                exit_code = 1;
                continue;
            }
            // Strip trailing slashes
            while (dest_path.len > 1 and dest_path[dest_path.len - 1] == '/') {
                dest_path = dest_path[0 .. dest_path.len - 1];
            }
            allocator.free(cur_dest_z);
            cur_dest_z = try allocator.dupeZ(u8, dest_path);
            dst_lst_ok = (c.lstat(cur_dest_z.ptr, &dst_lst) == 0);
        }

        // Check if destination is a subdirectory of source
        if ((src_lst.st_mode & c.S_IFMT) == c.S_IFDIR) {
            var dest_parent = std.fs.path.dirname(dest_path) orelse ".";
            var inside_self = false;
            while (true) {
                const p_z = try allocator.dupeZ(u8, dest_parent);
                defer allocator.free(p_z);
                var p_st: c.struct_stat = undefined;
                if (c.stat(p_z.ptr, &p_st) == 0) {
                    if (p_st.st_dev == src_lst.st_dev and p_st.st_ino == src_lst.st_ino) {
                        try stderr.print("mv: cannot move '{s}' to a subdirectory of itself, '{s}'\n", .{ source, dest_path });
                        exit_code = 1;
                        inside_self = true;
                        break;
                    }
                }
                const next_parent = std.fs.path.dirname(dest_parent);
                if (next_parent == null or std.mem.eql(u8, next_parent.?, dest_parent)) break;
                dest_parent = next_parent.?;
            }
            if (inside_self) continue;
        }

        // Same file check
        if (dst_lst_ok) {
            var src_eff_st: c.struct_stat = undefined;
            var dst_eff_st: c.struct_stat = undefined;
            const src_st_ok = (c.stat(src_z.ptr, &src_eff_st) == 0);
            const dst_st_ok = (c.stat(cur_dest_z.ptr, &dst_eff_st) == 0);

            if (src_st_ok and dst_st_ok and src_eff_st.st_dev == dst_eff_st.st_dev and src_eff_st.st_ino == dst_eff_st.st_ino) {
                const same_entry = isSameEntry(allocator, source, dest_path);
                var same_file_err = false;

                if (same_entry) {
                    same_file_err = true;
                } else if (backup_type != .none) {
                    same_file_err = false;
                } else {
                    const src_is_lnk = (src_lst.st_mode & c.S_IFMT) == c.S_IFLNK;
                    const dst_is_lnk = (dst_lst.st_mode & c.S_IFMT) == c.S_IFLNK;
                    if (!src_is_lnk and dst_is_lnk) {
                        same_file_err = false;
                    } else {
                        same_file_err = true;
                    }
                }

                if (same_file_err) {
                    try stderr.print("mv: '{s}' and '{s}' are the same file\n", .{ source, dest_path });
                    exit_code = 1;
                    continue;
                }
            }
        }

        // Will not overwrite just-created check
        if (created_dest_files.contains(dest_path) and backup_type != .numbered and !exchange) {
            try stderr.print("mv: will not overwrite just-created '{s}' with '{s}'\n", .{ dest_path, source });
            exit_code = 1;
            continue;
        }

        // Overwrite prompt and update mode
        if (dst_lst_ok) {
            if (prompt_choice == .always_skip or update_mode == .none) {
                continue;
            }
            if (update_mode == .none_fail) {
                try stderr.print("mv: not replacing '{s}': File exists\n", .{dest_path});
                exit_code = 1;
                continue;
            }
            if (update_mode == .older) {
                if (dst_lst.st_mtim.tv_sec > src_lst.st_mtim.tv_sec or
                    (dst_lst.st_mtim.tv_sec == src_lst.st_mtim.tv_sec and dst_lst.st_mtim.tv_nsec >= src_lst.st_mtim.tv_nsec))
                {
                    continue;
                }
            }

            const is_writable = ((dst_lst.st_mode & c.S_IFMT) == c.S_IFLNK) or (c.access(cur_dest_z.ptr, c.W_OK) == 0);
            const should_prompt = (prompt_choice == .ask_user) or
                (prompt_choice == .unspecified and c.isatty(0) == 1 and !is_writable);

            if (should_prompt) {
                var buf: [9]u8 = undefined;
                const mode_oct = @as(u32, @intCast(dst_lst.st_mode & 0o7777));
                const perms = mode_mod.formatMode(mode_oct, &buf);
                if (!is_writable) {
                    try stderr.print("mv: replace '{s}', overriding mode {o:0>4} ({s})? ", .{ dest_path, mode_oct, perms });
                } else {
                    try stderr.print("mv: overwrite '{s}'? ", .{dest_path});
                }
                try stderr.flush();
                var resp_buf: [64]u8 = undefined;
                const n = c.read(0, &resp_buf, resp_buf.len);
                if (n <= 0 or (resp_buf[0] != 'y' and resp_buf[0] != 'Y')) {
                    exit_code = 1;
                    continue;
                }
            }
        }

        var actual_backup: ?[]const u8 = null;
        defer if (actual_backup) |bp| allocator.free(bp);

        if (dst_lst_ok and backup_type != .none) {
            const b_path = try backup_mod.findBackupPath(allocator, dest_path, backup_type, backup_suffix);
            if (b_path) |bp| {
                if (backup_mod.isBackupSource(bp, source)) {
                    try stderr.print("mv: backing up '{s}' might destroy source;  '{s}' not moved\n", .{ dest_path, source });
                    exit_code = 1;
                    allocator.free(bp);
                    continue;
                }

                const backup_z = try allocator.dupeZ(u8, bp);
                defer allocator.free(backup_z);
                if (c.rename(cur_dest_z.ptr, backup_z.ptr) != 0) {
                    const err = c.__errno_location().*;
                    try stderr.print("mv: cannot backup '{s}': {s}\n", .{ dest_path, c.strerror(err) });
                    exit_code = 1;
                    allocator.free(bp);
                    continue;
                }
                actual_backup = bp;
            }
        }

        if (c.rename(src_z.ptr, cur_dest_z.ptr) == 0) {
            const duped_dest = try allocator.dupe(u8, dest_path);
            try created_dest_files.put(duped_dest, {});
            if (verbose) {
                if (actual_backup) |bp| {
                    try stdout.print("renamed '{s}' -> '{s}' (backup: '{s}')\n", .{ source, dest_path, bp });
                } else {
                    try stdout.print("renamed '{s}' -> '{s}'\n", .{ source, dest_path });
                }
            }
            continue;
        }

        const rename_err = c.__errno_location().*;
        if (rename_err == c.EXDEV) {
            if (no_copy) {
                try stderr.print("mv: cannot move '{s}' to '{s}': Cross-device link\n", .{ source, dest_path });
                exit_code = 1;
                continue;
            }

            // In cross-device move, remove existing destination first like rename syscall
            if (dst_lst_ok) {
                const src_is_dir = (src_lst.st_mode & c.S_IFMT) == c.S_IFDIR;
                const unlink_res = if (src_is_dir) c.rmdir(cur_dest_z.ptr) else c.unlink(cur_dest_z.ptr);
                if (unlink_res != 0) {
                    const un_err = c.__errno_location().*;
                    if (un_err != c.ENOENT) {
                        if (un_err == c.ENOTEMPTY or un_err == c.EEXIST) {
                            try stderr.print("mv: cannot overwrite directory '{s}': Directory not empty\n", .{dest_path});
                        } else {
                            try stderr.print("mv: inter-device move failed: '{s}' to '{s}'; unable to remove target: {s}\n", .{ source, dest_path, c.strerror(un_err) });
                        }
                        exit_code = 1;
                        continue;
                    }
                }
            }

            if (!copyTreeForMove(allocator, source, dest_path, &hard_links, verbose, stdout, stderr)) {
                exit_code = 1;
                continue;
            }
            if (!removeTree(allocator, source, stderr)) {
                exit_code = 1;
                continue;
            }
            const duped_dest = try allocator.dupe(u8, dest_path);
            try created_dest_files.put(duped_dest, {});
        } else if (rename_err == c.EEXIST or rename_err == c.ENOTEMPTY) {
            try stderr.print("mv: cannot overwrite '{s}': {s}\n", .{ dest_path, c.strerror(rename_err) });
            exit_code = 1;
            continue;
        } else {
            try stderr.print("mv: cannot move '{s}' to '{s}': {s}\n", .{ source, dest_path, c.strerror(rename_err) });
            exit_code = 1;
            continue;
        }
    }

    return exit_code;
}

fn copyTreeForMove(
    allocator: std.mem.Allocator,
    src: []const u8,
    dest: []const u8,
    hard_links: *std.AutoHashMap(DevIno, []const u8),
    verbose: bool,
    stdout: anytype,
    stderr: anytype,
) bool {
    const src_z = allocator.dupeZ(u8, src) catch return false;
    defer allocator.free(src_z);
    const dest_z = allocator.dupeZ(u8, dest) catch return false;
    defer allocator.free(dest_z);

    var st: c.struct_stat = undefined;
    if (c.lstat(src_z.ptr, &st) != 0) {
        const err = c.__errno_location().*;
        stderr.print("mv: cannot stat '{s}': {s}\n", .{ src, c.strerror(err) }) catch {};
        return false;
    }

    if ((st.st_mode & c.S_IFMT) == c.S_IFDIR) {
        if (c.mkdir(dest_z.ptr, (st.st_mode & 0o7777) | 0o700) != 0) {
            const err = c.__errno_location().*;
            if (err != c.EEXIST) {
                stderr.print("mv: cannot move '{s}' to '{s}': {s}\n", .{ src, dest, c.strerror(err) }) catch {};
                return false;
            }
        }
        if (verbose) {
            stdout.print("created directory '{s}'\n", .{dest}) catch {};
        }
        var dir = std.Io.Dir.cwd().openDir(std.Options.debug_io, src, .{ .iterate = true }) catch |err| {
            errors.printErrorWithArg(stderr, name, src, err) catch {};
            return false;
        };
        defer dir.close(std.Options.debug_io);
        var it = dir.iterate();
        var all_ok = true;
        while (it.next(std.Options.debug_io) catch null) |entry| {
            const sub_src = std.fs.path.join(allocator, &[_][]const u8{ src, entry.name }) catch return false;
            defer allocator.free(sub_src);
            const sub_dest = std.fs.path.join(allocator, &[_][]const u8{ dest, entry.name }) catch return false;
            defer allocator.free(sub_dest);
            if (!copyTreeForMove(allocator, sub_src, sub_dest, hard_links, verbose, stdout, stderr)) {
                all_ok = false;
            }
        }
        _ = c.chmod(dest_z.ptr, st.st_mode & 0o7777);
        var times = [2]c.struct_timespec{ st.st_atim, st.st_mtim };
        _ = c.utimensat(c.AT_FDCWD, dest_z.ptr, &times, 0);
        return all_ok;
    }

    // Check hard links for non-directories
    // Even if st_nlink == 1, in move mode an earlier link was unlinked
    {
        const key = DevIno{ .dev = st.st_dev, .ino = st.st_ino };
        if (hard_links.get(key)) |earlier_dest| {
            const earlier_z = allocator.dupeZ(u8, earlier_dest) catch return false;
            defer allocator.free(earlier_z);
            _ = c.unlink(dest_z.ptr);
            if (c.link(earlier_z.ptr, dest_z.ptr) == 0) {
                if (verbose) {
                    stdout.print("copied '{s}' -> '{s}'\n", .{ src, dest }) catch {};
                }
                return true;
            }
        }
    }

    if ((st.st_mode & c.S_IFMT) == c.S_IFLNK) {
        var link_buf: [c.PATH_MAX]u8 = undefined;
        const len = c.readlink(src_z.ptr, &link_buf, link_buf.len - 1);
        if (len < 0) {
            const err = c.__errno_location().*;
            stderr.print("mv: cannot read symbolic link '{s}': {s}\n", .{ src, c.strerror(err) }) catch {};
            return false;
        }
        link_buf[@intCast(len)] = 0;
        _ = c.unlink(dest_z.ptr);
        if (c.symlink(&link_buf, dest_z.ptr) != 0) {
            const err = c.__errno_location().*;
            stderr.print("mv: cannot move '{s}' to '{s}': {s}\n", .{ src, dest, c.strerror(err) }) catch {};
            return false;
        }
        var times = [2]c.struct_timespec{ st.st_atim, st.st_mtim };
        _ = c.utimensat(c.AT_FDCWD, dest_z.ptr, &times, c.AT_SYMLINK_NOFOLLOW);
        if (st.st_nlink > 1) {
            const key = DevIno{ .dev = st.st_dev, .ino = st.st_ino };
            hard_links.put(key, allocator.dupe(u8, dest) catch return false) catch return false;
        }
        if (verbose) {
            stdout.print("copied '{s}' -> '{s}'\n", .{ src, dest }) catch {};
        }
        return true;
    } else if ((st.st_mode & c.S_IFMT) == c.S_IFIFO) {
        _ = c.unlink(dest_z.ptr);
        if (c.mkfifo(dest_z.ptr, st.st_mode & 0o7777) != 0) {
            const err = c.__errno_location().*;
            stderr.print("mv: cannot move '{s}' to '{s}': {s}\n", .{ src, dest, c.strerror(err) }) catch {};
            return false;
        }
        _ = c.chmod(dest_z.ptr, st.st_mode & 0o7777);
        var times = [2]c.struct_timespec{ st.st_atim, st.st_mtim };
        _ = c.utimensat(c.AT_FDCWD, dest_z.ptr, &times, 0);
        if (st.st_nlink > 1) {
            const key = DevIno{ .dev = st.st_dev, .ino = st.st_ino };
            hard_links.put(key, allocator.dupe(u8, dest) catch return false) catch return false;
        }
        if (verbose) {
            stdout.print("copied '{s}' -> '{s}'\n", .{ src, dest }) catch {};
        }
        return true;
    } else {
        const in_fd = c.open(src_z.ptr, c.O_RDONLY);
        if (in_fd < 0) {
            const err = c.__errno_location().*;
            stderr.print("mv: cannot open '{s}' for reading: {s}\n", .{ src, c.strerror(err) }) catch {};
            return false;
        }
        defer _ = c.close(in_fd);

        _ = c.unlink(dest_z.ptr);
        const out_fd = c.open(dest_z.ptr, c.O_WRONLY | c.O_CREAT | c.O_TRUNC, st.st_mode & 0o7777);
        if (out_fd < 0) {
            const err = c.__errno_location().*;
            stderr.print("mv: cannot move '{s}' to '{s}': {s}\n", .{ src, dest, c.strerror(err) }) catch {};
            return false;
        }
        defer _ = c.close(out_fd);

        var buf: [65536]u8 = undefined;
        while (true) {
            const n = c.read(in_fd, &buf, buf.len);
            if (n < 0) {
                const err = c.__errno_location().*;
                stderr.print("mv: error reading '{s}': {s}\n", .{ src, c.strerror(err) }) catch {};
                return false;
            }
            if (n == 0) break;
            var written: usize = 0;
            const to_write: usize = @intCast(n);
            while (written < to_write) {
                const w = c.write(out_fd, buf[written..to_write].ptr, to_write - written);
                if (w < 0) {
                    const err = c.__errno_location().*;
                    stderr.print("mv: error writing '{s}': {s}\n", .{ dest, c.strerror(err) }) catch {};
                    return false;
                }
                written += @intCast(w);
            }
        }
        _ = c.fchmod(out_fd, st.st_mode & 0o7777);
        var times = [2]c.struct_timespec{ st.st_atim, st.st_mtim };
        _ = c.futimens(out_fd, &times);
        if (st.st_nlink > 1) {
            const key = DevIno{ .dev = st.st_dev, .ino = st.st_ino };
            hard_links.put(key, allocator.dupe(u8, dest) catch return false) catch return false;
        }
        if (verbose) {
            stdout.print("copied '{s}' -> '{s}'\n", .{ src, dest }) catch {};
        }
        return true;
    }
}

fn removeTree(allocator: std.mem.Allocator, path: []const u8, stderr: anytype) bool {
    const path_z = allocator.dupeZ(u8, path) catch return false;
    defer allocator.free(path_z);

    var st: c.struct_stat = undefined;
    if (c.lstat(path_z.ptr, &st) != 0) return true;

    if ((st.st_mode & c.S_IFMT) == c.S_IFDIR) {
        var dir = std.Io.Dir.cwd().openDir(std.Options.debug_io, path, .{ .iterate = true }) catch return false;
        defer dir.close(std.Options.debug_io);
        var it = dir.iterate();
        var all_ok = true;
        while (it.next(std.Options.debug_io) catch null) |entry| {
            const sub = std.fs.path.join(allocator, &[_][]const u8{ path, entry.name }) catch return false;
            defer allocator.free(sub);
            if (!removeTree(allocator, sub, stderr)) {
                all_ok = false;
            }
        }
        if (c.rmdir(path_z.ptr) != 0) {
            const err = c.__errno_location().*;
            stderr.print("mv: cannot remove '{s}': {s}\n", .{ path, c.strerror(err) }) catch {};
            return false;
        }
        return all_ok;
    } else {
        if (c.unlink(path_z.ptr) != 0) {
            const err = c.__errno_location().*;
            stderr.print("mv: cannot remove '{s}': {s}\n", .{ path, c.strerror(err) }) catch {};
            return false;
        }
        return true;
    }
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: mv [OPTION]... SOURCE DEST
        \\  or:  mv [OPTION]... SOURCE... DIRECTORY
        \\  or:  mv [OPTION]... -t DIRECTORY SOURCE...
        \\Rename SOURCE to DEST, or move SOURCE(s) to DIRECTORY.
        \\
        \\  -b                           like --backup but does not accept an argument
        \\      --backup[=CONTROL]       make a backup of each existing destination file
        \\  -f, --force                  do not prompt before overwriting
        \\  -i, --interactive            prompt before overwrite
        \\  -n, --no-clobber             do not overwrite an existing file
        \\      --no-copy                do not copy if rename fails across file systems
        \\      --exchange               exchange source and destination
        \\  -S, --suffix=SUFFIX          override the usual backup suffix
        \\  -t, --target-directory=DIR   move all SOURCE arguments into DIR
        \\  -T, --no-target-directory    treat DEST as a normal file
        \\  -u, --update[=UPDATE]        control which existing files are replaced;
        \\                                 UPDATE={all,none,none-fail,older(default)}
        \\  -v, --verbose                explain what is being done
        \\      --help                   display this help and exit
        \\      --version                output version information and exit
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
