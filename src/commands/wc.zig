const std = @import("std");
const errors = @import("../utils/errors.zig");

const c = @import("../compat/c.zig").c;

extern "c" fn btowc(c_int) c.wint_t;

pub const name: []const u8 = "wc";
pub const version: []const u8 = "0.1.0";

const TotalMode = enum {
    auto,
    always,
    only,
    never,
};

const Counts = struct {
    lines: u64 = 0,
    words: u64 = 0,
    chars: u64 = 0,
    bytes: u64 = 0,
    max_line_length: usize = 0,
};

const LocaleContext = struct {
    is_space_table: [256]bool = undefined,
    char_width_table: [256]i8 = undefined,
    is_multibyte: bool = false,
    posixly_correct: bool = false,

    fn init() LocaleContext {
        _ = c.setlocale(c.LC_ALL, "");
        const posixly = errors.isPosixlyCorrect();
        const multibyte = c.__ctype_get_mb_cur_max() > 1;

        var ctx = LocaleContext{
            .is_multibyte = multibyte,
            .posixly_correct = posixly,
        };

        for (0..256) |byte_val| {
            const b: u8 = @intCast(byte_val);
            const w = btowc(b);
            const is_sp = (c.isspace(b) != 0) or (!posixly and (w == 0x00A0 or w == 0x2007 or w == 0x202F or w == 0x2060));
            ctx.is_space_table[b] = is_sp;
            if (w != c.WEOF) {
                const width = c.wcwidth(@intCast(w));
                ctx.char_width_table[b] = if (width >= 0) @intCast(width) else 0;
            } else {
                ctx.char_width_table[b] = if (c.isprint(b) != 0) 1 else 0;
            }
        }
        return ctx;
    }
};

fn errnoString(err_num: c_int) []const u8 {
    const s = c.strerror(err_num);
    return if (s != null) std.mem.span(s) else "Unknown error";
}

