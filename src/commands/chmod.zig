const std = @import("std");
const errors = @import("../utils/errors.zig");
const mode_utils = @import("../utils/mode.zig");

const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "chmod";
pub const version: []const u8 = "0.1.0";

const DEREFERENCE_OPTION = 256;
const NO_PRESERVE_ROOT = 257;
const PRESERVE_ROOT = 258;
const REFERENCE_FILE_OPTION = 259;
const HELP_OPTION = 260;
const VERSION_OPTION = 261;

const long_options = [_]c.struct_option{
    .{ .name = "changes", .has_arg = 0, .flag = null, .val = 'c' },
    .{ .name = "dereference", .has_arg = 0, .flag = null, .val = DEREFERENCE_OPTION },
    .{ .name = "recursive", .has_arg = 0, .flag = null, .val = 'R' },
    .{ .name = "no-dereference", .has_arg = 0, .flag = null, .val = 'h' },
    .{ .name = "no-preserve-root", .has_arg = 0, .flag = null, .val = NO_PRESERVE_ROOT },
    .{ .name = "preserve-root", .has_arg = 0, .flag = null, .val = PRESERVE_ROOT },
    .{ .name = "quiet", .has_arg = 0, .flag = null, .val = 'f' },
    .{ .name = "reference", .has_arg = 1, .flag = null, .val = REFERENCE_FILE_OPTION },
    .{ .name = "silent", .has_arg = 0, .flag = null, .val = 'f' },
    .{ .name = "verbose", .has_arg = 0, .flag = null, .val = 'v' },
    .{ .name = "help", .has_arg = 0, .flag = null, .val = HELP_OPTION },
    .{ .name = "version", .has_arg = 0, .flag = null, .val = VERSION_OPTION },
    .{ .name = null, .has_arg = 0, .flag = null, .val = 0 },
};

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buffer: [16384]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .init(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var argv_list: std.ArrayList(?[*:0]u8) = .empty;
    defer argv_list.deinit(allocator);

    for (args) |a| {
        const a_z = try allocator.dupeZ(u8, a);
        try argv_list.append(allocator, a_z.ptr);
    }
    try argv_list.append(allocator, null);
    defer {
        for (argv_list.items[0 .. argv_list.items.len - 1]) |ptr| {
            if (ptr) |p| allocator.free(std.mem.span(p));
        }
    }

    var mode_buf: std.ArrayList(u8) = .empty;
    defer mode_buf.deinit(allocator);

    var diagnose_surprises = false;
    var recurse = false;
    var changes = false;
    var verbose = false;
    var silent = false;
    var reference_file: ?[]const u8 = null;
    var dereference: i32 = -1;
    const FTS_PHYSICAL = 1;
    const FTS_LOGICAL = 2;
    const FTS_COMFOLLOW = 4;
    var bit_flags: i32 = FTS_COMFOLLOW | FTS_PHYSICAL;

    c.optind = 0;
    while (true) {
        const argc: c_int = @intCast(argv_list.items.len - 1);
        const optc = c.getopt_long(
            argc,
            @ptrCast(argv_list.items.ptr),
            "HLPRcfhvr::w::x::X::s::t::u::g::o::a::,::+::=::0::1::2::3::4::5::6::7::",
            &long_options,
            null,
        );
        if (optc == -1) break;

        switch (optc) {
            'H' => bit_flags = FTS_COMFOLLOW | FTS_PHYSICAL,
            'L' => bit_flags = FTS_LOGICAL,
            'P' => bit_flags = FTS_PHYSICAL,
            'h' => dereference = 0,
            DEREFERENCE_OPTION => dereference = 1,
            'R' => recurse = true,
            'c' => changes = true,
            'f' => silent = true,
            'v' => verbose = true,
            REFERENCE_FILE_OPTION => reference_file = std.mem.span(c.optarg),
            NO_PRESERVE_ROOT, PRESERVE_ROOT => {},
            HELP_OPTION => {
                printHelp(stdout) catch return 1;
                stdout.flush() catch return 1;
                return 0;
            },
            VERSION_OPTION => {
                printVersion(stdout) catch return 1;
                stdout.flush() catch return 1;
                return 0;
            },
            'r', 'w', 'x', 'X', 's', 't', 'u', 'g', 'o', 'a', ',', '+', '=', '0', '1', '2', '3', '4', '5', '6', '7' => {
                const opt_arg = std.mem.span(argv_list.items[@intCast(c.optind - 1)].?);
                if (mode_buf.items.len > 0) {
                    try mode_buf.append(allocator, ',');
                }
                try mode_buf.appendSlice(allocator, opt_arg);
                diagnose_surprises = true;
            },
            else => {
                try stderr.print("Try '{s} --help' for more information.\n", .{name});
                return 1;
            },
        }
    }

    if (recurse) {
        if (bit_flags == FTS_PHYSICAL) {
            if (dereference == 1) {
                try stderr.print("chmod: -R --dereference requires either -H or -L\nTry '{s} --help' for more information.\n", .{name});
                return 1;
            }
            dereference = 0;
        }
    }

    if (dereference == -1 and bit_flags == FTS_LOGICAL) {
        dereference = 1;
    }

    var mode_str: ?[]const u8 = if (mode_buf.items.len > 0) mode_buf.items else null;

    if (reference_file != null) {
        if (mode_str != null) {
            try stderr.print("chmod: cannot combine mode and --reference options\nTry '{s} --help' for more information.\n", .{name});
            return 1;
        }
    } else {
        if (mode_str == null) {
            if (c.optind < argv_list.items.len - 1) {
                mode_str = std.mem.span(argv_list.items[@intCast(c.optind)].?);
                c.optind += 1;
            }
        }
    }

    const total_argc = argv_list.items.len - 1;
    var cur_optind: usize = @intCast(c.optind);

    if (cur_optind >= total_argc) {
        if (mode_str == null or (cur_optind > 0 and !std.mem.eql(u8, mode_str.?, std.mem.span(argv_list.items[cur_optind - 1].?)))) {
            try stderr.print("chmod: missing operand\nTry '{s} --help' for more information.\n", .{name});
        } else {
            try stderr.print("chmod: missing operand after '{s}'\nTry '{s} --help' for more information.\n", .{ std.mem.span(argv_list.items[total_argc - 1].?), name });
        }
        return 1;
    }

    var fixed_mode: ?u32 = null;
    var umask_val: u32 = 0;

    if (reference_file) |ref| {
        const ref_z = try allocator.dupeZ(u8, ref);
        defer allocator.free(ref_z);
        var ref_st: c.struct_stat = undefined;
        if (c.stat(ref_z.ptr, &ref_st) != 0) {
            const err_msg = std.mem.span(c.strerror(c.__errno_location().*));
            try stderr.print("chmod: failed to get attributes of '{s}': {s}\n", .{ ref, err_msg });
            return 1;
        }
        fixed_mode = ref_st.st_mode & 0o7777;
    } else {
        _ = mode_utils.parseMode(mode_str.?, 0o777, true, 0) catch {
            try stderr.print("chmod: invalid mode: '{s}'\nTry '{s} --help' for more information.\n", .{ mode_str.?, name });
            return 1;
        };
        const orig_umask = c.umask(0);
        _ = c.umask(orig_umask);
        umask_val = @intCast(orig_umask);
    }

    var exit_status: u8 = 0;
    while (cur_optind < total_argc) : (cur_optind += 1) {
        const file = std.mem.span(argv_list.items[cur_optind].?);
        const ok = try chmodRoot(
            allocator,
            file,
            mode_str,
            fixed_mode,
            recurse,
            bit_flags,
            dereference,
            diagnose_surprises,
            umask_val,
            verbose,
            changes,
            silent,
            stdout,
            stderr,
        );
        if (!ok) exit_status = 1;
    }

    return exit_status;
}

