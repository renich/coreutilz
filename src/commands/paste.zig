const std = @import("std");
const errors = @import("../utils/errors.zig");
const c = @cImport({
    @cInclude("locale.h");
    @cInclude("wchar.h");
});

pub const name: []const u8 = "paste";
pub const version: []const u8 = "0.1.0";

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

fn printHelp(writer: anytype) !void {
    try writer.print(
        \\Usage: {s} [OPTION]... [FILE]...
        \\Write lines consisting of the sequentially corresponding lines from
        \\each FILE, separated by TABs, to standard output.
        \\The newline of every line except the line from the last file
        \\is replaced with a TAB.
        \\
        \\With no FILE, or when FILE is -, read standard input.
        \\
        \\Mandatory arguments to long options are mandatory for short options too.
        \\  -d, --delimiters=LIST
        \\         reuse characters from LIST instead of TABs;
        \\         backslash escapes are supported
        \\  -s, --serial
        \\         paste one file at a time instead of in parallel; the newline of
        \\         every line except the last line in each file is replaced with a TAB
        \\  -z, --zero-terminated
        \\         line delimiter is NUL, not newline
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
        \\Report bugs to: bug-coreutils@gnu.org
        \\GNU coreutils home page: <https://www.gnu.org/software/coreutils/>
        \\General help using GNU software: <https://www.gnu.org/gethelp/>
        \\Full documentation <https://www.gnu.org/software/coreutils/paste>
        \\or available locally via: info '(coreutils) paste invocation'
        \\
    , .{name});
}

fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}

fn nextCharLen(slice: []const u8) usize {
    if (slice.len == 0) return 0;
    var state: c.mbstate_t = std.mem.zeroes(c.mbstate_t);
    var wc: c.wchar_t = 0;
    const res = c.mbrtowc(&wc, slice.ptr, slice.len, &state);
    if (res == 0) return 1;
    if (res == std.math.maxInt(usize) or res == std.math.maxInt(usize) - 1) {
        return 1;
    }
    return res;
}

fn parseDelimiters(
    delim_arg: []const u8,
    allocator: std.mem.Allocator,
    stderr: anytype,
) ![][]const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    errdefer list.deinit(allocator);

    var i: usize = 0;
    while (i < delim_arg.len) {
        if (delim_arg[i] == '\\') {
            i += 1;
            if (i >= delim_arg.len) {
                try stderr.print("paste: delimiter list ends with an unescaped backslash: {s}\n", .{delim_arg});
                return error.UnescapedBackslash;
            }
            const esc_ch = delim_arg[i];
            switch (esc_ch) {
                '0' => {
                    try list.append(allocator, "");
                    i += 1;
                },
                'b' => {
                    try list.append(allocator, "\x08");
                    i += 1;
                },
                'f' => {
                    try list.append(allocator, "\x0c");
                    i += 1;
                },
                'n' => {
                    try list.append(allocator, "\n");
                    i += 1;
                },
                'r' => {
                    try list.append(allocator, "\r");
                    i += 1;
                },
                't' => {
                    try list.append(allocator, "\t");
                    i += 1;
                },
                'v' => {
                    try list.append(allocator, "\x0b");
                    i += 1;
                },
                '\\' => {
                    try list.append(allocator, "\\");
                    i += 1;
                },
                else => {
                    const len = nextCharLen(delim_arg[i..]);
                    try list.append(allocator, delim_arg[i .. i + len]);
                    i += len;
                },
            }
        } else {
            const len = nextCharLen(delim_arg[i..]);
            try list.append(allocator, delim_arg[i .. i + len]);
            i += len;
        }
    }

    if (list.items.len == 0) {
        try list.append(allocator, "");
    }

    return list.toOwnedSlice(allocator);
}

const FileReader = struct {
    file: std.Io.File,
    is_stdin: bool,
    r_buf: [16384]u8 = undefined,
    reader_impl: ?std.Io.File.Reader = null,
    reader: ?*std.Io.Reader = null,
    is_closed: bool = false,

    fn init(file: std.Io.File, is_stdin: bool) FileReader {
        return .{
            .file = file,
            .is_stdin = is_stdin,
        };
    }

    fn ensureReader(self: *FileReader) *std.Io.Reader {
        if (self.reader == null) {
            self.reader_impl = self.file.readerStreaming(std.Options.debug_io, &self.r_buf);
            self.reader = &self.reader_impl.?.interface;
        }
        return self.reader.?;
    }

    fn getByte(self: *FileReader) !?u8 {
        const r = self.ensureReader();
        return r.takeByte() catch |err| switch (err) {
            error.EndOfStream => null,
            else => |e| e,
        };
    }

    fn close(self: *FileReader) void {
        if (!self.is_stdin and !self.is_closed) {
            self.is_closed = true;
            self.file.close(std.Options.debug_io);
        }
    }
};