fn quoteFileName(allocator: std.mem.Allocator, file: []const u8) ![]const u8 {
    if (std.mem.indexOfScalar(u8, file, '\n') == null) {
        return file;
    }

    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);

    var in_single_quotes = true;
    try list.append(allocator, '\'');

    for (file) |ch| {
        if (ch == '\n') {
            if (in_single_quotes) {
                try list.append(allocator, '\'');
                in_single_quotes = false;
            }
            try list.appendSlice(allocator, "$'\\n'");
        } else if (ch == '\'') {
            if (in_single_quotes) {
                try list.append(allocator, '\'');
                in_single_quotes = false;
            }
            try list.appendSlice(allocator, "\\'");
        } else {
            if (!in_single_quotes) {
                try list.append(allocator, '\'');
                in_single_quotes = true;
            }
            try list.append(allocator, ch);
        }
    }

    if (in_single_quotes) {
        try list.append(allocator, '\'');
    }

    return list.toOwnedSlice(allocator);
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    const locale = LocaleContext.init();

    var stdout_buffer: [4096]u8 = undefined;
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
                printHelp(stdout) catch return 1;
                stdout.flush() catch return 1;
                return 0;
            } else if (std.mem.eql(u8, arg, "--version")) {
                printVersion(stdout) catch return 1;
                stdout.flush() catch return 1;
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
            } else if (std.mem.eql(u8, arg, "--debug")) {
                // GNU wc --debug accepts flag for CPU capabilities inspection
            } else if (std.mem.eql(u8, arg, "--total")) {
                try stderr.print("wc: option '--total' requires an argument\nTry 'wc --help' for more information.\n", .{});
                return 1;
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
                    try stderr.print("Valid arguments are:\n  - 'auto'\n  - 'always'\n  - 'only'\n  - 'never'\nTry 'wc --help' for more information.\n", .{});
                    return 1;
                }
            } else if (std.mem.eql(u8, arg, "--files0-from")) {
                i += 1;
                if (i >= args.len) {
                    try stderr.print("wc: option '--files0-from' requires an argument\nTry 'wc --help' for more information.\n", .{});
                    return 1;
                }
                files0_from = args[i];
            } else if (std.mem.startsWith(u8, arg, "--files0-from=")) {
                files0_from = arg["--files0-from=".len..];
            } else {
                try stderr.print("wc: unrecognized option '{s}'\nTry 'wc --help' for more information.\n", .{arg});
                return 1;
            }
        } else {
            // Short options
            var j: usize = 1;
            while (j < arg.len) : (j += 1) {
                const opt = arg[j];
                switch (opt) {
                    'l' => print_lines = true,
                    'w' => print_words = true,
                    'c' => print_bytes = true,
                    'm' => print_chars = true,
                    'L' => print_linelength = true,
                    else => {
                        try stderr.print("wc: invalid option -- '{c}'\nTry 'wc --help' for more information.\n", .{opt});
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

    var exit_status: u8 = 0;
    var total_items_seen: usize = 0;
    var is_stream = false;

    if (files0_from) |f0_path| {
        if (file_start < args.len) {
            try stderr.print("wc: extra operand '{s}'\nfile operands cannot be combined with --files0-from\nTry 'wc --help' for more information.\n", .{args[file_start]});
            return 1;
        }

        var f0_fd: c_int = 0;
        const f0_is_stdin = std.mem.eql(u8, f0_path, "-");
        if (f0_is_stdin) {
            f0_fd = 0;
        } else {
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            if (f0_path.len >= path_buf.len) {
                try stderr.print("wc: file name too long\n", .{});
                return 1;
            }
            @memcpy(path_buf[0..f0_path.len], f0_path);
            path_buf[f0_path.len] = 0;
            f0_fd = c.open(&path_buf, c.O_RDONLY);
            if (f0_fd < 0) {
                const err_str = errnoString(c.__errno_location().*);
                try stderr.print("wc: cannot open '{s}' for reading: {s}\n", .{ f0_path, err_str });
                return 1;
            }
        }
        defer {
            if (!f0_is_stdin) _ = c.close(f0_fd);
        }

        var st0: c.struct_stat = undefined;
        if (c.fstat(f0_fd, &st0) != 0 or (st0.st_mode & c.S_IFMT) != c.S_IFREG) {
            is_stream = true;
        }

        var cur_name: std.ArrayList(u8) = .empty;
        defer cur_name.deinit(allocator);

        var buf: [16384]u8 = undefined;
        while (true) {
            const nr = c.read(f0_fd, &buf, buf.len);
            if (nr <= 0) break;
            const n: usize = @intCast(nr);
            for (buf[0..n]) |b| {
                if (b == 0) {
                    total_items_seen += 1;
                    if (cur_name.items.len == 0) {
                        try stderr.print("wc: {s}:{d}: invalid zero-length file name\n", .{ f0_path, total_items_seen });
                        exit_status = 1;
                    } else if (f0_is_stdin and std.mem.eql(u8, cur_name.items, "-")) {
                        try stderr.print("wc: when reading file names from standard input, no file name of '-' allowed\n", .{});
                        exit_status = 1;
                        cur_name.clearRetainingCapacity();
                    } else {
                        try file_list.append(allocator, try allocator.dupe(u8, cur_name.items));
                        cur_name.clearRetainingCapacity();
                    }
                } else {
                    try cur_name.append(allocator, b);
                }
            }
        }

        if (cur_name.items.len > 0) {
            total_items_seen += 1;
            if (f0_is_stdin and std.mem.eql(u8, cur_name.items, "-")) {
                try stderr.print("wc: when reading file names from standard input, no file name of '-' allowed\n", .{});
                exit_status = 1;
            } else {
                try file_list.append(allocator, try allocator.dupe(u8, cur_name.items));
            }
        }
    } else {
        if (file_start < args.len) {
            for (args[file_start..]) |f| {
                try file_list.append(allocator, f);
            }
        } else {
            try file_list.append(allocator, "-");
        }
        total_items_seen = file_list.items.len;
    }

    const nfiles = file_list.items.len;
    const is_single_stdin = (nfiles == 1 and std.mem.eql(u8, file_list.items[0], "-") and (file_start >= args.len or std.mem.eql(u8, args[file_start], "-")));

    var number_width: usize = 1;
    if (total_mode == .only or (files0_from != null and is_stream)) {
        number_width = 1;
    } else if (nfiles == 0 or (nfiles == 1 and count_selected == 1 and is_single_stdin)) {
        number_width = 1;
    } else {
        var min_width: usize = 1;
        var regular_total: u64 = 0;
        for (file_list.items) |f| {
            var st: c.struct_stat = undefined;
            var stat_res: c_int = 0;
            if (std.mem.eql(u8, f, "-")) {
                stat_res = c.fstat(0, &st);
            } else {
                var path_buf: [std.fs.max_path_bytes]u8 = undefined;
                if (f.len < path_buf.len) {
                    @memcpy(path_buf[0..f.len], f);
                    path_buf[f.len] = 0;
                    stat_res = c.stat(&path_buf, &st);
                } else {
                    stat_res = -1;
                }
            }

            if (stat_res == 0) {
                if ((st.st_mode & c.S_IFMT) == c.S_IFREG) {
                    regular_total +|= @intCast(st.st_size);
                } else {
                    min_width = 7;
                }
            }
        }

        var w: usize = 1;
        var temp_total = regular_total;
        while (temp_total >= 10) : (temp_total /= 10) {
            w += 1;
        }
        number_width = @max(w, min_width);
    }

    var total_counts = Counts{};
    var total_lines_overflow = false;
    var total_words_overflow = false;
    var total_chars_overflow = false;
    var total_bytes_overflow = false;

    for (file_list.items) |filename| {
        const is_stdin = std.mem.eql(u8, filename, "-");
        var fd: c_int = 0;
        if (is_stdin) {
            fd = 0;
        } else {
            var path_buf: [std.fs.max_path_bytes]u8 = undefined;
            if (filename.len >= path_buf.len) {
                try stderr.print("wc: {s}: File name too long\n", .{filename});
                exit_status = 1;
                continue;
            }
            @memcpy(path_buf[0..filename.len], filename);
            path_buf[filename.len] = 0;
            fd = c.open(&path_buf, c.O_RDONLY);
            if (fd < 0) {
                const err_str = errnoString(c.__errno_location().*);
                const quoted_name = try quoteFileName(allocator, filename);
                defer {
                    if (quoted_name.ptr != filename.ptr) allocator.free(quoted_name);
                }
                try stderr.print("wc: {s}: {s}\n", .{ quoted_name, err_str });
                exit_status = 1;
                continue;
            }
        }
        defer {
            if (!is_stdin) _ = c.close(fd);
        }

        const counts = countFd(fd, print_lines, print_words, print_chars, print_bytes, print_linelength, &locale) catch |err| {
            try stderr.print("wc: {s}: {s}\n", .{ filename, @errorName(err) });
            exit_status = 1;
            continue;
        };

        if (std.math.add(u64, total_counts.lines, counts.lines)) |v| {
            total_counts.lines = v;
        } else |_| {
            total_counts.lines = std.math.maxInt(u64);
            total_lines_overflow = true;
        }

        if (std.math.add(u64, total_counts.words, counts.words)) |v| {
            total_counts.words = v;
        } else |_| {
            total_counts.words = std.math.maxInt(u64);
            total_words_overflow = true;
        }

        if (std.math.add(u64, total_counts.chars, counts.chars)) |v| {
            total_counts.chars = v;
        } else |_| {
            total_counts.chars = std.math.maxInt(u64);
            total_chars_overflow = true;
        }

        if (std.math.add(u64, total_counts.bytes, counts.bytes)) |v| {
            total_counts.bytes = v;
        } else |_| {
            total_counts.bytes = std.math.maxInt(u64);
            total_bytes_overflow = true;
        }

        total_counts.max_line_length = @max(total_counts.max_line_length, counts.max_line_length);

        if (total_mode != .only) {
            const display_name = if (is_single_stdin and file_start >= args.len and files0_from == null) null else filename;
            try writeCountsLine(stdout, allocator, counts, print_lines, print_words, print_chars, print_bytes, print_linelength, number_width, display_name);
        }
    }

    const print_total_line = switch (total_mode) {
        .auto => total_items_seen > 1,
        .always => true,
        .only => true,
        .never => false,
    };

    if (print_total_line) {
        if (total_lines_overflow) {
            try stderr.print("wc: total lines: Value too large for defined data type\n", .{});
            exit_status = 1;
        }
        if (total_words_overflow) {
            try stderr.print("wc: total words: Value too large for defined data type\n", .{});
            exit_status = 1;
        }
        if (total_chars_overflow) {
            try stderr.print("wc: total characters: Value too large for defined data type\n", .{});
            exit_status = 1;
        }
        if (total_bytes_overflow) {
            try stderr.print("wc: total bytes: Value too large for defined data type\n", .{});
            exit_status = 1;
        }

        const total_name: ?[]const u8 = if (total_mode == .only) null else "total";
        try writeCountsLine(stdout, allocator, total_counts, print_lines, print_words, print_chars, print_bytes, print_linelength, number_width, total_name);
    }

    return exit_status;
}

fn countFd(
    fd: c_int,
    p_lines: bool,
    p_words: bool,
    p_chars: bool,
    p_bytes: bool,
    p_linelength: bool,
    locale: *const LocaleContext,
) !Counts {
    var counts = Counts{};

    // Fast path: byte count only
    if (p_bytes and !p_lines and !p_words and !p_chars and !p_linelength) {
        var st: c.struct_stat = undefined;
        if (c.fstat(fd, &st) == 0 and ((st.st_mode & c.S_IFMT) == c.S_IFREG) and st.st_size >= 0) {
            const end_pos = st.st_size;
            const cur_pos = c.lseek(fd, 0, c.SEEK_CUR);
            if (cur_pos >= 0) {
                const page_size: c.off_t = @intCast(c.getpagesize());
                if (@rem(end_pos, page_size) != 0) {
                    const b = if (end_pos < cur_pos) 0 else end_pos - cur_pos;
                    if (b > 0 and c.lseek(fd, b, c.SEEK_CUR) >= 0) {
                        counts.bytes = @intCast(b);
                        return counts;
                    }
                } else {
                    const blksize: c.off_t = if (st.st_blksize > 0) st.st_blksize else 4096;
                    const hi_pos = end_pos - @rem(end_pos, blksize + 1);
                    if (cur_pos < hi_pos and c.lseek(fd, hi_pos, c.SEEK_SET) >= 0) {
                        counts.bytes = @intCast(hi_pos - cur_pos);
                    }
                }
            }
        }

        while (true) {
            var buf: [16384]u8 = undefined;
            const nr = c.read(fd, &buf, buf.len);
            if (nr <= 0) break;
            counts.bytes += @intCast(nr);
        }
        return counts;
    }

    // Line/word/char counting
    if (locale.is_multibyte) {
        var mbs: c.mbstate_t = std.mem.zeroes(c.mbstate_t);
        var in_word = false;
        var linepos: usize = 0;
        var prev: usize = 0;
        var buf: [16384]u8 = undefined;

        while (true) {
            const nr = c.read(fd, buf[prev..].ptr, buf.len - prev);
            if (nr < 0) return error.ReadFailed;
            if (nr == 0 and prev == 0) break;
            const bytes_read: usize = if (nr > 0) @intCast(nr) else 0;
            counts.bytes += bytes_read;

            var p = buf[0..].ptr;
            const plim = buf[0..].ptr + prev + bytes_read;
            prev = 0;

            while (@intFromPtr(p) < @intFromPtr(plim)) {
                var wc: c.wchar_t = 0;
                var charbytes: usize = 1;
                var is_sp = false;
                var char_w: usize = 0;

                const first_b = p[0];
                if (first_b < 0x80) {
                    charbytes = 1;
                    wc = first_b;
                    is_sp = locale.is_space_table[first_b];
                    char_w = if (locale.char_width_table[first_b] > 0) @intCast(locale.char_width_table[first_b]) else 0;
                } else {
                    const scanbytes = @intFromPtr(plim) - @intFromPtr(p);
                    const res = c.mbrtowc(&wc, p, scanbytes, &mbs);
                    if (res == 0) {
                        charbytes = 1;
                        is_sp = false;
                        char_w = 0;
                    } else if (res > 0 and res <= 4) {
                        charbytes = res;
                        is_sp = (c.iswspace(@intCast(wc)) != 0) or (!locale.posixly_correct and (wc == 0x00A0 or wc == 0x2007 or wc == 0x202F or wc == 0x2060));
                        const cw = c.wcwidth(wc);
                        char_w = if (cw > 0) @intCast(cw) else 0;
                    } else if (res == @as(usize, @bitCast(@as(isize, -2)))) {
                        // Incomplete multibyte sequence at buffer boundary
                        prev = scanbytes;
                        @memcpy(buf[0..prev], p[0..prev]);
                        break;
                    } else {
                        // Decoding error
                        charbytes = 1;
                        mbs = std.mem.zeroes(c.mbstate_t);
                        p += 1;
                        if (!in_word) counts.words += 1;
                        in_word = true;
                        continue;
                    }
                }

                switch (wc) {
                    '\n' => {
                        counts.lines += 1;
                        if (linepos > counts.max_line_length) counts.max_line_length = linepos;
                        linepos = 0;
                        in_word = false;
                    },
                    '\r', 0x0c => {
                        if (linepos > counts.max_line_length) counts.max_line_length = linepos;
                        linepos = 0;
                        in_word = false;
                    },
                    '\t' => {
                        linepos += 8 - (linepos % 8);
                        in_word = false;
                    },
                    ' ' => {
                        linepos += 1;
                        in_word = false;
                    },
                    0x0b => {
                        in_word = false;
                    },
                    else => {
                        linepos += char_w;
                        if (!in_word and !is_sp) {
                            counts.words += 1;
                        }
                        in_word = !is_sp;
                    },
                }

                counts.chars += 1;
                p += charbytes;
            }

            if (nr == 0 and prev > 0) {
                // Trailing incomplete bytes
                counts.chars += prev;
                if (!in_word) counts.words += 1;
                break;
            }
        }

        if (linepos > counts.max_line_length) counts.max_line_length = linepos;
    } else {
        // Single-byte locale
        var in_word = false;
        var linepos: usize = 0;
        var buf: [16384]u8 = undefined;

        while (true) {
            const nr = c.read(fd, &buf, buf.len);
            if (nr < 0) return error.ReadFailed;
            if (nr == 0) break;
            const n: usize = @intCast(nr);
            counts.bytes += n;
            counts.chars += n;

            for (buf[0..n]) |b| {
                const is_sp = locale.is_space_table[b];
                switch (b) {
                    '\n' => {
                        counts.lines += 1;
                        if (linepos > counts.max_line_length) counts.max_line_length = linepos;
                        linepos = 0;
                        in_word = false;
                    },
                    '\r', 0x0c => {
                        if (linepos > counts.max_line_length) counts.max_line_length = linepos;
                        linepos = 0;
                        in_word = false;
                    },
                    '\t' => {
                        linepos += 8 - (linepos % 8);
                        in_word = false;
                    },
                    ' ' => {
                        linepos += 1;
                        in_word = false;
                    },
                    0x0b => {
                        in_word = false;
                    },
                    else => {
                        const cw = locale.char_width_table[b];
                        if (cw > 0) linepos += @intCast(cw);
                        if (!in_word and !is_sp) {
                            counts.words += 1;
                        }
                        in_word = !is_sp;
                    },
                }
            }
        }

        if (linepos > counts.max_line_length) counts.max_line_length = linepos;
    }

    return counts;
}

fn writeCountsLine(
    writer: anytype,
    allocator: std.mem.Allocator,
    counts: Counts,
    p_lines: bool,
    p_words: bool,
    p_chars: bool,
    p_bytes: bool,
    p_linelength: bool,
    width: usize,
    file: ?[]const u8,
) !void {
    var line_buf: [4096]u8 = undefined;
    var len: usize = 0;

    var first = true;
    if (p_lines) {
        len += formatCountItem(line_buf[len..], counts.lines, width, first);
        first = false;
    }
    if (p_words) {
        len += formatCountItem(line_buf[len..], counts.words, width, first);
        first = false;
    }
    if (p_chars) {
        len += formatCountItem(line_buf[len..], counts.chars, width, first);
        first = false;
    }
    if (p_bytes) {
        len += formatCountItem(line_buf[len..], counts.bytes, width, first);
        first = false;
    }
    if (p_linelength) {
        len += formatCountItem(line_buf[len..], counts.max_line_length, width, first);
        first = false;
    }

    if (file) |filename| {
        const quoted = try quoteFileName(allocator, filename);
        defer {
            if (quoted.ptr != filename.ptr) allocator.free(quoted);
        }
        if (len < line_buf.len) {
            line_buf[len] = ' ';
            len += 1;
        }
        try writer.writeAll(line_buf[0..len]);
        try writer.writeAll(quoted);
        try writer.writeByte('\n');
    } else {
        if (len < line_buf.len) {
            line_buf[len] = '\n';
            len += 1;
        }
        try writer.writeAll(line_buf[0..len]);
    }
    try writer.flush();
}

fn formatCountItem(dest: []u8, val: u64, width: usize, first: bool) usize {
    var buf: [32]u8 = undefined;
    const num_str = std.fmt.bufPrint(&buf, "{d}", .{val}) catch unreachable;
    var written: usize = 0;

    if (!first) {
        if (written < dest.len) {
            dest[written] = ' ';
            written += 1;
        }
    }

    if (num_str.len < width) {
        const padding = width - num_str.len;
        var k: usize = 0;
        while (k < padding) : (k += 1) {
            if (written < dest.len) {
                dest[written] = ' ';
                written += 1;
            }
        }
    }

    const to_copy = @min(num_str.len, dest.len - written);
    @memcpy(dest[written .. written + to_copy], num_str[0..to_copy]);
    written += to_copy;

    return written;
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
