const std = @import("std");
const errors = @import("../utils/errors.zig");

const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "tee";
pub const version: []const u8 = "0.1.0";

const OutputError = enum {
    sigpipe, // default traditional behavior, SIGPIPE enabled
    warn, // warn on EPIPE, continue
    warn_nopipe, // ignore EPIPE, continue (default for -p)
    exit, // exit on any error including EPIPE
    exit_nopipe, // exit on any error except EPIPE
};

const Output = struct {
    name: []const u8,
    fd: c_int,
    active: bool,
    is_pipe: bool,
    is_stdout: bool,
};

const IOPOLL_BROKEN_OUTPUT: c_int = 1;
const IOPOLL_READY: c_int = 0;
const IOPOLL_ERROR: c_int = -1;

fn iopoll(fdin: c_int, fdout: c_int, block: bool) c_int {
    var pfds = [2]c.struct_pollfd{
        .{ .fd = fdin, .events = c.POLLIN | c.POLLRDBAND, .revents = 0 },
        .{ .fd = fdout, .events = c.POLLRDBAND, .revents = 0 },
    };
    const check_out_events: c_short = c.POLLERR | c.POLLHUP | c.POLLNVAL;

    while (true) {
        const ret = c.poll(&pfds, 2, if (block) -1 else 0);
        if (ret < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            return IOPOLL_ERROR;
        }
        if (ret == 0 and !block) return IOPOLL_READY;
        if (pfds[0].revents != 0) {
            return IOPOLL_READY;
        }
        if ((pfds[1].revents & check_out_events) != 0) {
            return IOPOLL_BROKEN_OUTPUT;
        }
    }
}

fn iopollInputOk(fd: c_int) bool {
    var st: c.struct_stat = undefined;
    if (c.fstat(fd, &st) == 0) {
        const fmt = st.st_mode & c.S_IFMT;
        if (fmt == c.S_IFREG or fmt == c.S_IFBLK) {
            return false;
        }
    }
    return true;
}

fn isPipe(fd: c_int) bool {
    var st: c.struct_stat = undefined;
    if (c.fstat(fd, &st) == 0) {
        return (st.st_mode & c.S_IFMT) == c.S_IFIFO;
    }
    return false;
}

fn writeWait(fd: c_int, bytes: []const u8) bool {
    var written: usize = 0;
    while (written < bytes.len) {
        const count = bytes.len - written;
        const res = c.write(fd, bytes[written..].ptr, count);
        if (res < 0) {
            const err = c.__errno_location().*;
            if (err == c.EINTR) continue;
            if (err == c.EAGAIN or err == c.EWOULDBLOCK) {
                var pfd = c.struct_pollfd{
                    .fd = fd,
                    .events = c.POLLOUT,
                    .revents = 0,
                };
                while (true) {
                    const pret = c.poll(&pfd, 1, -1);
                    if (pret < 0 and c.__errno_location().* == c.EINTR) continue;
                    if (pret <= 0) return false;
                    break;
                }
                continue;
            }
            return false;
        }
        if (res == 0) return false;
        written += @intCast(res);
    }
    return true;
}

fn handleOutputFailure(
    stderr: anytype,
    output_error: OutputError,
    name_str: []const u8,
    err: c_int,
) !bool {
    const is_epipe = (err == c.EPIPE);
    const should_fail = !is_epipe or output_error == .exit or output_error == .warn;

    if (should_fail) {
        const msg = std.mem.span(c.strerror(err));
        try stderr.print("{s}: {s}: {s}\n", .{ name, name_str, msg });
        try stderr.flush();
    }

    return should_fail;
}

