const std = @import("std");
const errors = @import("../utils/errors.zig");

const c = @cImport({
    @cInclude("sys/stat.h");
    @cInclude("unistd.h");
    @cInclude("string.h");
    @cInclude("errno.h");
});

pub const name: []const u8 = "chmod";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buffer: [16384]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .init(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .init(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var recursive = false;
    var verbose = false;
    var changes = false;
    var silent = false;
    var reference_file: ?[]const u8 = null;
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
        } else if (std.mem.eql(u8, arg, "-R") or std.mem.eql(u8, arg, "--recursive")) {
            recursive = true;
        } else if (std.mem.eql(u8, arg, "-v") or std.mem.eql(u8, arg, "--verbose")) {
            verbose = true;
        } else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--changes")) {
            changes = true;
        } else if (std.mem.eql(u8, arg, "-f") or std.mem.eql(u8, arg, "--silent") or std.mem.eql(u8, arg, "--quiet")) {
            silent = true;
        } else if (std.mem.startsWith(u8, arg, "--reference=")) {
            reference_file = arg["--reference=".len..];
        } else if (std.mem.eql(u8, arg, "--reference")) {
            if (i + 1 >= args.len) {
                try errors.printError(stderr, name, "option '--reference' requires an argument");
                return 1;
            }
            i += 1;
            reference_file = args[i];
        } else if (std.mem.eql(u8, arg, "--")) {
            files_start = i + 1;
            break;
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1 and arg[1] != '-') {
            var j: usize = 1;
            var is_flag = true;
            while (j < arg.len) : (j += 1) {
                switch (arg[j]) {
                    'R' => recursive = true,
                    'v' => verbose = true,
                    'c' => changes = true,
                    'f' => silent = true,
                    else => {
                        // Could be symbolic mode like -w or -x
                        is_flag = false;
                        break;
                    },
                }
            }
            if (!is_flag) {
                // It's a mode argument starting with -
                files_start = i;
                break;
            }
        } else {
            files_start = i;
            break;
        }
    }

    var fixed_mode: ?u32 = null;
    var mode_spec: ?[]const u8 = null;
    var target_files: [][]const u8 = undefined;

    if (reference_file) |ref| {
        const ref_z = try allocator.dupeZ(u8, ref);
        defer allocator.free(ref_z);
        var ref_st: c.struct_stat = undefined;
        if (c.stat(ref_z.ptr, &ref_st) != 0) {
            if (!silent) {
                const err_msg = std.mem.span(c.strerror(c.__errno_location().*));
                const msg = try std.fmt.allocPrint(allocator, "failed to get attributes of '{s}': {s}", .{ ref, err_msg });
                defer allocator.free(msg);
                try errors.printError(stderr, name, msg);
            }
            return 1;
        }
        fixed_mode = ref_st.st_mode & 0o7777;
        if (files_start >= args.len) {
            try errors.printError(stderr, name, "missing operand");
            return 1;
        }
        target_files = args[files_start..];
    } else {
        if (files_start >= args.len) {
            try errors.printError(stderr, name, "missing operand");
            return 1;
        }
        mode_spec = args[files_start];
        if (files_start + 1 >= args.len) {
            const msg = try std.fmt.allocPrint(allocator, "missing operand after '{s}'", .{mode_spec.?});
            defer allocator.free(msg);
            try errors.printError(stderr, name, msg);
            return 1;
        }
        target_files = args[files_start + 1 ..];
    }

    var exit_status: u8 = 0;

    for (target_files) |file| {
        const ok = try chmodPath(
            allocator,
            file,
            mode_spec,
            fixed_mode,
            recursive,
            verbose,
            changes,
            silent,
            stdout,
            stderr,
        );
        if (!ok and !silent) {
            exit_status = 1;
        }
    }

    return exit_status;
}

