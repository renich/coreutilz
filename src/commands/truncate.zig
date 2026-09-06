const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "truncate";
pub const version: []const u8 = "0.1.0";

const RelMode = enum {
    none,
    relative, // '+' or '-'
    at_least, // '>'
    at_most, // '<'
    round_down, // '/'
    round_up, // '%'
};

const ParseSizeError = error{
    InvalidNumber,
    ValueTooLarge,
    DivisionByZero,
    MultipleModifiers,
};

fn parseSize(str: []const u8) ParseSizeError!struct { size: i64, rel_mode: RelMode } {
    var s = std.mem.trim(u8, str, " \t\r\n");
    if (s.len == 0) return error.InvalidNumber;

    var rel_mode: RelMode = .none;
    if (s[0] == '<') {
        rel_mode = .at_most;
        s = s[1..];
    } else if (s[0] == '>') {
        rel_mode = .at_least;
        s = s[1..];
    } else if (s[0] == '/') {
        rel_mode = .round_down;
        s = s[1..];
    } else if (s[0] == '%') {
        rel_mode = .round_up;
        s = s[1..];
    }

    s = std.mem.trim(u8, s, " \t\r\n");
    if (s.len == 0) return error.InvalidNumber;

    var is_negative = false;
    if (s[0] == '+') {
        if (rel_mode != .none) return error.MultipleModifiers;
        rel_mode = .relative;
        s = s[1..];
    } else if (s[0] == '-') {
        if (rel_mode != .none) return error.MultipleModifiers;
        rel_mode = .relative;
        is_negative = true;
        s = s[1..];
    }

    s = std.mem.trim(u8, s, " \t\r\n");
    if (s.len == 0) return error.InvalidNumber;

    var multiplier: ?i64 = 1;
    var num_part = s;
    var is_huge_suffix = false;

    // Check suffixes
    if (std.mem.endsWith(u8, s, "KiB")) {
        multiplier = 1024;
        num_part = s[0 .. s.len - 3];
    } else if (std.mem.endsWith(u8, s, "MiB")) {
        multiplier = 1024 * 1024;
        num_part = s[0 .. s.len - 3];
    } else if (std.mem.endsWith(u8, s, "GiB")) {
        multiplier = 1024 * 1024 * 1024;
        num_part = s[0 .. s.len - 3];
    } else if (std.mem.endsWith(u8, s, "TiB")) {
        multiplier = 1024 * 1024 * 1024 * 1024;
        num_part = s[0 .. s.len - 3];
    } else if (std.mem.endsWith(u8, s, "PiB")) {
        multiplier = 1024 * 1024 * 1024 * 1024 * 1024;
        num_part = s[0 .. s.len - 3];
    } else if (std.mem.endsWith(u8, s, "EiB")) {
        multiplier = 1024 * 1024 * 1024 * 1024 * 1024 * 1024;
        num_part = s[0 .. s.len - 3];
    } else if (std.mem.endsWith(u8, s, "ZiB") or std.mem.endsWith(u8, s, "YiB") or std.mem.endsWith(u8, s, "RiB") or std.mem.endsWith(u8, s, "QiB")) {
        is_huge_suffix = true;
        multiplier = null;
        num_part = s[0 .. s.len - 3];
    } else if (std.mem.endsWith(u8, s, "kB") or std.mem.endsWith(u8, s, "KB")) {
        multiplier = 1000;
        num_part = s[0 .. s.len - 2];
    } else if (std.mem.endsWith(u8, s, "MB")) {
        multiplier = 1000 * 1000;
        num_part = s[0 .. s.len - 2];
    } else if (std.mem.endsWith(u8, s, "GB")) {
        multiplier = 1000 * 1000 * 1000;
        num_part = s[0 .. s.len - 2];
    } else if (std.mem.endsWith(u8, s, "TB")) {
        multiplier = 1000 * 1000 * 1000 * 1000;
        num_part = s[0 .. s.len - 2];
    } else if (std.mem.endsWith(u8, s, "PB")) {
        multiplier = 1000 * 1000 * 1000 * 1000 * 1000;
        num_part = s[0 .. s.len - 2];
    } else if (std.mem.endsWith(u8, s, "EB")) {
        multiplier = 1000 * 1000 * 1000 * 1000 * 1000 * 1000;
        num_part = s[0 .. s.len - 2];
    } else if (std.mem.endsWith(u8, s, "ZB") or std.mem.endsWith(u8, s, "YB") or std.mem.endsWith(u8, s, "RB") or std.mem.endsWith(u8, s, "QB")) {
        is_huge_suffix = true;
        multiplier = null;
        num_part = s[0 .. s.len - 2];
    } else if (s.len > 0) {
        const last = s[s.len - 1];
        switch (last) {
            'k', 'K' => {
                multiplier = 1024;
                num_part = s[0 .. s.len - 1];
            },
            'm', 'M' => {
                multiplier = 1024 * 1024;
                num_part = s[0 .. s.len - 1];
            },
            'g', 'G' => {
                multiplier = 1024 * 1024 * 1024;
                num_part = s[0 .. s.len - 1];
            },
            't', 'T' => {
                multiplier = 1024 * 1024 * 1024 * 1024;
                num_part = s[0 .. s.len - 1];
            },
            'p', 'P' => {
                multiplier = 1024 * 1024 * 1024 * 1024 * 1024;
                num_part = s[0 .. s.len - 1];
            },
            'e', 'E' => {
                multiplier = 1024 * 1024 * 1024 * 1024 * 1024 * 1024;
                num_part = s[0 .. s.len - 1];
            },
            'z', 'Z', 'y', 'Y', 'r', 'R', 'q', 'Q' => {
                is_huge_suffix = true;
                multiplier = null;
                num_part = s[0 .. s.len - 1];
            },
            '0'...'9' => {},
            else => return error.InvalidNumber,
        }
    }

    if (num_part.len == 0) return error.InvalidNumber;
    const base_val = std.fmt.parseInt(i64, num_part, 10) catch |err| {
        return if (err == error.Overflow) error.ValueTooLarge else error.InvalidNumber;
    };
    if (base_val < 0) return error.InvalidNumber;

    var abs_size: i64 = 0;
    if (is_huge_suffix) {
        if (base_val == 0) {
            abs_size = 0;
        } else {
            return error.ValueTooLarge;
        }
    } else if (multiplier) |m| {
        const mul_res = @mulWithOverflow(base_val, m);
        if (mul_res[1] != 0) return error.ValueTooLarge;
        abs_size = mul_res[0];
    }

    if ((rel_mode == .round_down or rel_mode == .round_up) and abs_size == 0) {
        return error.DivisionByZero;
    }

    var final_size: i64 = abs_size;
    if (is_negative) {
        final_size = -abs_size;
    }
    return .{ .size = final_size, .rel_mode = rel_mode };
}

