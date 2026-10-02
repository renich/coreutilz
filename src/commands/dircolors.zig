const std = @import("std");
const c = @import("../compat/c.zig").c;
const database = @import("dircolors/database.zig");

pub const name: []const u8 = "dircolors";
pub const version: []const u8 = "0.1.0";

const slack_codes = [_][]const u8{
    "NORMAL",        "NORM",      "FILE",           "RESET",   "DIR",                   "LNK",    "LINK",
    "SYMLINK",       "ORPHAN",    "MISSING",        "FIFO",    "PIPE",                  "SOCK",   "BLK",
    "BLOCK",         "CHR",       "CHAR",           "DOOR",    "EXEC",                  "LEFT",   "LEFTCODE",
    "RIGHT",         "RIGHTCODE", "END",            "ENDCODE", "SUID",                  "SETUID", "SGID",
    "SETGID",        "STICKY",    "OTHER_WRITABLE", "OWR",     "STICKY_OTHER_WRITABLE", "OWT",    "CAPABILITY",
    "MULTIHARDLINK", "CLRTOEOL",
};

const ls_codes = [_][]const u8{
    "no", "no", "fi", "rs", "di", "ln", "ln",
    "ln", "or", "mi", "pi", "pi", "so", "bd",
    "bd", "cd", "cd", "do", "ex", "lc", "lc",
    "rc", "rc", "ec", "ec", "su", "su", "sg",
    "sg", "st", "ow", "ow", "tw", "tw", "ca",
    "mh", "cl",
};

const ShellType = enum { sh, csh };
const State = enum { st_termno, st_termyes, st_termsure, st_global };

const DircolorsOptions = struct {
    shell: ?ShellType = null,
    print_database: bool = false,
    print_ls_colors: bool = false,
};

fn isCsh() bool {
    const s = std.mem.span(c.getenv("SHELL") orelse return false);
    const base = std.fs.path.basename(s);
    return std.mem.eql(u8, base, "csh") or std.mem.eql(u8, base, "tcsh");
}

fn appendQuoted(str: []const u8, print_ls: bool, out: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator) !void {
    var need_backslash = true;
    for (str) |ch| {
        if (!print_ls) {
            switch (ch) {
                '\'' => {
                    try out.appendSlice(alloc, "'\\''");
                    need_backslash = true;
                    continue;
                },
                '\\', '^' => {
                    need_backslash = !need_backslash;
                },
                ':', '=' => {
                    if (need_backslash) try out.append(alloc, '\\');
                    need_backslash = true;
                },
                else => {
                    need_backslash = true;
                },
            }
        }
        try out.append(alloc, ch);
    }
}

fn appendEntry(prefix: u8, item: []const u8, arg: []const u8, print_ls: bool, out: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator) !void {
    if (print_ls) {
        try appendQuoted("\x1b[", print_ls, out, alloc);
        try appendQuoted(arg, print_ls, out, alloc);
        try out.append(alloc, 'm');
    }
    if (prefix != 0) try out.append(alloc, prefix);
    try appendQuoted(item, print_ls, out, alloc);
    try out.append(alloc, if (print_ls) '\t' else '=');
    try appendQuoted(arg, print_ls, out, alloc);
    if (print_ls) try appendQuoted("\x1b[0m", print_ls, out, alloc);
    try out.append(alloc, if (print_ls) '\n' else ':');
}

fn termMatch(pattern: []const u8, val: [*:0]const u8, alloc: std.mem.Allocator) bool {
    const pat_z = alloc.dupeZ(u8, pattern) catch return false;
    defer alloc.free(pat_z);
    return c.fnmatch(pat_z.ptr, val, 0) == 0;
}

fn parseTokensFromLine(line: []const u8) ?struct { []const u8, ?[]const u8 } {
    var p: usize = 0;
    while (p < line.len and std.ascii.isWhitespace(line[p])) : (p += 1) {}
    if (p >= line.len or line[p] == '#') return null;
    const kw_start = p;
    while (p < line.len and !std.ascii.isWhitespace(line[p])) : (p += 1) {}
    const kw = line[kw_start..p];
    while (p < line.len and std.ascii.isWhitespace(line[p])) : (p += 1) {}
    if (p >= line.len or line[p] == '#') return .{ kw, null };
    const arg_start = p;
    while (p < line.len and line[p] != '#') : (p += 1) {}
    var arg_end = p;
    while (arg_end > arg_start and std.ascii.isWhitespace(line[arg_end - 1])) : (arg_end -= 1) {}
    return .{ kw, line[arg_start..arg_end] };
}

