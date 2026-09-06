const std = @import("std");
const errors = @import("../utils/errors.zig");

pub const name: []const u8 = "cut";
pub const version: []const u8 = "0.1.0";

pub const RangePair = struct {
    lo: u64,
    hi: u64,
};

fn rangeLessThan(_: void, a: RangePair, b: RangePair) bool {
    return a.lo < b.lo;
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

fn printHelp(writer: anytype) !void {
    try writer.print(
        \\Usage: {s} OPTION... [FILE]...
        \\Print selected parts of lines from each FILE to standard output.
        \\
        \\With no FILE, or when FILE is -, read standard input.
        \\
        \\Mandatory arguments to long options are mandatory for short options too.
        \\  -b, --bytes=LIST
        \\         select only these bytes
        \\  -c, --characters=LIST
        \\         select only these characters
        \\  -d, --delimiter=DELIM
        \\         use DELIM instead of TAB for field delimiter
        \\  -f, --fields=LIST
        \\         select only these fields;  also print any line that contains
        \\         no delimiter character, unless the -s option is specified
        \\  -n
        \\         with -b: don't split multibyte characters
        \\      --complement
        \\         complement the set of selected bytes, characters or fields
        \\  -s, --only-delimited
        \\         do not print lines not containing delimiters
        \\      --output-delimiter=STRING
        \\         use STRING as the output delimiter;
        \\         the default is to use the input delimiter
        \\  -z, --zero-terminated
        \\         line delimiter is NUL, not newline
        \\      --help
        \\         display this help and exit
        \\      --version
        \\         output version information and exit
        \\
        \\Use one, and only one of -b, -c or -f.  Each LIST is made up of one
        \\range, or many ranges separated by commas.  Selected input is written
        \\in the same order that it is read, and is written exactly once.
        \\Each range is one of:
        \\
        \\  N     N'th byte, character or field, counted from 1
        \\  N-    from N'th byte, character or field, to end of line
        \\  N-M   from N'th to M'th (included) byte, character or field
        \\  -M    from first to M'th (included) byte, character or field
        \\
        \\Report bugs to: bug-coreutils@gnu.org
        \\GNU coreutils home page: <https://www.gnu.org/software/coreutils/>
        \\General help using GNU software: <https://www.gnu.org/gethelp/>
        \\Full documentation <https://www.gnu.org/software/coreutils/cut>
        \\or available locally via: info '(coreutils) cut invocation'
        \\
    , .{name});
}

fn printVersion(writer: anytype) !void {
    try errors.printVersion(writer, name, version);
}

fn setFields(
    spec_list: []const u8,
    byte_mode: bool,
    complement: bool,
    allocator: std.mem.Allocator,
    stderr: anytype,
) ![]RangePair {
    var ranges: std.ArrayList(RangePair) = .empty;
    defer ranges.deinit(allocator);

    var initial: u64 = 1;
    var value: u64 = 0;
    var lhs_specified = false;
    var rhs_specified = false;
    var dash_found = false;
    var in_digits = false;
    var num_start_idx: ?usize = null;

    var idx: usize = 0;
    while (true) : (idx += 1) {
        const is_eof = (idx == spec_list.len);
        const c: u8 = if (is_eof) 0 else spec_list[idx];

        if (!is_eof and c == '-') {
            in_digits = false;
            num_start_idx = null;
            if (dash_found) {
                if (byte_mode) {
                    try stderr.print("cut: invalid byte or character range\nTry 'cut --help' for more information.\n", .{});
                } else {
                    try stderr.print("cut: invalid field range\nTry 'cut --help' for more information.\n", .{});
                }
                return error.InvalidRange;
            }
            dash_found = true;
            if (lhs_specified and value == 0) {
                if (byte_mode) {
                    try stderr.print("cut: byte/character positions are numbered from 1\nTry 'cut --help' for more information.\n", .{});
                } else {
                    try stderr.print("cut: fields are numbered from 1\nTry 'cut --help' for more information.\n", .{});
                }
                return error.InvalidRange;
            }
            initial = if (lhs_specified) value else 1;
            value = 0;
        } else if (is_eof or c == ',' or c == ' ' or c == '\t') {
            in_digits = false;
            num_start_idx = null;
            if (dash_found) {
                dash_found = false;
                if (!lhs_specified and !rhs_specified) {
                    try stderr.print("cut: invalid range with no endpoint: -\nTry 'cut --help' for more information.\n", .{});
                    return error.InvalidRange;
                }
                if (!rhs_specified) {
                    try ranges.append(allocator, .{ .lo = initial, .hi = std.math.maxInt(u64) });
                } else {
                    if (value < initial) {
                        try stderr.print("cut: invalid decreasing range\nTry 'cut --help' for more information.\n", .{});
                        return error.InvalidRange;
                    }
                    try ranges.append(allocator, .{ .lo = initial, .hi = value });
                }
                value = 0;
            } else {
                if (value == 0) {
                    if (byte_mode) {
                        try stderr.print("cut: byte/character positions are numbered from 1\nTry 'cut --help' for more information.\n", .{});
                    } else {
                        try stderr.print("cut: fields are numbered from 1\nTry 'cut --help' for more information.\n", .{});
                    }
                    return error.InvalidRange;
                }
                try ranges.append(allocator, .{ .lo = value, .hi = value });
                value = 0;
            }
            if (is_eof) break;
            lhs_specified = false;
            rhs_specified = false;
        } else if (c >= '0' and c <= '9') {
            if (!in_digits) {
                num_start_idx = idx;
                in_digits = true;
            }
            if (dash_found) {
                rhs_specified = true;
            } else {
                lhs_specified = true;
            }
            const digit: u64 = c - '0';
            const max_allowed: u64 = std.math.maxInt(u64) - 1;
            var overflow = false;
            if (value > max_allowed / 10) {
                overflow = true;
            } else {
                value = value * 10;
                if (value > max_allowed - digit) {
                    overflow = true;
                } else {
                    value += digit;
                }
            }
            if (overflow) {
                const start = num_start_idx orelse idx;
                var end = start;
                while (end < spec_list.len and spec_list[end] >= '0' and spec_list[end] <= '9') : (end += 1) {}
                const bad_num = spec_list[start..end];
                if (byte_mode) {
                    try stderr.print("cut: byte/character offset '{s}' is too large\nTry 'cut --help' for more information.\n", .{bad_num});
                } else {
                    try stderr.print("cut: field number '{s}' is too large\nTry 'cut --help' for more information.\n", .{bad_num});
                }
                return error.InvalidRange;
            }
        } else {
            const rest = spec_list[idx..];
            if (byte_mode) {
                try stderr.print("cut: invalid byte/character position '{s}'\nTry 'cut --help' for more information.\n", .{rest});
            } else {
                try stderr.print("cut: invalid field value '{s}'\nTry 'cut --help' for more information.\n", .{rest});
            }
            return error.InvalidRange;
        }
    }

    if (ranges.items.len == 0) {
        if (byte_mode) {
            try stderr.print("cut: missing list of byte/character positions\nTry 'cut --help' for more information.\n", .{});
        } else {
            try stderr.print("cut: missing list of fields\nTry 'cut --help' for more information.\n", .{});
        }
        return error.InvalidRange;
    }

    std.mem.sort(RangePair, ranges.items, {}, rangeLessThan);

    // Merge overlapping ranges
    var i: usize = 0;
    while (i < ranges.items.len) : (i += 1) {
        const j = i + 1;
        while (j < ranges.items.len) {
            if (ranges.items[j].lo <= ranges.items[i].hi) {
                ranges.items[i].hi = @max(ranges.items[i].hi, ranges.items[j].hi);
                _ = ranges.orderedRemove(j);
            } else {
                break;
            }
        }
    }

    // Complement
    if (complement) {
        var comp: std.ArrayList(RangePair) = .empty;
        errdefer comp.deinit(allocator);

        if (ranges.items.len > 0) {
            if (ranges.items[0].lo > 1) {
                try comp.append(allocator, .{ .lo = 1, .hi = ranges.items[0].lo - 1 });
            }
            var k: usize = 1;
            while (k < ranges.items.len) : (k += 1) {
                if (ranges.items[k - 1].hi + 1 == ranges.items[k].lo) {
                    continue;
                }
                try comp.append(allocator, .{ .lo = ranges.items[k - 1].hi + 1, .hi = ranges.items[k].lo - 1 });
            }
            if (ranges.items[ranges.items.len - 1].hi < std.math.maxInt(u64)) {
                try comp.append(allocator, .{ .lo = ranges.items[ranges.items.len - 1].hi + 1, .hi = std.math.maxInt(u64) });
            }
        } else {
            try comp.append(allocator, .{ .lo = 1, .hi = std.math.maxInt(u64) });
        }
        ranges.deinit(allocator);
        ranges = comp;
    }

    // Add sentinel
    try ranges.append(allocator, .{ .lo = std.math.maxInt(u64), .hi = std.math.maxInt(u64) });

    return ranges.toOwnedSlice(allocator);
}

const StreamReader = struct {
    reader: *std.Io.Reader,
    peeked: ?u8 = null,

    fn getByte(self: *StreamReader) !?u8 {
        if (self.peeked) |b| {
            self.peeked = null;
            return b;
        }
        return self.reader.takeByte() catch |err| switch (err) {
            error.EndOfStream => null,
            else => |e| e,
        };
    }

    fn ungetByte(self: *StreamReader, b: u8) void {
        std.debug.assert(self.peeked == null);
        self.peeked = b;
    }
};

fn cutBytes(
    file: std.Io.File,
    ranges: []const RangePair,
    output_delimiter: ?[]const u8,
    line_delim: u8,
    stdout: anytype,
) !void {
    var r_buf: [16384]u8 = undefined;
    var r = file.readerStreaming(std.Options.debug_io, &r_buf);
    const reader = &r.interface;

    var byte_idx: u64 = 0;
    var print_delimiter = false;
    var rp_idx: usize = 0;

    var in_buf: [16384]u8 = undefined;

    while (true) {
        const bytes_read = try reader.readSliceShort(&in_buf);
        if (bytes_read == 0) break;

        for (in_buf[0..bytes_read]) |c| {
            if (c == line_delim) {
                try stdout.writeByte(c);
                byte_idx = 0;
                print_delimiter = false;
                rp_idx = 0;
            } else {
                byte_idx += 1;
                if (byte_idx > ranges[rp_idx].hi) {
                    rp_idx += 1;
                }
                if (byte_idx >= ranges[rp_idx].lo) {
                    if (output_delimiter) |odelim| {
                        if (print_delimiter and byte_idx == ranges[rp_idx].lo) {
                            try stdout.writeAll(odelim);
                        }
                        print_delimiter = true;
                    }
                    try stdout.writeByte(c);
                }
            }
        }
    }

    if (byte_idx > 0) {
        try stdout.writeByte(line_delim);
    }
}

fn cutFields(
    file: std.Io.File,
    ranges: []const RangePair,
    delim: u8,
    output_delimiter: []const u8,
    line_delim: u8,
    suppress_non_delimited: bool,
    stdout: anytype,
    allocator: std.mem.Allocator,
) !void {
    var r_buf: [16384]u8 = undefined;
    var r = file.readerStreaming(std.Options.debug_io, &r_buf);
    var stream = StreamReader{ .reader = &r.interface };

    // If stream is empty, return immediately
    const first_byte = (try stream.getByte()) orelse return;
    stream.ungetByte(first_byte);

    var field_idx: u64 = 1;
    var rp_idx: usize = 0;
    var found_any_selected_field = false;

    const print_field_1 = (ranges[0].lo <= 1);
    const buffer_first_field = (suppress_non_delimited == print_field_1);

    var field_1_buffer: std.ArrayList(u8) = .empty;
    defer field_1_buffer.deinit(allocator);

    var c: ?u8 = 0;

    while (true) {
        if (field_idx == 1 and buffer_first_field) {
            field_1_buffer.clearRetainingCapacity();

            var ended_with_delim = false;
            var ended_with_line_delim = false;
            while (true) {
                const b_opt = try stream.getByte();
                if (b_opt) |b| {
                    try field_1_buffer.append(allocator, b);
                    if (b == delim) {
                        ended_with_delim = true;
                        break;
                    }
                    if (b == line_delim) {
                        ended_with_line_delim = true;
                        break;
                    }
                } else {
                    break;
                }
            }

            const n_bytes = field_1_buffer.items.len;
            if (n_bytes == 0) {
                break; // EOF
            }

            c = 0;

            // If the first field extends to the end of line (it is not delimited)
            if (!ended_with_delim) {
                if (!suppress_non_delimited) {
                    try stdout.writeAll(field_1_buffer.items);
                    if (!ended_with_line_delim) {
                        try stdout.writeByte(line_delim);
                    }
                    c = line_delim;
                }
                continue;
            }

            if (print_field_1) {
                try stdout.writeAll(field_1_buffer.items[0 .. n_bytes - 1]);
                if (delim == line_delim) {
                    const last_c = try stream.getByte();
                    if (last_c) |lc| {
                        stream.ungetByte(lc);
                        found_any_selected_field = true;
                    }
                } else {
                    found_any_selected_field = true;
                }
            }

            field_idx += 1;
            if (field_idx > ranges[rp_idx].hi) {
                rp_idx += 1;
            }
        }

        var prev_c: ?u8 = c;

        const is_selected = (field_idx >= ranges[rp_idx].lo);
        if (is_selected) {
            if (found_any_selected_field) {
                try stdout.writeAll(output_delimiter);
            }
            found_any_selected_field = true;

            while (true) {
                const b_opt = try stream.getByte();
                if (b_opt == null) {
                    c = null;
                    break;
                }
                const b = b_opt.?;
                if (b == delim or b == line_delim) {
                    c = b;
                    break;
                }
                try stdout.writeByte(b);
                prev_c = b;
            }
        } else {
            while (true) {
                const b_opt = try stream.getByte();
                if (b_opt == null) {
                    c = null;
                    break;
                }
                const b = b_opt.?;
                if (b == delim or b == line_delim) {
                    c = b;
                    break;
                }
                prev_c = b;
            }
        }

        // With -d$'\n' don't treat the last '\n' as a delimiter
        if (c != null and delim == line_delim and c.? == delim) {
            const last_c = try stream.getByte();
            if (last_c) |lc| {
                stream.ungetByte(lc);
            } else {
                c = null; // treat as EOF
            }
        }

        if (c != null and c.? == delim) {
            field_idx += 1;
            if (field_idx > ranges[rp_idx].hi) {
                rp_idx += 1;
            }
        } else if (c == null or c.? == line_delim) {
            if (found_any_selected_field or !(suppress_non_delimited and field_idx == 1)) {
                if (c != null or (prev_c != null and prev_c.? != line_delim) or delim == line_delim) {
                    try stdout.writeByte(line_delim);
                }
            }
            if (c == null) {
                break;
            }

            field_idx = 1;
            rp_idx = 0;
            found_any_selected_field = false;
        }
    }
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

    var byte_mode = false;
    var spec_list_string: ?[]const u8 = null;
    var delim: u8 = '\t';
    var delim_specified = false;
    var output_delimiter_string: ?[]const u8 = null;
    var output_delimiter_specified = false;
    var suppress_non_delimited = false;
    var line_delim: u8 = '\n';
    var complement = false;

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

            if (std.mem.eql(u8, opt_name, "--c")) {
                try stderr.print("cut: option '--c' is ambiguous; possibilities: '--characters' '--complement'\nTry 'cut --help' for more information.\n", .{});
                return 1;
            } else if (std.mem.eql(u8, opt_name, "--o")) {
                try stderr.print("cut: option '--o' is ambiguous; possibilities: '--only-delimited' '--output-delimiter'\nTry 'cut --help' for more information.\n", .{});
                return 1;
            } else if (std.mem.startsWith(u8, "--help", opt_name)) {
                printHelp(stdout) catch return 1;
                stdout.flush() catch return 1;
                return 0;
            } else if (std.mem.startsWith(u8, "--version", opt_name)) {
                printVersion(stdout) catch return 1;
                stdout.flush() catch return 1;
                return 0;
            } else if (std.mem.startsWith(u8, "--bytes", opt_name)) {
                if (spec_list_string != null) {
                    try stderr.print("cut: only one list may be specified\nTry 'cut --help' for more information.\n", .{});
                    return 1;
                }
                byte_mode = true;
                const val = if (val_in_opt) |v| v else blk: {
                    i += 1;
                    if (i >= args.len) {
                        try stderr.print("cut: option '{s}' requires an argument\nTry 'cut --help' for more information.\n", .{opt_name});
                        return 1;
                    }
                    break :blk args[i];
                };
                spec_list_string = val;
            } else if (std.mem.startsWith(u8, "--characters", opt_name)) {
                if (spec_list_string != null) {
                    try stderr.print("cut: only one list may be specified\nTry 'cut --help' for more information.\n", .{});
                    return 1;
                }
                byte_mode = true;
                const val = if (val_in_opt) |v| v else blk: {
                    i += 1;
                    if (i >= args.len) {
                        try stderr.print("cut: option '{s}' requires an argument\nTry 'cut --help' for more information.\n", .{opt_name});
                        return 1;
                    }
                    break :blk args[i];
                };
                spec_list_string = val;
            } else if (std.mem.startsWith(u8, "--fields", opt_name)) {
                if (spec_list_string != null) {
                    try stderr.print("cut: only one list may be specified\nTry 'cut --help' for more information.\n", .{});
                    return 1;
                }
                const val = if (val_in_opt) |v| v else blk: {
                    i += 1;
                    if (i >= args.len) {
                        try stderr.print("cut: option '{s}' requires an argument\nTry 'cut --help' for more information.\n", .{opt_name});
                        return 1;
                    }
                    break :blk args[i];
                };
                spec_list_string = val;
            } else if (std.mem.startsWith(u8, "--delimiter", opt_name)) {
                const val = if (val_in_opt) |v| v else blk: {
                    i += 1;
                    if (i >= args.len) {
                        try stderr.print("cut: option '{s}' requires an argument\nTry 'cut --help' for more information.\n", .{opt_name});
                        return 1;
                    }
                    break :blk args[i];
                };
                if (val.len > 1) {
                    try stderr.print("cut: the delimiter must be a single character\nTry 'cut --help' for more information.\n", .{});
                    return 1;
                }
                delim = if (val.len == 0) 0 else val[0];
                delim_specified = true;
            } else if (std.mem.startsWith(u8, "--output-delimiter", opt_name)) {
                const val = if (val_in_opt) |v| v else blk: {
                    i += 1;
                    if (i >= args.len) {
                        try stderr.print("cut: option '{s}' requires an argument\nTry 'cut --help' for more information.\n", .{opt_name});
                        return 1;
                    }
                    break :blk args[i];
                };
                output_delimiter_specified = true;
                output_delimiter_string = val;
            } else if (std.mem.startsWith(u8, "--complement", opt_name)) {
                if (val_in_opt != null) {
                    try stderr.print("cut: option '{s}' doesn't allow an argument\nTry 'cut --help' for more information.\n", .{opt_name});
                    return 1;
                }
                complement = true;
            } else if (std.mem.startsWith(u8, "--only-delimited", opt_name)) {
                if (val_in_opt != null) {
                    try stderr.print("cut: option '{s}' doesn't allow an argument\nTry 'cut --help' for more information.\n", .{opt_name});
                    return 1;
                }
                suppress_non_delimited = true;
            } else if (std.mem.startsWith(u8, "--zero-terminated", opt_name)) {
                if (val_in_opt != null) {
                    try stderr.print("cut: option '{s}' doesn't allow an argument\nTry 'cut --help' for more information.\n", .{opt_name});
                    return 1;
                }
                line_delim = 0;
            } else {
                try stderr.print("cut: unrecognized option '{s}'\nTry 'cut --help' for more information.\n", .{arg});
                return 1;
            }
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            var j: usize = 1;
            while (j < arg.len) : (j += 1) {
                const c = arg[j];
                switch (c) {
                    'b', 'c' => {
                        if (spec_list_string != null) {
                            try stderr.print("cut: only one list may be specified\nTry 'cut --help' for more information.\n", .{});
                            return 1;
                        }
                        byte_mode = true;
                        const val = if (j + 1 < arg.len) arg[j + 1 ..] else blk: {
                            i += 1;
                            if (i >= args.len) {
                                try stderr.print("cut: option requires an argument -- '{c}'\nTry 'cut --help' for more information.\n", .{c});
                                return 1;
                            }
                            break :blk args[i];
                        };
                        spec_list_string = val;
                        break;
                    },
                    'f' => {
                        if (spec_list_string != null) {
                            try stderr.print("cut: only one list may be specified\nTry 'cut --help' for more information.\n", .{});
                            return 1;
                        }
                        const val = if (j + 1 < arg.len) arg[j + 1 ..] else blk: {
                            i += 1;
                            if (i >= args.len) {
                                try stderr.print("cut: option requires an argument -- 'f'\nTry 'cut --help' for more information.\n", .{});
                                return 1;
                            }
                            break :blk args[i];
                        };
                        spec_list_string = val;
                        break;
                    },
                    'd' => {
                        const val = if (j + 1 < arg.len) arg[j + 1 ..] else blk: {
                            i += 1;
                            if (i >= args.len) {
                                try stderr.print("cut: option requires an argument -- 'd'\nTry 'cut --help' for more information.\n", .{});
                                return 1;
                            }
                            break :blk args[i];
                        };
                        if (val.len > 1) {
                            try stderr.print("cut: the delimiter must be a single character\nTry 'cut --help' for more information.\n", .{});
                            return 1;
                        }
                        delim = if (val.len == 0) 0 else val[0];
                        delim_specified = true;
                        break;
                    },
                    'n' => {},
                    's' => {
                        suppress_non_delimited = true;
                    },
                    'z' => {
                        line_delim = 0;
                    },
                    else => {
                        try stderr.print("cut: invalid option -- '{c}'\nTry 'cut --help' for more information.\n", .{c});
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

    if (spec_list_string == null) {
        try stderr.print("cut: you must specify a list of bytes, characters, or fields\nTry 'cut --help' for more information.\n", .{});
        return 1;
    }

    if (byte_mode) {
        if (delim_specified) {
            try stderr.print("cut: an input delimiter may be specified only when operating on fields\nTry 'cut --help' for more information.\n", .{});
            return 1;
        }
        if (suppress_non_delimited) {
            try stderr.print("cut: suppressing non-delimited lines makes sense\n\tonly when operating on fields\nTry 'cut --help' for more information.\n", .{});
            return 1;
        }
    }

    const ranges = setFields(spec_list_string.?, byte_mode, complement, allocator, stderr) catch {
        return 1;
    };
    defer allocator.free(ranges);

    var byte_output_delim: ?[]const u8 = null;
    var field_output_delim: []const u8 = undefined;

    var default_field_delim_buf: [1]u8 = [_]u8{delim};
    var nul_buf: [1]u8 = [_]u8{0};

    if (output_delimiter_specified) {
        if (output_delimiter_string.?.len == 0) {
            byte_output_delim = &nul_buf;
            field_output_delim = &nul_buf;
        } else {
            byte_output_delim = output_delimiter_string.?;
            field_output_delim = output_delimiter_string.?;
        }
    } else {
        field_output_delim = &default_field_delim_buf;
    }

    var exit_code: u8 = 0;

    for (files.items) |file_path| {
        if (std.mem.eql(u8, file_path, "-")) {
            if (byte_mode) {
                cutBytes(std.Io.File.stdin(), ranges, byte_output_delim, line_delim, stdout) catch |err| {
                    try stderr.print("cut: -: {s}\n", .{openErrorDescription(err)});
                    exit_code = 1;
                };
            } else {
                cutFields(std.Io.File.stdin(), ranges, delim, field_output_delim, line_delim, suppress_non_delimited, stdout, allocator) catch |err| {
                    try stderr.print("cut: -: {s}\n", .{openErrorDescription(err)});
                    exit_code = 1;
                };
            }
        } else {
            const f = std.Io.Dir.cwd().openFile(std.Options.debug_io, file_path, .{ .mode = .read_only }) catch |err| {
                try stderr.print("cut: {s}: {s}\n", .{ file_path, openErrorDescription(err) });
                exit_code = 1;
                continue;
            };
            defer f.close(std.Options.debug_io);

            if (byte_mode) {
                cutBytes(f, ranges, byte_output_delim, line_delim, stdout) catch |err| {
                    try stderr.print("cut: {s}: {s}\n", .{ file_path, openErrorDescription(err) });
                    exit_code = 1;
                };
            } else {
                cutFields(f, ranges, delim, field_output_delim, line_delim, suppress_non_delimited, stdout, allocator) catch |err| {
                    try stderr.print("cut: {s}: {s}\n", .{ file_path, openErrorDescription(err) });
                    exit_code = 1;
                };
            }
        }
    }

    return exit_code;
}
