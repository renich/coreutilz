const std = @import("std");
const errors = @import("../utils/errors.zig");
const args_mod = @import("fold/args.zig");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "fold";
pub const version: []const u8 = "0.1.0";

fn printHelp(writer: anytype) !void {
    try writer.print(
        \\Usage: {s} [OPTION]... [FILE]...
        \\Wrap input lines in each FILE, writing to standard output.
        \\
        \\With no FILE, or when FILE is -, read standard input.
        \\
        \\Mandatory arguments to long options are mandatory for short options too.
        \\  -b, --bytes         count bytes rather than columns
        \\  -c, --characters    count characters rather than columns
        \\  -s, --spaces        break at spaces
        \\  -w, --width=WIDTH   use WIDTH columns instead of 80
        \\      --help          display this help and exit
        \\      --version       output version information and exit
        \\
        \\GNU coreutils online help: <https://www.gnu.org/software/coreutils/>
        \\Full documentation <https://www.gnu.org/software/coreutils/fold>
        \\or available locally via: info '(coreutils) fold invocation'
        \\
    , .{name});
}

fn adjustColumn(
    col: usize,
    cp: u21,
    byte_len: usize,
    mode: args_mod.Mode,
    last_char_w: *usize,
) usize {
    if (mode == .bytes) {
        last_char_w.* = byte_len;
        return col + byte_len;
    }
    if (cp == '\x08') {
        return if (col > last_char_w.*) col - last_char_w.* else 0;
    }
    if (cp == '\r') {
        return 0;
    }
    if (cp == '\t') {
        return col + (8 - (col % 8));
    }
    if (mode == .characters) {
        last_char_w.* = 1;
    } else {
        const w = c.wcwidth(@intCast(cp));
        last_char_w.* = if (w < 0) 1 else @intCast(w);
    }
    return col + last_char_w.*;
}

fn writeOut(stdout: anytype, slice: []const u8, newline: bool) !void {
    if (slice.len > 0) {
        try stdout.writeAll(slice);
    }
    if (newline) {
        try stdout.writeAll("\n");
    }
}

const Folder = struct {
    opts: args_mod.Options,
    line_out: [65536]u8 = undefined,
    offset_out: usize = 0,
    col: usize = 0,
    last_char_w: usize = 0,

    fn init(opts: args_mod.Options) Folder {
        return .{
            .opts = opts,
            .offset_out = 0,
            .col = 0,
            .last_char_w = 0,
        };
    }

    fn findLastBlank(self: *const Folder) ?usize {
        var p: usize = self.offset_out;
        while (p > 0) {
            p -= 1;
            const b = self.line_out[p];
            if (b == ' ' or b == '\t') return p;
        }
        return null;
    }

    fn recomputeCol(self: *Folder) void {
        self.col = 0;
        self.last_char_w = 0;
        var i: usize = 0;
        while (i < self.offset_out) {
            const b = self.line_out[i];
            const seq_len = std.unicode.utf8ByteSequenceLength(b) catch 1;
            const rem = self.offset_out - i;
            if (seq_len <= rem and self.opts.mode != .bytes) {
                const cp = std.unicode.utf8Decode(self.line_out[i .. i + seq_len]) catch {
                    self.col = adjustColumn(self.col, b, 1, self.opts.mode, &self.last_char_w);
                    i += 1;
                    continue;
                };
                self.col = adjustColumn(self.col, cp, seq_len, self.opts.mode, &self.last_char_w);
                i += seq_len;
            } else {
                self.col = adjustColumn(self.col, b, 1, self.opts.mode, &self.last_char_w);
                i += 1;
            }
        }
    }

    fn breakOnBlank(self: *Folder, blank_pos: usize, stdout: anytype) !void {
        const break_len = blank_pos + 1;
        try writeOut(stdout, self.line_out[0..break_len], true);
        const rem = self.offset_out - break_len;
        if (rem > 0) {
            std.mem.copyForwards(u8, self.line_out[0..rem], self.line_out[break_len..self.offset_out]);
        }
        self.offset_out = rem;
        self.recomputeCol();
    }

    fn outputChar(
        self: *Folder,
        bytes: []const u8,
        cp: u21,
        stdout: anytype,
    ) !void {
        if (cp == '\n') {
            try writeOut(stdout, self.line_out[0..self.offset_out], true);
            self.offset_out = 0;
            self.col = 0;
            self.last_char_w = 0;
            return;
        }

        while (true) {
            var temp_last_w = self.last_char_w;
            const new_col = adjustColumn(self.col, cp, bytes.len, self.opts.mode, &temp_last_w);

            if (new_col > self.opts.width) {
                if (self.opts.spaces) {
                    if (self.findLastBlank()) |blank_pos| {
                        try self.breakOnBlank(blank_pos, stdout);
                        continue;
                    }
                }
                if (self.offset_out == 0) {
                    @memcpy(self.line_out[0..bytes.len], bytes);
                    self.offset_out = bytes.len;
                    self.col = new_col;
                    self.last_char_w = temp_last_w;
                    return;
                }
                try writeOut(stdout, self.line_out[0..self.offset_out], true);
                self.offset_out = 0;
                self.col = 0;
                self.last_char_w = 0;
                continue;
            }

            if (self.offset_out + bytes.len > self.line_out.len) {
                try writeOut(stdout, self.line_out[0..self.offset_out], false);
                self.offset_out = 0;
            }

            @memcpy(self.line_out[self.offset_out .. self.offset_out + bytes.len], bytes);
            self.offset_out += bytes.len;
            self.col = new_col;
            self.last_char_w = temp_last_w;
            return;
        }
    }

    fn flush(self: *Folder, stdout: anytype) !void {
        if (self.offset_out > 0) {
            try writeOut(stdout, self.line_out[0..self.offset_out], false);
            self.offset_out = 0;
            self.col = 0;
            self.last_char_w = 0;
        }
    }
};

