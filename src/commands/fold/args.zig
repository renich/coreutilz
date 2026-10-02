const std = @import("std");
const errors = @import("../../utils/errors.zig");

pub const Mode = enum {
    columns,
    bytes,
    characters,
};

pub const Options = struct {
    mode: Mode = .columns,
    spaces: bool = false,
    width: usize = 80,
    files: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator) Options {
        _ = allocator;
        return .{
            .files = std.ArrayList([]const u8).empty,
            .mode = .columns,
            .spaces = false,
            .width = 80,
        };
    }

    pub fn deinit(self: *Options, allocator: std.mem.Allocator) void {
        self.files.deinit(allocator);
    }
};

pub const ParseResult = union(enum) {
    ok: Options,
    help,
    version,
    err: u8,
};

fn parseWidth(str: []const u8) ?usize {
    const val = std.fmt.parseUnsigned(usize, str, 10) catch return null;
    if (val == 0) return null;
    return val;
}

fn parseLegacyWidth(arg: []const u8) ?usize {
    if (arg.len < 2 or arg[0] != '-') return null;
    for (arg[1..]) |c| {
        if (!std.ascii.isDigit(c)) return null;
    }
    return parseWidth(arg[1..]);
}

fn handleLongOption(
    args: [][]const u8,
    i: *usize,
    opts: *Options,
    stderr: anytype,
) ?ParseResult {
    const arg = args[i.*];
    if (std.mem.eql(u8, arg, "--help")) return .help;
    if (std.mem.eql(u8, arg, "--version")) return .version;
    if (std.mem.eql(u8, arg, "--bytes")) {
        opts.mode = .bytes;
        return null;
    }
    if (std.mem.eql(u8, arg, "--characters")) {
        opts.mode = .characters;
        return null;
    }
    if (std.mem.eql(u8, arg, "--spaces")) {
        opts.spaces = true;
        return null;
    }
    if (std.mem.startsWith(u8, arg, "--width=")) {
        const val_str = arg["--width=".len..];
        if (parseWidth(val_str)) |w| {
            opts.width = w;
            return null;
        }
        errors.printError(stderr, "fold", "invalid number of columns") catch {};
        return .{ .err = 1 };
    }
    if (std.mem.eql(u8, arg, "--width")) {
        if (i.* + 1 < args.len) {
            i.* += 1;
            if (parseWidth(args[i.*])) |w| {
                opts.width = w;
                return null;
            }
        }
        errors.printError(stderr, "fold", "invalid number of columns") catch {};
        return .{ .err = 1 };
    }
    errors.printUnrecognizedOption(stderr, "fold", arg) catch {};
    return .{ .err = 1 };
}

fn handleShortOption(
    args: [][]const u8,
    i: *usize,
    opts: *Options,
    stderr: anytype,
) ?ParseResult {
    const arg = args[i.*];
    var j: usize = 1;
    while (j < arg.len) : (j += 1) {
        switch (arg[j]) {
            'b' => opts.mode = .bytes,
            'c' => opts.mode = .characters,
            's' => opts.spaces = true,
            'w' => {
                const rest = arg[j + 1 ..];
                if (rest.len > 0) {
                    if (parseWidth(rest)) |w| {
                        opts.width = w;
                        return null;
                    }
                } else if (i.* + 1 < args.len) {
                    i.* += 1;
                    if (parseWidth(args[i.*])) |w| {
                        opts.width = w;
                        return null;
                    }
                }
                errors.printError(stderr, "fold", "invalid number of columns") catch {};
                return .{ .err = 1 };
            },
            else => {
                errors.printInvalidOption(stderr, "fold", arg[j]) catch {};
                return .{ .err = 1 };
            },
        }
    }
    return null;
}

pub fn parseArgs(
    args: [][]const u8,
    allocator: std.mem.Allocator,
    stderr: anytype,
) ParseResult {
    var opts = Options.init(allocator);
    errdefer opts.deinit(allocator);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            while (i < args.len) : (i += 1) {
                opts.files.append(allocator, args[i]) catch return .{ .err = 1 };
            }
            break;
        }
        if (parseLegacyWidth(arg)) |w| {
            opts.width = w;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "--") and arg.len > 2) {
            if (handleLongOption(args, &i, &opts, stderr)) |res| return res;
            continue;
        }
        if (arg.len > 1 and arg[0] == '-') {
            if (handleShortOption(args, &i, &opts, stderr)) |res| return res;
            continue;
        }
        opts.files.append(allocator, arg) catch return .{ .err = 1 };
    }
    return .{ .ok = opts };
}