fn chmodRoot(
    allocator: std.mem.Allocator,
    file: []const u8,
    mode_str: ?[]const u8,
    fixed_mode: ?u32,
    recurse: bool,
    bit_flags: i32,
    dereference: i32,
    diagnose_surprises: bool,
    umask_val: u32,
    verbose: bool,
    changes: bool,
    silent: bool,
    stdout: anytype,
    stderr: anytype,
) !bool {
    const follow_symlink = if (dereference == 1)
        true
    else if (dereference == 0)
        false
    else if (recurse)
        (bit_flags == 2 or (bit_flags & 4 != 0))
    else
        true;

    const file_z = try allocator.dupeZ(u8, file);
    defer allocator.free(file_z);

    var st: c.struct_stat = undefined;
    const stat_res = if (follow_symlink) c.stat(file_z.ptr, &st) else c.lstat(file_z.ptr, &st);

    if (follow_symlink and stat_res != 0) {
        var lst: c.struct_stat = undefined;
        if (c.lstat(file_z.ptr, &lst) == 0 and ((lst.st_mode & c.S_IFMT) == c.S_IFLNK)) {
            if (!silent) {
                try stderr.print("chmod: cannot operate on dangling symlink '{s}'\n", .{file});
            }
            return false;
        }
    }

    if (stat_res != 0) {
        if (!silent) {
            const err_msg = std.mem.span(c.strerror(c.__errno_location().*));
            try stderr.print("chmod: cannot access '{s}': {s}\n", .{ file, err_msg });
        }
        return false;
    }

    if (!follow_symlink and ((st.st_mode & c.S_IFMT) == c.S_IFLNK)) {
        return true;
    }

    const is_dir = ((st.st_mode & c.S_IFMT) == c.S_IFDIR);
    const old_mode = st.st_mode & 0o7777;
    const new_mode = if (fixed_mode) |m|
        m
    else
        try mode_utils.parseMode(mode_str.?, old_mode, is_dir, umask_val);

    var ok = true;
    if (c.chmod(file_z.ptr, @intCast(new_mode)) != 0) {
        if (!silent) {
            const err_msg = std.mem.span(c.strerror(c.__errno_location().*));
            try stderr.print("chmod: changing permissions of '{s}': {s}\n", .{ file, err_msg });
        }
        ok = false;
    } else {
        if (verbose or (changes and new_mode != old_mode)) {
            var old_buf: [9]u8 = undefined;
            var new_buf: [9]u8 = undefined;
            const old_str = mode_utils.formatMode(old_mode, &old_buf);
            const new_str = mode_utils.formatMode(new_mode, &new_buf);
            if (new_mode != old_mode) {
                try stdout.print("mode of '{s}' changed from {o:0>4} ({s}) to {o:0>4} ({s})\n", .{ file, old_mode, old_str, new_mode, new_str });
            } else {
                try stdout.print("mode of '{s}' retained as {o:0>4} ({s})\n", .{ file, new_mode, new_str });
            }
        }
    }

    if (ok and diagnose_surprises and mode_str != null) {
        const naively_expected_mode = mode_utils.parseMode(mode_str.?, old_mode, is_dir, 0) catch new_mode;
        if ((new_mode & ~naively_expected_mode) != 0) {
            var new_buf: [9]u8 = undefined;
            var naive_buf: [9]u8 = undefined;
            const new_str = mode_utils.formatMode(new_mode, &new_buf);
            const naive_str = mode_utils.formatMode(naively_expected_mode, &naive_buf);
            try stderr.print("chmod: {s}: new permissions are {s}, not {s}\n", .{ file, new_str, naive_str });
            ok = false;
        }
    }

    if (recurse and is_dir) {
        var dir = std.Io.Dir.cwd().openDir(std.Options.debug_io, file, .{ .iterate = true }) catch return ok;
        defer dir.close(std.Options.debug_io);
        var it = dir.iterate();
        while (it.next(std.Options.debug_io) catch null) |entry| {
            const sub_path = try std.fs.path.join(allocator, &[_][]const u8{ file, entry.name });
            defer allocator.free(sub_path);

            const sub_ok = try chmodRecurseEntry(
                allocator,
                sub_path,
                entry.kind,
                mode_str,
                fixed_mode,
                bit_flags,
                umask_val,
                verbose,
                changes,
                silent,
                stdout,
                stderr,
            );
            if (!sub_ok) ok = false;
        }
    }

    return ok;
}

