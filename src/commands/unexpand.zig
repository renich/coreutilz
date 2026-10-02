const std = @import("std");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "unexpand";
pub const version: []const u8 = "0.1.0";

const TabConfig = struct {
    stops: std.ArrayList(usize) = .empty,
    all: bool = false,

    fn deinit(self: *TabConfig, allocator: std.mem.Allocator) void {
        self.stops.deinit(allocator);
    }

    fn nextTab(self: *const TabConfig, col: usize) ?usize {
        if (self.stops.items.len > 0) {
            for (self.stops.items) |stop| {
                if (stop > col) return stop;
            }
            return null;
        }
        return ((col / 8) + 1) * 8;
    }
};

fn parseTabStops(cfg: *TabConfig, s: []const u8, allocator: std.mem.Allocator) !void {
    var i: usize = 0;
    while (i < s.len) {
        while (i < s.len and (s[i] == ' ' or s[i] == ',' or s[i] == '/')) i += 1;
        if (i >= s.len) break;
        var num: usize = 0;
        var has_digit = false;
        while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) {
            num = num * 10 + (s[i] - '0');
            has_digit = true;
        }
        if (!has_digit) return error.InvalidTab;
        if (num == 0) return error.ZeroTab;
        if (cfg.stops.items.len > 0 and num <= cfg.stops.items[cfg.stops.items.len - 1]) return error.UnorderedTab;
        try cfg.stops.append(allocator, num);
    }
}

fn unexpandFd(fd: c_int, writer: anytype, cfg: *const TabConfig) !void {
    var buf: [16384]u8 = undefined;
    var col: usize = 0;
    var pending_start_col: usize = 0;
    var in_whitespace = false;
    var seen_non_blank = false;

    while (true) {
        const nr = c.read(fd, &buf, buf.len);
        if (nr <= 0) break;
        const n: usize = @intCast(nr);
        for (buf[0..n]) |b| {
            if (b == '\n') {
                if (in_whitespace) {
                    try flushWhitespace(writer, pending_start_col, col, cfg);
                    in_whitespace = false;
                }
                try writer.writeByte('\n');
                col = 0;
                seen_non_blank = false;
            } else if (b == ' ' or b == '\t') {
                if (!cfg.all and seen_non_blank) {
                    try writer.writeByte(b);
                    col += if (b == ' ') 1 else ((cfg.nextTab(col) orelse (col + 1)) - col);
                } else {
                    if (!in_whitespace) {
                        in_whitespace = true;
                        pending_start_col = col;
                    }
                    if (b == ' ') {
                        col += 1;
                    } else {
                        col = cfg.nextTab(col) orelse (col + 1);
                    }
                }
            } else {
                seen_non_blank = true;
                if (in_whitespace) {
                    try flushWhitespace(writer, pending_start_col, col, cfg);
                    in_whitespace = false;
                }
                try writer.writeByte(b);
                col += 1;
            }
        }
    }
    if (in_whitespace) {
        try flushWhitespace(writer, pending_start_col, col, cfg);
    }
}

fn flushWhitespace(writer: anytype, start_col: usize, target_col: usize, cfg: *const TabConfig) !void {
    var cur = start_col;
    while (cur < target_col) {
        if (cfg.nextTab(cur)) |next_stop| {
            if (next_stop <= target_col) {
                try writer.writeByte('\t');
                cur = next_stop;
                continue;
            }
        }
        while (cur < target_col) : (cur += 1) {
            try writer.writeByte(' ');
        }
    }
}

fn printUsage(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: unexpand [OPTION]... [FILE]...
        \\Convert spaces in each FILE to tabs, writing to standard output.
        \\
        \\With no FILE, or when FILE is -, read standard input.
        \\
        \\  -a, --all        convert all blanks, instead of only initial blanks
        \\      --first-only convert only leading sequences of blanks (overrides -a)
        \\  -t, --tabs=N     have tabs N characters apart instead of 8 (enables -a)
        \\  -t, --tabs=LIST  use comma separated list of tab positions (enables -a)
        \\      --help       display this help and exit
        \\      --version    output version information and exit
        \\
    );
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var cfg = TabConfig{};
    defer cfg.deinit(allocator);

    var files: std.ArrayList([]const u8) = .empty;
    defer files.deinit(allocator);

    var tabs_specified = false;
    var first_only = false;

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--help")) {
            var buf: [1024]u8 = undefined;
            var w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &buf);
            try printUsage(&w.interface);
            w.interface.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            var buf: [256]u8 = undefined;
            var w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &buf);
            try w.interface.print("unexpand (coreutilz) {s}\n", .{version});
            w.interface.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "-a") or std.mem.eql(u8, arg, "--all")) {
            cfg.all = true;
        } else if (std.mem.eql(u8, arg, "--first-only")) {
            first_only = true;
        } else if (std.mem.startsWith(u8, arg, "--tabs=")) {
            tabs_specified = true;
            parseTabStops(&cfg, arg["--tabs=".len..], allocator) catch return 1;
        } else if (std.mem.eql(u8, arg, "-t")) {
            i += 1;
            if (i >= args.len) return 1;
            tabs_specified = true;
            parseTabStops(&cfg, args[i], allocator) catch return 1;
        } else if (std.mem.startsWith(u8, arg, "-") and !std.mem.eql(u8, arg, "-")) {
            return 1;
        } else {
            try files.append(allocator, arg);
        }
    }

    if (tabs_specified and !first_only) {
        cfg.all = true;
    }
    if (first_only) {
        cfg.all = false;
    }

    var out_buf: [16384]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &out_buf);
    const writer = &out_w.interface;

    if (files.items.len == 0) {
        unexpandFd(0, writer, &cfg) catch |err| {
            if (err == error.DiskFull or err == error.NoSpaceLeft or err == error.WriteFailed) return 1;
            return err;
        };
    } else {
        for (files.items) |file_path| {
            if (std.mem.eql(u8, file_path, "-")) {
                unexpandFd(0, writer, &cfg) catch return 1;
            } else {
                var zpath: [std.fs.max_path_bytes:0]u8 = undefined;
                if (file_path.len >= zpath.len) return 1;
                @memcpy(zpath[0..file_path.len], file_path);
                zpath[file_path.len] = 0;
                const fd = c.open(&zpath, c.O_RDONLY);
                if (fd < 0) return 1;
                defer _ = c.close(fd);
                unexpandFd(fd, writer, &cfg) catch return 1;
            }
        }
    }

    out_w.interface.flush() catch return 1;
    return 0;
}