fn chmodPath(
    allocator: std.mem.Allocator,
    file: []const u8,
    mode_spec: ?[]const u8,
    fixed_mode: ?u32,
    recursive: bool,
    verbose: bool,
    changes: bool,
    silent: bool,
    stdout: anytype,
    stderr: anytype,
) !bool {
    const file_z = try allocator.dupeZ(u8, file);
    defer allocator.free(file_z);

    var st: c.struct_stat = undefined;
    if (c.lstat(file_z.ptr, &st) != 0) {
        if (!silent) {
            const err_msg = std.mem.span(c.strerror(c.__errno_location().*));
            const msg = try std.fmt.allocPrint(allocator, "cannot access '{s}': {s}", .{ file, err_msg });
            defer allocator.free(msg);
            try errors.printError(stderr, name, msg);
        }
        return false;
    }

    const is_dir = ((st.st_mode & c.S_IFMT) == c.S_IFDIR);
    const old_mode = st.st_mode & 0o7777;

    const new_mode = if (fixed_mode) |m|
        m
    else
        applyMode(old_mode, mode_spec.?, is_dir) catch {
            if (!silent) {
                const msg = try std.fmt.allocPrint(allocator, "invalid mode: '{s}'", .{mode_spec.?});
                defer allocator.free(msg);
                try errors.printError(stderr, name, msg);
            }
            return false;
        };

    var ok = true;
    if (c.chmod(file_z.ptr, @intCast(new_mode)) != 0) {
        if (!silent) {
            const err_msg = std.mem.span(c.strerror(c.__errno_location().*));
            const msg = try std.fmt.allocPrint(allocator, "changing permissions of '{s}': {s}", .{ file, err_msg });
            defer allocator.free(msg);
            try errors.printError(stderr, name, msg);
        }
        ok = false;
    } else {
        if (verbose or (changes and new_mode != old_mode)) {
            if (new_mode != old_mode) {
                try stdout.print("mode of '{s}' changed from {o:0>4} to {o:0>4}\n", .{ file, old_mode, new_mode });
            } else {
                try stdout.print("mode of '{s}' retained as {o:0>4}\n", .{ file, new_mode });
            }
        }
    }

    if (recursive and is_dir) {
        var dir = std.Io.Dir.cwd().openDir(std.Options.debug_io, file, .{ .iterate = true }) catch return ok;
        defer dir.close(std.Options.debug_io);
        var it = dir.iterate();
        while (it.next(std.Options.debug_io) catch null) |entry| {
            const sub_path = try std.fs.path.join(allocator, &[_][]const u8{ file, entry.name });
            defer allocator.free(sub_path);
            const sub_ok = try chmodPath(
                allocator,
                sub_path,
                mode_spec,
                fixed_mode,
                recursive,
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

fn applyMode(current_mode: u32, spec: []const u8, is_dir: bool) !u32 {
    if (spec.len > 0 and spec[0] >= '0' and spec[0] <= '7') {
        const num = std.fmt.parseInt(u32, spec, 8) catch return error.InvalidMode;
        return num & 0o7777;
    }

    var mode = current_mode & 0o7777;
    var clause_it = std.mem.splitScalar(u8, spec, ',');
    while (clause_it.next()) |clause| {
        if (clause.len == 0) continue;
        var idx: usize = 0;

        var who_u = false;
        var who_g = false;
        var who_o = false;

        while (idx < clause.len) : (idx += 1) {
            switch (clause[idx]) {
                'u' => who_u = true,
                'g' => who_g = true,
                'o' => who_o = true,
                'a' => {
                    who_u = true;
                    who_g = true;
                    who_o = true;
                },
                '+', '-', '=' => break,
                else => return error.InvalidMode,
            }
        }

        if (!who_u and !who_g and !who_o) {
            who_u = true;
            who_g = true;
            who_o = true;
        }

        if (idx >= clause.len) return error.InvalidMode;
        const op = clause[idx];
        idx += 1;

        var perm_bits: u32 = 0;
        var copy_from_u = false;
        var copy_from_g = false;
        var copy_from_o = false;

        while (idx < clause.len) : (idx += 1) {
            switch (clause[idx]) {
                'r' => perm_bits |= 4,
                'w' => perm_bits |= 2,
                'x' => perm_bits |= 1,
                'X' => {
                    if (is_dir or (current_mode & 0o111 != 0)) {
                        perm_bits |= 1;
                    }
                },
                's' => {},
                't' => {},
                'u' => copy_from_u = true,
                'g' => copy_from_g = true,
                'o' => copy_from_o = true,
                else => return error.InvalidMode,
            }
        }

        if (copy_from_u) {
            perm_bits = (current_mode >> 6) & 7;
        } else if (copy_from_g) {
            perm_bits = (current_mode >> 3) & 7;
        } else if (copy_from_o) {
            perm_bits = current_mode & 7;
        }

        var mask: u32 = 0;
        if (who_u) mask |= (perm_bits << 6);
        if (who_g) mask |= (perm_bits << 3);
        if (who_o) mask |= perm_bits;

        switch (op) {
            '+' => mode |= mask,
            '-' => mode &= ~mask,
            '=' => {
                var clear_mask: u32 = 0;
                if (who_u) clear_mask |= (7 << 6);
                if (who_g) clear_mask |= (7 << 3);
                if (who_o) clear_mask |= 7;
                mode = (mode & ~clear_mask) | mask;
            },
            else => return error.InvalidMode,
        }
    }

    return mode;
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
        \\      --reference=RFILE  use RFILE's mode instead of MODE values
        \\  -R, --recursive        change files and directories recursively
        \\      --help     display this help and exit
        \\      --version  output version information and exit
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