fn chmodRecurseEntry(
    allocator: std.mem.Allocator,
    sub_path: []const u8,
    kind: std.Io.File.Kind,
    mode_str: ?[]const u8,
    fixed_mode: ?u32,
    bit_flags: i32,
    umask_val: u32,
    verbose: bool,
    changes: bool,
    silent: bool,
    stdout: anytype,
    stderr: anytype,
) !bool {
    const follow_traversed_symlinks = (bit_flags == 2);
    if (kind == .sym_link and !follow_traversed_symlinks) {
        return true;
    }

    const sub_z = try allocator.dupeZ(u8, sub_path);
    defer allocator.free(sub_z);

    var st: c.struct_stat = undefined;
    const stat_res = if (follow_traversed_symlinks) c.stat(sub_z.ptr, &st) else c.lstat(sub_z.ptr, &st);
    if (stat_res != 0) {
        if (!silent) {
            const err_msg = std.mem.span(c.strerror(c.__errno_location().*));
            try stderr.print("chmod: cannot access '{s}': {s}\n", .{ sub_path, err_msg });
        }
        return false;
    }

    const is_dir = ((st.st_mode & c.S_IFMT) == c.S_IFDIR);
    const old_mode = st.st_mode & 0o7777;
    const new_mode = if (fixed_mode) |m|
        m
    else
        try mode_utils.parseMode(mode_str.?, old_mode, is_dir, umask_val);

    var ok = true;
    if (c.chmod(sub_z.ptr, @intCast(new_mode)) != 0) {
        if (!silent) {
            const err_msg = std.mem.span(c.strerror(c.__errno_location().*));
            try stderr.print("chmod: changing permissions of '{s}': {s}\n", .{ sub_path, err_msg });
        }
        ok = false;
    } else {
        if (verbose or (changes and new_mode != old_mode)) {
            var old_buf: [9]u8 = undefined;
            var new_buf: [9]u8 = undefined;
            const old_str = mode_utils.formatMode(old_mode, &old_buf);
            const new_str = mode_utils.formatMode(new_mode, &new_buf);
            if (new_mode != old_mode) {
                try stdout.print("mode of '{s}' changed from {o:0>4} ({s}) to {o:0>4} ({s})\n", .{ sub_path, old_mode, old_str, new_mode, new_str });
            } else {
                try stdout.print("mode of '{s}' retained as {o:0>4} ({s})\n", .{ sub_path, new_mode, new_str });
            }
        }
    }

    if (is_dir) {
        var dir = std.Io.Dir.cwd().openDir(std.Options.debug_io, sub_path, .{ .iterate = true }) catch return ok;
        defer dir.close(std.Options.debug_io);
        var it = dir.iterate();
        while (it.next(std.Options.debug_io) catch null) |entry| {
            const next_path = try std.fs.path.join(allocator, &[_][]const u8{ sub_path, entry.name });
            defer allocator.free(next_path);

            const next_ok = try chmodRecurseEntry(
                allocator,
                next_path,
                entry.kind,
                mode_str,
                fixed_mode,
                bit_flags,
                umask_val,
                verbose,
                changes,
                silent,
                stdout,
                stderr,
            );
            if (!next_ok) ok = false;
        }
    }

    return ok;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: chmod [OPTION]... MODE[,MODE]... FILE...
        \\  or:  chmod [OPTION]... OCTAL-MODE FILE...
        \\  or:  chmod [OPTION]... --reference=RFILE FILE...
        \\Change the mode of each FILE to MODE.
        \\
        \\  -c, --changes          like verbose but report only when a change is made
        \\  -f, --silent, --quiet  suppress most error messages
        \\  -v, --verbose          output a diagnostic for every file processed
        \\      --dereference      affect the referent of each symbolic link (this is
        \\                         the default) rather than the symbolic link itself
        \\  -h, --no-dereference   affect symbolic links instead of any referenced file
        \\                         (useless on systems that don't support chmod on links)
        \\      --reference=RFILE  use RFILE's mode instead of MODE values
        \\  -R, --recursive        change files and directories recursively
        \\  -H                     if -R is specified, traverse symbolic links to directories
        \\                         given on the command line
        \\  -L                     if -R is specified, traverse every symbolic link to a
        \\                         directory encountered
        \\  -P                     if -R is specified, do not traverse any symbolic links
        \\                         (default)
        \\      --help     display this help and exit
        \\      --version  output version information and exit
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
