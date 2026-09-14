const std = @import("std");
pub const types = @import("sort/types.zig");
pub const comparator = @import("sort/comparator.zig");
pub const args_mod = @import("sort/args.zig");
pub const files0 = @import("sort/files0.zig");
pub const key_parser = @import("sort/key_parser.zig");
pub const compress = @import("sort/compress.zig");

const c = @cImport({
    @cInclude("locale.h");
});

pub const name: []const u8 = "sort";
pub const version: []const u8 = "0.1.0";

const Context = struct {
    opt: *const types.Options,

    pub fn lessThan(self: Context, a: []const u8, b: []const u8) bool {
        return comparator.compareLines(a, b, self.opt) == .lt;
    }
};

fn readFileRaw(allocator: std.mem.Allocator, path: ?[]const u8) ![]u8 {
    const is_stdin = (path == null) or std.mem.eql(u8, path.?, "-");
    const file = if (is_stdin)
        std.Io.File.stdin()
    else
        try std.Io.Dir.cwd().openFile(std.Options.debug_io, path.?, .{ .mode = .read_only });
    defer if (!is_stdin) file.close(std.Options.debug_io);

    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);

    var r_buf: [16384]u8 = undefined;
    var r = file.readerStreaming(std.Options.debug_io, &r_buf);
    const reader = &r.interface;

    var in_buf: [16384]u8 = undefined;
    while (true) {
        const n = try reader.readSliceShort(&in_buf);
        if (n == 0) break;
        try list.appendSlice(allocator, in_buf[0..n]);
    }
    return list.toOwnedSlice(allocator);
}

const LinesBuffer = struct {
    buffers: std.ArrayList([]u8),
    lines: std.ArrayList([]const u8),
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) LinesBuffer {
        return .{
            .buffers = .empty,
            .lines = .empty,
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *LinesBuffer) void {
        for (self.buffers.items) |buf| {
            self.allocator.free(buf);
        }
        self.buffers.deinit(self.allocator);
        self.lines.deinit(self.allocator);
    }

    pub fn ingestFile(self: *LinesBuffer, path: ?[]const u8, delim: u8) !void {
        const raw = try readFileRaw(self.allocator, path);
        try self.buffers.append(self.allocator, raw);
        if (raw.len == 0) return;
        const input = if (std.mem.endsWith(u8, raw, &[_]u8{delim}))
            raw[0 .. raw.len - 1]
        else
            raw;
        var it = std.mem.splitScalar(u8, input, delim);
        while (it.next()) |line| {
            try self.lines.append(self.allocator, line);
        }
    }
};

fn executeCheck(lines: []const []const u8, opt: *const types.Options, stderr: anytype) !u8 {
    if (lines.len <= 1) return 0;
    var i: usize = 1;
    while (i < lines.len) : (i += 1) {
        const ord = comparator.compareLines(lines[i - 1], lines[i], opt);
        const disorder = if (opt.unique) (ord != .lt) else (ord == .gt);
        if (disorder) {
            if (!opt.check_silent) {
                const fn_name = if (opt.files.len > 0) opt.files[0] else "-";
                try stderr.print("sort: {s}:{d}: disorder: {s}\n", .{ fn_name, i + 1, lines[i] });
            }
            return 1;
        }
    }
    return 0;
}

fn emitLines(lines: []const []const u8, opt: *const types.Options, writer: anytype) !void {
    const term = if (opt.zero_terminated) @as(u8, 0) else @as(u8, '\n');
    var prev_line: ?[]const u8 = null;

    for (lines) |line| {
        if (opt.unique and prev_line != null) {
            if (comparator.compareLines(prev_line.?, line, opt) == .eq) continue;
        }
        try writer.print("{s}{c}", .{ line, term });
        prev_line = line;
    }
}

fn emitOutput(lines: []const []const u8, opt: *const types.Options, stdout: anytype, stderr: anytype) !u8 {
    if (opt.output_file) |out_path| {
        const out_file = std.Io.Dir.cwd().createFile(std.Options.debug_io, out_path, .{}) catch |err| {
            try stderr.print("sort: {s}: {s}\n", .{ out_path, @errorName(err) });
            return 2;
        };
        defer out_file.close(std.Options.debug_io);
        var out_buf: [16384]u8 = undefined;
        var out_w: std.Io.File.Writer = .initStreaming(out_file, std.Options.debug_io, &out_buf);
        const w = &out_w.interface;
        try emitLines(lines, opt, w);
        try w.flush();
    } else {
        try emitLines(lines, opt, stdout);
    }
    return 0;
}

fn loadInputs(lines_buf: *LinesBuffer, opt: *const types.Options) !void {
    const delim = if (opt.zero_terminated) @as(u8, 0) else @as(u8, '\n');
    if (opt.files.len == 0) {
        try lines_buf.ingestFile(null, delim);
    } else {
        for (opt.files) |path| {
            try lines_buf.ingestFile(path, delim);
        }
    }
}

fn initRandomSeed(opt: *types.Options) void {
    if (opt.random_source) |src| {
        if (std.Io.Dir.cwd().openFile(std.Options.debug_io, src, .{ .mode = .read_only })) |file| {
            defer file.close(std.Options.debug_io);
            var buf: [8]u8 = undefined;
            var r = file.readerStreaming(std.Options.debug_io, &buf);
            if (r.interface.readSliceShort(&buf)) |n| {
                if (n == 8) {
                    opt.random_seed = std.mem.readInt(u64, &buf, .little);
                    return;
                }
            } else |_| {}
        } else |_| {}
    }
    var io_source: std.Random.IoSource = .{ .io = std.Options.debug_io };
    opt.random_seed = io_source.interface().int(u64);
}

