const std = @import("std");

pub const ShredOptions = struct {
    force: bool = false,
    iterations: usize = 3,
    remove: bool = false,
    verbose: bool = false,
    zero: bool = false,
    exact: bool = false,
    custom_size: ?usize = null,
    random_source: ?[]const u8 = null,
};

pub fn parseSize(str: []const u8, stderr: anytype) ?usize {
    if (str.len == 0 or str[0] == '-') {
        stderr.print("shred: invalid file size: '{s}'\n", .{str}) catch {};
        return null;
    }
    var base: u8 = 10;
    var start: usize = 0;
    if (str.len >= 2 and str[0] == '0' and (str[1] == 'x' or str[1] == 'X')) {
        base = 16;
        start = 2;
    } else if (str.len >= 2 and str[0] == '0' and (str[1] >= '0' and str[1] <= '7')) {
        base = 8;
        start = 1;
    }
    var end = start;
    while (end < str.len) : (end += 1) {
        const ch = str[end];
        if (base == 16) {
            if (!std.ascii.isHex(ch)) break;
        } else if (base == 8) {
            if (ch < '0' or ch > '7') break;
        } else {
            if (!std.ascii.isDigit(ch)) break;
        }
    }
    if (end == start) {
        stderr.print("shred: invalid file size: '{s}'\n", .{str}) catch {};
        return null;
    }
    const val = std.fmt.parseInt(usize, str[start..end], base) catch {
        stderr.print("shred: invalid file size: '{s}'\n", .{str}) catch {};
        return null;
    };
    const suff = str[end..];
    const mult = parseMult(suff, str, stderr) orelse return null;
    return val * mult;
}

fn parseMult(suff: []const u8, orig: []const u8, stderr: anytype) ?usize {
    if (suff.len == 0) return 1;
    if (std.mem.eql(u8, suff, "c")) return 1;
    if (std.mem.eql(u8, suff, "w")) return 2;
    if (std.mem.eql(u8, suff, "b")) return 512;
    if (std.mem.eql(u8, suff, "kB")) return 1000;
    if (std.mem.eql(u8, suff, "K") or std.mem.eql(u8, suff, "k") or std.mem.eql(u8, suff, "KiB")) return 1024;
    if (std.mem.eql(u8, suff, "MB")) return 1000 * 1000;
    if (std.mem.eql(u8, suff, "M") or std.mem.eql(u8, suff, "m") or std.mem.eql(u8, suff, "MiB")) return 1024 * 1024;
    if (std.mem.eql(u8, suff, "GB")) return 1000 * 1000 * 1000;
    if (std.mem.eql(u8, suff, "G") or std.mem.eql(u8, suff, "g") or std.mem.eql(u8, suff, "GiB")) return 1024 * 1024 * 1024;
    stderr.print("shred: invalid file size: '{s}'\n", .{orig}) catch {};
    return null;
}

fn parseLongOption(arg: []const u8, i: *usize, args: [][]const u8, opts: *ShredOptions, stderr: anytype) bool {
    if (std.mem.eql(u8, arg, "--force")) {
        opts.force = true;
    } else if (std.mem.startsWith(u8, arg, "--remove")) {
        if (std.mem.startsWith(u8, arg, "--remove=")) {
            const how = arg["--remove=".len..];
            if (!std.mem.eql(u8, how, "unlink") and !std.mem.eql(u8, how, "wipe") and !std.mem.eql(u8, how, "wipesync")) {
                stderr.print("shred: invalid --remove option: '{s}'\n", .{how}) catch {};
                return false;
            }
        }
        opts.remove = true;
    } else if (std.mem.eql(u8, arg, "--verbose")) {
        opts.verbose = true;
    } else if (std.mem.eql(u8, arg, "--exact")) {
        opts.exact = true;
    } else if (std.mem.eql(u8, arg, "--zero")) {
        opts.zero = true;
    } else if (std.mem.startsWith(u8, arg, "--iterations=")) {
        opts.iterations = std.fmt.parseInt(usize, arg["--iterations=".len..], 10) catch 3;
    } else if (std.mem.startsWith(u8, arg, "--size=")) {
        opts.custom_size = parseSize(arg["--size=".len..], stderr) orelse return false;
    } else if (std.mem.startsWith(u8, arg, "--random-source=")) {
        opts.random_source = arg["--random-source=".len..];
    } else if (std.mem.eql(u8, arg, "--random-source")) {
        if (i.* + 1 < args.len) {
            i.* += 1;
            opts.random_source = args[i.*];
        }
    } else {
        stderr.print("shred: unrecognized option '{s}'\nTry 'shred --help' for more information.\n", .{arg}) catch {};
        return false;
    }
    return true;
}

fn parseShortOption(arg: []const u8, i: *usize, args: [][]const u8, opts: *ShredOptions, stderr: anytype) bool {
    var idx: usize = 1;
    while (idx < arg.len) : (idx += 1) {
        const c_opt = arg[idx];
        switch (c_opt) {
            'f' => opts.force = true,
            'u' => opts.remove = true,
            'v' => opts.verbose = true,
            'x' => opts.exact = true,
            'z' => opts.zero = true,
            'n' => {
                const val = if (idx + 1 < arg.len) arg[idx + 1 ..] else if (i.* + 1 < args.len) blk: {
                    i.* += 1;
                    break :blk args[i.*];
                } else "3";
                opts.iterations = std.fmt.parseInt(usize, val, 10) catch 3;
                return true;
            },
            's' => {
                const val = if (idx + 1 < arg.len) arg[idx + 1 ..] else if (i.* + 1 < args.len) blk: {
                    i.* += 1;
                    break :blk args[i.*];
                } else "";
                opts.custom_size = parseSize(val, stderr) orelse return false;
                return true;
            },
            else => {
                stderr.print("shred: unrecognized option '{s}'\nTry 'shred --help' for more information.\n", .{arg}) catch {};
                return false;
            },
        }
    }
    return true;
}

pub fn parseArgs(args: [][]const u8, opts: *ShredOptions, files: *std.ArrayListUnmanaged([]const u8), alloc: std.mem.Allocator, stdout: anytype, stderr: anytype) !?u8 {
    var i: usize = 1;
    var past = false;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (past or !std.mem.startsWith(u8, arg, "-") or std.mem.eql(u8, arg, "-")) {
            try files.append(alloc, arg);
        } else if (std.mem.eql(u8, arg, "--")) {
            past = true;
        } else if (std.mem.eql(u8, arg, "--help")) {
            try stdout.print("Usage: shred [OPTION]... FILE...\nOverwrite the specified FILE(s) repeatedly.\n", .{});
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try stdout.print("shred (coreutilz) 0.1.0\n", .{});
            return 0;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            if (!parseLongOption(arg, &i, args, opts, stderr)) return 1;
        } else {
            if (!parseShortOption(arg, &i, args, opts, stderr)) return 1;
        }
    }
    return null;
}
