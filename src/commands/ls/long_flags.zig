const std = @import("std");
const c = @import("../../compat/c.zig").c;
const types = @import("types.zig");

const Options = types.Options;
const Action = @import("args.zig").Action;

pub const MatchResult = union(enum) {
    not_matched,
    success,
    action: Action,
};

fn parseListingFormatFlag(arg: []const u8, opt: *Options) bool {
    if (std.mem.eql(u8, arg, "--all")) {
        opt.all = true;
        opt.almost_all = false;
    } else if (std.mem.eql(u8, arg, "--almost-all")) {
        opt.almost_all = true;
        opt.all = false;
    } else if (std.mem.eql(u8, arg, "--directory")) {
        opt.directory = true;
    } else if (std.mem.eql(u8, arg, "--recursive")) {
        opt.recursive = true;
    } else if (std.mem.eql(u8, arg, "--dereference")) {
        opt.dereference = true;
    } else if (std.mem.eql(u8, arg, "--dereference-command-line") or std.mem.eql(u8, arg, "--dereference-command-line-symlink-to-dir")) {
        opt.dereference_args = true;
    } else if (std.mem.startsWith(u8, "--group-directories-first", arg) and arg.len >= "--group".len) {
        opt.group_directories_first = true;
    } else if (std.mem.eql(u8, arg, "--context")) {
        opt.context = true;
    } else if (std.mem.eql(u8, arg, "--zero")) {
        opt.zero = true;
        opt.hide_control_chars = false;
    } else if (std.mem.eql(u8, arg, "--dired")) {
        opt.dired = true;
        opt.format = .long;
    } else {
        return false;
    }
    return true;
}

fn parseLongListingFlag(arg: []const u8, opt: *Options) bool {
    if (std.mem.eql(u8, arg, "--numeric-uid-gid")) {
        opt.numeric_ids = true;
        opt.format = .long;
    } else if (std.mem.eql(u8, arg, "--no-group")) {
        opt.omit_group = true;
    } else if (std.mem.eql(u8, arg, "--human-readable")) {
        opt.human_readable = true;
    } else if (std.mem.eql(u8, arg, "--full-time")) {
        opt.full_time = true;
        opt.format = .long;
    } else if (std.mem.eql(u8, arg, "--inode")) {
        opt.inode = true;
    } else if (std.mem.eql(u8, arg, "--size")) {
        opt.size_blocks = true;
    } else if (std.mem.eql(u8, arg, "--reverse")) {
        opt.reverse_sort = true;
    } else {
        return false;
    }
    return true;
}

pub fn parseDisplayFlag(arg: []const u8, opt: *Options) bool {
    return parseListingFormatFlag(arg, opt) or parseLongListingFlag(arg, opt);
}

pub fn parseQuotingFlag(arg: []const u8, opt: *Options) bool {
    if (std.mem.eql(u8, arg, "--quote-name")) {
        opt.quote_name = true;
        opt.quoting_style = .c_style;
        return true;
    }
    if (std.mem.eql(u8, arg, "--literal")) {
        opt.quoting_style = .literal;
        opt.hide_control_chars = false;
        return true;
    }
    if (std.mem.eql(u8, arg, "--escape")) {
        opt.quoting_style = .escape;
        return true;
    }
    if (std.mem.eql(u8, arg, "--hide-control-chars")) {
        opt.hide_control_chars = true;
        return true;
    }
    if (std.mem.eql(u8, arg, "--show-control-chars")) {
        opt.hide_control_chars = false;
        return true;
    }
    if (std.mem.startsWith(u8, arg, "--quoting-style=") or std.mem.startsWith(u8, arg, "--quoting=")) {
        const val = if (std.mem.startsWith(u8, arg, "--quoting-style="))
            arg["--quoting-style=".len..]
        else
            arg["--quoting=".len..];
        parseQuotingValue(val, opt);
        return true;
    }
    return false;
}