fn makeGlobalKey(opt: *const types.Options) types.KeySpec {
    return types.KeySpec{
        .numeric = opt.numeric,
        .general_numeric = opt.general_numeric,
        .human_numeric = opt.human_numeric,
        .month = opt.month,
        .version = opt.version,
        .random = opt.random,
        .reverse = opt.reverse,
        .skipsblanks = opt.ignore_blanks,
        .skipeblanks = opt.ignore_blanks,
        .ignore_case = opt.ignore_case,
        .dictionary_order = opt.dictionary_order,
        .ignore_nonprinting = opt.ignore_nonprinting,
    };
}

fn validateOptions(opt: *const types.Options, keys: []const types.KeySpec, stderr: anytype) !bool {
    const gkey = makeGlobalKey(opt);
    if (!try args_mod.checkOrderingCompatibility(&gkey, stderr)) return false;
    for (keys) |*k| {
        if (!try args_mod.checkOrderingCompatibility(k, stderr)) return false;
    }
    if (opt.check or opt.check_silent) {
        if (opt.files.len > 1) {
            const ch: u8 = if (opt.check) 'c' else 'C';
            try stderr.print("sort: extra operand '{s}' not allowed with -{c}\n", .{ opt.files[1], ch });
            return false;
        }
        if (opt.output_file != null) {
            const ch: u8 = if (opt.check) 'c' else 'C';
            try stderr.print("sort: options '-{c}o' are incompatible\n", .{ch});
            return false;
        }
    }
    return true;
}

fn applyInheritance(opt: *const types.Options, keys: *std.ArrayList(types.KeySpec), alloc: std.mem.Allocator) !void {
    const gkey = makeGlobalKey(opt);
    if (keys.items.len == 0) {
        if (!types.defaultKeyCompare(&gkey)) {
            try keys.append(alloc, gkey);
        }
        return;
    }
    for (keys.items) |*key| {
        if (types.defaultKeyCompare(key) and !key.reverse) {
            key.numeric = gkey.numeric;
            key.general_numeric = gkey.general_numeric;
            key.human_numeric = gkey.human_numeric;
            key.month = gkey.month;
            key.version = gkey.version;
            key.random = gkey.random;
            key.reverse = gkey.reverse;
            key.skipsblanks = gkey.skipsblanks;
            key.skipeblanks = gkey.skipeblanks;
            key.ignore_case = gkey.ignore_case;
            key.dictionary_order = gkey.dictionary_order;
            key.ignore_nonprinting = gkey.ignore_nonprinting;
        }
    }
}

fn checkTempDir(opt: *const types.Options, stderr: anytype) !bool {
    if (opt.temp_dir) |td| {
        if (opt.merge and opt.batch_size != null and opt.files.len > opt.batch_size.?) {
            const dir = std.Io.Dir.cwd().openDir(std.Options.debug_io, td, .{}) catch {
                try stderr.print("sort: cannot create temporary file in '{s}': No such file or directory\n", .{td});
                return false;
            };
            dir.close(std.Options.debug_io);
        }
    }
    return true;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    _ = c.setlocale(c.LC_ALL, "");

    var stdout_buffer: [16384]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var opt = types.Options{};
    var keys: std.ArrayList(types.KeySpec) = .empty;
    defer keys.deinit(allocator);
    var files: std.ArrayList([]const u8) = .empty;
    defer files.deinit(allocator);

    if (try args_mod.parseArgs(args, &opt, &keys, &files, allocator, stdout, stderr)) |code| return code;
    if (opt.files0_from) |f0| {
        if (files.items.len > 0) {
            try stderr.print("sort: extra operand '{s}'\nfile operands cannot be combined with --files0-from\nTry 'sort --help' for more information.\n", .{files.items[0]});
            return 2;
        }
        if (!try files0.readFiles0From(f0, &files, allocator, stderr)) return 2;
    }
    opt.files = files.items;
    if (!try validateOptions(&opt, keys.items, stderr)) return 2;
    if (!try files0.checkInputs(opt.files, stderr)) return 2;
    if (!try files0.checkOutput(opt.output_file, stderr)) return 2;
    if (!try checkTempDir(&opt, stderr)) return 2;
    if (opt.compress_program) |cp| {
        try compress.handleCompressProgram(cp, allocator, stderr);
    }

    try applyInheritance(&opt, &keys, allocator);
    opt.keys = keys.items;
    initRandomSeed(&opt);

    var lines_buf = LinesBuffer.init(allocator);
    defer lines_buf.deinit();
    loadInputs(&lines_buf, &opt) catch |err| {
        try stderr.print("sort: cannot read input: {s}\n", .{@errorName(err)});
        return 2;
    };
    if (opt.check or opt.check_silent) return try executeCheck(lines_buf.lines.items, &opt, stderr);

    std.sort.pdq([]const u8, lines_buf.lines.items, Context{ .opt = &opt }, Context.lessThan);
    const rc = try emitOutput(lines_buf.lines.items, &opt, stdout, stderr);
    stdout.flush() catch return 2;
    return rc;
}
