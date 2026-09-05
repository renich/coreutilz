const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "wc";
pub const version: []const u8 = "0.1.0";

const TotalMode = enum {
    auto,
    always,
    only,
    never,
};

const Counts = struct {
    lines: usize = 0,
    words: usize = 0,
    chars: usize = 0,
    bytes: usize = 0,
    max_line_length: usize = 0,

    fn add(self: *Counts, other: Counts) void {
        self.lines += other.lines;
        self.words += other.words;
        self.chars += other.chars;
        self.bytes += other.bytes;
        self.max_line_length = @max(self.max_line_length, other.max_line_length);
    }
};

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buffer: [16384]u8 = undefined;
    var stderr_buffer: [4096]u8 = undefined;
    var stdout_writer: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buffer);
    var stderr_writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buffer);
    const stdout = &stdout_writer.interface;
    const stderr = &stderr_writer.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    var print_lines = false;
    var print_words = false;
    var print_chars = false;
    var print_bytes = false;
    var print_linelength = false;

    var total_mode: TotalMode = .auto;
    var files0_from: ?[]const u8 = null;

    var file_start: usize = args.len;
    var i: usize = 1;

    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "-")) {
            file_start = i;
            break;
        }
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
                try printHelp(stdout);
                return 0;
            } else if (std.mem.eql(u8, arg, "--version")) {
                try printVersion(stdout);
                return 0;
            } else if (std.mem.eql(u8, arg, "--lines")) {
                print_lines = true;
            } else if (std.mem.eql(u8, arg, "--words")) {
                print_words = true;
            } else if (std.mem.eql(u8, arg, "--chars")) {
                print_chars = true;
            } else if (std.mem.eql(u8, arg, "--bytes")) {
                print_bytes = true;
            } else if (std.mem.eql(u8, arg, "--max-line-length")) {
                print_linelength = true;
            } else if (std.mem.startsWith(u8, arg, "--total=")) {
                const mode_str = arg["--total=".len..];
                if (std.mem.eql(u8, mode_str, "auto")) {
                    total_mode = .auto;
                } else if (std.mem.eql(u8, mode_str, "always")) {
                    total_mode = .always;
                } else if (std.mem.eql(u8, mode_str, "only")) {
                    total_mode = .only;
                } else if (std.mem.eql(u8, mode_str, "never")) {
                    total_mode = .never;
                } else {
                    try stderr.print("wc: invalid argument '{s}' for '--total'\n", .{mode_str});
                    try stderr.print("Valid arguments are:\n  - 'auto'\n  - 'always'\n  - 'only'\n  - 'never'\n", .{});
                    return 1;
                }
            } else if (std.mem.startsWith(u8, arg, "--files0-from=")) {
                files0_from = arg["--files0-from=".len..];
            } else {
                try stderr.print("wc: unrecognized option '{s}'\n", .{arg});
                return 1;
            }
        } else {
            // Short options
            var j: usize = 1;
            while (j < arg.len) : (j += 1) {
                const c = arg[j];
                switch (c) {
                    'l' => print_lines = true,
                    'w' => print_words = true,
                    'c' => print_bytes = true,
                    'm' => print_chars = true,
                    'L' => print_linelength = true,
                    else => {
                        try stderr.print("wc: invalid option -- '{c}'\n", .{c});
                        return 1;
                    },
                }
            }
        }
    }

    if (!print_lines and !print_words and !print_chars and !print_bytes and !print_linelength) {
        print_lines = true;
        print_words = true;
        print_bytes = true;
    }

    const count_selected = (@as(usize, if (print_lines) 1 else 0) +
        @as(usize, if (print_words) 1 else 0) +
        @as(usize, if (print_chars) 1 else 0) +
        @as(usize, if (print_bytes) 1 else 0) +
        @as(usize, if (print_linelength) 1 else 0));

    var file_list: std.ArrayList([]const u8) = .empty;
    defer file_list.deinit(allocator);

    if (files0_from) |f0_path| {
        if (file_start < args.len) {
            try stderr.print("wc: extra operand '{s}'\nfile operands cannot be combined with --files0-from\n", .{args[file_start]});
            return 1;
        }

        var f0_file: std.Io.File = undefined;
        const f0_is_stdin = std.mem.eql(u8, f0_path, "-");
        if (f0_is_stdin) {
            f0_file = std.Io.File.stdin();
        } else {
            f0_file = std.Io.Dir.cwd().openFile(std.Options.debug_io, f0_path, .{ .mode = .read_only }) catch |err| {
                try stderr.print("wc: cannot open '{s}' for reading: {s}\n", .{ f0_path, @errorName(err) });
                return 1;
            };
        }
        defer if (!f0_is_stdin) f0_file.close(std.Options.debug_io);

        var r_buf: [16384]u8 = undefined;
        var r = f0_file.readerStreaming(std.Options.debug_io, &r_buf);
        const reader = &r.interface;
        var cur_name: std.ArrayList(u8) = .empty;
        defer cur_name.deinit(allocator);

        var buf: [16384]u8 = undefined;
        while (true) {
            const n = try reader.readSliceShort(&buf);
            if (n == 0) break;
            for (buf[0..n]) |b| {
                if (b == 0) {
                    if (cur_name.items.len > 0) {
                        try file_list.append(allocator, try allocator.dupe(u8, cur_name.items));
                        cur_name.clearRetainingCapacity();
                    }
                } else {
                    try cur_name.append(allocator, b);
                }
            }
        }
        if (cur_name.items.len > 0) {
            try file_list.append(allocator, try allocator.dupe(u8, cur_name.items));
        }
    } else {
        if (file_start < args.len) {
            for (args[file_start..]) |f| {
                try file_list.append(allocator, f);
            }
        } else {
            try file_list.append(allocator, "-");
        }
    }

    const nfiles = file_list.items.len;
    const is_single_stdin = (nfiles == 1 and std.mem.eql(u8, file_list.items[0], "-") and (file_start >= args.len or std.mem.eql(u8, args[file_start], "-")));

    var number_width: usize = 1;
    if (total_mode == .only) {
        number_width = 1;
    } else if (nfiles == 0 or (nfiles == 1 and count_selected == 1 and is_single_stdin)) {
        number_width = 1;
    } else {
        var min_width: usize = 1;
        var regular_total: u64 = 0;
        for (file_list.items) |f| {
            if (std.mem.eql(u8, f, "-")) {
                min_width = 7;
            } else if (std.Io.Dir.cwd().openFile(std.Options.debug_io, f, .{ .mode = .read_only })) |file| {
                defer file.close(std.Options.debug_io);
                if (file.stat(std.Options.debug_io)) |st| {
                    if (st.kind == .file) {
                        regular_total +|= st.size;
                    } else {
                        min_width = 7;
                    }
                } else |_| {
                    min_width = 7;
                }
            } else |_| {}
        }

        var w: usize = 1;
        var temp_total = regular_total;
        while (temp_total >= 10) : (temp_total /= 10) {
            w += 1;
        }
        number_width = @max(w, min_width);
    }

    var total_counts = Counts{};
    var exit_status: u8 = 0;

    for (file_list.items) |filename| {
        const is_stdin = std.mem.eql(u8, filename, "-");
        var file: std.Io.File = undefined;
        if (is_stdin) {
            file = std.Io.File.stdin();
        } else {
            file = std.Io.Dir.cwd().openFile(std.Options.debug_io, filename, .{ .mode = .read_only }) catch |err| {
                const err_desc = switch (err) {
                    error.FileNotFound => "No such file or directory",
                    error.AccessDenied => "Permission denied",
                    error.IsDir => "Is a directory",
                    else => "Cannot open file",
                };
                try stderr.print("wc: {s}: {s}\n", .{ filename, err_desc });
                exit_status = 1;
                continue;
            };
        }
        defer if (!is_stdin) file.close(std.Options.debug_io);

        const counts = countFile(file, print_words, print_chars, print_linelength) catch |err| {
            try stderr.print("wc: {s}: {s}\n", .{ filename, @errorName(err) });
            exit_status = 1;
            continue;
        };

        total_counts.add(counts);

        if (total_mode != .only) {
            const display_name = if (is_single_stdin and file_start >= args.len) null else filename;
            try writeCounts(stdout, counts, print_lines, print_words, print_chars, print_bytes, print_linelength, number_width, display_name);
        }
    }

    const print_total_line = switch (total_mode) {
        .auto => nfiles > 1,
        .always => true,
        .only => true,
        .never => false,
    };

    if (print_total_line) {
        try writeCounts(stdout, total_counts, print_lines, print_words, print_chars, print_bytes, print_linelength, number_width, "total");
    }

    return exit_status;
}

