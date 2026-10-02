const std = @import("std");
const errors = @import("../utils/errors.zig");
const args_mod = @import("split/args.zig");
const args_validate = @import("split/args_validate.zig");
const file_namer = @import("split/file_namer.zig");
const chunk_writer = @import("split/chunk_writer.zig");
const strategy = @import("split/strategy.zig");
const strategy_numbered = @import("split/strategy_numbered.zig");
const temp_spill = @import("split/temp_spill.zig");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "split";
pub const version: []const u8 = "0.1.0";

fn printHelp(writer: anytype) !void {
    try writer.print(
        \\Usage: {s} [OPTION]... [FILE [PREFIX]]
        \\Output pieces of FILE to PREFIXaa, PREFIXab, ...;
        \\default size is 1000 lines, and default PREFIX is 'x'.
        \\
        \\With no FILE, or when FILE is -, read standard input.
        \\
        \\Mandatory arguments to long options are mandatory for short options too.
        \\  -a, --suffix-length=N   generate suffixes of length N (default 2)
        \\      --additional-suffix=SUFFIX  append an additional SUFFIX to file names
        \\  -b, --bytes=SIZE        put SIZE bytes per output file
        \\  -C, --line-bytes=SIZE   put at most SIZE bytes of records per output file
        \\  -d                      use numeric suffixes starting at 0, not alphabetic
        \\      --numeric-suffixes[=FROM]  same as -d, but allow setting the start value
        \\  -x                      use hex suffixes starting at 0, not alphabetic
        \\      --hex-suffixes[=FROM]  same as -x, but allow setting the start value
        \\  -e, --elide-empty-files  do not generate empty output files with '-n'
        \\      --filter=COMMAND    write to shell COMMAND; file name is $FILE
        \\  -l, --lines=NUMBER      put NUMBER lines/records per output file
        \\  -n, --number=CHUNKS     generate CHUNKS output files; see explanation below
        \\  -t, --separator=SEP     use SEP instead of newline as the record separator;
        \\                            '\\0' (zero) specifies the NUL character
        \\  -u, --unbuffered        immediately copy input to output with '-n r/...'
        \\      --verbose           print a diagnostic just before each
        \\                            output file is opened
        \\      --help              display this help and exit
        \\      --version           output version information and exit
        \\
        \\GNU coreutils online help: <https://www.gnu.org/software/coreutils/>
        \\Full documentation <https://www.gnu.org/software/coreutils/split>
        \\or available locally via: info '(coreutils) split invocation'
        \\
    , .{name});
}

fn isSeekable(file: std.Io.File) bool {
    const cur = c.lseek(file.handle, 0, c.SEEK_CUR);
    if (cur < 0) return false;
    var st: c.struct_stat = undefined;
    if (c.fstat(file.handle, &st) == 0) {
        if ((st.st_mode & c.S_IFMT) == c.S_IFIFO or (st.st_mode & c.S_IFMT) == c.S_IFSOCK) {
            return false;
        }
    }
    return true;
}

fn executeNumbered(
    allocator: std.mem.Allocator,
    file: std.Io.File,
    is_stdin: bool,
    opts: *const args_mod.Options,
    spec: args_mod.NumberSpec,
    namer: *file_namer.FileNamer,
    writer: *chunk_writer.ChunkWriter,
    stdout: anytype,
    stderr: anytype,
) !void {
    if (spec.mode == .round_robin or spec.mode == .round_robin_stdout) {
        try strategy_numbered.splitRoundRobin(allocator, file, spec, opts.separator, opts.filter_cmd, opts.verbose, opts.elide_empty, namer, stdout, stderr);
        return;
    }
    var in_st: ?c.struct_stat = null;
    var st: c.struct_stat = undefined;
    if (c.fstat(file.handle, &st) == 0) in_st = st;
    const is_proc_or_sys = if (in_st) |s| (s.st_size == 0 or (s.st_size <= 4096 and s.st_blocks == 0)) else false;

    var active_file = file;
    var spilled_opt: ?std.Io.File = null;
    defer if (spilled_opt) |f| f.close(std.Options.debug_io);

    if (is_stdin or !isSeekable(file) or is_proc_or_sys) {
        const spilled = try temp_spill.spillStreamToTemp(file);
        spilled_opt = spilled;
        active_file = spilled;
    }
    const size = c.lseek(active_file.handle, 0, c.SEEK_END);
    _ = c.lseek(active_file.handle, 0, c.SEEK_SET);
    const u_size: usize = if (size > 0) @intCast(size) else 0;

    if (spec.mode == .bytes or spec.mode == .bytes_stdout) {
        try strategy_numbered.splitNumberedBytes(active_file, u_size, spec, opts.elide_empty, writer, namer, stdout, stderr);
    } else {
        try strategy_numbered.splitNumberedLines(active_file, u_size, spec, opts.separator, opts.elide_empty, writer, namer, stdout, stderr);
    }
}

fn executeSplit(
    allocator: std.mem.Allocator,
    file: std.Io.File,
    is_stdin: bool,
    opts: *const args_mod.Options,
    namer: *file_namer.FileNamer,
    writer: *chunk_writer.ChunkWriter,
    stdout: anytype,
    stderr: anytype,
) !void {
    switch (opts.mode) {
        .lines => |n| try strategy.splitLines(file, n, opts.separator, writer, namer, stdout, stderr),
        .bytes => |b| try strategy.splitBytes(file, b, writer, namer, stdout, stderr),
        .line_bytes => |c_sz| try strategy.splitLineBytes(allocator, file, c_sz, opts.separator, writer, namer, stdout, stderr),
        .number => |spec| try executeNumbered(allocator, file, is_stdin, opts, spec, namer, writer, stdout, stderr),
    }
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buf: [65536]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_w: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var stderr_w: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &stdout_w.interface;
    const stderr = &stderr_w.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    const res = args_mod.parseArgs(args, stderr);
    var opts = switch (res) {
        .ok => |o| o,
        .help => {
            try printHelp(stdout);
            return 0;
        },
        .version => {
            try errors.printVersion(stdout, name, version);
            return 0;
        },
        .err => |code| return code,
    };
    args_validate.validateOptions(&opts, stderr) catch return 1;

    if (opts.filter_cmd != null) {
        _ = c.signal(c.SIGPIPE, c.SIG_IGN);
    } else {
        _ = c.signal(c.SIGPIPE, c.SIG_DFL);
    }

    const is_stdin = (opts.input_file == null or std.mem.eql(u8, opts.input_file.?, "-"));
    const file = if (is_stdin)
        std.Io.File.stdin()
    else
        std.Io.Dir.cwd().openFile(std.Options.debug_io, opts.input_file.?, .{ .mode = .read_only }) catch |err| {
            errors.printErrorWithArg(stderr, name, opts.input_file.?, err) catch {};
            return 1;
        };
    defer if (!is_stdin) file.close(std.Options.debug_io);

    var namer = file_namer.FileNamer.init(allocator, &opts) catch return 1;
    defer namer.deinit();

    var in_st: ?c.struct_stat = null;
    var st: c.struct_stat = undefined;
    if (c.fstat(file.handle, &st) == 0) in_st = st;

    var writer = chunk_writer.ChunkWriter.init(allocator, opts.filter_cmd, opts.verbose, in_st);
    defer writer.deinit();

    executeSplit(allocator, file, is_stdin, &opts, &namer, &writer, stdout, stderr) catch |err| {
        switch (err) {
            error.SuffixesExhausted => {
                errors.printError(stderr, name, "output file suffixes exhausted") catch {};
                return 1;
            },
            else => return 1,
        }
    };
    return 0;
}
