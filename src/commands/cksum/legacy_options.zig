const std = @import("std");
const opt_mod = @import("options.zig");

pub const LegacyParsedArgs = struct {
    check: bool = false,
    tag_seen: bool = false,
    tagged: bool = false,
    binary: bool = false,
    binary_seen: bool = false,
    text_seen: bool = false,
    zero: bool = false,
    zero_seen: bool = false,
    quiet: bool = false,
    status_only: bool = false,
    strict: bool = false,
    warn: bool = false,
    ignore_missing: bool = false,
    length_str: ?[]const u8 = null,
    length_bits: ?usize = null,
    files: std.ArrayList([]const u8),
};

pub const LegacyParseResult = union(enum) {
    parsed: LegacyParsedArgs,
    help: void,
    version: void,
    err: void,
};

const LongAction = enum {
    help,
    version,
    err,
};

pub fn parseLegacyArgs(
    cmd_name: []const u8,
    accepts_length: bool,
    args: [][]const u8,
    allocator: std.mem.Allocator,
) !LegacyParseResult {
    var p = LegacyParsedArgs{ .files = .empty };
    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            while (i < args.len) : (i += 1) try p.files.append(allocator, args[i]);
            break;
        }
        if (std.mem.startsWith(u8, arg, "--")) {
            if (handleLong(cmd_name, arg, &i, args, accepts_length, &p)) |act| {
                p.files.deinit(allocator);
                return switch (act) {
                    .help => .help,
                    .version => .version,
                    .err => .err,
                };
            }
        } else if (arg.len > 1 and arg[0] == '-') {
            if (!handleShort(cmd_name, arg, &i, args, accepts_length, &p)) {
                p.files.deinit(allocator);
                return .err;
            }
        } else {
            try p.files.append(allocator, arg);
        }
    }
    return .{ .parsed = p };
}

fn handleLong(
    cmd_name: []const u8,
    arg: []const u8,
    i: *usize,
    args: [][]const u8,
    accepts_length: bool,
    p: *LegacyParsedArgs,
) ?LongAction {
    if (std.mem.eql(u8, arg, "--help")) {
        return .help;
    } else if (std.mem.eql(u8, arg, "--version")) {
        return .version;
    } else if (std.mem.eql(u8, arg, "--check")) {
        p.check = true;
    } else if (std.mem.eql(u8, arg, "--tag")) {
        p.tagged = true;
        p.tag_seen = true;
    } else if (std.mem.eql(u8, arg, "--binary")) {
        p.binary = true;
        p.binary_seen = true;
    } else if (std.mem.eql(u8, arg, "--text")) {
        p.binary = false;
        p.text_seen = true;
    } else if (std.mem.eql(u8, arg, "--zero")) {
        p.zero = true;
        p.zero_seen = true;
    } else {
        return handleLongRest(cmd_name, arg, i, args, accepts_length, p);
    }
    return null;
}

fn handleLengthOption(cmd_name: []const u8, arg: []const u8, i: *usize, args: [][]const u8, p: *LegacyParsedArgs) ?LongAction {
    if (std.mem.startsWith(u8, arg, "--length=")) {
        p.length_str = arg[9..];
        return null;
    }
    i.* += 1;
    if (i.* >= args.len) {
        opt_mod.emitError(cmd_name, "option '--length' requires an argument", .{});
        opt_mod.emitTryHelp(cmd_name);
        return .err;
    }
    p.length_str = args[i.*];
    return null;
}

fn handleLongRest(
    cmd_name: []const u8,
    arg: []const u8,
    i: *usize,
    args: [][]const u8,
    accepts_length: bool,
    p: *LegacyParsedArgs,
) ?LongAction {
    if (std.mem.eql(u8, arg, "--quiet")) {
        p.status_only = false;
        p.warn = false;
        p.quiet = true;
    } else if (std.mem.eql(u8, arg, "--status")) {
        p.status_only = true;
        p.warn = false;
        p.quiet = false;
    } else if (std.mem.eql(u8, arg, "--strict")) {
        p.strict = true;
    } else if (std.mem.eql(u8, arg, "--warn")) {
        p.status_only = false;
        p.warn = true;
        p.quiet = false;
    } else if (std.mem.eql(u8, arg, "--ignore-missing")) {
        p.ignore_missing = true;
    } else if (accepts_length and (std.mem.startsWith(u8, arg, "--length=") or std.mem.eql(u8, arg, "--length"))) {
        return handleLengthOption(cmd_name, arg, i, args, p);
    } else {
        opt_mod.emitError(cmd_name, "unrecognized option '{s}'", .{arg});
        opt_mod.emitTryHelp(cmd_name);
        return .err;
    }
    return null;
}

fn handleShortLength(cmd_name: []const u8, arg: []const u8, j: usize, i: *usize, args: [][]const u8, p: *LegacyParsedArgs) bool {
    const val = if (j + 1 < arg.len) arg[j + 1 ..] else blk: {
        i.* += 1;
        if (i.* >= args.len) {
            opt_mod.emitError(cmd_name, "option requires an argument -- 'l'", .{});
            opt_mod.emitTryHelp(cmd_name);
            return false;
        }
        break :blk args[i.*];
    };
    p.length_str = val;
    return true;
}

fn handleShortFlag(opt: u8, p: *LegacyParsedArgs) bool {
    switch (opt) {
        'c' => p.check = true,
        'b' => {
            p.binary = true;
            p.binary_seen = true;
        },
        't' => {
            p.binary = false;
            p.text_seen = true;
        },
        'z' => {
            p.zero = true;
            p.zero_seen = true;
        },
        'w' => {
            p.status_only = false;
            p.warn = true;
            p.quiet = false;
        },
        else => return false,
    }
    return true;
}

fn handleShort(
    cmd_name: []const u8,
    arg: []const u8,
    i: *usize,
    args: [][]const u8,
    accepts_length: bool,
    p: *LegacyParsedArgs,
) bool {
    var j: usize = 1;
    while (j < arg.len) : (j += 1) {
        if (handleShortFlag(arg[j], p)) continue;
        switch (arg[j]) {
            'l' => if (accepts_length) {
                if (!handleShortLength(cmd_name, arg, j, i, args, p)) return false;
                break;
            } else {
                opt_mod.emitError(cmd_name, "invalid option -- 'l'", .{});
                opt_mod.emitTryHelp(cmd_name);
                return false;
            },
            else => {
                opt_mod.emitError(cmd_name, "invalid option -- '{c}'", .{arg[j]});
                opt_mod.emitTryHelp(cmd_name);
                return false;
            },
        }
    }
    return true;
}