fn countFile(file: std.Io.File, do_words: bool, do_chars: bool, do_linelength: bool) !Counts {
    var counts = Counts{};
    var r_buf: [16384]u8 = undefined;
    var r = file.readerStreaming(std.Options.debug_io, &r_buf);
    const reader = &r.interface;

    var buf: [16384]u8 = undefined;
    var in_word = false;
    var linepos: usize = 0;

    while (true) {
        const n = try reader.readSliceShort(&buf);
        if (n == 0) break;
        counts.bytes += n;

        const slice = buf[0..n];
        for (slice) |b| {
            if (b == '\n') {
                counts.lines += 1;
                if (do_linelength) {
                    if (linepos > counts.max_line_length) counts.max_line_length = linepos;
                    linepos = 0;
                }
                in_word = false;
            } else if (b == '\r' or b == 0x0c) {
                if (do_linelength) {
                    if (linepos > counts.max_line_length) counts.max_line_length = linepos;
                    linepos = 0;
                }
                in_word = false;
            } else if (b == ' ' or b == '\t' or b == 0x0b) {
                if (do_linelength) {
                    if (b == '\t') {
                        linepos += 8 - (linepos % 8);
                    } else if (b == ' ') {
                        linepos += 1;
                    }
                }
                in_word = false;
            } else {
                if (do_linelength) {
                    if ((b & 0xc0) != 0x80) {
                        linepos += 1;
                    }
                }
                if (do_words) {
                    if (!in_word) {
                        counts.words += 1;
                        in_word = true;
                    }
                }
            }

            if (do_chars) {
                if ((b & 0xc0) != 0x80) {
                    counts.chars += 1;
                }
            }
        }
    }

    if (do_linelength and linepos > counts.max_line_length) {
        counts.max_line_length = linepos;
    }

    return counts;
}