fn foldStream(file: std.Io.File, folder: *Folder, stdout: anytype) !void {
    var in_buf: [65536]u8 = undefined;
    var in_len: usize = 0;

    while (true) {
        const n = c.read(file.handle, in_buf[in_len..].ptr, in_buf.len - in_len);
        if (n < 0) {
            if (c.__errno_location().* == c.EINTR) continue;
            return error.ReadError;
        }
        if (n == 0) {
            if (in_len > 0) {
                for (in_buf[0..in_len]) |b| {
                    const single = [1]u8{b};
                    try folder.outputChar(&single, b, stdout);
                }
            }
            break;
        }
        in_len += @intCast(n);

        var i: usize = 0;
        while (i < in_len) {
            const b = in_buf[i];
            if (folder.opts.mode == .bytes) {
                const single = [1]u8{b};
                try folder.outputChar(&single, b, stdout);
                i += 1;
                continue;
            }
            const seq_len = std.unicode.utf8ByteSequenceLength(b) catch 1;
            if (i + seq_len > in_len) {
                break;
            }
            if (seq_len == 1) {
                const single = [1]u8{b};
                try folder.outputChar(&single, b, stdout);
                i += 1;
            } else {
                const slice = in_buf[i .. i + seq_len];
                const cp = std.unicode.utf8Decode(slice) catch {
                    const single = [1]u8{b};
                    try folder.outputChar(&single, b, stdout);
                    i += 1;
                    continue;
                };
                try folder.outputChar(slice, cp, stdout);
                i += seq_len;
            }
        }

        const rem = in_len - i;
        if (rem > 0 and i > 0) {
            std.mem.copyForwards(u8, in_buf[0..rem], in_buf[i..in_len]);
        }
        in_len = rem;
    }
}

fn handleWriteError(stderr: anytype) void {
    const errno_val = c.__errno_location().*;
    if (errno_val != 0) {
        const err_str = std.mem.span(c.strerror(errno_val));
        stderr.print("fold: write error: {s}\n", .{err_str}) catch {};
    } else {
        stderr.print("fold: write error: No space left on device\n", .{}) catch {};
    }
}

fn processFile(path: []const u8, folder: *Folder, stdout: anytype, stderr: anytype) u8 {
    if (std.mem.eql(u8, path, "-")) {
        foldStream(std.Io.File.stdin(), folder, stdout) catch |err| {
            if (err == error.WriteFailed or err == error.DiskFull or err == error.NoSpaceLeft) {
                handleWriteError(stderr);
            }
            return 1;
        };
        return 0;
    }
    const file = std.Io.Dir.cwd().openFile(std.Options.debug_io, path, .{ .mode = .read_only }) catch |err| {
        errors.printErrorWithArg(stderr, "fold", path, err) catch {};
        return 1;
    };
    defer file.close(std.Options.debug_io);
    foldStream(file, folder, stdout) catch |err| {
        if (err == error.WriteFailed or err == error.DiskFull or err == error.NoSpaceLeft) {
            handleWriteError(stderr);
        }
        return 1;
    };
    return 0;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    _ = c.setlocale(c.LC_ALL, "");
    _ = c.signal(c.SIGPIPE, c.SIG_DFL);

    var stdout_buf: [65536]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_w: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var stderr_w: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &stdout_w.interface;
    const stderr = &stderr_w.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    const res = args_mod.parseArgs(args, allocator, stderr);
    var opts = switch (res) {
        .ok => |o| o,
        .help => {
            try printHelp(stdout);
            stdout.flush() catch return 1;
            return 0;
        },
        .version => {
            try errors.printVersion(stdout, name, version);
            stdout.flush() catch return 1;
            return 0;
        },
        .err => |code| return code,
    };
    defer opts.deinit(allocator);

    var folder = Folder.init(opts);
    var exit_code: u8 = 0;
    if (opts.files.items.len == 0) {
        foldStream(std.Io.File.stdin(), &folder, stdout) catch |err| {
            if (err == error.WriteFailed or err == error.DiskFull or err == error.NoSpaceLeft) {
                handleWriteError(stderr);
                return 1;
            }
            exit_code = 1;
        };
    } else {
        for (opts.files.items) |path| {
            if (processFile(path, &folder, stdout, stderr) != 0) {
                exit_code = 1;
            }
        }
    }
    folder.flush(stdout) catch |err| {
        if (err == error.WriteFailed or err == error.DiskFull or err == error.NoSpaceLeft) {
            handleWriteError(stderr);
            return 1;
        }
        return 1;
    };
    stdout.flush() catch |err| {
        if (err == error.WriteFailed or err == error.DiskFull or err == error.NoSpaceLeft) {
            handleWriteError(stderr);
            return 1;
        }
        return 1;
    };
    return exit_code;
}
