const std = @import("std");
const args_mod = @import("csplit/args.zig");
const pattern_mod = @import("csplit/pattern.zig");
const file_manager_mod = @import("csplit/file_manager.zig");
const buffer_mod = @import("csplit/buffer.zig");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "csplit";
pub const version: []const u8 = "0.1.0";

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buf: [65536]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_w: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var stderr_w: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &stdout_w.interface;
    const stderr = &stderr_w.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    const parse_res = args_mod.parseArgs(allocator, args, stderr);
    const opts = switch (parse_res) {
        .ok => |o| o,
        .help => {
            try args_mod.printHelp(stdout);
            stdout.flush() catch return 1;
            return 0;
        },
        .version => {
            try args_mod.printVersion(stdout);
            stdout.flush() catch return 1;
            return 0;
        },
        .err => |code| return code,
    };
    defer if (opts.suffix_format) |fmt| allocator.free(fmt);

    const patterns = pattern_mod.parsePatterns(allocator, opts.pattern_args, stderr) catch return 1;
    defer {
        for (patterns) |*p| p.deinit();
        allocator.free(patterns);
    }

    const input_fd = openInputFd(opts.input_file, stderr) catch return 1;
    defer if (input_fd > 0) {
        _ = c.close(input_fd);
    };

    var fm = file_manager_mod.FileManager.init(
        allocator,
        opts.prefix,
        opts.suffix_format,
        opts.digits,
        opts.keep_files,
        opts.silent,
        opts.elide_empty,
    );
    defer fm.deinit();

    var line_buf = buffer_mod.LineBuffer.init(allocator, input_fd);
    defer line_buf.deinit();

    const rc = executeSplit(allocator, &fm, &line_buf, patterns, opts.suppress_matched, stdout, stderr);
    stdout.flush() catch return 1;
    return rc;
}

fn openInputFd(path: []const u8, stderr: anytype) !c_int {
    if (std.mem.eql(u8, path, "-")) return 0;
    var path_z: [4096]u8 = undefined;
    if (path.len >= path_z.len) return error.PathTooLong;
    @memcpy(path_z[0..path.len], path);
    path_z[path.len] = 0;
    const fd = c.open(&path_z, c.O_RDONLY);
    if (fd < 0) {
        const err_msg = std.mem.sliceTo(c.strerror(c.__errno_location().*), 0);
        try stderr.print("csplit: {s}: {s}\n", .{ path, err_msg });
        return error.OpenFailed;
    }
    return fd;
}

fn executeSplit(
    allocator: std.mem.Allocator,
    fm: *file_manager_mod.FileManager,
    line_buf: *buffer_mod.LineBuffer,
    patterns: []pattern_mod.Pattern,
    suppress_matched: bool,
    stdout: anytype,
    stderr: anytype,
) u8 {
    var regex_buf: [8192]u8 = undefined;
    var search_start_line: usize = 1;

    for (patterns) |*pat| {
        const status = executePatternReps(
            allocator,
            fm,
            line_buf,
            pat,
            suppress_matched,
            &search_start_line,
            &regex_buf,
            stdout,
            stderr,
        );
        if (status == .fatal_error) return 1;
        if (status == .clean_eof) return 0;
    }

    fm.createOutputFile(stdout, stderr) catch return 1;
    line_buf.dumpRest(fm, stderr) catch return 1;
    fm.closeOutputFile(stdout, stderr) catch return 1;
    return 0;
}

const ExecStatus = enum {
    ok,
    clean_eof,
    fatal_error,
};

fn executePatternReps(
    allocator: std.mem.Allocator,
    fm: *file_manager_mod.FileManager,
    line_buf: *buffer_mod.LineBuffer,
    pat: *pattern_mod.Pattern,
    suppress_matched: bool,
    search_start: *usize,
    regex_buf: *[8192]u8,
    stdout: anytype,
    stderr: anytype,
) ExecStatus {
    var rep: usize = 0;
    while (pat.repeat_forever or rep <= pat.repeat) : (rep += 1) {
        const res = switch (pat.pattern_type) {
            .line_number => processLineNumber(allocator, fm, line_buf, pat, rep, suppress_matched, stdout, stderr),
            .regex => processRegex(
                allocator,
                fm,
                line_buf,
                pat,
                rep,
                suppress_matched,
                search_start,
                regex_buf,
                stdout,
                stderr,
            ),
        };
        if (res != .ok) return res;
    }
    return .ok;
}

fn processLineNumber(
    allocator: std.mem.Allocator,
    fm: *file_manager_mod.FileManager,
    line_buf: *buffer_mod.LineBuffer,
    pat: *pattern_mod.Pattern,
    rep: usize,
    suppress_matched: bool,
    stdout: anytype,
    stderr: anytype,
) ExecStatus {
    const target = pat.line_number * (rep + 1);
    const first_line = (line_buf.peek(0) catch null) orelse {
        emitLineError(pat.line_number, rep, stderr);
        fm.cleanupFiles();
        return .fatal_error;
    };
    if (first_line.num > target) {
        emitLineError(pat.line_number, rep, stderr);
        fm.cleanupFiles();
        return .fatal_error;
    }

    fm.createOutputFile(stdout, stderr) catch return .fatal_error;
    while (true) {
        const next_line = (line_buf.peek(0) catch null) orelse {
            emitLineError(pat.line_number, rep, stderr);
            fm.cleanupFiles();
            return .fatal_error;
        };
        if (next_line.num >= target) break;
        const popped = line_buf.pop() catch {
            emitLineError(pat.line_number, rep, stderr);
            fm.cleanupFiles();
            return .fatal_error;
        };
        fm.writeLine(popped.data, stderr) catch {
            allocator.free(popped.data);
            return .fatal_error;
        };
        allocator.free(popped.data);
    }
    fm.closeOutputFile(stdout, stderr) catch return .fatal_error;

    if (suppress_matched) {
        line_buf.discardFirst();
    }
    if (!suppress_matched and (line_buf.peek(0) catch null) == null) {
        emitLineError(pat.line_number, rep, stderr);
        fm.cleanupFiles();
        return .fatal_error;
    }
    return .ok;
}

