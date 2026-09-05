const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "mkdir";
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

    var parents = false;
    var verbose = false;
    var mode: std.posix.mode_t = 0o777;
    var mode_provided = false;
    var files_start: usize = args.len;

    // Parse options
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            try printHelp(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try printVersion(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--parents")) {
            parents = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (std.mem.startsWith(u8, arg, "--mode=")) {
            const mode_str = arg["--mode=".len..];
            mode = std.fmt.parseInt(std.posix.mode_t, mode_str, 8) catch {
                const msg = try std.fmt.allocPrint(allocator, "invalid mode '{s}'", .{mode_str});
                defer allocator.free(msg);
                try errors.printError(stderr, name, msg);
                return 1;
            };
            mode_provided = true;
        } else if (std.mem.eql(u8, arg, "--mode")) {
            if (i + 1 >= args.len) {
                try errors.printError(stderr, name, "option '--mode' requires an argument");
                return 1;
            }
            i += 1;
            const mode_str = args[i];
            mode = std.fmt.parseInt(std.posix.mode_t, mode_str, 8) catch {
                const msg = try std.fmt.allocPrint(allocator, "invalid mode '{s}'", .{mode_str});
                defer allocator.free(msg);
                try errors.printError(stderr, name, msg);
                return 1;
            };
            mode_provided = true;
        } else if (std.mem.eql(u8, arg, "--")) {
            files_start = i + 1;
            break;
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1 and arg[1] != '-') {
            var j: usize = 1;
            while (j < arg.len) : (j += 1) {
                switch (arg[j]) {
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
                                try errors.printError(stderr, name, "option requires an argument -- 'm'");
                                return 1;
                            }
                            i += 1;
                            mode_str = args[i];
                        }
                        mode = std.fmt.parseInt(std.posix.mode_t, mode_str, 8) catch {
                            const msg = try std.fmt.allocPrint(allocator, "invalid mode '{s}'", .{mode_str});
                            defer allocator.free(msg);
                            try errors.printError(stderr, name, msg);
                            return 1;
                        };
                        mode_provided = true;
                        break;
                    },
                    else => {
                        const msg = try std.fmt.allocPrint(allocator, "invalid option -- '{c}'", .{arg[j]});
                        defer allocator.free(msg);
                        try errors.printError(stderr, name, msg);
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
        try errors.printError(stderr, name, "missing operand");
        return 1;
    }

    var exit_status: u8 = 0;

    for (args[files_start..]) |dir_name| {
        if (parents) {
            makePath(dir_name, mode, mode_provided, verbose, stdout) catch |err| {
                try errors.printErrorWithArg(stderr, name, dir_name, err);
                exit_status = 1;
            };
        } else {
            const perms: std.Io.File.Permissions = if (mode_provided) @enumFromInt(mode) else .default_dir;
            std.Io.Dir.cwd().createDir(std.Options.debug_io, dir_name, perms) catch |err| {
                try errors.printErrorWithArg(stderr, name, dir_name, err);
                exit_status = 1;
                continue;
            };
            if (mode_provided) {
                std.Io.Dir.cwd().setFilePermissions(std.Options.debug_io, dir_name, @enumFromInt(mode), .{}) catch {};
            }
            if (verbose) {
                try stdout.print("mkdir: created directory '{s}'\n", .{dir_name});
            }
        }
    }

    return exit_status;
}

fn makePath(path: []const u8, mode: std.posix.mode_t, mode_provided: bool, verbose: bool, stdout: anytype) !void {
    if (path.len == 0) return;

    var i: usize = 0;
    while (i < path.len) {
        while (i < path.len and path[i] == '/') i += 1;
        while (i < path.len and path[i] != '/') i += 1;

        if (i == 0) break;
        const is_last = (i == path.len or (i < path.len and std.mem.indexOfNone(u8, path[i..], "/") == null));
        const sub_path = if (is_last) path else path[0..i];

        var created = false;
        if (std.Io.Dir.cwd().createDir(std.Options.debug_io, sub_path, .default_dir)) |_| {
            created = true;
        } else |err| switch (err) {
            error.PathAlreadyExists => {
                const stat = std.Io.Dir.cwd().statFile(std.Options.debug_io, sub_path, .{}) catch |s_err| return s_err;
                if (stat.kind != .directory) return error.NotDir;
            },
            else => return err,
        }

        if (is_last and mode_provided) {
            try std.Io.Dir.cwd().setFilePermissions(std.Options.debug_io, sub_path, @enumFromInt(mode), .{});
        }
        if (created and verbose) {
            try stdout.print("mkdir: created directory '{s}'\n", .{sub_path});
        }
        if (is_last) break;
    }
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: mkdir [OPTION]... DIRECTORY...
        \\Create the DIRECTORY(ies), if they do not already exist.
        \\
        \\  -m, --mode=MODE   set file mode (as in chmod), not a=rwx - umask
        \\  -p, --parents     no error if existing, make parent directories as needed
        \\  -v, --verbose     print a message for each created directory
        \\  -Z                set SELinux security context of each created directory
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