fn getNextOut(outputs: []const Output, start_idx: usize) usize {
    var idx = start_idx + 1;
    while (idx < outputs.len) : (idx += 1) {
        if (outputs[idx].active) return idx;
    }
    return outputs.len;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stderr_buffer: [4096]u8 = undefined;
    var stderr_writer = std.Io.File.Writer.init(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stderr = &stderr_writer.interface;

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_writer = std.Io.File.Writer.init(.stdout(), std.Options.debug_io, &stdout_buffer);
    const stdout = &stdout_writer.interface;

    var append = false;
    var ignore_interrupts = false;
    var output_error = OutputError.sigpipe;

    var file_operands: std.ArrayList([]const u8) = .empty;
    defer file_operands.deinit(allocator);

    const posixly_correct = errors.isPosixlyCorrect();
    var parsing_options = true;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (parsing_options and arg.len > 0 and arg[0] == '-') {
            if (std.mem.eql(u8, arg, "-")) {
                if (posixly_correct) parsing_options = false;
                try file_operands.append(allocator, arg);
                continue;
            }
            if (std.mem.eql(u8, arg, "--")) {
                parsing_options = false;
                continue;
            }
            if (std.mem.startsWith(u8, arg, "--")) {
                if (std.mem.eql(u8, arg, "--help")) {
                    try printHelp(stdout);
                    try stdout.flush();
                    return 0;
                } else if (std.mem.eql(u8, arg, "--version")) {
                    try printVersion(stdout);
                    try stdout.flush();
                    return 0;
                } else if (std.mem.eql(u8, arg, "--append")) {
                    append = true;
                } else if (std.mem.eql(u8, arg, "--ignore-interrupts")) {
                    ignore_interrupts = true;
                } else if (std.mem.eql(u8, arg, "--output-error")) {
                    output_error = .warn_nopipe;
                } else if (std.mem.startsWith(u8, arg, "--output-error=")) {
                    const mode_str = arg["--output-error=".len..];
                    if (std.mem.eql(u8, mode_str, "warn")) {
                        output_error = .warn;
                    } else if (std.mem.eql(u8, mode_str, "warn-nopipe")) {
                        output_error = .warn_nopipe;
                    } else if (std.mem.eql(u8, mode_str, "exit")) {
                        output_error = .exit;
                    } else if (std.mem.eql(u8, mode_str, "exit-nopipe")) {
                        output_error = .exit_nopipe;
                    } else {
                        try stderr.print("{s}: invalid argument '{s}' for '--output-error'\n", .{ name, mode_str });
                        try stderr.writeAll("Valid arguments are:\n  - 'warn'\n  - 'warn-nopipe'\n  - 'exit'\n  - 'exit-nopipe'\n");
                        try stderr.print("Try '{s} --help' for more information.\n", .{name});
                        try stderr.flush();
                        return 1;
                    }
                } else {
                    try errors.printUnrecognizedOption(stderr, name, arg);
                    try stderr.flush();
                    return 1;
                }
                continue;
            }

            // Short options
            var j: usize = 1;
            while (j < arg.len) : (j += 1) {
                const c_opt = arg[j];
                switch (c_opt) {
                    'a' => append = true,
                    'i' => ignore_interrupts = true,
                    'p' => output_error = .warn_nopipe,
                    else => {
                        try errors.printInvalidOption(stderr, name, c_opt);
                        try stderr.flush();
                        return 1;
                    },
                }
            }
            continue;
        }

        if (posixly_correct) parsing_options = false;
        try file_operands.append(allocator, arg);
    }

    if (ignore_interrupts) {
        _ = c.signal(c.SIGINT, c.SIG_IGN);
    }

    if (output_error == .sigpipe) {
        _ = c.signal(c.SIGPIPE, c.SIG_DFL);
    } else {
        _ = c.signal(c.SIGPIPE, c.SIG_IGN);
    }

    const pipe_check = (output_error == .warn_nopipe or output_error == .exit_nopipe) and iopollInputOk(c.STDIN_FILENO);

    var outputs = std.ArrayList(Output).empty;
    defer outputs.deinit(allocator);

    var active_outputs_count: usize = 1; // stdout is always output 0
    var ok = true;

    try outputs.append(allocator, Output{
        .name = "standard output",
        .fd = c.STDOUT_FILENO,
        .active = true,
        .is_pipe = isPipe(c.STDOUT_FILENO),
        .is_stdout = true,
    });

    const open_flags = c.O_WRONLY | c.O_CREAT | (if (append) c.O_APPEND else c.O_TRUNC);

    for (file_operands.items) |filename| {
        const filename_z = try allocator.dupeZ(u8, filename);
        defer allocator.free(filename_z);

        const fd = c.open(filename_z.ptr, open_flags, @as(c_uint, 0o666));
        if (fd < 0) {
            const err = c.__errno_location().*;
            const msg = std.mem.span(c.strerror(err));
            try stderr.print("{s}: {s}: {s}\n", .{ name, filename, msg });
            try stderr.flush();
            ok = false;
            if (output_error == .exit or output_error == .exit_nopipe) {
                return 1;
            }
            try outputs.append(allocator, Output{
                .name = filename,
                .fd = -1,
                .active = false,
                .is_pipe = false,
                .is_stdout = false,
            });
        } else {
            active_outputs_count += 1;
            try outputs.append(allocator, Output{
                .name = filename,
                .fd = fd,
                .active = true,
                .is_pipe = isPipe(fd),
                .is_stdout = false,
            });
        }
    }

    var first_out: usize = 0;

    while (active_outputs_count > 0) {
        if (pipe_check and first_out < outputs.items.len and outputs.items[first_out].is_pipe) {
            const poll_res = iopoll(c.STDIN_FILENO, outputs.items[first_out].fd, true);
            if (poll_res == IOPOLL_BROKEN_OUTPUT) {
                const failed = try handleOutputFailure(stderr, output_error, outputs.items[first_out].name, c.EPIPE);
                if (failed) ok = false;
                if (!outputs.items[first_out].is_stdout) {
                    _ = c.close(outputs.items[first_out].fd);
                }
                outputs.items[first_out].active = false;
                outputs.items[first_out].fd = -1;
                active_outputs_count -= 1;
                if (output_error == .exit or (output_error == .exit_nopipe and failed)) {
                    return 1;
                }
                first_out = getNextOut(outputs.items, first_out);
                continue;
            } else if (poll_res == IOPOLL_ERROR) {
                const p_errno = c.__errno_location().*;
                const msg = std.mem.span(c.strerror(p_errno));
                try stderr.print("{s}: iopoll error: {s}\n", .{ name, msg });
                try stderr.flush();
                ok = false;
            }
        }

        var buf: [8192]u8 = undefined;
        const bytes_read = c.read(c.STDIN_FILENO, &buf, buf.len);
        if (bytes_read < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            const r_errno = c.__errno_location().*;
            const msg = std.mem.span(c.strerror(r_errno));
            try stderr.print("{s}: read error: {s}\n", .{ name, msg });
            try stderr.flush();
            ok = false;
            break;
        }
        if (bytes_read == 0) {
            break; // EOF
        }

        const slice = buf[0..@intCast(bytes_read)];

        var idx: usize = 0;
        while (idx < outputs.items.len) : (idx += 1) {
            if (!outputs.items[idx].active) continue;

            if (!writeWait(outputs.items[idx].fd, slice)) {
                const w_errno = c.__errno_location().*;
                const failed = try handleOutputFailure(stderr, output_error, outputs.items[idx].name, w_errno);
                if (failed) ok = false;
                if (!outputs.items[idx].is_stdout) {
                    _ = c.close(outputs.items[idx].fd);
                }
                outputs.items[idx].active = false;
                outputs.items[idx].fd = -1;
                active_outputs_count -= 1;

                if (output_error == .exit or (output_error == .exit_nopipe and failed)) {
                    return 1;
                }
                if (idx == first_out) {
                    first_out = getNextOut(outputs.items, idx);
                }
            }
        }
    }

    // Close open file outputs (not stdout)
    for (outputs.items) |*out| {
        if (out.active and !out.is_stdout) {
            if (c.close(out.fd) != 0) {
                const c_errno = c.__errno_location().*;
                const msg = std.mem.span(c.strerror(c_errno));
                try stderr.print("{s}: {s}: {s}\n", .{ name, out.name, msg });
                try stderr.flush();
                ok = false;
            }
            out.active = false;
            out.fd = -1;
        }
    }

    if (c.close(c.STDIN_FILENO) != 0) {
        const s_errno = c.__errno_location().*;
        const msg = std.mem.span(c.strerror(s_errno));
        try stderr.print("{s}: standard input: {s}\n", .{ name, msg });
        try stderr.flush();
        return 1;
    }

    return if (ok) 0 else 1;
}

pub fn printHelp(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: tee [OPTION]... [FILE]...
        \\Copy standard input to each FILE, and also to standard output.
        \\
        \\  -a, --append              append to the given FILEs, do not overwrite
        \\  -i, --ignore-interrupts   ignore interrupt signals
        \\  -p                        diagnose errors writing to non pipes
        \\      --output-error[=MODE]   set behavior on write error.  See MODE below
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
        \\MODE determines behavior with write errors on the outputs:
        \\  warn         diagnose errors writing to any output
        \\  warn-nopipe  diagnose errors writing to any output not a pipe
        \\  exit         exit on error writing to any output
        \\  exit-nopipe  exit on error writing to any output not a pipe
        \\The default MODE for the -p option is 'warn-nopipe'.
        \\With "nopipe" MODEs, exit immediately if all outputs become broken pipes.
        \\The default operation when --output-error is not specified, is to
        \\exit immediately on error writing to a pipe, and diagnose errors
        \\writing to non pipe outputs.
        \\
    );
}

pub fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