fn parseQuotingValue(val: []const u8, opt: *Options) void {
    if (std.mem.eql(u8, val, "c")) {
        opt.quote_name = true;
        opt.quoting_style = .c_style;
    } else if (std.mem.eql(u8, val, "escape")) {
        opt.quoting_style = .escape;
    } else if (std.mem.eql(u8, val, "shell-escape")) {
        opt.quoting_style = .shell_escape;
    } else if (std.mem.startsWith(u8, val, "shell-al")) {
        opt.quoting_style = .shell_always;
    } else if (std.mem.eql(u8, val, "shell")) {
        opt.quoting_style = .shell;
    } else if (std.mem.eql(u8, val, "locale")) {
        opt.quoting_style = .locale;
    } else if (std.mem.eql(u8, val, "clocale")) {
        opt.quoting_style = .clocale;
    } else {
        opt.quoting_style = .literal;
    }
}

pub fn parseFilterFlag(
    arg: []const u8,
    opt: *Options,
    arena: std.mem.Allocator,
    ignore_patterns: *std.ArrayList([]const u8),
    hide_patterns: *std.ArrayList([]const u8),
) !bool {
    if (std.mem.eql(u8, arg, "--ignore-backups")) {
        opt.ignore_backups = true;
        try ignore_patterns.append(arena, "*~");
        try ignore_patterns.append(arena, ".*~");
        return true;
    }
    if (std.mem.startsWith(u8, arg, "--ignore=")) {
        try ignore_patterns.append(arena, arg["--ignore=".len..]);
        return true;
    }
    if (std.mem.startsWith(u8, arg, "--hide=")) {
        try hide_patterns.append(arena, arg["--hide=".len..]);
        return true;
    }
    return false;
}

pub fn parseIndicatorFlag(arg: []const u8, opt: *Options, stderr: anytype, prog_name: []const u8) MatchResult {
    if (std.mem.eql(u8, arg, "--classify")) {
        opt.indicator = .classify;
        return .success;
    }
    if (std.mem.startsWith(u8, arg, "--classify=")) {
        const val = arg["--classify=".len..];
        if (std.mem.eql(u8, val, "never") or std.mem.eql(u8, val, "none")) opt.indicator = .none else if (std.mem.eql(u8, val, "always") or std.mem.eql(u8, val, "yes") or std.mem.eql(u8, val, "force")) opt.indicator = .classify else if (std.mem.eql(u8, val, "auto") or std.mem.eql(u8, val, "tty")) opt.indicator = if (c.isatty(c.STDOUT_FILENO) != 0) .classify else .none else {
            stderr.print("{s}: invalid argument '{s}' for '--classify'\nTry '{s} --help' for more information.\n", .{ prog_name, val, prog_name }) catch {};
            return .{ .action = Action{ .error_exit = 1 } };
        }
        return .success;
    }
    if (std.mem.eql(u8, arg, "--file-type")) {
        opt.indicator = .file_type;
        return .success;
    }
    if (std.mem.startsWith(u8, arg, "--indicator-style=")) {
        const val = arg["--indicator-style=".len..];
        if (std.mem.eql(u8, val, "none")) opt.indicator = .none else if (std.mem.eql(u8, val, "slash")) opt.indicator = .slash else if (std.mem.eql(u8, val, "file-type")) opt.indicator = .file_type else if (std.mem.eql(u8, val, "classify")) opt.indicator = .classify else {
            stderr.print("{s}: invalid argument '{s}' for '--indicator-style'\nTry '{s} --help' for more information.\n", .{ prog_name, val, prog_name }) catch {};
            return .{ .action = Action{ .error_exit = 1 } };
        }
        return .success;
    }
    return .not_matched;
}

