const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "cp";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), std.Options.debug_io, &stdout_buf);
    var stderr_writer: std.Io.File.Writer = .init(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var recursive = false;
    var verbose = false;
    var force = false;
    var interactive = false;
    var preserve = false;
    var target_dir: ?[]const u8 = null;
    var no_target_dir = false;
    var file_start: usize = args.len;
    var end_of_opts = false;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (end_of_opts or !std.mem.startsWith(u8, arg, "-") or arg.len == 1) {
            file_start = i;
            break;
        }
        if (std.mem.eql(u8, arg, "--")) {
            end_of_opts = true;
            continue;
        }
        if (std.mem.eql(u8, arg, "--help")) {
            try printHelp(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try printVersion(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "-r") or std.mem.eql(u8, arg, "-R") or std.mem.eql(u8, arg, "--recursive")) {
            recursive = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--force")) {
            force = true;
            interactive = false;
        } else if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--interactive")) {
            interactive = true;
            force = false;
        } else if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--preserve")) {
            preserve = true;
        } else if (std.mem.eql(u8, arg, "-a") or std.mem.eql(u8, arg, "--archive")) {
            recursive = true;
            preserve = true;
        } else if (std.mem.eql(u8, arg, "--no-target-directory") or std.mem.eql(u8, arg, "-T")) {
            no_target_dir = true;
        } else if (std.mem.startsWith(u8, arg, "--target-directory=")) {
            target_dir = arg["--target-directory=".len..];
        } else if (std.mem.eql(u8, arg, "-t")) {
            i += 1;
            if (i >= args.len) {
                try errors.printError(stderr, name, "option requires an argument -- 't'");
                return 1;
            }
            target_dir = args[i];
        } else if (arg[0] == '-') {
            var j: usize = 1;
            while (j < arg.len) : (j += 1) {
                const c = arg[j];
                switch (c) {
                    'r', 'R' => recursive = true,
                    'v' => verbose = true,
                    'f' => {
                        force = true;
                        interactive = false;
                    },
                    'i' => {
                        interactive = true;
                        force = false;
                    },
                    'p' => preserve = true,
                    'a' => {
                        recursive = true;
                        preserve = true;
                    },
                    'T' => no_target_dir = true,
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
                        const msg = try std.fmt.allocPrint(allocator, "invalid option -- '{c}'", .{c});
                        defer allocator.free(msg);
                        try errors.printError(stderr, name, msg);
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

    const dest_stat = std.Io.Dir.cwd().statFile(std.Options.debug_io, dest, .{}) catch null;
    const dest_is_dir = if (dest_stat) |st| st.kind == .directory else false;

    if (sources.len > 1 and !dest_is_dir) {
        const msg = try std.fmt.allocPrint(allocator, "target '{s}' is not a directory", .{dest});
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

    var exit_code: u8 = 0;
    for (sources) |source| {
        const dest_path = if (dest_is_dir)
            try std.fs.path.join(allocator, &[_][]const u8{ dest, std.fs.path.basename(source) })
        else
            dest;
        defer if (dest_is_dir) allocator.free(dest_path);

        const ok = try copyPath(allocator, source, dest_path, recursive, force, interactive, preserve, verbose, stdout, stderr);
        if (!ok) {
            exit_code = 1;
        }
    }

    return exit_code;
}

fn copyPath(
    allocator: std.mem.Allocator,
    src: []const u8,
    dest: []const u8,
    recursive: bool,
    force: bool,
    interactive: bool,
    preserve: bool,
    verbose: bool,
    stdout: anytype,
    stderr: anytype,
) anyerror!bool {
    const src_stat = std.Io.Dir.cwd().statFile(std.Options.debug_io, src, .{}) catch |err| {
        try errors.printErrorWithArg(stderr, name, src, err);
        return false;
    };

    if (src_stat.kind == .directory) {
        if (!recursive) {
            const msg = try std.fmt.allocPrint(allocator, "-r not specified; omitting directory '{s}'", .{src});
            defer allocator.free(msg);
            try errors.printError(stderr, name, msg);
            return false;
        }
        return try copyDir(allocator, src, dest, recursive, force, interactive, preserve, verbose, stdout, stderr);
    } else {
        return try copyFile(allocator, src, dest, force, interactive, preserve, verbose, stdout, stderr);
    }
}

fn copyFile(
    allocator: std.mem.Allocator,
    src: []const u8,
    dest: []const u8,
    force: bool,
    interactive: bool,
    preserve: bool,
    verbose: bool,
    stdout: anytype,
    stderr: anytype,
) anyerror!bool {
    _ = allocator;
    const dest_stat = std.Io.Dir.cwd().statFile(std.Options.debug_io, dest, .{}) catch null;
    if (dest_stat != null and interactive and !force) {
        return true;
    }

    var src_file = std.Io.Dir.cwd().openFile(std.Options.debug_io, src, .{ .mode = .read_only }) catch |err| {
        try errors.printErrorWithArg(stderr, name, src, err);
        return false;
    };
    defer src_file.close(std.Options.debug_io);

    const src_stat = src_file.stat(std.Options.debug_io) catch |err| {
        try errors.printErrorWithArg(stderr, name, src, err);
        return false;
    };

    var dest_file = std.Io.Dir.cwd().createFile(std.Options.debug_io, dest, .{}) catch |err| blk: {
        if (force and (err == error.AccessDenied or err == error.PermissionDenied)) {
            std.Io.Dir.cwd().deleteFile(std.Options.debug_io, dest) catch {};
            break :blk std.Io.Dir.cwd().createFile(std.Options.debug_io, dest, .{}) catch |e2| {
                try errors.printErrorWithArg(stderr, name, dest, e2);
                return false;
            };
        }
        try errors.printErrorWithArg(stderr, name, dest, err);
        return false;
    };
    defer dest_file.close(std.Options.debug_io);

    var read_buf: [64 * 1024]u8 = undefined;
    var r = src_file.readerStreaming(std.Options.debug_io, &read_buf);
    const reader = &r.interface;
    var write_buf: [64 * 1024]u8 = undefined;
    var w: std.Io.File.Writer = .init(dest_file, std.Options.debug_io, &write_buf);
    const writer = &w.interface;
    defer writer.flush() catch {};

    while (true) {
        var chunk: [8192]u8 = undefined;
        const n = reader.readSliceShort(&chunk) catch |err| {
            try errors.printErrorWithArg(stderr, name, src, err);
            return false;
        };
        if (n == 0) break;
        writer.writeAll(chunk[0..n]) catch |err| {
            try errors.printErrorWithArg(stderr, name, dest, err);
            return false;
        };
    }
    writer.flush() catch |err| {
        try errors.printErrorWithArg(stderr, name, dest, err);
        return false;
    };

    if (preserve) {
        std.Io.Dir.cwd().setFilePermissions(std.Options.debug_io, dest, src_stat.permissions, .{}) catch {};
    }

    if (verbose) {
        try stdout.print("'{s}' -> '{s}'\n", .{ src, dest });
    }
    return true;
}

fn copyDir(
    allocator: std.mem.Allocator,
    src: []const u8,
    dest: []const u8,
    recursive: bool,
    force: bool,
    interactive: bool,
    preserve: bool,
    verbose: bool,
    stdout: anytype,
    stderr: anytype,
) anyerror!bool {
    const dest_stat = std.Io.Dir.cwd().statFile(std.Options.debug_io, dest, .{}) catch null;
    if (dest_stat) |st| {
        if (st.kind != .directory) {
            const msg = try std.fmt.allocPrint(allocator, "cannot overwrite non-directory '{s}' with directory '{s}'", .{ dest, src });
            defer allocator.free(msg);
            try errors.printError(stderr, name, msg);
            return false;
        }
    } else {
        std.Io.Dir.cwd().createDir(std.Options.debug_io, dest, .default_dir) catch |err| {
            try errors.printErrorWithArg(stderr, name, dest, err);
            return false;
        };
    }

    var dir = std.Io.Dir.cwd().openDir(std.Options.debug_io, src, .{ .iterate = true }) catch |err| {
        try errors.printErrorWithArg(stderr, name, src, err);
        return false;
    };
    defer dir.close(std.Options.debug_io);

    var it = dir.iterate();
    var ok = true;
    while (it.next(std.Options.debug_io) catch null) |entry| {
        const sub_src = try std.fs.path.join(allocator, &[_][]const u8{ src, entry.name });
        defer allocator.free(sub_src);
        const sub_dest = try std.fs.path.join(allocator, &[_][]const u8{ dest, entry.name });
        defer allocator.free(sub_dest);

        const res = try copyPath(allocator, sub_src, sub_dest, recursive, force, interactive, preserve, verbose, stdout, stderr);
        if (!res) ok = false;
    }
    return ok;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: cp [OPTION]... SOURCE DEST
        \\  or:  cp [OPTION]... SOURCE... DIRECTORY
        \\  or:  cp [OPTION]... -t DIRECTORY SOURCE...
        \\Copy SOURCE to DEST, or multiple SOURCE(s) to DIRECTORY.
        \\
        \\  -a, --archive                same as -dpR
        \\  -f, --force                  if an existing destination file cannot be
        \\                                 opened, remove it and try again
        \\  -i, --interactive            prompt before overwrite
        \\  -p, --preserve               preserve mode, ownership, timestamps
        \\  -r, -R, --recursive          copy directories recursively
        \\  -t, --target-directory=DIR   copy all SOURCE arguments into DIR
        \\  -T, --no-target-directory    treat DEST as a normal file
        \\  -v, --verbose                explain what is being done
        \\      --help                   display this help and exit
        \\      --version                output version information and exit
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
