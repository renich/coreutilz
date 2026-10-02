const std = @import("std");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "expand";
pub const version: []const u8 = "0.1.0";

const TabConfig = struct {
    stops: std.ArrayList(usize) = .empty,
    auto_increment: usize = 0,
    initial_only: bool = false,

    fn deinit(self: *TabConfig, allocator: std.mem.Allocator) void {
        self.stops.deinit(allocator);
    }

    fn nextStop(self: *const TabConfig, col: usize) usize {
        for (self.stops.items) |stop| {
            if (stop > col) return stop;
        }
        if (self.auto_increment > 0) {
            const base = if (self.stops.items.len > 0) self.stops.items[self.stops.items.len - 1] else 0;
            if (col < base) return base;
            const delta = col - base;
            return base + ((delta / self.auto_increment) + 1) * self.auto_increment;
        }
        if (self.stops.items.len > 0) {
            return col + 1;
        }
        return ((col / 8) + 1) * 8;
    }
};

fn parseTabStops(cfg: *TabConfig, s: []const u8, allocator: std.mem.Allocator) !void {
    var i: usize = 0;
    while (i < s.len) {
        while (i < s.len and (s[i] == ' ' or s[i] == ',' or s[i] == '/')) i += 1;
        if (i >= s.len) break;
        if (s[i] == '+') {
            i += 1;
            var num: usize = 0;
            var has_digit = false;
            while (i < s.len and s[i] >= '0' and s[i] <= '9') : (i += 1) {
                num = num * 10 + (s[i] - '0');
                has_digit = true;
            }
            if (!has_digit or num == 0) return error.InvalidTab;
            cfg.auto_increment = num;
            continue;
        }
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

fn isDigitArg(arg: []const u8) bool {
    if (arg.len < 2 or arg[0] != '-') return false;
    for (arg[1..]) |c_ch| {
        if (!std.ascii.isDigit(c_ch) and c_ch != ',' and c_ch != ' ') return false;
    }
    return true;
}

fn expandFd(fd: c_int, writer: anytype, cfg: *const TabConfig) !void {
    var col: usize = 0;
    var seen_non_blank = false;
    var buf: [16384]u8 = undefined;
    while (true) {
        const nr = c.read(fd, &buf, buf.len);
        if (nr <= 0) break;
        const n: usize = @intCast(nr);
        for (buf[0..n]) |b| {
            if (b == '\n') {
                try writer.writeByte('\n');
                col = 0;
                seen_non_blank = false;
            } else if (b == '\t') {
                if (cfg.initial_only and seen_non_blank) {
                    try writer.writeByte('\t');
                    col += 1;
                } else {
                    const target = cfg.nextStop(col);
                    const spaces = if (target > col) target - col else 1;
                    for (0..spaces) |_| try writer.writeByte(' ');
                    col = target;
                }
            } else {
                if (b != ' ') seen_non_blank = true;
                if (b == '\x08') {
                    if (col > 0) col -= 1;
                } else {
                    col += 1;
                }
                try writer.writeByte(b);
            }
        }
    }
}

fn printUsage(writer: anytype) !void {
    try writer.writeAll(
        \\Usage: expand [OPTION]... [FILE]...
        \\Convert tabs in each FILE to spaces, writing to standard output.
        \\
        \\With no FILE, or when FILE is -, read standard input.
        \\
        \\  -i, --initial       do not convert tabs after non blanks
        \\  -t, --tabs=N        have tabs N characters apart, not 8
        \\  -t, --tabs=LIST     use comma separated list of tab positions
        \\      --help          display this help and exit
        \\      --version       output version information and exit
        \\
    );
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var cfg = TabConfig{};
    defer cfg.deinit(allocator);

    var files: std.ArrayList([]const u8) = .empty;
    defer files.deinit(allocator);

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
            try w.interface.print("expand (coreutilz) {s}\n", .{version});
            w.interface.flush() catch return 1;
            return 0;
        } else if (std.mem.eql(u8, arg, "-i") or std.mem.eql(u8, arg, "--initial")) {
            cfg.initial_only = true;
        } else if (std.mem.startsWith(u8, arg, "--tabs=")) {
            parseTabStops(&cfg, arg["--tabs=".len..], allocator) catch {
                var err_buf: [256]u8 = undefined;
                var ew = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &err_buf);
                try ew.interface.print("expand: tab size contains invalid character(s): '{s}'\n", .{arg["--tabs=".len..]});
                ew.interface.flush() catch {};
                return 1;
            };
        } else if (std.mem.eql(u8, arg, "-t")) {
            i += 1;
            if (i >= args.len) return 1;
            parseTabStops(&cfg, args[i], allocator) catch {
                var err_buf: [256]u8 = undefined;
                var ew = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &err_buf);
                try ew.interface.print("expand: tab size contains invalid character(s): '{s}'\n", .{args[i]});
                ew.interface.flush() catch {};
                return 1;
            };
        } else if (isDigitArg(arg)) {
            parseTabStops(&cfg, arg[1..], allocator) catch {
                var err_buf: [256]u8 = undefined;
                var ew = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &err_buf);
                try ew.interface.print("expand: invalid tab stop: '{s}'\n", .{arg[1..]});
                ew.interface.flush() catch {};
                return 1;
            };
        } else if (std.mem.startsWith(u8, arg, "-") and !std.mem.eql(u8, arg, "-")) {
            var err_buf: [256]u8 = undefined;
            var ew = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &err_buf);
            try ew.interface.print("expand: unrecognized option '{s}'\n", .{arg});
            ew.interface.flush() catch {};
            return 1;
        } else {
            try files.append(allocator, arg);
        }
    }

    var out_buf: [16384]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &out_buf);
    const writer = &out_w.interface;

    if (files.items.len == 0) {
        expandFd(0, writer, &cfg) catch |err| {
            if (err == error.DiskFull or err == error.NoSpaceLeft or err == error.WriteFailed) return 1;
            return err;
        };
    } else {
        for (files.items) |file_path| {
            if (std.mem.eql(u8, file_path, "-")) {
                expandFd(0, writer, &cfg) catch return 1;
            } else {
                var zpath: [std.fs.max_path_bytes:0]u8 = undefined;
                if (file_path.len >= zpath.len) return 1;
                @memcpy(zpath[0..file_path.len], file_path);
                zpath[file_path.len] = 0;
                const fd = c.open(&zpath, c.O_RDONLY);
                if (fd < 0) {
                    var err_buf: [256]u8 = undefined;
                    var ew = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &err_buf);
                    try ew.interface.print("expand: {s}: No such file or directory\n", .{file_path});
                    ew.interface.flush() catch {};
                    return 1;
                }
                defer _ = c.close(fd);
                expandFd(fd, writer, &cfg) catch return 1;
            }
        }
    }

    out_w.interface.flush() catch return 1;
    return 0;
}