fn writeCounts(
    writer: anytype,
    counts: Counts,
    p_lines: bool,
    p_words: bool,
    p_chars: bool,
    p_bytes: bool,
    p_linelength: bool,
    width: usize,
    file: ?[]const u8,
) !void {
    var first = true;

    if (p_lines) {
        try printItem(writer, counts.lines, width, first);
        first = false;
    }
    if (p_words) {
        try printItem(writer, counts.words, width, first);
        first = false;
    }
    if (p_chars) {
        try printItem(writer, counts.chars, width, first);
        first = false;
    }
    if (p_bytes) {
        try printItem(writer, counts.bytes, width, first);
        first = false;
    }
    if (p_linelength) {
        try printItem(writer, counts.max_line_length, width, first);
        first = false;
    }

    if (file) |filename| {
        try writer.print(" {s}\n", .{filename});
    } else {
        try writer.writeByte('\n');
    }
}

fn printItem(writer: anytype, val: usize, width: usize, first: bool) !void {
    var buf: [32]u8 = undefined;
    const num_str = std.fmt.bufPrint(&buf, "{d}", .{val}) catch unreachable;

    if (!first) {
        try writer.writeByte(' ');
    }

    if (num_str.len < width) {
        const padding = width - num_str.len;
        var k: usize = 0;
        while (k < padding) : (k += 1) {
            try writer.writeByte(' ');
        }
    }
    try writer.writeAll(num_str);
}

fn printHelp(writer: anytype) !void {
    try writer.print(
        \\Usage: {s} [OPTION]... [FILE]...
        \\  or:  {s} [OPTION]... --files0-from=F
        \\Print newline, word, and byte counts for each FILE, and a total line if
        \\more than one FILE is specified.  A word is a non-zero-length sequence of
        \\printable characters delimited by white space.
        \\
        \\With no FILE, or when FILE is -, read standard input.
        \\
        \\The options below may be used to select which counts are printed, always in
        \\the following order: newline, word, character, byte, maximum line length.
        \\  -c, --bytes            print the byte counts
        \\  -m, --chars            print the character counts
        \\  -l, --lines            print the newline counts
        \\      --files0-from=F    read input from the files specified by
        \\                           NUL-terminated names in file F;
        \\                           If F is - then read names from standard input
        \\  -L, --max-line-length  print the maximum display width
        \\  -w, --words            print the word counts
        \\      --total=WHEN       when to print a line with total counts;
        \\                           WHEN can be: auto, always, only, never
        \\      --help        display this help and exit
        \\      --version     output version information and exit
        \\
    , .{ name, name });
}

fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}
