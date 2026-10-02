const std = @import("std");
const errors = @import("../utils/errors.zig");
const args_mod = @import("tr/args.zig");
const set_parser = @import("tr/set_parser.zig");
const filter = @import("tr/filter.zig");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "tr";
pub const version: []const u8 = "0.1.0";

fn printHelp(writer: anytype) !void {
    try writer.print(
        \\Usage: {s} [OPTION]... SET1 [SET2]
        \\Translate, squeeze, and/or delete characters from standard input,
        \\writing to standard output.  SET1 and SET2 specify arrays of
        \\characters that control the action.
        \\
        \\  -c, -C, --complement    use the complement of SET1
        \\  -d, --delete            delete characters in SET1, do not translate
        \\  -s, --squeeze-repeats   replace each sequence of a repeated character
        \\                            that is listed in the last specified SET,
        \\                            with a single occurrence of that character
        \\  -t, --truncate-set1     first truncate SET1 to length of SET2
        \\      --help              display this help and exit
        \\      --version           output version information and exit
        \\
        \\GNU coreutils online help: <https://www.gnu.org/software/coreutils/>
        \\Full documentation <https://www.gnu.org/software/coreutils/tr>
        \\or available locally via: info '(coreutils) tr invocation'
        \\
    , .{name});
}

fn buildTranslationMap(
    tables: *filter.Tables,
    set1: []const u8,
    set2: []const u8,
    truncate_set1: bool,
) void {
    if (set2.len == 0) return;
    const limit = if (truncate_set1) @min(set1.len, set2.len) else set1.len;
    for (0..limit) |i| {
        const dest = if (i < set2.len) set2[i] else set2[set2.len - 1];
        tables.map[set1[i]] = dest;
    }
}

fn executeTr(
    opts: *const args_mod.Options,
    set1: []const u8,
    set2: ?[]const u8,
    stdout: anytype,
    stderr: anytype,
) !u8 {
    var tables = filter.Tables.init();
    if (set1.len == 0 and !opts.delete and !opts.squeeze) {
        filter.translateStream(&tables, stdout) catch return 1;
        return 0;
    }
    if (opts.delete and !opts.squeeze) {
        for (set1) |b| tables.delete[b] = true;
        filter.deleteStream(&tables, stdout) catch return 1;
        return 0;
    }
    if (opts.delete and opts.squeeze) {
        for (set1) |b| tables.delete[b] = true;
        if (set2) |s2| {
            for (s2) |b| tables.squeeze[b] = true;
        }
        filter.deleteAndSqueezeStream(&tables, stdout) catch return 1;
        return 0;
    }
    if (opts.squeeze and !opts.delete and set2 == null) {
        for (set1) |b| tables.squeeze[b] = true;
        filter.squeezeStream(&tables, stdout) catch return 1;
        return 0;
    }
    if (set2 == null or set2.?.len == 0) {
        errors.printError(stderr, name, "when not truncating set1, string2 must be non-empty") catch {};
        return 1;
    }
    const s2 = set2.?;
    buildTranslationMap(&tables, set1, s2, opts.truncate_set1);
    if (opts.squeeze) {
        for (s2) |b| tables.squeeze[b] = true;
        filter.translateAndSqueezeStream(&tables, stdout) catch return 1;
    } else {
        filter.translateStream(&tables, stdout) catch return 1;
    }
    return 0;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    _ = c.signal(c.SIGPIPE, c.SIG_DFL);

    var stdout_buf: [65536]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var stdout_w: std.Io.File.Writer = .initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var stderr_w: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &stdout_w.interface;
    const stderr = &stderr_w.interface;
    defer stdout.flush() catch {};
    defer stderr.flush() catch {};

    const res = args_mod.parseArgs(args, allocator, stderr);
    const opts = switch (res) {
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

    var case_spans = std.ArrayList(set_parser.CaseSpan).empty;
    defer case_spans.deinit(allocator);

    var set1 = set_parser.expandSet(opts.set1, 0, null, &case_spans, allocator, stderr) orelse return 1;
    defer allocator.free(set1);

    const has_class = set_parser.hasCharClass(opts.set1);

    if (opts.complement) {
        const comp = set_parser.complementSet(set1, allocator) orelse return 1;
        allocator.free(set1);
        set1 = comp;
    }

    var set2: ?[]u8 = null;
    defer if (set2) |s| allocator.free(s);
    if (opts.set2) |s2_str| {
        const spans_in = if (!opts.delete) case_spans.items else null;
        set2 = set_parser.expandSet(s2_str, set1.len, spans_in, null, allocator, stderr) orelse return 1;
        if (opts.complement and !opts.delete and has_class) {
            var distinct_count: usize = 0;
            var seen = [_]bool{false} ** 256;
            for (set2.?) |b| {
                if (!seen[b]) {
                    seen[b] = true;
                    distinct_count += 1;
                }
            }
            if (distinct_count > 1) {
                stderr.print("tr: when translating with complemented character classes,\nstring2 must map all characters in the domain to one\n", .{}) catch {};
                return 1;
            }
        }
        if (!opts.truncate_set1 and !opts.delete and set1.len > set2.?.len) {
            if (std.mem.endsWith(u8, s2_str, ":]")) {
                stderr.print("tr: when translating with string1 longer than string2,\nthe latter string must not end with a character class\n", .{}) catch {};
                return 1;
            }
        }
    }

    const code = try executeTr(&opts, set1, set2, stdout, stderr);
    stdout.flush() catch return 1;
    return code;
}
