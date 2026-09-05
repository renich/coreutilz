const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "ln";
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

    var symbolic = false;
    var force = false;
    var verbose = false;
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
        } else if (std.mem.eql(u8, arg, "--symbolic")) {
            symbolic = true;
        } else if (std.mem.eql(u8, arg, "--force")) {
            force = true;
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
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
                    's' => symbolic = true,
                    'f' => force = true,
                    'v' => verbose = true,
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

    const files = args[file_start..];

    if (target_dir) |dest| {
        var exit_code: u8 = 0;
        for (files) |target| {
            const base = std.fs.path.basename(target);
            const link_path = try std.fs.path.join(allocator, &[_][]const u8{ dest, base });
            defer allocator.free(link_path);
            if (force) std.Io.Dir.cwd().deleteFile(std.Options.debug_io, link_path) catch {};
            if (symbolic) {
                std.Io.Dir.cwd().symLink(std.Options.debug_io, target, link_path, .{}) catch |err| {
                    try errors.printErrorWithArg(stderr, name, link_path, err);
                    exit_code = 1;
                    continue;
                };
            } else {
                std.Io.Dir.cwd().hardLink(target, std.Io.Dir.cwd(), link_path, std.Options.debug_io, .{}) catch |err| {
                    try errors.printErrorWithArg(stderr, name, link_path, err);
                    exit_code = 1;
                    continue;
                };
            }
            const sep = if (symbolic) "->" else "=>";
            if (verbose) try stdout.print("'{s}' {s} '{s}'\n", .{ link_path, sep, target });
        }
        return exit_code;
    }

    if (!no_target_dir and files.len >= 2) {
        const dest = files[files.len - 1];
        const is_dir = blk: {
            const stat = std.Io.Dir.cwd().statFile(std.Options.debug_io, dest, .{}) catch break :blk false;
            break :blk stat.kind == .directory;
        };

        if (is_dir) {
            var exit_code: u8 = 0;
            for (files[0 .. files.len - 1]) |target| {
                const base = std.fs.path.basename(target);
                const link_path = try std.fs.path.join(allocator, &[_][]const u8{ dest, base });
                defer allocator.free(link_path);
                if (force) std.Io.Dir.cwd().deleteFile(std.Options.debug_io, link_path) catch {};
                if (symbolic) {
                    std.Io.Dir.cwd().symLink(std.Options.debug_io, target, link_path, .{}) catch |err| {
                        try errors.printErrorWithArg(stderr, name, link_path, err);
                        exit_code = 1;
                        continue;
                    };
                } else {
                    std.Io.Dir.cwd().hardLink(target, std.Io.Dir.cwd(), link_path, std.Options.debug_io, .{}) catch |err| {
                        try errors.printErrorWithArg(stderr, name, link_path, err);
                        exit_code = 1;
                        continue;
                    };
                }
                const sep = if (symbolic) "->" else "=>";
                if (verbose) try stdout.print("'{s}' {s} '{s}'\n", .{ link_path, sep, target });
            }
            return exit_code;
        } else if (files.len > 2) {
            const msg = try std.fmt.allocPrint(allocator, "target '{s}' is not a directory", .{dest});
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

    const target = files[0];
    const link_name = if (files.len > 1) files[1] else std.fs.path.basename(target);

    if (force) std.Io.Dir.cwd().deleteFile(std.Options.debug_io, link_name) catch {};

    if (symbolic) {
        std.Io.Dir.cwd().symLink(std.Options.debug_io, target, link_name, .{}) catch |err| {
            try errors.printErrorWithArg(stderr, name, link_name, err);
            return 1;
        };
    } else {
        std.Io.Dir.cwd().hardLink(target, std.Io.Dir.cwd(), link_name, std.Options.debug_io, .{}) catch |err| {
            try errors.printErrorWithArg(stderr, name, link_name, err);
            return 1;
        };
    }

    const sep = if (symbolic) "->" else "=>";
    if (verbose) try stdout.print("'{s}' {s} '{s}'\n", .{ link_name, sep, target });

    return 0;
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
