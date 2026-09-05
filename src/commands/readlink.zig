const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "readlink";
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

    var canonicalize_mode: enum { none, normal, existing, missing } = .none;
    var no_newline = false;
    var verbose: bool = (std.c.getenv("POSIXLY_CORRECT") != null);
    var use_nuls = false;
    var files_start: usize = args.len;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            try printHelp(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try printVersion(stdout);
            return 0;
        } else if (std.mem.eql(u8, arg, "--canonicalize")) {
            canonicalize_mode = .normal;
        } else if (std.mem.eql(u8, arg, "--canonicalize-existing")) {
            canonicalize_mode = .existing;
        } else if (std.mem.eql(u8, arg, "--canonicalize-missing")) {
            canonicalize_mode = .missing;
        } else if (std.mem.eql(u8, arg, "--no-newline")) {
            no_newline = true;
        } else if (std.mem.eql(u8, arg, "--quiet") or std.mem.eql(u8, arg, "--silent")) {
            verbose = false;
        } else if (std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "--zero")) {
            use_nuls = true;
        } else if (std.mem.eql(u8, arg, "--")) {
            files_start = i + 1;
            break;
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1 and arg[1] != '-') {
            for (arg[1..]) |c| {
                switch (c) {
                    'f' => canonicalize_mode = .normal,
                    'e' => canonicalize_mode = .existing,
                    'm' => canonicalize_mode = .missing,
                    'n' => no_newline = true,
                    'q', 's' => verbose = false,
                    'v' => verbose = true,
                    'z' => use_nuls = true,
                    else => {
                        const msg = try std.fmt.allocPrint(allocator, "invalid option -- '{c}'", .{c});
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

    if (args.len - files_start > 1) {
        if (no_newline) {
            try errors.printError(stderr, name, "ignoring --no-newline with multiple arguments");
            no_newline = false;
        }
    }

    const delimiter: u8 = if (use_nuls) 0 else '\n';
    var status: u8 = 0;

    for (args[files_start..]) |file| {
        var buf: [std.Io.Dir.max_path_bytes]u8 = undefined;

        switch (canonicalize_mode) {
            .none => {
                const len = std.Io.Dir.cwd().readLink(std.Options.debug_io, file, &buf) catch |err| {
                    status = 1;
                    if (verbose) try errors.printErrorWithArg(stderr, name, file, err);
                    continue;
                };
                try stdout.writeAll(buf[0..len]);
            },
            .existing => {
                const len = std.Io.Dir.cwd().realPathFile(std.Options.debug_io, file, &buf) catch |err| {
                    status = 1;
                    if (verbose) try errors.printErrorWithArg(stderr, name, file, err);
                    continue;
                };
                try stdout.writeAll(buf[0..len]);
            },
            .normal => {
                if (std.Io.Dir.cwd().realPathFile(std.Options.debug_io, file, &buf)) |len| {
                    try stdout.writeAll(buf[0..len]);
                } else |_| {
                    const dirname = std.fs.path.dirname(file) orelse ".";
                    var dir_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
                    const dir_len = std.Io.Dir.cwd().realPathFile(std.Options.debug_io, dirname, &dir_buf) catch |err| {
                        status = 1;
                        if (verbose) try errors.printErrorWithArg(stderr, name, file, err);
                        continue;
                    };
                    const base = std.fs.path.basename(file);
                    const res = try std.fs.path.resolve(allocator, &[_][]const u8{ dir_buf[0..dir_len], base });
                    defer allocator.free(res);
                    try stdout.writeAll(res);
                }
            },
            .missing => {
                if (std.Io.Dir.cwd().realPathFile(std.Options.debug_io, file, &buf)) |len| {
                    try stdout.writeAll(buf[0..len]);
                } else |_| {
                    var cwd_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
                    const cwd_len = std.process.currentPath(std.Options.debug_io, &cwd_buf) catch {
                        status = 1;
                        continue;
                    };
                    const abs_path = try std.fs.path.resolve(allocator, &[_][]const u8{ cwd_buf[0..cwd_len], file });
                    defer allocator.free(abs_path);

                    var curr: []const u8 = abs_path;
                    var found_prefix = false;
                    while (true) {
                        if (std.Io.Dir.cwd().realPathFile(std.Options.debug_io, curr, &buf)) |real_len| {
                            const suffix = abs_path[curr.len..];
                            const trimmed_suffix = std.mem.trimStart(u8, suffix, "/");
                            const res = try std.fs.path.resolve(allocator, &[_][]const u8{ buf[0..real_len], trimmed_suffix });
                            defer allocator.free(res);
                            try stdout.writeAll(res);
                            found_prefix = true;
                            break;
                        } else |_| {
                            if (std.fs.path.dirname(curr)) |parent| {
                                if (std.mem.eql(u8, curr, parent)) break;
                                curr = parent;
                            } else {
                                break;
                            }
                        }
                    }
                    if (!found_prefix) {
                        try stdout.writeAll(abs_path);
                    }
                }
            },
        }

        if (!no_newline) {
            try stdout.writeByte(delimiter);
        }
    }

    return status;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: readlink [OPTION]... FILE...
        \\Print value of a symbolic link or canonical file name
        \\
        \\  -f, --canonicalize            canonicalize by following every symlink in
        \\                                every component of the given name recursively;
        \\                                all but the last component must exist
        \\  -e, --canonicalize-existing   canonicalize by following every symlink in
        \\                                every component of the given name recursively,
        \\                                all components must exist
        \\  -m, --canonicalize-missing    canonicalize by following every symlink in
        \\                                every component of the given name recursively,
        \\                                without requirements on components existence
        \\  -n, --no-newline              do not output the trailing newline
        \\  -q, -s, --silent, --quiet     suppress most error messages
        \\  -v, --verbose                 report error messages
        \\  -z, --zero                    end each output line with NUL, not newline
        \\      --help     display this help and exit
        \\      --version  output version information and exit
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