fn handleItem(kw: []const u8, arg: []const u8, print_ls: bool, out: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator) bool {
    if (kw[0] == '.') {
        appendEntry('*', kw, arg, print_ls, out, alloc) catch return false;
        return true;
    } else if (kw[0] == '*') {
        appendEntry(0, kw, arg, print_ls, out, alloc) catch return false;
        return true;
    } else if (std.ascii.eqlIgnoreCase(kw, "OPTIONS") or std.ascii.eqlIgnoreCase(kw, "COLOR") or std.ascii.eqlIgnoreCase(kw, "EIGHTBIT")) {
        return true;
    }
    for (slack_codes, 0..) |sc, i| {
        if (std.ascii.eqlIgnoreCase(kw, sc)) {
            appendEntry(0, ls_codes[i], arg, print_ls, out, alloc) catch return false;
            return true;
        }
    }
    return false;
}

fn processLine(kw: []const u8, arg_opt: ?[]const u8, state: *State, line_num: usize, name_str: []const u8, print_ls: bool, out: *std.ArrayListUnmanaged(u8), stderr: anytype, alloc: std.mem.Allocator) bool {
    const arg = arg_opt orelse {
        stderr.print("dircolors: {s}:{d}: invalid line;  missing second token\n", .{ name_str, line_num }) catch {};
        return false;
    };
    const term_c = c.getenv("TERM");
    const term: [*:0]const u8 = if (term_c) |t| t else "none";
    const cterm_c = c.getenv("COLORTERM");
    const colorterm: [*:0]const u8 = if (cterm_c) |ct| ct else "";
    if (std.ascii.eqlIgnoreCase(kw, "TERM")) {
        if (state.* != .st_termsure) state.* = if (termMatch(arg, term, alloc)) .st_termsure else .st_termno;
        return true;
    } else if (std.ascii.eqlIgnoreCase(kw, "COLORTERM")) {
        if (state.* != .st_termsure) state.* = if (termMatch(arg, colorterm, alloc)) .st_termsure else .st_termno;
        return true;
    }
    if (state.* == .st_termsure) state.* = .st_termyes;
    if (state.* != .st_termno and handleItem(kw, arg, print_ls, out, alloc)) return true;
    if (state.* == .st_termsure or state.* == .st_termyes) {
        stderr.print("dircolors: {s}:{d}: unrecognized keyword {s}\n", .{ name_str, line_num, kw }) catch {};
        return false;
    }
    return true;
}

fn parseContent(content: []const u8, name_str: []const u8, print_ls: bool, out: *std.ArrayListUnmanaged(u8), stderr: anytype, alloc: std.mem.Allocator) bool {
    var state: State = .st_global;
    var line_it = std.mem.splitScalar(u8, content, '\n');
    var line_num: usize = 0;
    var ok = true;
    while (line_it.next()) |line| {
        line_num += 1;
        if (parseTokensFromLine(line)) |toks| {
            if (!processLine(toks[0], toks[1], &state, line_num, name_str, print_ls, out, stderr, alloc)) ok = false;
        }
    }
    return ok;
}

fn readInputFile(path: []const u8, alloc: std.mem.Allocator, stderr: anytype) !?[]const u8 {
    var fd: c_int = 0;
    var should_close = false;
    if (!std.mem.eql(u8, path, "-")) {
        const pz = try alloc.dupeZ(u8, path);
        defer alloc.free(pz);
        fd = c.open(pz.ptr, c.O_RDONLY);
        if (fd < 0) {
            stderr.print("dircolors: '{s}': No such file or directory\n", .{path}) catch {};
            return null;
        }
        should_close = true;
    }
    defer if (should_close) {
        _ = c.close(fd);
    };
    var list: std.ArrayListUnmanaged(u8) = .empty;
    defer list.deinit(alloc);
    var buf: [16384]u8 = undefined;
    while (true) {
        const n = c.read(fd, &buf, buf.len);
        if (n <= 0) break;
        try list.appendSlice(alloc, buf[0..@intCast(n)]);
    }
    return try list.toOwnedSlice(alloc);
}