fn openErrorDescription(err: anyerror) []const u8 {
    return switch (err) {
        error.FileNotFound => "No such file or directory",
        error.IsDir => "Is a directory",
        error.NotDir => "Not a directory",
        error.AccessDenied, error.PermissionDenied => "Permission denied",
        error.NoDevice => "No such device or address",
        error.ReadOnlyFileSystem => "Read-only file system",
        error.NoSpaceLeft => "No space left on device",
        error.FileTooBig => "File too large",
        else => @errorName(err),
    };
}

pub fn run(args: [][]const u8, _: std.mem.Allocator) !u8 {
    var stdout_buffer: [4096]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var no_create = false;
    var block_mode = false;
    var ref_file: ?[]const u8 = null;
    var target_size: ?i64 = null;
    var rel_mode: RelMode = .none;

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
            if (std.mem.eql(u8, arg, "--help")) {
                printHelp(stdout) catch return 1;
                stdout.flush() catch return 1;
                return 0;
            } else if (std.mem.eql(u8, arg, "--version")) {
                printVersion(stdout) catch return 1;
                stdout.flush() catch return 1;
                return 0;
            } else if (std.mem.eql(u8, arg, "--no-create")) {
                no_create = true;
            } else if (std.mem.eql(u8, arg, "--io-blocks")) {
                block_mode = true;
            } else if (std.mem.startsWith(u8, arg, "--reference=")) {
                ref_file = arg["--reference=".len..];
            } else if (std.mem.eql(u8, arg, "--reference")) {
                i += 1;
                if (i >= args.len) {
                    try stderr.print("truncate: option '--reference' requires an argument\n", .{});
                    return 1;
                }
                ref_file = args[i];
            } else if (std.mem.startsWith(u8, arg, "--size=")) {
                const s_str = arg["--size=".len..];
                const res = parseSize(s_str) catch |err| {
                    switch (err) {
                        error.DivisionByZero => try stderr.print("truncate: division by zero\n", .{}),
                        error.MultipleModifiers => try stderr.print("truncate: multiple relative modifiers specified\nTry 'truncate --help' for more information.\n", .{}),
                        error.ValueTooLarge => try stderr.print("truncate: Invalid number: '{s}': Value too large for defined data type\n", .{s_str}),
                        error.InvalidNumber => try stderr.print("truncate: Invalid number: '{s}'\n", .{s_str}),
                    }
                    return 1;
                };
                target_size = res.size;
                rel_mode = res.rel_mode;
            } else if (std.mem.eql(u8, arg, "--size")) {
                i += 1;
                if (i >= args.len) {
                    try stderr.print("truncate: option '--size' requires an argument\n", .{});
                    return 1;
                }
                const s_str = args[i];
                const res = parseSize(s_str) catch |err| {
                    switch (err) {
                        error.DivisionByZero => try stderr.print("truncate: division by zero\n", .{}),
                        error.MultipleModifiers => try stderr.print("truncate: multiple relative modifiers specified\nTry 'truncate --help' for more information.\n", .{}),
                        error.ValueTooLarge => try stderr.print("truncate: Invalid number: '{s}': Value too large for defined data type\n", .{s_str}),
                        error.InvalidNumber => try stderr.print("truncate: Invalid number: '{s}'\n", .{s_str}),
                    }
                    return 1;
                };
                target_size = res.size;
                rel_mode = res.rel_mode;
            } else {
                try stderr.print("truncate: unrecognized option '{s}'\n", .{arg});
                return 1;
            }
        } else {
            // Short options
            var j: usize = 1;
            while (j < arg.len) : (j += 1) {
                const c = arg[j];
                switch (c) {
                    'c' => no_create = true,
                    'o' => block_mode = true,
                    'r' => {
                        if (j + 1 < arg.len) {
                            ref_file = arg[j + 1 ..];
                            j = arg.len;
                        } else {
                            i += 1;
                            if (i >= args.len) {
                                try stderr.print("truncate: option requires an argument -- 'r'\n", .{});
                                return 1;
                            }
                            ref_file = args[i];
                        }
                    },
                    's' => {
                        var s_str: []const u8 = undefined;
                        if (j + 1 < arg.len) {
                            s_str = arg[j + 1 ..];
                            j = arg.len;
                        } else {
                            i += 1;
                            if (i >= args.len) {
                                try stderr.print("truncate: option requires an argument -- 's'\n", .{});
                                return 1;
                            }
                            s_str = args[i];
                        }
                        const res = parseSize(s_str) catch |err| {
                            switch (err) {
                                error.DivisionByZero => try stderr.print("truncate: division by zero\n", .{}),
                                error.MultipleModifiers => try stderr.print("truncate: multiple relative modifiers specified\nTry 'truncate --help' for more information.\n", .{}),
                                error.ValueTooLarge => try stderr.print("truncate: Invalid number: '{s}': Value too large for defined data type\n", .{s_str}),
                                error.InvalidNumber => try stderr.print("truncate: Invalid number: '{s}'\n", .{s_str}),
                            }
                            return 1;
                        };
                        target_size = res.size;
                        rel_mode = res.rel_mode;
                    },
                    else => {
                        try stderr.print("truncate: invalid option -- '{c}'\n", .{c});
                        return 1;
                    },
                }
            }
        }
    }

    if (ref_file == null and target_size == null) {
        try stderr.print("truncate: you must specify either '--size' or '--reference'\nTry 'truncate --help' for more information.\n", .{});
        return 1;
    }

    if (ref_file != null and target_size != null and rel_mode == .none) {
        try stderr.print("truncate: you must specify a relative '--size' with '--reference'\nTry 'truncate --help' for more information.\n", .{});
        return 1;
    }

    if (block_mode and target_size == null) {
        try stderr.print("truncate: '--io-blocks' was specified but '--size' was not\nTry 'truncate --help' for more information.\n", .{});
        return 1;
    }

    if (file_start >= args.len) {
        try stderr.print("truncate: missing file operand\nTry 'truncate --help' for more information.\n", .{});
        return 1;
    }

    var rsize: ?i64 = null;
    if (ref_file) |rpath| {
        const file = std.Io.Dir.cwd().openFile(std.Options.debug_io, rpath, .{ .mode = .read_only }) catch |err| {
            try stderr.print("truncate: cannot stat '{s}': {s}\n", .{ rpath, openErrorDescription(err) });
            return 1;
        };
        defer file.close(std.Options.debug_io);
        const st = file.stat(std.Options.debug_io) catch |err| {
            try stderr.print("truncate: cannot get the size of '{s}': {s}\n", .{ rpath, @errorName(err) });
            return 1;
        };
        if (target_size == null) {
            target_size = @intCast(st.size);
        } else {
            rsize = @intCast(st.size);
        }
    }

    var exit_status: u8 = 0;
    const base_size = target_size.?;

    for (args[file_start..]) |filename| {
        const flags: std.posix.O = .{
            .ACCMODE = .WRONLY,
            .CREAT = !no_create,
            .NONBLOCK = true,
        };
        const fd = std.posix.openat(std.posix.AT.FDCWD, filename, flags, 0o666) catch |err| {
            if (no_create and err == error.FileNotFound) {
                continue;
            }
            const err_str = openErrorDescription(err);
            try stderr.print("truncate: cannot open '{s}' for writing: {s}\n", .{ filename, err_str });
            exit_status = 1;
            continue;
        };
        const file = std.Io.File{ .handle = fd, .flags = .{ .nonblocking = true } };
        defer file.close(std.Options.debug_io);

        var stx = std.mem.zeroes(std.os.linux.Statx);
        const statx_rc = std.os.linux.statx(fd, "", std.os.linux.AT.EMPTY_PATH, .{ .SIZE = true, .BLOCKS = true }, &stx);
        const statx_err = std.posix.errno(statx_rc);
        if (statx_err != .SUCCESS) {
            const err_str = switch (statx_err) {
                .INVAL => "Invalid argument",
                .FBIG => "File too large",
                .PERM, .ACCES => "Permission denied",
                .IO => "Input/output error",
                else => @tagName(statx_err),
            };
            try stderr.print("truncate: cannot fstat '{s}': {s}\n", .{ filename, err_str });
            exit_status = 1;
            continue;
        }

        var ssize = base_size;
        if (block_mode) {
            const blksize: i64 = if (stx.blksize > 0) @intCast(stx.blksize) else 4096;
            const mul_res = @mulWithOverflow(ssize, blksize);
            if (mul_res[1] != 0) {
                try stderr.print("truncate: overflow in {d} * {d} byte blocks for file '{s}'\n", .{ ssize, blksize, filename });
                exit_status = 1;
                continue;
            }
            ssize = mul_res[0];
        }

        var new_size: i64 = 0;
        if (rel_mode != .none) {
            const fsize: i64 = if (rsize) |r| r else @intCast(stx.size);
            if (fsize < 0) {
                try stderr.print("truncate: '{s}' has unusable, apparently negative size\n", .{filename});
                exit_status = 1;
                continue;
            }

            switch (rel_mode) {
                .none => unreachable,
                .relative => {
                    const add_res = @addWithOverflow(fsize, ssize);
                    if (add_res[1] != 0) {
                        try stderr.print("truncate: overflow extending size of file '{s}'\n", .{filename});
                        exit_status = 1;
                        continue;
                    }
                    new_size = add_res[0];
                },
                .at_least => new_size = @max(fsize, ssize),
                .at_most => new_size = @min(fsize, ssize),
                .round_down => {
                    const r = @rem(fsize, ssize);
                    new_size = fsize - r;
                },
                .round_up => {
                    const r = @rem(fsize, ssize);
                    const add = if (r == 0) 0 else ssize - r;
                    const add_res = @addWithOverflow(fsize, add);
                    if (add_res[1] != 0) {
                        try stderr.print("truncate: overflow extending size of file '{s}'\n", .{filename});
                        exit_status = 1;
                        continue;
                    }
                    new_size = add_res[0];
                },
            }
        } else {
            new_size = ssize;
        }

        if (new_size < 0) new_size = 0;

        const rc = std.posix.system.ftruncate(fd, new_size);
        const err_code = std.posix.errno(rc);
        if (err_code != .SUCCESS) {
            const err_str = switch (err_code) {
                .INVAL => "Invalid argument",
                .FBIG => "File too large",
                .PERM, .ACCES => "Permission denied",
                .IO => "Input/output error",
                .ROFS => "Read-only file system",
                else => @tagName(err_code),
            };
            try stderr.print("truncate: failed to truncate '{s}' at {d} bytes: {s}\n", .{ filename, new_size, err_str });
            exit_status = 1;
        }
    }

    return exit_status;
}

fn printHelp(writer: anytype) !void {
    try writer.print(
        \\Usage: {s} OPTION... FILE...
        \\Shrink or extend the size of each FILE to the specified size
        \\
        \\A FILE argument that does not exist is created.
        \\
        \\If a FILE is larger than the specified size, the extra data is lost.
        \\If a FILE is shorter, it is extended and the sparse extended part (hole)
        \\reads as zero bytes.
        \\
        \\Mandatory arguments to long options are mandatory for short options too.
        \\  -c, --no-create        do not create any files
        \\  -o, --io-blocks        treat SIZE as number of IO blocks instead of bytes
        \\  -r, --reference=RFILE  base size on RFILE
        \\  -s, --size=SIZE        set or adjust the file size by SIZE bytes
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
        \\SIZE may also be prefixed by one of the following modifying characters:
        \\'+' extend by, '-' reduce by, '<' at most, '>' at least,
        \\'/' round down to multiple of, '%' round up to multiple of.
        \\
    , .{name});
}

fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
