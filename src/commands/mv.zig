const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "mv";
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

    var verbose = false;
    var force = false;
    var interactive = false;
    var no_clobber = false;
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
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--force")) {
            force = true;
            interactive = false;
            no_clobber = false;
        } else if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--interactive")) {
            interactive = true;
            force = false;
            no_clobber = false;
        } else if (std.mem.eql(u8, arg, "-n") or std.mem.eql(u8, arg, "--no-clobber")) {
            no_clobber = true;
            force = false;
            interactive = false;
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
                    'v' => verbose = true,
                    'f' => {
                        force = true;
                        interactive = false;
                        no_clobber = false;
                    },
                    'i' => {
                        interactive = true;
                        force = false;
                        no_clobber = false;
                    },
                    'n' => {
                        no_clobber = true;
                        force = false;
                        interactive = false;
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

    const dest_is_dir = blk: {
        const stat = std.Io.Dir.cwd().statFile(std.Options.debug_io, dest, .{}) catch break :blk false;
        break :blk stat.kind == .directory;
    };

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

        if (no_clobber) {
            if (std.Io.Dir.cwd().statFile(std.Options.debug_io, dest_path, .{})) |_| {
                continue;
            } else |_| {}
        }

        std.Io.Dir.rename(.cwd(), source, .cwd(), dest_path, std.Options.debug_io) catch |err| {
            try errors.printErrorWithArg(stderr, name, source, err);
            exit_code = 1;
            continue;
        };

        if (verbose) {
            try stdout.print("renamed '{s}' -> '{s}'\n", .{ source, dest_path });
        }
    }

    return exit_code;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: mv [OPTION]... SOURCE DEST
        \\  or:  mv [OPTION]... SOURCE... DIRECTORY
        \\  or:  mv [OPTION]... -t DIRECTORY SOURCE...
        \\Rename SOURCE to DEST, or move SOURCE(s) to DIRECTORY.
        \\
        \\  -f, --force                  do not prompt before overwriting
        \\  -i, --interactive            prompt before overwrite
        \\  -n, --no-clobber             do not overwrite an existing file
        \\  -t, --target-directory=DIR   move all SOURCE arguments into DIR
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