fn pasteParallel(
    files: [][]const u8,
    delims: []const []const u8,
    line_delim: u8,
    stdout: anytype,
    stderr: anytype,
    allocator: std.mem.Allocator,
) !u8 {
    const nfiles = files.len;
    const file_ptrs = try allocator.alloc(?*FileReader, nfiles);
    defer allocator.free(file_ptrs);

    var all_readers: std.ArrayList(*FileReader) = .empty;
    defer {
        for (all_readers.items) |r| {
            r.close();
            allocator.destroy(r);
        }
        all_readers.deinit(allocator);
    }

    var stdin_reader: ?*FileReader = null;
    var files_open: usize = 0;

    for (files, 0..) |file_path, i| {
        if (std.mem.eql(u8, file_path, "-")) {
            if (stdin_reader == null) {
                const r = try allocator.create(FileReader);
                r.* = FileReader.init(std.Io.File.stdin(), true);
                try all_readers.append(allocator, r);
                stdin_reader = r;
            }
            file_ptrs[i] = stdin_reader;
            files_open += 1;
        } else {
            const f = std.Io.Dir.cwd().openFile(std.Options.debug_io, file_path, .{ .mode = .read_only }) catch |err| {
                try stderr.print("paste: {s}: {s}\n", .{ file_path, openErrorDescription(err) });
                return 1;
            };
            const r = try allocator.create(FileReader);
            r.* = FileReader.init(f, false);
            try all_readers.append(allocator, r);
            file_ptrs[i] = r;
            files_open += 1;
        }
    }

    var delbuf: std.ArrayList(u8) = .empty;
    defer delbuf.deinit(allocator);

    while (files_open > 0) {
        var somedone = false;
        var delimidx: usize = 0;
        delbuf.clearRetainingCapacity();

        var i: usize = 0;
        while (i < nfiles and files_open > 0) : (i += 1) {
            var chr_opt: ?u8 = null;
            var sometodo = false;

            if (file_ptrs[i]) |reader| {
                chr_opt = try reader.getByte();
                if (chr_opt != null and delbuf.items.len > 0) {
                    try stdout.writeAll(delbuf.items);
                    delbuf.clearRetainingCapacity();
                }

                while (chr_opt) |chr| {
                    sometodo = true;
                    if (chr == line_delim) break;
                    try stdout.writeByte(chr);
                    chr_opt = try reader.getByte();
                }
            }

            if (!sometodo) {
                if (file_ptrs[i]) |reader| {
                    if (reader.is_stdin) {
                        for (file_ptrs, 0..) |slot, idx| {
                            if (slot == reader) {
                                file_ptrs[idx] = null;
                                files_open -= 1;
                            }
                        }
                    } else {
                        reader.close();
                        file_ptrs[i] = null;
                        files_open -= 1;
                    }
                }

                if (i + 1 == nfiles) {
                    if (somedone) {
                        if (delbuf.items.len > 0) {
                            try stdout.writeAll(delbuf.items);
                            delbuf.clearRetainingCapacity();
                        }
                        try stdout.writeByte(line_delim);
                    }
                } else {
                    const delim = delims[delimidx];
                    try delbuf.appendSlice(allocator, delim);
                    delimidx += 1;
                    if (delimidx == delims.len) delimidx = 0;
                }
            } else {
                somedone = true;
                if (i + 1 != nfiles) {
                    if (chr_opt) |chr| {
                        if (chr != line_delim) {
                            try stdout.writeByte(chr);
                        }
                    }
                    const delim = delims[delimidx];
                    try stdout.writeAll(delim);
                    delimidx += 1;
                    if (delimidx == delims.len) delimidx = 0;
                } else {
                    const chr = chr_opt orelse line_delim;
                    try stdout.writeByte(chr);
                }
            }
        }
    }

    return 0;
}

