const std = @import("std");
const errors = @import("../utils/errors.zig");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "rm";
pub const version: []const u8 = "0.1.0";

const InteractiveMode = enum {
    never,
    once,
    always,
    sometimes,
};

const RemoveStatus = enum {
    ok,
    declined,
    err,
};

fn isRoot(path: []const u8) bool {
    if (path.len == 0) return false;
    for (path) |ch| {
        if (ch != '/') return false;
    }
    return true;
}

fn normalizeTrailingSlashes(path: []const u8) []const u8 {
    if (path.len <= 1) return path;
    var end = path.len;
    while (end > 1 and path[end - 1] == '/') {
        end -= 1;
    }
    if (end < path.len and end > 0 and path[end - 1] != '/') {
        return path[0 .. end + 1];
    }
    return path[0..end];
}

fn stripTrailingSlashes(path: []const u8) []const u8 {
    if (path.len <= 1) return path;
    var end = path.len;
    while (end > 1 and path[end - 1] == '/') {
        end -= 1;
    }
    return path[0..end];
}

fn isDotOrDotDot(path: []const u8) bool {
    const trimmed = stripTrailingSlashes(path);
    if (trimmed.len == 0) return false;
    const base = std.fs.path.basename(trimmed);
    return std.mem.eql(u8, base, ".") or std.mem.eql(u8, base, "..");
}

fn yesno() bool {
    var ch: u8 = 0;
    var first_char: ?u8 = null;
    while (true) {
        const n = c.read(c.STDIN_FILENO, &ch, 1);
        if (n <= 0) break;
        if (first_char == null and ch != '\n') {
            first_char = ch;
        }
        if (ch == '\n') break;
    }
    if (first_char) |fc| {
        return fc == 'y' or fc == 'Y';
    }
    return false;
}

fn fileTypeDescription(st: c.struct_stat) []const u8 {
    const mode = st.st_mode;
    if ((mode & c.S_IFMT) == c.S_IFREG) {
        return if (st.st_size == 0) "regular empty file" else "regular file";
    } else if ((mode & c.S_IFMT) == c.S_IFDIR) {
        return "directory";
    } else if ((mode & c.S_IFMT) == c.S_IFLNK) {
        return "symbolic link";
    } else if ((mode & c.S_IFMT) == c.S_IFBLK) {
        return "block special file";
    } else if ((mode & c.S_IFMT) == c.S_IFCHR) {
        return "character special file";
    } else if ((mode & c.S_IFMT) == c.S_IFIFO) {
        return "fifo";
    } else if ((mode & c.S_IFMT) == c.S_IFSOCK) {
        return "socket";
    } else {
        return "file";
    }
}

fn isWriteProtected(dirfd: c_int, filename: [*:0]const u8, st: c.struct_stat) bool {
    if (c.geteuid() == 0) return false;
    if ((st.st_mode & c.S_IFMT) == c.S_IFLNK) return false;
    if (c.faccessat(dirfd, filename, c.W_OK, c.AT_EACCESS) == 0) {
        return false;
    }
    return c.__errno_location().* == c.EACCES;
}

fn isIgnorableMissing(err: c_int) bool {
    return err == c.ENOENT or err == c.ENOTDIR or err == c.EINVAL or err == c.EILSEQ;
}

