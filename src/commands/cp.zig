const std = @import("std");
const errors = @import("../utils/errors.zig");
const args_mod = @import("../utils/args.zig");
const backup_mod = @import("../utils/backup.zig");
const mode_mod = @import("../utils/mode.zig");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "cp";
pub const version: []const u8 = "0.1.0";

const cp_long_opts = &[_][]const u8{
    "--help",
    "--version",
    "--archive",
    "--attributes-only",
    "--copy-contents",
    "--debug",
    "--dereference",
    "--force",
    "--interactive",
    "--link",
    "--no-clobber",
    "--no-dereference",
    "--no-preserve",
    "--no-target-directory",
    "--one-file-system",
    "--parents",
    "--path",
    "--preserve",
    "--recursive",
    "--reflink",
    "--remove-destination",
    "--sparse",
    "--strip-trailing-slashes",
    "--suffix",
    "--symbolic-link",
    "--target-directory",
    "--update",
    "--verbose",
    "--backup",
};

const DerefMode = enum {
    unspecified,
    never,
    cmdline,
    always,
};

const UpdateMode = enum {
    not_set,
    all,
    older,
    none,
    none_fail,
};

const InteractiveMode = enum {
    unspecified,
    ask_user,
    always_skip,
};

const ReflinkMode = enum {
    auto,
    always,
    never,
};

const SparseMode = enum {
    auto,
    always,
    never,
};

const PreserveFlags = struct {
    mode: bool = false,
    ownership: bool = false,
    timestamps: bool = false,
    links: bool = false,
    context: bool = false,
    xattr: bool = false,
};

const DevIno = struct {
    dev: c.dev_t,
    ino: c.ino_t,
};

fn isZeroBuffer(buf: []const u8) bool {
    for (buf) |byte| {
        if (byte != 0) return false;
    }
    return true;
}

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

fn sameFileOk(
    allocator: std.mem.Allocator,
    src_name: []const u8,
    src_sb: *const c.struct_stat,
    dst_name: []const u8,
    dst_sb: *const c.struct_stat,
    deref: DerefMode,
    backup_type: backup_mod.BackupType,
    unlink_dest_before_opening: bool,
    move_mode: bool,
    hard_link: bool,
    symbolic_link: bool,
    return_now: *bool,
) bool {
    return_now.* = false;

    const same = (src_sb.st_dev == dst_sb.st_dev and src_sb.st_ino == dst_sb.st_ino);
    if (same and hard_link) {
        return_now.* = true;
        return true;
    }

    var src_sb_link: *const c.struct_stat = src_sb;
    var dst_sb_link: *const c.struct_stat = dst_sb;
    var tmp_dst_sb: c.struct_stat = undefined;
    var tmp_src_sb: c.struct_stat = undefined;
    var same_link: bool = false;

    if (deref == .never) {
        same_link = same;
        if ((src_sb.st_mode & c.S_IFMT) == c.S_IFLNK and (dst_sb.st_mode & c.S_IFMT) == c.S_IFLNK) {
            const sn = isSameEntry(allocator, src_name, dst_name);
            if (!sn) {
                if (backup_type != .none) return true;
                if (same_link) {
                    return_now.* = true;
                    return !move_mode;
                }
            }
            return !sn;
        }
    } else {
        if (!same) return true;
        const dst_z = allocator.dupeZ(u8, dst_name) catch return true;
        defer allocator.free(dst_z);
        const src_z = allocator.dupeZ(u8, src_name) catch return true;
        defer allocator.free(src_z);

        if (c.lstat(dst_z.ptr, &tmp_dst_sb) != 0 or c.lstat(src_z.ptr, &tmp_src_sb) != 0) {
            return true;
        }
        src_sb_link = &tmp_src_sb;
        dst_sb_link = &tmp_dst_sb;
        same_link = (src_sb_link.st_dev == dst_sb_link.st_dev and src_sb_link.st_ino == dst_sb_link.st_ino);

        if ((src_sb_link.st_mode & c.S_IFMT) == c.S_IFLNK and (dst_sb_link.st_mode & c.S_IFMT) == c.S_IFLNK and unlink_dest_before_opening) {
            return true;
        }
    }

    if (backup_type != .none) {
        if (!same_link) {
            if (!move_mode and deref != .never and (src_sb_link.st_mode & c.S_IFMT) == c.S_IFLNK and (dst_sb_link.st_mode & c.S_IFMT) != c.S_IFLNK) {
                return false;
            }
            return true;
        }
        return !isSameEntry(allocator, src_name, dst_name);
    }

    if (move_mode or unlink_dest_before_opening) {
        if ((dst_sb_link.st_mode & c.S_IFMT) == c.S_IFLNK) {
            return true;
        }
        if (same_link and dst_sb_link.st_nlink > 1 and !isSameEntry(allocator, src_name, dst_name)) {
            return !move_mode;
        }
    }

    if ((src_sb_link.st_mode & c.S_IFMT) != c.S_IFLNK and (dst_sb_link.st_mode & c.S_IFMT) != c.S_IFLNK) {
        if (!(src_sb_link.st_dev == dst_sb_link.st_dev and src_sb_link.st_ino == dst_sb_link.st_ino)) {
            return true;
        }
        if (hard_link) {
            return_now.* = true;
            return true;
        }
    }

    if (move_mode and (src_sb.st_mode & c.S_IFMT) == c.S_IFLNK and dst_sb_link.st_nlink > 1) {
        const src_z = allocator.dupeZ(u8, src_name) catch return false;
        defer allocator.free(src_z);
        if (c.realpath(src_z.ptr, null)) |abs_src| {
            defer c.free(abs_src);
            const abs_slice = std.mem.span(abs_src);
            return !isSameEntry(allocator, abs_slice, dst_name);
        }
    }

    if (symbolic_link and (dst_sb_link.st_mode & c.S_IFMT) == c.S_IFLNK) {
        return true;
    }

    if (deref == .never) {
        const src_z = allocator.dupeZ(u8, src_name) catch return true;
        defer allocator.free(src_z);
        const dst_z = allocator.dupeZ(u8, dst_name) catch return true;
        defer allocator.free(dst_z);

        if ((src_sb_link.st_mode & c.S_IFMT) != c.S_IFLNK) {
            tmp_src_sb = src_sb_link.*;
        } else if (c.stat(src_z.ptr, &tmp_src_sb) != 0) {
            return true;
        }

        if ((dst_sb_link.st_mode & c.S_IFMT) != c.S_IFLNK) {
            tmp_dst_sb = dst_sb_link.*;
        } else if (c.stat(dst_z.ptr, &tmp_dst_sb) != 0) {
            return true;
        }

        if (!(tmp_src_sb.st_dev == tmp_dst_sb.st_dev and tmp_src_sb.st_ino == tmp_dst_sb.st_ino)) {
            return true;
        }

        if (hard_link) {
            return_now.* = ((dst_sb_link.st_mode & c.S_IFMT) != c.S_IFLNK);
            return true;
        }
    }

    return false;
}