fn parseOption(arg: []const u8, opts: *DircolorsOptions, stderr: anytype) bool {
    if (std.mem.eql(u8, arg, "-b") or std.mem.eql(u8, arg, "--sh") or std.mem.eql(u8, arg, "--bourne-shell")) opts.shell = .sh else if (std.mem.eql(u8, arg, "-c") or std.mem.eql(u8, arg, "--csh") or std.mem.eql(u8, arg, "--c-shell")) opts.shell = .csh else if (std.mem.eql(u8, arg, "-p") or (std.mem.startsWith(u8, "--print-database", arg) and arg.len >= "--print-d".len)) opts.print_database = true else if (std.mem.startsWith(u8, "--print-ls-colors", arg) and arg.len >= "--print-l".len) opts.print_ls_colors = true else {
        stderr.print("dircolors: unrecognized option '{s}'\nTry 'dircolors --help' for more information.\n", .{arg}) catch {};
        return false;
    }
    return true;
}

fn checkClashes(opts: *const DircolorsOptions, file_arg: ?[]const u8, stderr: anytype) bool {
    if (opts.print_database and opts.print_ls_colors) {
        stderr.print("dircolors: options --print-database and --print-ls-colors are mutually exclusive\nTry 'dircolors --help' for more information.\n", .{}) catch {};
        return false;
    }
    if ((opts.print_database or opts.print_ls_colors) and opts.shell != null) {
        stderr.print("dircolors: the options to output non shell syntax,\nand to select a shell syntax are mutually exclusive\nTry 'dircolors --help' for more information.\n", .{}) catch {};
        return false;
    }
    if (opts.print_database and file_arg != null) {
        stderr.print("dircolors: extra operand '{s}'\nfile operands cannot be combined with --print-database (-p)\nTry 'dircolors --help' for more information.\n", .{file_arg.?}) catch {};
        return false;
    }
    return true;
}

fn parseArgs(args: [][]const u8, opts: *DircolorsOptions, file_arg: *?[]const u8, stdout: anytype, stderr: anytype) !?u8 {
    var past = false;
    for (args[1..]) |arg| {
        if (past or !std.mem.startsWith(u8, arg, "-") or std.mem.eql(u8, arg, "-")) {
            if (file_arg.* == null) file_arg.* = arg else {
                stderr.print("dircolors: extra operand '{s}'\nTry 'dircolors --help' for more information.\n", .{arg}) catch {};
                return 1;
            }
        } else if (std.mem.eql(u8, arg, "--")) {
            past = true;
        } else if (std.mem.eql(u8, arg, "--help")) {
            try stdout.print("Usage: dircolors [OPTION]... [FILE]\nOutput commands to set the LS_COLORS environment variable.\n", .{});
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try stdout.print("dircolors (coreutilz) {s}\n", .{version});
            return 0;
        } else if (!parseOption(arg, opts, stderr)) return 1;
    }
    if (!checkClashes(opts, file_arg.*, stderr)) return 1;
    return null;
}

fn emitOutput(opts: DircolorsOptions, items: []const u8, stdout: anytype) !void {
    if (opts.print_ls_colors) {
        try stdout.print("{s}", .{items});
    } else {
        const sh = opts.shell orelse if (isCsh()) ShellType.csh else ShellType.sh;
        switch (sh) {
            .sh => try stdout.print("LS_COLORS='{s}';\nexport LS_COLORS\n", .{items}),
            .csh => try stdout.print("setenv LS_COLORS '{s}'\n", .{items}),
        }
    }
}

fn parseSource(file_arg: ?[]const u8, print_ls: bool, out: *std.ArrayListUnmanaged(u8), alloc: std.mem.Allocator, stderr: anytype) !bool {
    if (file_arg) |f| {
        const content = (try readInputFile(f, alloc, stderr)) orelse return false;
        defer alloc.free(content);
        return parseContent(content, f, print_ls, out, stderr, alloc);
    }
    return parseContent(database.DEFAULT_DATABASE, "<internal>", print_ls, out, stderr, alloc);
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &out_w.interface;
    const stderr = &err_w.interface;

    var opts = DircolorsOptions{};
    var file_arg: ?[]const u8 = null;
    if (try parseArgs(args, &opts, &file_arg, stdout, stderr)) |rc| {
        stdout.flush() catch return 1;
        stderr.flush() catch {};
        return rc;
    }
    if (opts.print_database) {
        try stdout.print("{s}", .{database.DEFAULT_DATABASE});
        stdout.flush() catch return 1;
        return 0;
    }

    var out_buf: std.ArrayListUnmanaged(u8) = .empty;
    defer out_buf.deinit(allocator);

    if (!try parseSource(file_arg, opts.print_ls_colors, &out_buf, allocator, stderr)) {
        stderr.flush() catch {};
        return 1;
    }
    try emitOutput(opts, out_buf.items, stdout);
    stdout.flush() catch return 1;
    stderr.flush() catch {};
    return 0;
}