fn removeTreeFd(
    allocator: std.mem.Allocator,
    parent_fd: c_int,
    entry_name: [:0]const u8,
    display_path: []const u8,
    force: bool,
    verbose: bool,
    interactive: InteractiveMode,
    stdin_tty: bool,
    one_file_system: bool,
    preserve_all_root: bool,
    root_dev: ?c.dev_t,
    stdout: anytype,
    stderr: anytype,
) anyerror!RemoveStatus {
    const sub_fd = c.openat(parent_fd, entry_name.ptr, c.O_RDONLY | c.O_DIRECTORY | c.O_NOFOLLOW | c.O_CLOEXEC);
    if (sub_fd < 0) {
        const open_err = c.__errno_location().*;
        // Try removing empty directory directly with unlinkat(..., AT_REMOVEDIR)
        if (c.unlinkat(parent_fd, entry_name.ptr, c.AT_REMOVEDIR) == 0) {
            if (verbose) {
                try stdout.print("removed directory '{s}'\n", .{display_path});
            }
            return .ok;
        }
        if (force and isIgnorableMissing(open_err)) return .ok;
        try stderr.print("rm: cannot remove '{s}': {s}\n", .{ display_path, c.strerror(open_err) });
        return .err;
    }

    if (one_file_system) {
        var sub_st: c.struct_stat = undefined;
        if (c.fstat(sub_fd, &sub_st) == 0) {
            if (root_dev) |rdev| {
                if (sub_st.st_dev != rdev) {
                    _ = c.close(sub_fd);
                    try stderr.print("rm: skipping '{s}', since it's on a different device\n", .{display_path});
                    if (preserve_all_root) {
                        try stderr.print("rm: and --preserve-root=all is in effect\n", .{});
                    }
                    return .err;
                }
            }
        }
    }

    const dir_p = c.fdopendir(sub_fd) orelse {
        _ = c.close(sub_fd);
        try stderr.print("rm: cannot remove '{s}': {s}\n", .{ display_path, c.strerror(c.__errno_location().*) });
        return .err;
    };

    var child_names: std.ArrayList([:0]const u8) = .empty;
    defer {
        for (child_names.items) |cn| allocator.free(cn);
        child_names.deinit(allocator);
    }

    c.__errno_location().* = 0;
    while (c.readdir(dir_p)) |entry| {
        const d_name = std.mem.span(@as([*:0]const u8, @ptrCast(&entry.*.d_name)));
        if (std.mem.eql(u8, d_name, ".") or std.mem.eql(u8, d_name, "..")) {
            c.__errno_location().* = 0;
            continue;
        }
        const cn = try allocator.dupeZ(u8, d_name);
        try child_names.append(allocator, cn);
        c.__errno_location().* = 0;
    }
    const readdir_err = c.__errno_location().*;
    if (readdir_err != 0 and child_names.items.len > 0) {
        _ = c.closedir(dir_p);
        try stderr.print("rm: traversal failed: {s}: {s}\n", .{ display_path, c.strerror(readdir_err) });
        return .err;
    }

    var st: c.struct_stat = undefined;
    _ = c.fstat(sub_fd, &st);
    const is_write_prot = isWriteProtected(parent_fd, entry_name.ptr, st);

    const is_empty = (child_names.items.len == 0);
    if (!is_empty) {
        const should_prompt_descend = (interactive == .always) or (!force and interactive != .never and stdin_tty and is_write_prot);
        if (should_prompt_descend) {
            if (is_write_prot) {
                try stderr.print("rm: descend into write-protected directory '{s}'? ", .{display_path});
            } else {
                try stderr.print("rm: descend into directory '{s}'? ", .{display_path});
            }
            try stderr.flush();
            if (!yesno()) {
                _ = c.closedir(dir_p);
                return .declined;
            }
        }
    }

    var all_children_removed = true;
    var had_error = false;

    for (child_names.items) |cn| {
        const child_display_path = if (display_path.len > 0 and display_path[display_path.len - 1] == '/')
            try std.fmt.allocPrint(allocator, "{s}{s}", .{ display_path, cn })
        else
            try std.fmt.allocPrint(allocator, "{s}/{s}", .{ display_path, cn });
        defer allocator.free(child_display_path);

        var child_st: c.struct_stat = undefined;
        if (c.fstatat(sub_fd, cn.ptr, &child_st, c.AT_SYMLINK_NOFOLLOW) != 0) {
            const err = c.__errno_location().*;
            if (!(force and isIgnorableMissing(err))) {
                try stderr.print("rm: cannot remove '{s}': {s}\n", .{ child_display_path, c.strerror(err) });
                all_children_removed = false;
                had_error = true;
            }
            continue;
        }

        if ((child_st.st_mode & c.S_IFMT) == c.S_IFDIR) {
            const sub_res = try removeTreeFd(
                allocator,
                sub_fd,
                cn,
                child_display_path,
                force,
                verbose,
                interactive,
                stdin_tty,
                one_file_system,
                preserve_all_root,
                root_dev,
                stdout,
                stderr,
            );
            switch (sub_res) {
                .ok => {},
                .declined => all_children_removed = false,
                .err => {
                    all_children_removed = false;
                    had_error = true;
                },
            }
        } else {
            const child_wp = isWriteProtected(sub_fd, cn.ptr, child_st);
            const should_prompt_child = (interactive == .always) or (!force and interactive != .never and stdin_tty and child_wp);
            if (should_prompt_child) {
                const desc = fileTypeDescription(child_st);
                if (child_wp) {
                    try stderr.print("rm: remove write-protected {s} '{s}'? ", .{ desc, child_display_path });
                } else {
                    try stderr.print("rm: remove {s} '{s}'? ", .{ desc, child_display_path });
                }
                try stderr.flush();
                if (!yesno()) {
                    all_children_removed = false;
                    continue;
                }
            }
            if (c.unlinkat(sub_fd, cn.ptr, 0) == 0) {
                if (verbose) {
                    try stdout.print("removed '{s}'\n", .{child_display_path});
                }
            } else {
                const err = c.__errno_location().*;
                if (!(force and isIgnorableMissing(err))) {
                    try stderr.print("rm: cannot remove '{s}': {s}\n", .{ child_display_path, c.strerror(err) });
                    all_children_removed = false;
                    had_error = true;
                }
            }
        }
    }

    _ = c.closedir(dir_p);

    if (!all_children_removed) {
        return if (had_error) .err else .declined;
    }

    const should_prompt_rm_dir = (interactive == .always) or (!force and interactive != .never and stdin_tty and is_write_prot);
    if (should_prompt_rm_dir) {
        if (is_write_prot) {
            try stderr.print("rm: remove write-protected directory '{s}'? ", .{display_path});
        } else {
            try stderr.print("rm: remove directory '{s}'? ", .{display_path});
        }
        try stderr.flush();
        if (!yesno()) {
            return .declined;
        }
    }

    if (c.unlinkat(parent_fd, entry_name.ptr, c.AT_REMOVEDIR) == 0) {
        if (verbose) {
            try stdout.print("removed directory '{s}'\n", .{display_path});
        }
        return .ok;
    } else {
        const err = c.__errno_location().*;
        if (!(force and isIgnorableMissing(err))) {
            try stderr.print("rm: cannot remove '{s}': {s}\n", .{ display_path, c.strerror(err) });
            return .err;
        }
        return .ok;
    }
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

    var recursive = false;
    var force = false;
    var verbose = false;
    var dir_flag = false;
    var preserve_root = true;
    var preserve_all_root = false;
    var one_file_system = false;
    var interactive: InteractiveMode = .sometimes;
    var prompt_once = false;
    var stdin_tty = (c.isatty(c.STDIN_FILENO) != 0);

    var file_operands: std.ArrayList([]const u8) = .empty;
    defer file_operands.deinit(allocator);

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
                // Strip multiple leading dashes for GNU long options (e.g. ---presume-input-tty)
                var opt = arg;
                while (opt.len > 2 and opt[0] == '-' and opt[1] == '-' and opt[2] == '-') {
                    opt = opt[1..];
                }
                if (std.mem.eql(u8, opt, "--help")) {
                    printHelp(stdout) catch return 1;
                    stdout.flush() catch return 1;
                    return 0;
                } else if (std.mem.eql(u8, opt, "--version")) {
                    printVersion(stdout) catch return 1;
                    stdout.flush() catch return 1;
                    return 0;
                } else if (std.mem.eql(u8, opt, "--recursive")) {
                    recursive = true;
                } else if (std.mem.eql(u8, opt, "--force")) {
                    force = true;
                    interactive = .never;
                    prompt_once = false;
                } else if (std.mem.eql(u8, opt, "--verbose")) {
                    verbose = true;
                } else if (std.mem.eql(u8, opt, "--dir")) {
                    dir_flag = true;
                } else if (std.mem.startsWith(u8, opt, "--no-preserve")) {
                    if (!std.mem.eql(u8, opt, "--no-preserve-root")) {
                        try stderr.print("rm: you may not abbreviate the --no-preserve-root option\n", .{});
                        return 1;
                    }
                    preserve_root = false;
                } else if (std.mem.startsWith(u8, opt, "--preserve-root")) {
                    if (std.mem.eql(u8, opt, "--preserve-root")) {
                        preserve_root = true;
                    } else if (std.mem.eql(u8, opt, "--preserve-root=all")) {
                        preserve_root = true;
                        preserve_all_root = true;
                    } else {
                        const eq_pos = std.mem.indexOfScalar(u8, opt, '=');
                        const optarg = if (eq_pos) |pos| opt[pos + 1 ..] else "";
                        try stderr.print("rm: unrecognized --preserve-root argument: '{s}'\n", .{optarg});
                        return 1;
                    }
                } else if (std.mem.eql(u8, opt, "--one-file-system")) {
                    one_file_system = true;
                } else if (std.mem.startsWith(u8, opt, "--interactive")) {
                    if (std.mem.eql(u8, opt, "--interactive")) {
                        interactive = .always;
                        prompt_once = false;
                    } else if (std.mem.startsWith(u8, opt, "--interactive=")) {
                        const val = opt["--interactive=".len..];
                        if (std.mem.eql(u8, val, "never") or std.mem.eql(u8, val, "no") or std.mem.eql(u8, val, "none")) {
                            interactive = .never;
                            prompt_once = false;
                        } else if (std.mem.eql(u8, val, "once")) {
                            interactive = .sometimes;
                            prompt_once = true;
                        } else if (std.mem.eql(u8, val, "always") or std.mem.eql(u8, val, "yes")) {
                            interactive = .always;
                            prompt_once = false;
                        } else {
                            try stderr.print("rm: invalid argument '{s}' for '--interactive'\nValid arguments are:\n  - 'never', 'no', 'none'\n  - 'once'\n  - 'always', 'yes'\nTry 'rm --help' for more information.\n", .{val});
                            return 1;
                        }
                    } else {
                        try errors.printUnrecognizedOption(stderr, name, arg);
                        return 1;
                    }
                } else if (std.mem.eql(u8, opt, "--presume-input-tty")) {
                    stdin_tty = true;
                } else {
                    try errors.printUnrecognizedOption(stderr, name, arg);
                    return 1;
                }
            } else {
                // Short options
                var j: usize = 1;
                while (j < arg.len) : (j += 1) {
                    const ch = arg[j];
                    switch (ch) {
                        'r', 'R' => recursive = true,
                        'f' => {
                            force = true;
                            interactive = .never;
                            prompt_once = false;
                        },
                        'v' => verbose = true,
                        'd' => dir_flag = true,
                        'i' => {
                            interactive = .always;
                            prompt_once = false;
                        },
                        'I' => {
                            interactive = .sometimes;
                            prompt_once = true;
                        },
                        else => {
                            try errors.printInvalidOption(stderr, name, ch);
                            return 1;
                        },
                    }
                }
            }
        } else {
            try file_operands.append(allocator, arg);
            if (posixly_correct) {
                parsing_options = false;
            }
        }
    }

    if (file_operands.items.len == 0) {
        if (!force) {
            try errors.printMissingOperand(stderr, name);
            return 1;
        }
        return 0;
    }

    if (prompt_once and (recursive or file_operands.items.len > 3)) {
        if (recursive) {
            if (file_operands.items.len == 1) {
                try stderr.print("rm: remove 1 argument recursively? ", .{});
            } else {
                try stderr.print("rm: remove {d} arguments recursively? ", .{file_operands.items.len});
            }
        } else {
            if (file_operands.items.len == 1) {
                try stderr.print("rm: remove 1 argument? ", .{});
            } else {
                try stderr.print("rm: remove {d} arguments? ", .{file_operands.items.len});
            }
        }
        try stderr.flush();
        if (!yesno()) return 0;
    }

    var root_st: c.struct_stat = undefined;
    const has_root_st = (c.stat("/", &root_st) == 0);

    var exit_status: u8 = 0;

    for (file_operands.items) |file_path| {
        if (recursive and isDotOrDotDot(file_path)) {
            try stderr.print("rm: refusing to remove '.' or '..' directory: skipping '{s}'\n", .{file_path});
            exit_status = 1;
            continue;
        }

        const path_c = try allocator.dupeZ(u8, file_path);
        defer allocator.free(path_c);

        if (preserve_root and recursive) {
            var is_root_operand = isRoot(file_path);
            if (!is_root_operand and has_root_st) {
                var check_st: c.struct_stat = undefined;
                if (c.stat(path_c.ptr, &check_st) == 0) {
                    if (check_st.st_dev == root_st.st_dev and check_st.st_ino == root_st.st_ino) {
                        is_root_operand = true;
                    }
                }
            }
            if (is_root_operand) {
                try stderr.print("rm: it is dangerous to operate recursively on '{s}'\nrm: use --no-preserve-root to override this failsafe\n", .{file_path});
                exit_status = 1;
                continue;
            }
        }

        var st: c.struct_stat = undefined;
        const stat_ret = c.fstatat(c.AT_FDCWD, path_c.ptr, &st, c.AT_SYMLINK_NOFOLLOW);

        // If file_path has trailing slash, fstatat with AT_SYMLINK_NOFOLLOW may fail if target is not dir
        if (stat_ret != 0) {
            const err = c.__errno_location().*;
            if (force and isIgnorableMissing(err)) continue;
            try stderr.print("rm: cannot remove '{s}': {s}\n", .{ file_path, c.strerror(err) });
            exit_status = 1;
            continue;
        }

        const is_dir = ((st.st_mode & c.S_IFMT) == c.S_IFDIR);

        if (is_dir) {
            if (recursive) {
                const norm_display = normalizeTrailingSlashes(file_path);
                const res = try removeTreeFd(
                    allocator,
                    c.AT_FDCWD,
                    path_c,
                    norm_display,
                    force,
                    verbose,
                    interactive,
                    stdin_tty,
                    one_file_system,
                    preserve_all_root,
                    if (one_file_system) st.st_dev else null,
                    stdout,
                    stderr,
                );
                if (res == .err) exit_status = 1;
            } else if (dir_flag) {
                const sub_fd = c.openat(c.AT_FDCWD, path_c.ptr, c.O_RDONLY | c.O_DIRECTORY | c.O_NOFOLLOW | c.O_CLOEXEC);
                if (sub_fd < 0) {
                    const open_err = c.__errno_location().*;
                    if (open_err == c.EACCES) {
                        const should_prompt = (interactive == .always) or (!force and interactive != .never and stdin_tty);
                        if (should_prompt) {
                            try stderr.print("rm: attempt removal of inaccessible directory '{s}'? ", .{file_path});
                            try stderr.flush();
                            if (!yesno()) continue;
                        }
                        if (c.rmdir(path_c.ptr) == 0) {
                            if (verbose) try stdout.print("removed directory '{s}'\n", .{file_path});
                        } else {
                            try stderr.print("rm: cannot remove '{s}': {s}\n", .{ file_path, c.strerror(c.__errno_location().*) });
                            exit_status = 1;
                        }
                        continue;
                    }
                    if (!(force and isIgnorableMissing(open_err))) {
                        try stderr.print("rm: cannot remove '{s}': {s}\n", .{ file_path, c.strerror(open_err) });
                        exit_status = 1;
                    }
                    continue;
                }
                _ = c.close(sub_fd);

                const is_wp = isWriteProtected(c.AT_FDCWD, path_c.ptr, st);
                const should_prompt = (interactive == .always) or (!force and interactive != .never and stdin_tty and is_wp);
                if (should_prompt) {
                    if (is_wp) {
                        try stderr.print("rm: remove write-protected directory '{s}'? ", .{file_path});
                    } else {
                        try stderr.print("rm: remove directory '{s}'? ", .{file_path});
                    }
                    try stderr.flush();
                    if (!yesno()) continue;
                }
                if (c.rmdir(path_c.ptr) == 0) {
                    if (verbose) try stdout.print("removed directory '{s}'\n", .{file_path});
                } else {
                    const err = c.__errno_location().*;
                    if (!(force and isIgnorableMissing(err))) {
                        try stderr.print("rm: cannot remove '{s}': {s}\n", .{ file_path, c.strerror(err) });
                        exit_status = 1;
                    }
                }
            } else {
                try stderr.print("rm: cannot remove '{s}': Is a directory\n", .{file_path});
                exit_status = 1;
            }
        } else {
            const wp = isWriteProtected(c.AT_FDCWD, path_c.ptr, st);
            const should_prompt = (interactive == .always) or (!force and interactive != .never and stdin_tty and wp);
            if (should_prompt) {
                const desc = fileTypeDescription(st);
                if (wp) {
                    try stderr.print("rm: remove write-protected {s} '{s}'? ", .{ desc, file_path });
                } else {
                    try stderr.print("rm: remove {s} '{s}'? ", .{ desc, file_path });
                }
                try stderr.flush();
                if (!yesno()) continue;
            }
            if (c.unlinkat(c.AT_FDCWD, path_c.ptr, 0) == 0) {
                if (verbose) {
                    try stdout.print("removed '{s}'\n", .{file_path});
                }
            } else {
                const err = c.__errno_location().*;
                if (!(force and isIgnorableMissing(err))) {
                    try stderr.print("rm: cannot remove '{s}': {s}\n", .{ file_path, c.strerror(err) });
                    exit_status = 1;
                }
            }
        }
    }

    return exit_status;
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
        \\      --interactive[=WHEN]  prompt according to WHEN: never, once (-I), or
        \\                              always (-i); without WHEN, prompt always
        \\      --one-file-system  when removing a hierarchy recursively, skip any
        \\                           directory that is on a file system different from
        \\                           that of the corresponding command line argument
        \\      --no-preserve-root  do not treat '/' specially
        \\      --preserve-root   do not remove '/' (default)
        \\  -r, -R, --recursive   remove directories and their contents recursively
        \\  -d, --dir             remove empty directories
        \\  -v, --verbose         explain what is being done
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
        \\By default, rm does not remove directories.  Use the --recursive (-r or -R)
        \\option to remove each listed directory, too, along with all of its contents.
        \\
        \\To remove a file whose name starts with a '-', for example '-foo',
        \\use one of these commands:
        \\  rm -- -foo
        \\  rm ./-foo
        \\
        \\GNU coreutils online help: <https://www.gnu.org/software/coreutils/>
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