fn processRegex(
    allocator: std.mem.Allocator,
    fm: *file_manager_mod.FileManager,
    line_buf: *buffer_mod.LineBuffer,
    pat: *pattern_mod.Pattern,
    rep: usize,
    suppress_matched: bool,
    search_start: *usize,
    regex_buf: *[8192]u8,
    stdout: anytype,
    stderr: anytype,
) ExecStatus {
    if (!pat.ignore) {
        fm.createOutputFile(stdout, stderr) catch return .fatal_error;
    }

    if (pat.offset <= 0) {
        const k: usize = @intCast(-pat.offset);
        while (true) {
            const line = line_buf.peek(k) catch return .fatal_error;
            if (line == null) {
                return handleRegexEof(fm, line_buf, pat, rep, stdout, stderr);
            }
            if (line.?.num >= search_start.* and (pat.matchRegex(line.?.data, regex_buf, allocator) catch false)) {
                if (!pat.ignore) {
                    fm.closeOutputFile(stdout, stderr) catch return .fatal_error;
                }
                if (suppress_matched) {
                    line_buf.discardFirst();
                }
                search_start.* = line.?.num + 1;
                return .ok;
            }
            const popped = line_buf.pop() catch return .fatal_error;
            if (!pat.ignore) {
                fm.writeLine(popped.data, stderr) catch {
                    allocator.free(popped.data);
                    return .fatal_error;
                };
            }
            allocator.free(popped.data);
        }
    } else {
        return processPositiveOffset(allocator, fm, line_buf, pat, rep, suppress_matched, search_start, regex_buf, stdout, stderr);
    }
}

fn processPositiveOffset(
    allocator: std.mem.Allocator,
    fm: *file_manager_mod.FileManager,
    line_buf: *buffer_mod.LineBuffer,
    pat: *pattern_mod.Pattern,
    rep: usize,
    suppress_matched: bool,
    search_start: *usize,
    regex_buf: *[8192]u8,
    stdout: anytype,
    stderr: anytype,
) ExecStatus {
    const k: usize = @intCast(pat.offset);
    while (true) {
        const line = line_buf.peek(0) catch return .fatal_error;
        if (line == null) {
            return handleRegexEof(fm, line_buf, pat, rep, stdout, stderr);
        }
        if (line.?.num >= search_start.* and (pat.matchRegex(line.?.data, regex_buf, allocator) catch false)) {
            var i: usize = 0;
            while (i < k) : (i += 1) {
                const p = line_buf.pop() catch {
                    stderr.print("csplit: '{s}': line number out of range\n", .{pat.raw_arg}) catch {};
                    fm.cleanupFiles();
                    return .fatal_error;
                };
                if (!pat.ignore) {
                    fm.writeLine(p.data, stderr) catch {
                        allocator.free(p.data);
                        return .fatal_error;
                    };
                }
                allocator.free(p.data);
            }
            if (!pat.ignore) {
                fm.closeOutputFile(stdout, stderr) catch return .fatal_error;
            }
            if (suppress_matched) {
                line_buf.discardFirst();
            }
            search_start.* = line.?.num + k + 1;
            return .ok;
        }
        const popped = line_buf.pop() catch return .fatal_error;
        if (!pat.ignore) {
            fm.writeLine(popped.data, stderr) catch {
                allocator.free(popped.data);
                return .fatal_error;
            };
        }
        allocator.free(popped.data);
    }
}

fn handleRegexEof(
    fm: *file_manager_mod.FileManager,
    line_buf: *buffer_mod.LineBuffer,
    pat: *pattern_mod.Pattern,
    rep: usize,
    stdout: anytype,
    stderr: anytype,
) ExecStatus {
    if (pat.repeat_forever) {
        if (!pat.ignore) {
            line_buf.dumpRest(fm, stderr) catch return .fatal_error;
            fm.closeOutputFile(stdout, stderr) catch return .fatal_error;
        }
        return .clean_eof;
    }
    emitRegexError(pat.raw_arg, rep, stderr);
    fm.cleanupFiles();
    return .fatal_error;
}

fn emitLineError(line_num: usize, rep: usize, stderr: anytype) void {
    if (rep == 0) {
        stderr.print("csplit: '{d}': line number out of range\n", .{line_num}) catch {};
    } else {
        stderr.print("csplit: '{d}': line number out of range on repetition {d}\n", .{ line_num, rep }) catch {};
    }
}

fn emitRegexError(raw_arg: []const u8, rep: usize, stderr: anytype) void {
    if (rep == 0) {
        stderr.print("csplit: '{s}': match not found\n", .{raw_arg}) catch {};
    } else {
        stderr.print("csplit: '{s}': match not found on repetition {d}\n", .{ raw_arg, rep }) catch {};
    }
}