fn pasteSerial(
    files: [][]const u8,
    delims: []const []const u8,
    line_delim: u8,
    stdout: anytype,
    stderr: anytype,
    _: std.mem.Allocator,
) !u8 {
    var ok = true;

    for (files) |file_path| {
        const is_stdin = std.mem.eql(u8, file_path, "-");
        const file = if (is_stdin) std.Io.File.stdin() else std.Io.Dir.cwd().openFile(std.Options.debug_io, file_path, .{ .mode = .read_only }) catch |err| {
            try stderr.print("paste: {s}: {s}\n", .{ file_path, openErrorDescription(err) });
            ok = false;
            continue;
        };
        defer if (!is_stdin) file.close(std.Options.debug_io);

        var r_buf: [16384]u8 = undefined;
        var r = file.readerStreaming(std.Options.debug_io, &r_buf);
        const reader = &r.interface;

        var delimidx: usize = 0;

        const charold = reader.takeByte() catch |err| switch (err) {
            error.EndOfStream => null,
            else => |e| return e,
        };

        if (charold) |co| {
            var current_old = co;
            while (true) {
                const charnew = reader.takeByte() catch |err| switch (err) {
                    error.EndOfStream => null,
                    else => |e| return e,
                };
                if (charnew == null) break;

                if (current_old == line_delim) {
                    const delim = delims[delimidx];
                    try stdout.writeAll(delim);
                    delimidx += 1;
                    if (delimidx == delims.len) delimidx = 0;
                } else {
                    try stdout.writeByte(current_old);
                }

                current_old = charnew.?;
            }
            try stdout.writeByte(current_old);
            if (current_old != line_delim) {
                try stdout.writeByte(line_delim);
            }
        } else {
            // Empty file
            try stdout.writeByte(line_delim);
        }
    }

    return if (ok) 0 else 1;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buffer: [16384]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    _ = c.setlocale(c.LC_ALL, "");

    var serial_merge = false;
    var delim_arg: []const u8 = "\t";
    var line_delim: u8 = '\n';

    var files: std.ArrayList([]const u8) = .empty;
    defer files.deinit(allocator);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            while (i < args.len) : (i += 1) {
                try files.append(allocator, args[i]);
            }
            break;
        }

        if (std.mem.startsWith(u8, arg, "--")) {
            const eq_pos = std.mem.indexOfScalar(u8, arg, '=');
            const opt_name = if (eq_pos) |pos| arg[0..pos] else arg;
            const val_in_opt = if (eq_pos) |pos| arg[pos + 1 ..] else null;

            if (std.mem.startsWith(u8, "--help", opt_name)) {
                printHelp(stdout) catch return 1;
                stdout.flush() catch return 1;
                return 0;
            } else if (std.mem.startsWith(u8, "--version", opt_name)) {
                printVersion(stdout) catch return 1;
                stdout.flush() catch return 1;
                return 0;
            } else if (std.mem.startsWith(u8, "--serial", opt_name)) {
                if (val_in_opt != null) {
                    try stderr.print("paste: option '{s}' doesn't allow an argument\nTry 'paste --help' for more information.\n", .{opt_name});
                    return 1;
                }
                serial_merge = true;
            } else if (std.mem.startsWith(u8, "--zero-terminated", opt_name)) {
                if (val_in_opt != null) {
                    try stderr.print("paste: option '{s}' doesn't allow an argument\nTry 'paste --help' for more information.\n", .{opt_name});
                    return 1;
                }
                line_delim = 0;
            } else if (std.mem.startsWith(u8, "--delimiters", opt_name)) {
                const val = if (val_in_opt) |v| v else blk: {
                    i += 1;
                    if (i >= args.len) {
                        try stderr.print("paste: option '{s}' requires an argument\nTry 'paste --help' for more information.\n", .{opt_name});
                        return 1;
                    }
                    break :blk args[i];
                };
                delim_arg = if (val.len == 0) "\\0" else val;
            } else {
                try stderr.print("paste: unrecognized option '{s}'\nTry 'paste --help' for more information.\n", .{arg});
                return 1;
            }
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            var j: usize = 1;
            while (j < arg.len) : (j += 1) {
                const opt_ch = arg[j];
                switch (opt_ch) {
                    's' => {
                        serial_merge = true;
                    },
                    'z' => {
                        line_delim = 0;
                    },
                    'd' => {
                        const val = if (j + 1 < arg.len) arg[j + 1 ..] else blk: {
                            i += 1;
                            if (i >= args.len) {
                                try stderr.print("paste: option requires an argument -- 'd'\nTry 'paste --help' for more information.\n", .{});
                                return 1;
                            }
                            break :blk args[i];
                        };
                        delim_arg = if (val.len == 0) "\\0" else val;
                        break;
                    },
                    else => {
                        try stderr.print("paste: invalid option -- '{c}'\nTry 'paste --help' for more information.\n", .{opt_ch});
                        return 1;
                    },
                }
            }
        } else {
            try files.append(allocator, arg);
        }
    }

    if (files.items.len == 0) {
        try files.append(allocator, "-");
    }

    const delims = parseDelimiters(delim_arg, allocator, stderr) catch {
        return 1;
    };
    defer allocator.free(delims);

    if (serial_merge) {
        return pasteSerial(files.items, delims, line_delim, stdout, stderr, allocator);
    } else {
        return pasteParallel(files.items, delims, line_delim, stdout, stderr, allocator);
    }
}