pub fn parseColorAndHyperlink(arg: []const u8, opt: *Options, stderr: anytype, prog_name: []const u8) MatchResult {
    if (std.mem.startsWith(u8, "--hyperlink", arg) and arg.len >= "--hyper".len) {
        opt.hyperlink = true;
        return .success;
    }
    if (std.mem.startsWith(u8, arg, "--hyperlink=")) {
        opt.hyperlink = true;
        return .success;
    }
    if (std.mem.eql(u8, arg, "--color")) {
        opt.color = .always;
        return .success;
    }
    if (std.mem.startsWith(u8, arg, "--color=")) {
        const val = arg["--color=".len..];
        if (std.mem.eql(u8, val, "never") or std.mem.eql(u8, val, "no") or std.mem.eql(u8, val, "none")) opt.color = .never else if (std.mem.eql(u8, val, "always") or std.mem.eql(u8, val, "yes") or std.mem.eql(u8, val, "force")) opt.color = .always else if (std.mem.eql(u8, val, "auto") or std.mem.eql(u8, val, "tty")) opt.color = .auto else {
            stderr.print("{s}: invalid argument '{s}' for '--color'\nTry '{s} --help' for more information.\n", .{ prog_name, val, prog_name }) catch {};
            return .{ .action = Action{ .error_exit = 1 } };
        }
        return .success;
    }
    return .not_matched;
}

pub fn parseSortAndSize(arg: []const u8, opt: *Options, stderr: anytype, prog_name: []const u8) MatchResult {
    if (std.mem.startsWith(u8, arg, "--width=")) {
        const val = arg["--width=".len..];
        opt.term_width = types.parseWidth(val) catch {
            stderr.print("{s}: invalid line width: '{s}'\nTry '{s} --help' for more information.\n", .{ prog_name, val, prog_name }) catch {};
            return .{ .action = Action{ .error_exit = 2 } };
        };
        return .success;
    }
    if (std.mem.startsWith(u8, arg, "--tabsize=")) {
        opt.tab_size = std.fmt.parseInt(usize, arg["--tabsize=".len..], 10) catch 8;
        return .success;
    }
    if (std.mem.startsWith(u8, arg, "--sort=")) {
        const val = arg["--sort=".len..];
        if (std.mem.eql(u8, val, "none")) opt.sort = .none else if (std.mem.eql(u8, val, "time")) opt.sort = .time else if (std.mem.eql(u8, val, "size")) opt.sort = .size else if (std.mem.eql(u8, val, "extension")) opt.sort = .extension else if (std.mem.eql(u8, val, "version")) opt.sort = .version else if (std.mem.eql(u8, val, "width")) opt.sort = .width else {
            stderr.print("{s}: invalid argument '{s}' for '--sort'\nTry '{s} --help' for more information.\n", .{ prog_name, val, prog_name }) catch {};
            return .{ .action = Action{ .error_exit = 2 } };
        }
        return .success;
    }
    if (std.mem.startsWith(u8, arg, "--time-style=")) return parseTimeStyle(arg["--time-style=".len..], opt, stderr, prog_name);
    if (std.mem.startsWith(u8, arg, "--block-size=")) {
        if (types.parseBlockSize(arg["--block-size=".len..])) |bs| {
            opt.block_size = bs;
            opt.disk_block_size = bs;
        }
        return .success;
    }
    if (std.mem.startsWith(u8, arg, "--time=")) return .success;
    return .not_matched;
}

fn parseTimeStyle(val: []const u8, opt: *Options, stderr: anytype, prog_name: []const u8) MatchResult {
    opt.time_style = val;
    if (std.mem.eql(u8, val, "full-iso") or std.mem.eql(u8, val, "posix-full-iso")) {
        opt.full_time = true;
    } else if (std.mem.eql(u8, val, "long-iso") or std.mem.eql(u8, val, "posix-long-iso") or
        std.mem.eql(u8, val, "iso") or std.mem.eql(u8, val, "posix-iso") or
        std.mem.eql(u8, val, "locale") or std.mem.eql(u8, val, "posix-locale") or
        std.mem.startsWith(u8, val, "+"))
    {
        // Valid
    } else {
        stderr.print(
            \\{s}: invalid argument '{s}' for 'time style'
            \\Valid arguments are:
            \\  - [posix-]full-iso
            \\  - [posix-]long-iso
            \\  - [posix-]iso
            \\  - [posix-]locale
            \\  - +FORMAT (e.g., +%H:%M) for a 'date'-style format
            \\Try '{s} --help' for more information.
            \\
        , .{ prog_name, val, prog_name }) catch {};
        return .{ .action = Action{ .error_exit = 2 } };
    }
    return .success;
}
