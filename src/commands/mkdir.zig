const std = @import("std");
const errors = @import("../utils/errors.zig");
const mode_util = @import("../utils/mode.zig");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "mkdir";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buffer: [4096]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    const cur_umask = c.umask(0);
    _ = c.umask(cur_umask);

    var parents = false;
    var verbose = false;
    var final_mode: u32 = 0o777 & ~@as(u32, @intCast(cur_umask));
    var mode_provided = false;

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
                } else if (std.mem.eql(u8, opt, "--parents")) {
                    parents = true;
                } else if (std.mem.eql(u8, opt, "--verbose")) {
                    verbose = true;
                } else if (std.mem.startsWith(u8, opt, "--mode=")) {
                    const mode_str = opt["--mode=".len..];
                    final_mode = mode_util.parseMode(mode_str, 0o777, true, @intCast(cur_umask)) catch {
                        try stderr.print("mkdir: invalid mode '{s}'\n", .{mode_str});
                        return 1;
                    };
                    mode_provided = true;
                } else if (std.mem.eql(u8, opt, "--mode")) {
                    if (i + 1 >= args.len) {
                        try errors.printErrorWithHelp(stderr, name, "option '--mode' requires an argument");
                        return 1;
                    }
                    i += 1;
                    const mode_str = args[i];
                    final_mode = mode_util.parseMode(mode_str, 0o777, true, @intCast(cur_umask)) catch {
                        try stderr.print("mkdir: invalid mode '{s}'\n", .{mode_str});
                        return 1;
                    };
                    mode_provided = true;
                } else if (std.mem.startsWith(u8, opt, "--context")) {
                    // SELinux context option - accept and ignore
                } else {
                    try errors.printUnrecognizedOption(stderr, name, arg);
                    return 1;
                }
            } else {
                var j: usize = 1;
                while (j < arg.len) : (j += 1) {
                    const ch = arg[j];
                    switch (ch) {
                        'p' => parents = true,
                        'v' => verbose = true,
                        'Z' => {},
                        'm' => {
                            var mode_str: []const u8 = undefined;
                            if (j + 1 < arg.len) {
                                mode_str = arg[j + 1 ..];
                                j = arg.len;
                            } else {
                                if (i + 1 >= args.len) {
                                    try errors.printErrorWithHelp(stderr, name, "option requires an argument -- 'm'");
                                    return 1;
                                }
                                i += 1;
                                mode_str = args[i];
                            }
                            final_mode = mode_util.parseMode(mode_str, 0o777, true, @intCast(cur_umask)) catch {
                                try stderr.print("mkdir: invalid mode '{s}'\n", .{mode_str});
                                return 1;
                            };
                            mode_provided = true;
                            break;
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
        try errors.printMissingOperand(stderr, name);
        return 1;
    }

    var exit_status: u8 = 0;

    for (file_operands.items) |dir_name| {
        if (parents) {
            const ok = try makePath(allocator, dir_name, final_mode, mode_provided, verbose, @intCast(cur_umask), stdout, stderr);
            if (!ok) exit_status = 1;
        } else {
            const path_c = try allocator.dupeZ(u8, dir_name);
            defer allocator.free(path_c);

            const initial_create_mode: c_uint = if (mode_provided) @intCast(final_mode) else 0o777;
            if (c.mkdir(path_c.ptr, initial_create_mode) != 0) {
                const err = c.__errno_location().*;
                try stderr.print("mkdir: cannot create directory '{s}': {s}\n", .{ dir_name, c.strerror(err) });
                exit_status = 1;
                continue;
            }
            if (mode_provided) {
                _ = c.chmod(path_c.ptr, @intCast(final_mode));
            }
            if (verbose) {
                try stdout.print("mkdir: created directory '{s}'\n", .{dir_name});
            }
        }
    }

    return exit_status;
}

fn makePath(
    allocator: std.mem.Allocator,
    path: []const u8,
    mode: u32,
    mode_provided: bool,
    verbose: bool,
    cur_umask: c_uint,
    stdout: anytype,
    stderr: anytype,
) !bool {
    if (path.len == 0) return true;

    // Strip trailing slashes, but keep track if it ended in "/." or "/.."
    var end = path.len;
    while (end > 1 and path[end - 1] == '/') {
        end -= 1;
    }
    const clean_path = path[0..end];

    var i: usize = 0;
    while (i < clean_path.len) {
        while (i < clean_path.len and clean_path[i] == '/') i += 1;
        while (i < clean_path.len and clean_path[i] != '/') i += 1;

        if (i == 0) break;
        const sub_path = clean_path[0..i];
        const is_last = (i >= clean_path.len);

        const sub_base = std.fs.path.basename(sub_path);
        if (std.mem.eql(u8, sub_base, ".") or std.mem.eql(u8, sub_base, "..")) {
            if (is_last) break;
            continue;
        }

        const sub_c = try allocator.dupeZ(u8, sub_path);
        defer allocator.free(sub_c);

        var st: c.struct_stat = undefined;
        if (c.stat(sub_c.ptr, &st) == 0) {
            if ((st.st_mode & c.S_IFMT) != c.S_IFDIR) {
                try stderr.print("mkdir: cannot create directory '{s}': File exists\n", .{path});
                return false;
            }
            if (is_last) break;
            continue;
        }

        if (!is_last) {
            const ancestor_mask = cur_umask & ~@as(c_uint, 0o300);
            _ = c.umask(ancestor_mask);
        }
        const create_mode: c_uint = if (is_last and mode_provided) @intCast(mode) else 0o777;
        const mkdir_res = c.mkdir(sub_c.ptr, create_mode);
        if (!is_last) {
            _ = c.umask(cur_umask);
        }

        if (mkdir_res != 0) {
            const err = c.__errno_location().*;
            // Check if it was created concurrently
            if (err == c.EEXIST and c.stat(sub_c.ptr, &st) == 0 and (st.st_mode & c.S_IFMT) == c.S_IFDIR) {
                if (is_last) break;
                continue;
            }
            try stderr.print("mkdir: cannot create directory '{s}': {s}\n", .{ path, c.strerror(err) });
            return false;
        }

        if (is_last and mode_provided) {
            _ = c.chmod(sub_c.ptr, @intCast(mode));
        }

        if (verbose) {
            try stdout.print("mkdir: created directory '{s}'\n", .{sub_path});
        }

        if (is_last) break;
    }

    return true;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: mkdir [OPTION]... DIRECTORY...
        \\Create the DIRECTORY(ies), if they do not already exist.
        \\
        \\Mandatory arguments to long options are mandatory for short options too.
        \\  -m, --mode=MODE   set file mode (as in chmod), not a=rwx - umask
        \\  -p, --parents     no error if existing, make parent directories as needed
        \\  -v, --verbose     print a message for each created directory
        \\  -Z                set SELinux security context of each created directory
        \\      --context[=CTX]  like -Z, or if CTX is specified then set the SELinux
        \\                         or SMACK security context to CTX
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