fn parsePreserve(val: ?[]const u8, flags: *PreserveFlags, enable: bool, explicit_no_preserve_mode: *bool) void {
    if (val) |v| {
        var it = std.mem.splitScalar(u8, v, ',');
        while (it.next()) |item| {
            if (item.len == 0) continue;
            if (std.mem.startsWith(u8, "all", item)) {
                flags.mode = enable;
                flags.ownership = enable;
                flags.timestamps = enable;
                flags.links = enable;
                flags.context = enable;
                flags.xattr = enable;
                if (enable) explicit_no_preserve_mode.* = false;
            } else if (std.mem.startsWith(u8, "mode", item)) {
                flags.mode = enable;
                explicit_no_preserve_mode.* = !enable;
            } else if (std.mem.startsWith(u8, "ownership", item)) {
                flags.ownership = enable;
            } else if (std.mem.startsWith(u8, "timestamps", item)) {
                flags.timestamps = enable;
            } else if (std.mem.startsWith(u8, "links", item)) {
                flags.links = enable;
            } else if (std.mem.startsWith(u8, "context", item)) {
                flags.context = enable;
            } else if (std.mem.startsWith(u8, "xattr", item)) {
                flags.xattr = enable;
            }
        }
    } else {
        flags.mode = enable;
        flags.ownership = enable;
        flags.timestamps = enable;
        if (enable) explicit_no_preserve_mode.* = false;
    }
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

    var recursive = false;
    var verbose = false;
    var debug = false;
    var explicit_no_preserve_mode = false;
    var deref: DerefMode = .unspecified;
    var update_mode: UpdateMode = .not_set;
    var interactive_mode: InteractiveMode = .unspecified;
    var reflink: ReflinkMode = .never;
    var sparse: SparseMode = .auto;
    var preserve: PreserveFlags = .{};
    var unlink_dest_before_opening = false;
    var unlink_dest_after_failed_open = false;
    var parents = false;
    var hard_link = false;
    var symbolic_link = false;
    var attributes_only = false;
    var copy_contents = false;
    var one_file_system = false;
    _ = &one_file_system;
    var strip_trailing_slashes = false;
    _ = &strip_trailing_slashes;
    var backup_type: backup_mod.BackupType = .none;
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

            const matched = args_mod.matchLongOption(opt_name, cp_long_opts);
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
            } else if (std.mem.eql(u8, opt, "--archive")) {
                deref = .never;
                recursive = true;
                parsePreserve("all", &preserve, true, &explicit_no_preserve_mode);
            } else if (std.mem.eql(u8, opt, "--attributes-only")) {
                attributes_only = true;
            } else if (std.mem.eql(u8, opt, "--copy-contents")) {
                copy_contents = true;
            } else if (std.mem.eql(u8, opt, "--debug")) {
                debug = true;
            } else if (std.mem.eql(u8, opt, "--dereference")) {
                deref = .always;
            } else if (std.mem.eql(u8, opt, "--force")) {
                unlink_dest_after_failed_open = true;
            } else if (std.mem.eql(u8, opt, "--interactive")) {
                interactive_mode = .ask_user;
            } else if (std.mem.eql(u8, opt, "--link")) {
                hard_link = true;
            } else if (std.mem.eql(u8, opt, "--no-clobber")) {
                interactive_mode = .always_skip;
            } else if (std.mem.eql(u8, opt, "--no-dereference")) {
                deref = .never;
            } else if (std.mem.eql(u8, opt, "--no-preserve")) {
                if (opt_val) |val| {
                    parsePreserve(val, &preserve, false, &explicit_no_preserve_mode);
                } else {
                    i += 1;
                    if (i >= args.len) {
                        try errors.printError(stderr, name, "option '--no-preserve' requires an argument");
                        return 1;
                    }
                    parsePreserve(args[i], &preserve, false, &explicit_no_preserve_mode);
                }
            } else if (std.mem.eql(u8, opt, "--no-target-directory")) {
                no_target_dir = true;
            } else if (std.mem.eql(u8, opt, "--one-file-system")) {
                one_file_system = true;
            } else if (std.mem.eql(u8, opt, "--parents") or std.mem.eql(u8, opt, "--path")) {
                parents = true;
            } else if (std.mem.eql(u8, opt, "--preserve")) {
                parsePreserve(opt_val, &preserve, true, &explicit_no_preserve_mode);
            } else if (std.mem.eql(u8, opt, "--recursive")) {
                recursive = true;
            } else if (std.mem.eql(u8, opt, "--reflink")) {
                if (opt_val) |val| {
                    if (std.mem.eql(u8, val, "always")) {
                        reflink = .always;
                    } else if (std.mem.eql(u8, val, "auto")) {
                        reflink = .auto;
                    } else if (std.mem.eql(u8, val, "never")) {
                        reflink = .never;
                    } else {
                        try errors.printError(stderr, name, "invalid argument for --reflink");
                        return 1;
                    }
                } else {
                    reflink = .always;
                }
            } else if (std.mem.eql(u8, opt, "--remove-destination")) {
                unlink_dest_before_opening = true;
            } else if (std.mem.eql(u8, opt, "--sparse")) {
                if (opt_val) |val| {
                    if (std.mem.eql(u8, val, "always")) {
                        sparse = .always;
                    } else if (std.mem.eql(u8, val, "auto")) {
                        sparse = .auto;
                    } else if (std.mem.eql(u8, val, "never")) {
                        sparse = .never;
                    } else {
                        try errors.printError(stderr, name, "invalid argument for --sparse");
                        return 1;
                    }
                } else {
                    i += 1;
                    if (i >= args.len) {
                        try errors.printError(stderr, name, "option '--sparse' requires an argument");
                        return 1;
                    }
                    if (std.mem.eql(u8, args[i], "always")) {
                        sparse = .always;
                    } else if (std.mem.eql(u8, args[i], "auto")) {
                        sparse = .auto;
                    } else if (std.mem.eql(u8, args[i], "never")) {
                        sparse = .never;
                    } else {
                        try errors.printError(stderr, name, "invalid argument for --sparse");
                        return 1;
                    }
                }
            } else if (std.mem.eql(u8, opt, "--strip-trailing-slashes")) {
                strip_trailing_slashes = true;
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
            } else if (std.mem.eql(u8, opt, "--symbolic-link")) {
                symbolic_link = true;
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
            } else if (std.mem.eql(u8, opt, "--verbose")) {
                verbose = true;
            } else if (std.mem.eql(u8, opt, "--backup")) {
                if (opt_val) |val| {
                    backup_type = backup_mod.parseBackupType(val) orelse {
                        try errors.printError(stderr, name, "invalid backup type");
                        return 1;
                    };
                } else {
                    backup_type = backup_mod.getVersionControl();
                }
            }
        } else {
            var j: usize = 1;
            while (j < arg.len) : (j += 1) {
                const c_opt = arg[j];
                switch (c_opt) {
                    'a' => {
                        deref = .never;
                        recursive = true;
                        parsePreserve("all", &preserve, true, &explicit_no_preserve_mode);
                    },
                    'b' => backup_type = backup_mod.getVersionControl(),
                    'd' => {
                        deref = .never;
                        preserve.links = true;
                    },
                    'f' => unlink_dest_after_failed_open = true,
                    'H' => deref = .cmdline,
                    'i' => interactive_mode = .ask_user,
                    'l' => hard_link = true,
                    'L' => deref = .always,
                    'n' => {
                        interactive_mode = .always_skip;
                    },
                    'P' => deref = .never,
                    'p' => {
                        preserve.mode = true;
                        preserve.ownership = true;
                        preserve.timestamps = true;
                        explicit_no_preserve_mode = false;
                    },
                    'r', 'R' => recursive = true,
                    's' => symbolic_link = true,
                    'T' => no_target_dir = true,
                    'u' => update_mode = .older,
                    'v' => verbose = true,
                    'x' => one_file_system = true,
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

    if (interactive_mode == .always_skip) {
        update_mode = .none;
    }

    if (backup_type != .none and (interactive_mode == .always_skip or update_mode == .none or update_mode == .none_fail)) {
        try errors.printError(stderr, name, "options --backup and --no-clobber are mutually exclusive");
        return 1;
    }

    if (target_dir != null and no_target_dir) {
        try errors.printError(stderr, name, "cannot combine --target-directory (-t) and --no-target-directory (-T)");
        return 1;
    }

    if (reflink == .always and sparse != .auto) {
        try errors.printError(stderr, name, "--reflink can be used only with --sparse=auto");
        return 1;
    }

    if (deref == .unspecified) {
        if (recursive and !hard_link) {
            deref = .never;
        } else {
            deref = .always;
        }
    }

    if (file_start >= args.len) {
        try errors.printError(stderr, name, "missing file operand");
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
            try errors.printError(stderr, name, msg);
            return 1;
        }
        sources = args[file_start .. args.len - 1];
        dest = args[args.len - 1];
    }

    const dest_z = try allocator.dupeZ(u8, dest);
    defer allocator.free(dest_z);

    var dest_stat: c.struct_stat = undefined;
    const dest_stat_res = c.stat(dest_z.ptr, &dest_stat);
    const dest_stat_err = if (dest_stat_res != 0) c.__errno_location().* else 0;
    const dest_exists = (dest_stat_res == 0);
    const dest_is_dir = if (no_target_dir) false else (dest_exists and (dest_stat.st_mode & c.S_IFMT) == c.S_IFDIR);

    if (parents and !dest_is_dir) {
        const msg = if (!dest_exists)
            try std.fmt.allocPrint(allocator, "target directory '{s}': {s}", .{ dest, c.strerror(dest_stat_err) })
        else
            try std.fmt.allocPrint(allocator, "target '{s}' is not a directory", .{dest});
        defer allocator.free(msg);
        try errors.printError(stderr, name, msg);
        return 1;
    }

    if (target_dir != null) {
        if (!dest_is_dir) {
            const msg = if (!dest_exists)
                try std.fmt.allocPrint(allocator, "target directory '{s}': {s}", .{ dest, c.strerror(dest_stat_err) })
            else
                try std.fmt.allocPrint(allocator, "target directory '{s}': Not a directory", .{dest});
            defer allocator.free(msg);
            try errors.printError(stderr, name, msg);
            return 1;
        }
    } else {
        if (sources.len > 1 and !dest_is_dir) {
            const msg = if (!dest_exists)
                try std.fmt.allocPrint(allocator, "target '{s}': {s}", .{ dest, c.strerror(dest_stat_err) })
            else
                try std.fmt.allocPrint(allocator, "target '{s}': Not a directory", .{dest});
            defer allocator.free(msg);
            try errors.printError(stderr, name, msg);
            return 1;
        }
    }

    if (no_target_dir and sources.len > 1) {
        const msg = try std.fmt.allocPrint(allocator, "extra operand '{s}'", .{sources[1]});
        defer allocator.free(msg);
        try errors.printError(stderr, name, msg);
        return 1;
    }

    var seen_sources: std.ArrayList([]const u8) = .empty;
    defer seen_sources.deinit(allocator);

    var hard_links = std.AutoHashMap(DevIno, []const u8).init(allocator);
    defer {
        var it = hard_links.valueIterator();
        while (it.next()) |val| {
            allocator.free(val.*);
        }
        hard_links.deinit();
    }

    var created_dest_files = std.AutoHashMap(DevIno, void).init(allocator);
    defer created_dest_files.deinit();

    var created_dest_paths = std.StringHashMap(void).init(allocator);
    defer {
        var it = created_dest_paths.keyIterator();
        while (it.next()) |k| allocator.free(k.*);
        created_dest_paths.deinit();
    }

    var created_symlinks = std.StringHashMap(void).init(allocator);
    defer {
        var it = created_symlinks.keyIterator();
        while (it.next()) |k| allocator.free(k.*);
        created_symlinks.deinit();
    }

    const ParentDirAttr = struct {
        path: []const u8,
        mode: c.mode_t,
        uid: c.uid_t,
        gid: c.gid_t,
        atim: c.struct_timespec,
        mtim: c.struct_timespec,
    };
    var parents_to_reprotect: std.ArrayList(ParentDirAttr) = .empty;
    defer {
        for (parents_to_reprotect.items) |item| allocator.free(item.path);
        parents_to_reprotect.deinit(allocator);
    }

    var exit_code: u8 = 0;
    for (sources) |source| {
        const src_z = try allocator.dupeZ(u8, source);
        defer allocator.free(src_z);

        const should_deref_cmdline = (deref == .always or deref == .cmdline);
        var src_lst: c.struct_stat = undefined;
        const src_lst_ok = if (should_deref_cmdline)
            (c.stat(src_z.ptr, &src_lst) == 0)
        else
            (c.lstat(src_z.ptr, &src_lst) == 0);

        if (!src_lst_ok) {
            const err = c.__errno_location().*;
            try stderr.print("cp: cannot stat '{s}': {s}\n", .{ source, c.strerror(err) });
            exit_code = 1;
            continue;
        }

        // Duplicate source check on command line
        const src_is_dir = (src_lst.st_mode & c.S_IFMT) == c.S_IFDIR;
        if (backup_type == .none) {
            var already_seen = false;
            for (seen_sources.items) |prev| {
                if (isSameEntry(allocator, prev, source)) {
                    already_seen = true;
                    break;
                }
            }
            if (already_seen) {
                if (src_is_dir) {
                    try stderr.print("cp: warning: source directory '{s}' specified more than once\n", .{source});
                } else {
                    try stderr.print("cp: warning: source file '{s}' specified more than once\n", .{source});
                }
                continue;
            }
        }
        try seen_sources.append(allocator, source);

        var dest_path: []const u8 = undefined;
        var dest_path_allocated = false;
        defer if (dest_path_allocated) allocator.free(dest_path);

        if (parents) {
            var clean_src = source;
            while (clean_src.len > 0 and clean_src[0] == '/') clean_src = clean_src[1..];
            while (clean_src.len > 1 and clean_src[clean_src.len - 1] == '/') clean_src = clean_src[0 .. clean_src.len - 1];
            if (std.fs.path.dirname(clean_src)) |pdir| {
                // Ensure parent directory components exist
                var parent_ok = true;
                var comp_it = std.mem.splitScalar(u8, pdir, '/');
                var rel_path: ?[]const u8 = null;
                defer if (rel_path) |rp| allocator.free(rp);
                while (comp_it.next()) |comp| {
                    if (comp.len == 0) continue;
                    const new_rel = if (rel_path) |rp|
                        try std.fs.path.join(allocator, &.{ rp, comp })
                    else
                        try allocator.dupe(u8, comp);
                    if (rel_path) |rp| allocator.free(rp);
                    rel_path = new_rel;

                    // Check that the corresponding component in source actually exists as directory
                    const comp_src = if (source.len > 0 and source[0] == '/')
                        try std.fs.path.join(allocator, &.{ "/", new_rel })
                    else
                        try allocator.dupe(u8, new_rel);
                    defer allocator.free(comp_src);
                    const comp_src_z = try allocator.dupeZ(u8, comp_src);
                    defer allocator.free(comp_src_z);
                    var comp_st: c.struct_stat = undefined;
                    if (c.stat(comp_src_z.ptr, &comp_st) != 0 or (comp_st.st_mode & c.S_IFMT) != c.S_IFDIR) {
                        parent_ok = false;
                        break;
                    }

                    const target_parent = try std.fs.path.join(allocator, &[_][]const u8{ dest, new_rel });
                    defer allocator.free(target_parent);
                    const target_parent_z = try allocator.dupeZ(u8, target_parent);
                    defer allocator.free(target_parent_z);

                    var target_st: c.struct_stat = undefined;
                    if (c.stat(target_parent_z.ptr, &target_st) != 0) {
                        const src_mode: c.mode_t = if (explicit_no_preserve_mode) 0o777 else (comp_st.st_mode & 0o7777);
                        const omitted_permissions: c.mode_t = if (preserve.ownership)
                            0o077
                        else if (preserve.mode)
                            0o022
                        else
                            0;
                        const mkdir_mode = 0o700 | (src_mode & ~omitted_permissions);
                        if (c.mkdir(target_parent_z.ptr, mkdir_mode) != 0) {
                            const err = c.__errno_location().*;
                            if (err != c.EEXIST) {
                                try stderr.print("cp: cannot make directory '{s}': {s}\n", .{ target_parent, c.strerror(err) });
                                parent_ok = false;
                                break;
                            }
                        }
                        if (preserve.mode or preserve.ownership or preserve.timestamps) {
                            try parents_to_reprotect.append(allocator, .{
                                .path = try allocator.dupe(u8, target_parent),
                                .mode = comp_st.st_mode & 0o7777,
                                .uid = comp_st.st_uid,
                                .gid = comp_st.st_gid,
                                .atim = comp_st.st_atim,
                                .mtim = comp_st.st_mtim,
                            });
                        }
                    } else if ((target_st.st_mode & c.S_IFMT) != c.S_IFDIR) {
                        try stderr.print("cp: cannot overwrite non-directory '{s}' with directory '{s}'\n", .{ target_parent, comp_src });
                        parent_ok = false;
                        break;
                    } else {
                        if (preserve.mode or preserve.ownership or preserve.timestamps) {
                            try parents_to_reprotect.append(allocator, .{
                                .path = try allocator.dupe(u8, target_parent),
                                .mode = comp_st.st_mode & 0o7777,
                                .uid = comp_st.st_uid,
                                .gid = comp_st.st_gid,
                                .atim = comp_st.st_atim,
                                .mtim = comp_st.st_mtim,
                            });
                        }
                    }
                }
                if (!parent_ok) {
                    exit_code = 1;
                    continue;
                }
            }
            dest_path = try std.fs.path.join(allocator, &[_][]const u8{ dest, clean_src });
            dest_path_allocated = true;
        } else if (dest_is_dir) {
            var clean_source = source;
            while (clean_source.len > 1 and clean_source[clean_source.len - 1] == '/') {
                clean_source = clean_source[0 .. clean_source.len - 1];
            }
            const base_name = std.fs.path.basename(clean_source);
            if (std.mem.eql(u8, base_name, ".") or std.mem.eql(u8, base_name, "..")) {
                dest_path = try allocator.dupe(u8, dest);
            } else {
                dest_path = try std.fs.path.join(allocator, &[_][]const u8{ dest, base_name });
            }
            dest_path_allocated = true;
        } else {
            dest_path = dest;
            dest_path_allocated = false;
        }

        // Trailing slash handling on destination
        var cur_dest_z = try allocator.dupeZ(u8, dest_path);
        defer allocator.free(cur_dest_z);
        var dst_lst: c.struct_stat = undefined;
        var dst_lst_ok = (c.lstat(cur_dest_z.ptr, &dst_lst) == 0);

        if (std.mem.endsWith(u8, dest_path, "/") and !dst_lst_ok) {
            if (!src_is_dir) {
                try stderr.print("cp: cannot create regular file '{s}': Not a directory\n", .{dest_path});
                exit_code = 1;
                continue;
            }
            while (dest_path.len > 1 and dest_path[dest_path.len - 1] == '/') {
                dest_path = dest_path[0 .. dest_path.len - 1];
            }
            allocator.free(cur_dest_z);
            cur_dest_z = try allocator.dupeZ(u8, dest_path);
            dst_lst_ok = (c.lstat(cur_dest_z.ptr, &dst_lst) == 0);
        }

        // Check copying directory into itself
        if (src_is_dir) {
            if (!recursive) {
                try stderr.print("cp: -r not specified; omitting directory '{s}'\n", .{source});
                exit_code = 1;
                continue;
            }
            var src_real_buf: [c.PATH_MAX]u8 = undefined;
            var dst_real_buf: [c.PATH_MAX]u8 = undefined;
            if (c.realpath(src_z.ptr, &src_real_buf) != null) {
                const src_real = std.mem.span(@as([*:0]const u8, @ptrCast(&src_real_buf)));
                var inside_self = false;
                if (c.realpath(cur_dest_z.ptr, &dst_real_buf) != null) {
                    const dst_real = std.mem.span(@as([*:0]const u8, @ptrCast(&dst_real_buf)));
                    if (std.mem.startsWith(u8, dst_real, src_real) and (dst_real.len == src_real.len or dst_real[src_real.len] == '/')) {
                        inside_self = true;
                    }
                } else {
                    const dest_dir = std.fs.path.dirname(dest_path) orelse ".";
                    const dest_dir_z = try allocator.dupeZ(u8, dest_dir);
                    defer allocator.free(dest_dir_z);
                    if (c.realpath(dest_dir_z.ptr, &dst_real_buf) != null) {
                        const dst_parent_real = std.mem.span(@as([*:0]const u8, @ptrCast(&dst_real_buf)));
                        if (std.mem.startsWith(u8, dst_parent_real, src_real) and (dst_parent_real.len == src_real.len or dst_parent_real[src_real.len] == '/')) {
                            inside_self = true;
                        }
                    }
                }
                if (inside_self) {
                    try stderr.print("cp: cannot copy a directory, '{s}', into itself, '{s}'\n", .{ source, dest_path });
                    exit_code = 1;
                    continue;
                }
            }
        }

        // Special case: cp --force --backup foo foo
        var effective_backup_type = backup_type;
        var actual_dest_path = dest_path;
        var actual_dest_allocated = false;
        defer if (actual_dest_allocated) allocator.free(actual_dest_path);

        if (unlink_dest_after_failed_open and backup_type != .none and !src_is_dir and isSameEntry(allocator, source, dest_path)) {
            if (backup_mod.findBackupPath(allocator, dest_path, backup_type, backup_suffix) catch null) |bp| {
                actual_dest_path = bp;
                actual_dest_allocated = true;
                effective_backup_type = .none;
                allocator.free(cur_dest_z);
                cur_dest_z = try allocator.dupeZ(u8, actual_dest_path);
                dst_lst_ok = (c.lstat(cur_dest_z.ptr, &dst_lst) == 0);
            }
        }

        // Never copy through a symlink we've just created
        if (created_symlinks.contains(actual_dest_path) or (dst_lst_ok and (dst_lst.st_mode & c.S_IFMT) == c.S_IFLNK and created_dest_files.contains(DevIno{ .dev = dst_lst.st_dev, .ino = dst_lst.st_ino }))) {
            try stderr.print("cp: will not copy '{s}' through just-created symlink '{s}'\n", .{ source, actual_dest_path });
            exit_code = 1;
            continue;
        }

        // Dangling symlink check
        if (dst_lst_ok and (dst_lst.st_mode & c.S_IFMT) == c.S_IFLNK and !unlink_dest_before_opening) {
            var target_stat: c.struct_stat = undefined;
            if (c.stat(cur_dest_z.ptr, &target_stat) != 0) {
                const stat_err = c.__errno_location().*;
                if (stat_err == c.ENOENT) {
                    if (deref != .never and !symbolic_link and !src_is_dir and (src_lst.st_mode & c.S_IFMT) == c.S_IFREG) {
                        if (c.getenv("POSIXLY_CORRECT") == null) {
                            try stderr.print("cp: not writing through dangling symlink '{s}'\n", .{actual_dest_path});
                            exit_code = 1;
                            continue;
                        }
                    }
                } else if (stat_err == c.ELOOP and (unlink_dest_after_failed_open or unlink_dest_before_opening)) {
                    _ = c.unlink(cur_dest_z.ptr);
                    dst_lst_ok = false;
                } else if (deref != .never and !symbolic_link and !hard_link) {
                    try stderr.print("cp: cannot stat '{s}': {s}\n", .{ actual_dest_path, c.strerror(stat_err) });
                    exit_code = 1;
                    continue;
                }
            }
        }

        // Same file check
        if (dst_lst_ok) {
            var src_eff_st: c.struct_stat = undefined;
            var dst_eff_st: c.struct_stat = undefined;
            const src_st_ok = if (deref == .always or deref == .cmdline)
                (c.stat(src_z.ptr, &src_eff_st) == 0)
            else
                (c.lstat(src_z.ptr, &src_eff_st) == 0);

            const src_is_reg = (src_lst.st_mode & c.S_IFMT) == c.S_IFREG;
            const src_is_lnk = (src_lst.st_mode & c.S_IFMT) == c.S_IFLNK;
            const dst_use_lstat = ((!src_is_reg and (src_is_dir or src_is_lnk)) or unlink_dest_before_opening or effective_backup_type != .none or symbolic_link or hard_link);

            const dst_st_ok = if (dst_use_lstat)
                (c.lstat(cur_dest_z.ptr, &dst_eff_st) == 0)
            else
                (c.stat(cur_dest_z.ptr, &dst_eff_st) == 0);

            if (src_st_ok and dst_st_ok) {
                var return_now = false;
                if (!sameFileOk(
                    allocator,
                    source,
                    &src_eff_st,
                    actual_dest_path,
                    &dst_eff_st,
                    deref,
                    effective_backup_type,
                    unlink_dest_before_opening,
                    false,
                    hard_link,
                    symbolic_link,
                    &return_now,
                )) {
                    try stderr.print("cp: '{s}' and '{s}' are the same file\n", .{ source, actual_dest_path });
                    exit_code = 1;
                    continue;
                }
                if (return_now) {
                    continue;
                }
            }
        }

        // Directory vs Non-directory overwrite check
        if (dst_lst_ok and effective_backup_type == .none) {
            const dst_is_dir_entry = (dst_lst.st_mode & c.S_IFMT) == c.S_IFDIR;
            if (src_is_dir != dst_is_dir_entry) {
                if (src_is_dir) {
                    try stderr.print("cp: cannot overwrite non-directory '{s}' with directory '{s}'\n", .{ actual_dest_path, source });
                } else {
                    try stderr.print("cp: cannot overwrite directory '{s}' with non-directory '{s}'\n", .{ actual_dest_path, source });
                }
                exit_code = 1;
                continue;
            }
        }

        // Will not overwrite just-created check
        const dst_key = DevIno{ .dev = dst_lst.st_dev, .ino = dst_lst.st_ino };
        const just_created = created_dest_paths.contains(actual_dest_path) or (dst_lst_ok and created_dest_files.contains(dst_key));
        if (dst_lst_ok and just_created and effective_backup_type != .numbered) {
            try stderr.print("cp: will not overwrite just-created '{s}' with '{s}'\n", .{ actual_dest_path, source });
            exit_code = 1;
            continue;
        }

        // Overwrite prompt and update mode
        if (dst_lst_ok) {
            if (interactive_mode == .always_skip or update_mode == .none) {
                if (debug) {
                    try stdout.print("skipped '{s}'\n", .{actual_dest_path});
                }
                continue;
            }
            if (update_mode == .none_fail) {
                try stderr.print("cp: not replacing '{s}': File exists\n", .{actual_dest_path});
                exit_code = 1;
                continue;
            }
            if (update_mode == .older and !src_is_dir) {
                if (dst_lst.st_mtim.tv_sec > src_lst.st_mtim.tv_sec or
                    (dst_lst.st_mtim.tv_sec == src_lst.st_mtim.tv_sec and dst_lst.st_mtim.tv_nsec >= src_lst.st_mtim.tv_nsec))
                {
                    continue;
                }
            }

            if (interactive_mode == .ask_user) {
                const is_writable = ((dst_lst.st_mode & c.S_IFMT) == c.S_IFLNK) or (c.access(cur_dest_z.ptr, c.W_OK) == 0);
                var buf: [9]u8 = undefined;
                const mode_oct = @as(u32, @intCast(dst_lst.st_mode & 0o7777));
                const perms = mode_mod.formatMode(mode_oct, &buf);
                if (!is_writable) {
                    if (unlink_dest_after_failed_open or unlink_dest_before_opening) {
                        try stderr.print("cp: replace '{s}', overriding mode {o:0>4} ({s})? ", .{ actual_dest_path, mode_oct, perms });
                    } else {
                        try stderr.print("cp: unwritable '{s}' (mode {o:0>4}, {s}); try anyway? ", .{ actual_dest_path, mode_oct, perms });
                    }
                } else {
                    try stderr.print("cp: overwrite '{s}'? ", .{actual_dest_path});
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

        // Backup
        const dst_is_dir_type = dst_lst_ok and (dst_lst.st_mode & c.S_IFMT) == c.S_IFDIR;
        if (dst_lst_ok and effective_backup_type != .none and !dst_is_dir_type) {
            const backup_path = (try backup_mod.findBackupPath(allocator, actual_dest_path, effective_backup_type, backup_suffix)) orelse actual_dest_path;
            defer if (backup_path.ptr != actual_dest_path.ptr) allocator.free(backup_path);

            if (backup_mod.isBackupSource(backup_path, source)) {
                try stderr.print("cp: backing up '{s}' might destroy source;  '{s}' not copied\n", .{ actual_dest_path, source });
                exit_code = 1;
                continue;
            }

            const backup_z = try allocator.dupeZ(u8, backup_path);
            defer allocator.free(backup_z);
            if (c.rename(cur_dest_z.ptr, backup_z.ptr) != 0) {
                const err = c.__errno_location().*;
                try stderr.print("cp: cannot backup '{s}': {s}\n", .{ actual_dest_path, c.strerror(err) });
                exit_code = 1;
                continue;
            }
            dst_lst_ok = false;
        }

        // Remove destination
        if (dst_lst_ok and !dst_is_dir_type) {
            const data_copy_required = !attributes_only and !symbolic_link and !hard_link;
            const should_unlink_early = unlink_dest_before_opening or
                (data_copy_required and ((preserve.links and dst_lst.st_nlink > 1) or
                    (deref == .never and (src_lst.st_mode & c.S_IFMT) != c.S_IFREG) or
                    ((src_lst.st_mode & c.S_IFMT) == c.S_IFIFO and !copy_contents)));
            if (should_unlink_early) {
                if (c.unlink(cur_dest_z.ptr) == 0) {
                    dst_lst_ok = false;
                    if (verbose) {
                        try stdout.print("removed '{s}'\n", .{actual_dest_path});
                    }
                }
            }
        }

        // Hard link (-l) for files only
        if (hard_link and !src_is_dir) {
            if (dst_lst_ok and (unlink_dest_after_failed_open or unlink_dest_before_opening)) {
                _ = c.unlink(cur_dest_z.ptr);
            }
            const link_flags: c_int = if (deref == .always or deref == .cmdline) c.AT_SYMLINK_FOLLOW else 0;
            if (c.linkat(c.AT_FDCWD, src_z.ptr, c.AT_FDCWD, cur_dest_z.ptr, link_flags) != 0) {
                const err = c.__errno_location().*;
                try stderr.print("cp: cannot create hard link '{s}' to '{s}': {s}\n", .{ actual_dest_path, source, c.strerror(err) });
                exit_code = 1;
                continue;
            }
            created_dest_paths.put(try allocator.dupe(u8, actual_dest_path), {}) catch {};
            var new_dst_st: c.struct_stat = undefined;
            if (c.lstat(cur_dest_z.ptr, &new_dst_st) == 0) {
                created_dest_files.put(DevIno{ .dev = new_dst_st.st_dev, .ino = new_dst_st.st_ino }, {}) catch {};
            }
            if (verbose) {
                try stdout.print("'{s}' -> '{s}'\n", .{ source, actual_dest_path });
            }
            continue;
        }

        // Symbolic link (-s) for files only
        if (symbolic_link and !src_is_dir) {
            if (dst_lst_ok and (unlink_dest_after_failed_open or unlink_dest_before_opening)) {
                _ = c.unlink(cur_dest_z.ptr);
            }
            if (c.symlink(src_z.ptr, cur_dest_z.ptr) != 0) {
                const err = c.__errno_location().*;
                try stderr.print("cp: cannot create symbolic link '{s}' to '{s}': {s}\n", .{ actual_dest_path, source, c.strerror(err) });
                exit_code = 1;
                continue;
            }
            created_dest_paths.put(try allocator.dupe(u8, actual_dest_path), {}) catch {};
            created_symlinks.put(try allocator.dupe(u8, actual_dest_path), {}) catch {};
            var new_dst_st: c.struct_stat = undefined;
            if (c.lstat(cur_dest_z.ptr, &new_dst_st) == 0) {
                created_dest_files.put(DevIno{ .dev = new_dst_st.st_dev, .ino = new_dst_st.st_ino }, {}) catch {};
            }
            if (verbose) {
                try stdout.print("'{s}' -> '{s}'\n", .{ source, actual_dest_path });
            }
            continue;
        }

        // Actual copy
        const ok = if (src_is_dir)
            copyDirRecursive(
                allocator,
                source,
                actual_dest_path,
                deref,
                preserve,
                explicit_no_preserve_mode,
                reflink,
                sparse,
                attributes_only,
                copy_contents,
                unlink_dest_after_failed_open,
                unlink_dest_before_opening,
                &hard_links,
                &created_dest_files,
                &created_dest_paths,
                &created_symlinks,
                hard_link,
                symbolic_link,
                verbose,
                debug,
                stdout,
                stderr,
            )
        else
            copySingleFile(
                allocator,
                source,
                actual_dest_path,
                deref,
                preserve,
                explicit_no_preserve_mode,
                reflink,
                sparse,
                attributes_only,
                copy_contents,
                unlink_dest_after_failed_open,
                unlink_dest_before_opening,
                &hard_links,
                &created_dest_files,
                &created_dest_paths,
                &created_symlinks,
                hard_link,
                symbolic_link,
                verbose,
                debug,
                stdout,
                stderr,
            );

        if (!ok) {
            exit_code = 1;
        }
    }

    if (parents_to_reprotect.items.len > 0) {
        var idx = parents_to_reprotect.items.len;
        while (idx > 0) {
            idx -= 1;
            const item = parents_to_reprotect.items[idx];
            const pz = allocator.dupeZ(u8, item.path) catch continue;
            defer allocator.free(pz);
            if (preserve.ownership) {
                _ = c.chown(pz.ptr, item.uid, item.gid);
            }
            if (preserve.mode) {
                _ = c.chmod(pz.ptr, item.mode);
            }
            if (preserve.timestamps) {
                var times = [2]c.struct_timespec{ item.atim, item.mtim };
                _ = c.utimensat(c.AT_FDCWD, pz.ptr, &times, 0);
            }
        }
    }

    return exit_code;
}

fn copySingleFile(
    allocator: std.mem.Allocator,
    src: []const u8,
    dest: []const u8,
    deref: DerefMode,
    preserve: PreserveFlags,
    explicit_no_preserve_mode: bool,
    reflink: ReflinkMode,
    sparse: SparseMode,
    attributes_only: bool,
    copy_contents: bool,
    unlink_dest_after_failed_open: bool,
    unlink_dest_before_opening: bool,
    hard_links: *std.AutoHashMap(DevIno, []const u8),
    created_dest_files: *std.AutoHashMap(DevIno, void),
    created_dest_paths: *std.StringHashMap(void),
    created_symlinks: *std.StringHashMap(void),
    hard_link_mode: bool,
    symbolic_link_mode: bool,
    verbose: bool,
    debug: bool,
    stdout: anytype,
    stderr: anytype,
) bool {
    const src_z = allocator.dupeZ(u8, src) catch return false;
    defer allocator.free(src_z);
    const dest_z = allocator.dupeZ(u8, dest) catch return false;
    defer allocator.free(dest_z);

    var st: c.struct_stat = undefined;
    const stat_res = if (deref == .always or deref == .cmdline) c.stat(src_z.ptr, &st) else c.lstat(src_z.ptr, &st);
    if (stat_res != 0) {
        const err = c.__errno_location().*;
        stderr.print("cp: cannot stat '{s}': {s}\n", .{ src, c.strerror(err) }) catch {};
        return false;
    }

    if (hard_link_mode) {
        if (unlink_dest_after_failed_open) {
            _ = c.unlink(dest_z.ptr);
        }
        if (c.link(src_z.ptr, dest_z.ptr) != 0) {
            const err = c.__errno_location().*;
            stderr.print("cp: cannot create hard link '{s}' to '{s}': {s}\n", .{ dest, src, c.strerror(err) }) catch {};
            return false;
        }
        created_dest_paths.put(allocator.dupe(u8, dest) catch return false, {}) catch {};
        var new_dst_st: c.struct_stat = undefined;
        if (c.lstat(dest_z.ptr, &new_dst_st) == 0) {
            created_dest_files.put(DevIno{ .dev = new_dst_st.st_dev, .ino = new_dst_st.st_ino }, {}) catch {};
        }
        if (verbose) stdout.print("'{s}' -> '{s}'\n", .{ src, dest }) catch {};
        return true;
    }

    if (symbolic_link_mode) {
        if (unlink_dest_after_failed_open) {
            _ = c.unlink(dest_z.ptr);
        }
        if (c.symlink(src_z.ptr, dest_z.ptr) != 0) {
            const err = c.__errno_location().*;
            stderr.print("cp: cannot create symbolic link '{s}' to '{s}': {s}\n", .{ dest, src, c.strerror(err) }) catch {};
            return false;
        }
        created_dest_paths.put(allocator.dupe(u8, dest) catch return false, {}) catch {};
        created_symlinks.put(allocator.dupe(u8, dest) catch return false, {}) catch {};
        var new_dst_st: c.struct_stat = undefined;
        if (c.lstat(dest_z.ptr, &new_dst_st) == 0) {
            created_dest_files.put(DevIno{ .dev = new_dst_st.st_dev, .ino = new_dst_st.st_ino }, {}) catch {};
        }
        if (verbose) stdout.print("'{s}' -> '{s}'\n", .{ src, dest }) catch {};
        return true;
    }

    // Preserve links check
    const should_remember_link = preserve.links and !attributes_only and (st.st_nlink > 1 or deref == .always or deref == .cmdline);
    if (should_remember_link) {
        const key = DevIno{ .dev = st.st_dev, .ino = st.st_ino };
        if (hard_links.get(key)) |earlier_dest| {
            const earlier_z = allocator.dupeZ(u8, earlier_dest) catch return false;
            defer allocator.free(earlier_z);
            if (c.link(earlier_z.ptr, dest_z.ptr) != 0) {
                var link_err = c.__errno_location().*;
                if (link_err == c.EEXIST) {
                    if (c.unlink(dest_z.ptr) == 0) {
                        if (c.link(earlier_z.ptr, dest_z.ptr) == 0) {
                            link_err = 0;
                        } else {
                            link_err = c.__errno_location().*;
                        }
                    } else {
                        link_err = c.__errno_location().*;
                    }
                }
                if (link_err != 0) {
                    stderr.print("cp: cannot create hard link '{s}' to '{s}': {s}\n", .{ dest, earlier_dest, c.strerror(link_err) }) catch {};
                    return false;
                }
            }
            if (verbose) stdout.print("'{s}' -> '{s}'\n", .{ src, dest }) catch {};
            return true;
        }
    }

    if ((st.st_mode & c.S_IFMT) == c.S_IFLNK) {
        var link_buf: [c.PATH_MAX]u8 = undefined;
        const len = c.readlink(src_z.ptr, &link_buf, link_buf.len - 1);
        if (len < 0) {
            const err = c.__errno_location().*;
            stderr.print("cp: cannot read symbolic link '{s}': {s}\n", .{ src, c.strerror(err) }) catch {};
            return false;
        }
        link_buf[@intCast(len)] = 0;
        if (c.symlink(&link_buf, dest_z.ptr) != 0) {
            var err = c.__errno_location().*;
            if (err == c.EEXIST) {
                var existing_buf: [c.PATH_MAX]u8 = undefined;
                const elen = c.readlink(dest_z.ptr, &existing_buf, existing_buf.len - 1);
                if (elen > 0 and std.mem.eql(u8, existing_buf[0..@intCast(elen)], link_buf[0..@intCast(len)])) {
                    err = 0;
                } else if (unlink_dest_after_failed_open or unlink_dest_before_opening) {
                    _ = c.unlink(dest_z.ptr);
                    if (c.symlink(&link_buf, dest_z.ptr) == 0) {
                        err = 0;
                    } else {
                        err = c.__errno_location().*;
                    }
                }
            }
            if (err != 0) {
                stderr.print("cp: cannot create symbolic link '{s}': {s}\n", .{ dest, c.strerror(err) }) catch {};
                return false;
            }
        }
        created_dest_paths.put(allocator.dupe(u8, dest) catch return false, {}) catch {};
        created_symlinks.put(allocator.dupe(u8, dest) catch return false, {}) catch {};
        var new_dst_st: c.struct_stat = undefined;
        if (c.lstat(dest_z.ptr, &new_dst_st) == 0) {
            created_dest_files.put(DevIno{ .dev = new_dst_st.st_dev, .ino = new_dst_st.st_ino }, {}) catch {};
        }
        if (preserve.timestamps) {
            var times = [2]c.struct_timespec{ st.st_atim, st.st_mtim };
            _ = c.utimensat(c.AT_FDCWD, dest_z.ptr, &times, c.AT_SYMLINK_NOFOLLOW);
        }
        if (should_remember_link) {
            const key = DevIno{ .dev = st.st_dev, .ino = st.st_ino };
            hard_links.put(key, allocator.dupe(u8, dest) catch return false) catch return false;
        }
        if (verbose) stdout.print("'{s}' -> '{s}'\n", .{ src, dest }) catch {};
        return true;
    } else if ((st.st_mode & c.S_IFMT) == c.S_IFIFO and !copy_contents) {
        if (unlink_dest_after_failed_open or unlink_dest_before_opening) {
            _ = c.unlink(dest_z.ptr);
        }
        const fifo_mode: c.mode_t = if (explicit_no_preserve_mode) 0o666 else (st.st_mode & 0o7777);
        if (c.mkfifo(dest_z.ptr, fifo_mode) != 0) {
            const err = c.__errno_location().*;
            if (err == c.EEXIST and (unlink_dest_after_failed_open or unlink_dest_before_opening)) {
                _ = c.unlink(dest_z.ptr);
                if (c.mkfifo(dest_z.ptr, fifo_mode) != 0) {
                    const err2 = c.__errno_location().*;
                    stderr.print("cp: cannot create fifo '{s}': {s}\n", .{ dest, c.strerror(err2) }) catch {};
                    return false;
                }
            } else {
                stderr.print("cp: cannot create fifo '{s}': {s}\n", .{ dest, c.strerror(err) }) catch {};
                return false;
            }
        }
        created_dest_paths.put(allocator.dupe(u8, dest) catch return false, {}) catch {};
        var new_dst_st: c.struct_stat = undefined;
        if (c.lstat(dest_z.ptr, &new_dst_st) == 0) {
            created_dest_files.put(DevIno{ .dev = new_dst_st.st_dev, .ino = new_dst_st.st_ino }, {}) catch {};
        }
        if (preserve.mode) {
            _ = c.chmod(dest_z.ptr, st.st_mode & 0o7777);
        } else if (explicit_no_preserve_mode) {
            const cur_umask = c.umask(0);
            _ = c.umask(cur_umask);
            _ = c.chmod(dest_z.ptr, 0o666 & ~cur_umask);
        }
        if (preserve.timestamps) {
            var times = [2]c.struct_timespec{ st.st_atim, st.st_mtim };
            _ = c.utimensat(c.AT_FDCWD, dest_z.ptr, &times, 0);
        }
        if (should_remember_link) {
            const key = DevIno{ .dev = st.st_dev, .ino = st.st_ino };
            hard_links.put(key, allocator.dupe(u8, dest) catch return false) catch return false;
        }
        if (verbose) stdout.print("'{s}' -> '{s}'\n", .{ src, dest }) catch {};
        return true;
    } else {
        const in_fd = c.open(src_z.ptr, c.O_RDONLY);
        if (in_fd < 0) {
            const err = c.__errno_location().*;
            stderr.print("cp: cannot open '{s}' for reading: {s}\n", .{ src, c.strerror(err) }) catch {};
            return false;
        }
        defer _ = c.close(in_fd);

        var dst_before_st: c.struct_stat = undefined;
        const dest_existed_before = (c.lstat(dest_z.ptr, &dst_before_st) == 0);

        const open_flags: c_int = if (attributes_only)
            (c.O_WRONLY | c.O_CREAT)
        else
            (c.O_WRONLY | c.O_CREAT | c.O_TRUNC);

        const omitted_permissions: c.mode_t = if (preserve.ownership)
            0o077
        else
            0;
        const open_mode = (if (explicit_no_preserve_mode) 0o666 else (st.st_mode & 0o7777)) & ~omitted_permissions;
        var out_fd = c.open(dest_z.ptr, open_flags, open_mode);
        var newly_created = !dest_existed_before;
        if (out_fd < 0) {
            if (unlink_dest_after_failed_open or unlink_dest_before_opening) {
                _ = c.unlink(dest_z.ptr);
                out_fd = c.open(dest_z.ptr, open_flags, open_mode);
                newly_created = true;
            }
        }
        if (out_fd < 0) {
            const err = c.__errno_location().*;
            stderr.print("cp: cannot create regular file '{s}': {s}\n", .{ dest, c.strerror(err) }) catch {};
            return false;
        }
        defer _ = c.close(out_fd);

        var out_stat: c.struct_stat = undefined;
        const out_is_reg = (c.fstat(out_fd, &out_stat) == 0) and ((out_stat.st_mode & c.S_IFMT) == c.S_IFREG);

        if (!attributes_only) {
            const FICLONE: c_ulong = 0x40049409;
            var cloned = false;
            if (reflink == .always or reflink == .auto) {
                if (c.ioctl(out_fd, FICLONE, in_fd) == 0) {
                    cloned = true;
                } else if (reflink == .always) {
                    const err = c.__errno_location().*;
                    stderr.print("cp: failed to clone '{s}' from '{s}': {s}\n", .{ dest, src, c.strerror(err) }) catch {};
                    return false;
                }
            }

            if (!cloned) {
                var buf: [65536]u8 = undefined;
                var did_seek = false;
                const can_sparse = out_is_reg and (sparse == .always or (sparse == .auto and st.st_blocks < (@divTrunc(st.st_size, 512) + 1)));
                while (true) {
                    const n = c.read(in_fd, &buf, buf.len);
                    if (n < 0) {
                        const err = c.__errno_location().*;
                        stderr.print("cp: error reading '{s}': {s}\n", .{ src, c.strerror(err) }) catch {};
                        return false;
                    }
                    if (n == 0) break;
                    const to_write: usize = @intCast(n);

                    if (can_sparse and isZeroBuffer(buf[0..to_write])) {
                        if (c.lseek(out_fd, @intCast(to_write), c.SEEK_CUR) < 0) {
                            const err = c.__errno_location().*;
                            if (err == c.ESPIPE) {
                                var written: usize = 0;
                                while (written < to_write) {
                                    const w = c.write(out_fd, buf[written..to_write].ptr, to_write - written);
                                    if (w < 0) {
                                        const werr = c.__errno_location().*;
                                        stderr.print("cp: error writing '{s}': {s}\n", .{ dest, c.strerror(werr) }) catch {};
                                        return false;
                                    }
                                    written += @intCast(w);
                                }
                            } else {
                                stderr.print("cp: error seeking '{s}': {s}\n", .{ dest, c.strerror(err) }) catch {};
                                return false;
                            }
                        } else {
                            did_seek = true;
                        }
                    } else {
                        var written: usize = 0;
                        while (written < to_write) {
                            const w = c.write(out_fd, buf[written..to_write].ptr, to_write - written);
                            if (w < 0) {
                                const err = c.__errno_location().*;
                                stderr.print("cp: error writing '{s}': {s}\n", .{ dest, c.strerror(err) }) catch {};
                                return false;
                            }
                            written += @intCast(w);
                        }
                    }
                }
                if (did_seek and out_is_reg) {
                    _ = c.ftruncate(out_fd, st.st_size);
                }
            }
            if (debug) {
                stdout.print("copy offload: no, reflink: no, sparse detection: zeros\n", .{}) catch {};
            }
        }

        if (preserve.mode) {
            _ = c.fchmod(out_fd, st.st_mode & 0o7777);
        } else if (newly_created and omitted_permissions != 0) {
            const cur_umask = c.umask(0);
            _ = c.umask(cur_umask);
            _ = c.fchmod(out_fd, (if (explicit_no_preserve_mode) 0o666 else (st.st_mode & 0o7777)) & ~cur_umask);
        }
        if (preserve.ownership) {
            _ = c.fchown(out_fd, st.st_uid, st.st_gid);
        }
        if (preserve.timestamps) {
            var times = [2]c.struct_timespec{ st.st_atim, st.st_mtim };
            _ = c.futimens(out_fd, &times);
        }

        created_dest_paths.put(allocator.dupe(u8, dest) catch return false, {}) catch {};
        var new_dst_st: c.struct_stat = undefined;
        if (c.lstat(dest_z.ptr, &new_dst_st) == 0) {
            created_dest_files.put(DevIno{ .dev = new_dst_st.st_dev, .ino = new_dst_st.st_ino }, {}) catch {};
        }

        if (should_remember_link) {
            const key = DevIno{ .dev = st.st_dev, .ino = st.st_ino };
            hard_links.put(key, allocator.dupe(u8, dest) catch return false) catch return false;
        }

        if (verbose) {
            stdout.print("'{s}' -> '{s}'\n", .{ src, dest }) catch {};
        }
        return true;
    }
}

fn copyDirRecursive(
    allocator: std.mem.Allocator,
    src: []const u8,
    dest: []const u8,
    deref: DerefMode,
    preserve: PreserveFlags,
    explicit_no_preserve_mode: bool,
    reflink: ReflinkMode,
    sparse: SparseMode,
    attributes_only: bool,
    copy_contents: bool,
    unlink_dest_after_failed_open: bool,
    unlink_dest_before_opening: bool,
    hard_links: *std.AutoHashMap(DevIno, []const u8),
    created_dest_files: *std.AutoHashMap(DevIno, void),
    created_dest_paths: *std.StringHashMap(void),
    created_symlinks: *std.StringHashMap(void),
    hard_link_mode: bool,
    symbolic_link_mode: bool,
    verbose: bool,
    debug: bool,
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
        stderr.print("cp: cannot stat '{s}': {s}\n", .{ src, c.strerror(err) }) catch {};
        return false;
    }

    const omitted_permissions: c.mode_t = if (preserve.ownership)
        (st.st_mode & 0o077)
    else if (preserve.mode)
        (st.st_mode & 0o022)
    else
        0;
    const mkdir_mode = 0o700 | ((st.st_mode & 0o7777) & ~omitted_permissions);
    var newly_created = false;
    if (c.mkdir(dest_z.ptr, mkdir_mode) != 0) {
        const err = c.__errno_location().*;
        if (err != c.EEXIST) {
            stderr.print("cp: cannot create directory '{s}': {s}\n", .{ dest, c.strerror(err) }) catch {};
            return false;
        }
    } else {
        newly_created = true;
    }
    created_dest_paths.put(allocator.dupe(u8, dest) catch return false, {}) catch {};
    var dst_st: c.struct_stat = undefined;
    if (c.lstat(dest_z.ptr, &dst_st) == 0) {
        created_dest_files.put(DevIno{ .dev = dst_st.st_dev, .ino = dst_st.st_ino }, {}) catch {};
    }

    if (verbose and newly_created) {
        stdout.print("'{s}' -> '{s}'\n", .{ src, dest }) catch {};
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

        const sub_src_z = allocator.dupeZ(u8, sub_src) catch return false;
        defer allocator.free(sub_src_z);

        const child_deref: DerefMode = if (deref == .always) .always else .never;
        var sub_st: c.struct_stat = undefined;
        const sub_st_ok = if (child_deref == .always)
            (c.stat(sub_src_z.ptr, &sub_st) == 0)
        else
            (c.lstat(sub_src_z.ptr, &sub_st) == 0);
        if (!sub_st_ok) {
            all_ok = false;
            continue;
        }

        if ((sub_st.st_mode & c.S_IFMT) == c.S_IFDIR) {
            if (!copyDirRecursive(
                allocator,
                sub_src,
                sub_dest,
                child_deref,
                preserve,
                explicit_no_preserve_mode,
                reflink,
                sparse,
                attributes_only,
                copy_contents,
                unlink_dest_after_failed_open,
                unlink_dest_before_opening,
                hard_links,
                created_dest_files,
                created_dest_paths,
                created_symlinks,
                hard_link_mode,
                symbolic_link_mode,
                verbose,
                debug,
                stdout,
                stderr,
            )) {
                all_ok = false;
            }
        } else {
            if (!copySingleFile(
                allocator,
                sub_src,
                sub_dest,
                child_deref,
                preserve,
                explicit_no_preserve_mode,
                reflink,
                sparse,
                attributes_only,
                copy_contents,
                unlink_dest_after_failed_open,
                unlink_dest_before_opening,
                hard_links,
                created_dest_files,
                created_dest_paths,
                created_symlinks,
                hard_link_mode,
                symbolic_link_mode,
                verbose,
                debug,
                stdout,
                stderr,
            )) {
                all_ok = false;
            }
        }
    }

    if (preserve.mode) {
        _ = c.chmod(dest_z.ptr, st.st_mode & 0o7777);
    } else if (explicit_no_preserve_mode and newly_created) {
        const cur_umask = c.umask(0);
        _ = c.umask(cur_umask);
        _ = c.chmod(dest_z.ptr, 0o777 & ~cur_umask);
    } else if (omitted_permissions != 0 and newly_created) {
        const cur_umask = c.umask(0);
        _ = c.umask(cur_umask);
        _ = c.chmod(dest_z.ptr, (st.st_mode & 0o7777) & ~cur_umask);
    }
    if (preserve.ownership) {
        _ = c.chown(dest_z.ptr, st.st_uid, st.st_gid);
    }
    if (preserve.timestamps) {
        var times = [2]c.struct_timespec{ st.st_atim, st.st_mtim };
        _ = c.utimensat(c.AT_FDCWD, dest_z.ptr, &times, 0);
    }

    return all_ok;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: cp [OPTION]... [-T] SOURCE DEST
        \\  or:  cp [OPTION]... SOURCE... DIRECTORY
        \\  or:  cp [OPTION]... -t DIRECTORY SOURCE...
        \\Copy SOURCE to DEST, or multiple SOURCE(s) to DIRECTORY.
        \\
        \\  -a, --archive                same as -dR --preserve=all
        \\      --attributes-only        don't copy the file data, just the attributes
        \\      --backup[=CONTROL]       make a backup of each existing destination file
        \\  -b                           like --backup but does not accept an argument
        \\      --copy-contents          copy contents of the special file when recursive
        \\  -d                           same as --no-dereference --preserve=links
        \\  -f, --force                  if an existing destination file cannot be
        \\                                 opened, remove it and try again
        \\  -i, --interactive            prompt before overwrite
        \\  -H                           follow command-line symbolic links in SOURCE
        \\  -l, --link                   hard link files instead of copying
        \\  -L, --dereference            always follow symbolic links in SOURCE
        \\  -n, --no-clobber             do not overwrite an existing file
        \\  -P, --no-dereference         never follow symbolic links in SOURCE
        \\  -p                           same as --preserve=mode,ownership,timestamps
        \\      --preserve[=ATTR_LIST]   preserve the specified attributes
        \\      --no-preserve=ATTR_LIST  don't preserve the specified attributes
        \\      --parents                use full source file name under DIRECTORY
        \\  -R, -r, --recursive          copy directories recursively
        \\      --reflink[=WHEN]         control clone/CoW copies. See below
        \\      --remove-destination     remove each existing destination file before
        \\                                 attempting to open it
        \\      --sparse=WHEN            control creation of sparse files. See below
        \\      --strip-trailing-slashes  remove any trailing slashes from each SOURCE
        \\                                 argument
        \\  -s, --symbolic-link          make symbolic links instead of copying
        \\  -S, --suffix=SUFFIX          override the usual backup suffix
        \\  -t, --target-directory=DIR   copy all SOURCE arguments into DIR
        \\  -T, --no-target-directory    treat DEST as a normal file
        \\  -u, --update[=UPDATE]        control which existing files are replaced;
        \\                                 UPDATE={all,none,none-fail,older(default)}
        \\  -v, --verbose                explain what is being done
        \\  -x, --one-file-system        stay on this file system
        \\      --help                   display this help and exit
        \\      --version                output version information and exit
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
