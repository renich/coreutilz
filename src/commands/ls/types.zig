const std = @import("std");
const c = @import("../../compat/c.zig").c;

pub const FormatMode = enum {
    columns,
    across,
    one_per_line,
    comma,
    long,
};

pub const SortMode = enum {
    none,
    name,
    time,
    size,
    extension,
    version,
    width,
};

pub const IndicatorStyle = enum {
    none,
    classify,
    slash,
    file_type,
};

pub const QuotingStyle = enum {
    literal,
    shell,
    shell_always,
    shell_escape,
    c_style,
    escape,
    locale,
    clocale,
};

pub const ColorMode = enum {
    never,
    auto,
    always,
};

pub const TimeType = enum {
    mtime,
    ctime,
    atime,
};

pub const Options = struct {
    format: FormatMode = .columns,
    sort: SortMode = .name,
    reverse_sort: bool = false,
    all: bool = false,
    almost_all: bool = false,
    directory: bool = false,
    recursive: bool = false,
    numeric_ids: bool = false,
    human_readable: bool = false,
    omit_owner: bool = false,
    omit_group: bool = false,
    full_time: bool = false,
    quote_name: bool = false,
    inode: bool = false,
    size_blocks: bool = false,
    indicator: IndicatorStyle = .none,
    term_width: usize = 80,
    dereference: bool = false,
    dereference_args: bool = false,
    ignore_backups: bool = false,
    group_directories_first: bool = false,
    zero: bool = false,
    dired: bool = false,
    hyperlink: bool = false,
    color: ColorMode = .never,
    time_type: TimeType = .mtime,
    tab_size: usize = 8,
    quoting_style: QuotingStyle = .literal,
    hide_control_chars: bool = false,
    ignore_patterns: []const []const u8 = &.{},
    hide_patterns: []const []const u8 = &.{},
    context: bool = false,
    time_style: ?[]const u8 = null,
    block_size: u64 = 1,
    disk_block_size: u64 = 1024,

    pub fn formatNeedsStat(self: *const Options) bool {
        return self.format == .long or
            self.inode or
            self.size_blocks or
            self.sort == .time or
            self.sort == .size or
            self.hyperlink or
            self.context;
    }
};

pub const FileEntry = struct {
    name: []const u8,
    full_path: []const u8,
    stat: c.struct_stat,
    is_dir: bool,
    is_symlink: bool,
    link_target: ?[]const u8 = null,
    has_stat_error: bool = false,
    is_dir_or_link_to_dir: bool = false,
    is_broken_link: bool = false,
};

pub fn parseWidth(str: []const u8) !usize {
    if (str.len == 0 or str[0] == '-') return error.Invalid;
    if (str.len > 1 and str[0] == '0' and str[1] != 'x' and str[1] != 'X') {
        return std.fmt.parseInt(usize, str, 8) catch |err| switch (err) {
            error.Overflow => std.math.maxInt(usize),
            else => error.Invalid,
        };
    }
    return std.fmt.parseInt(usize, str, 10) catch |err| switch (err) {
        error.Overflow => std.math.maxInt(usize),
        else => error.Invalid,
    };
}

pub fn parseBlockSize(str: []const u8) ?u64 {
    if (str.len == 0) return null;
    var num_len: usize = 0;
    while (num_len < str.len and std.ascii.isDigit(str[num_len])) : (num_len += 1) {}
    const base_num: u64 = if (num_len > 0)
        std.fmt.parseInt(u64, str[0..num_len], 10) catch return null
    else
        1;
    const suffix = str[num_len..];
    var multiplier: u64 = 1;
    if (suffix.len == 0) {
        multiplier = 1;
    } else if (std.mem.eql(u8, suffix, "K") or std.mem.eql(u8, suffix, "KiB") or std.mem.eql(u8, suffix, "k")) {
        multiplier = 1024;
    } else if (std.mem.eql(u8, suffix, "KB")) {
        multiplier = 1000;
    } else if (std.mem.eql(u8, suffix, "M") or std.mem.eql(u8, suffix, "MiB")) {
        multiplier = 1024 * 1024;
    } else if (std.mem.eql(u8, suffix, "MB")) {
        multiplier = 1000 * 1000;
    } else if (std.mem.eql(u8, suffix, "G") or std.mem.eql(u8, suffix, "GiB")) {
        multiplier = 1024 * 1024 * 1024;
    } else if (std.mem.eql(u8, suffix, "GB")) {
        multiplier = 1000 * 1000 * 1000;
    } else if (std.mem.eql(u8, suffix, "T") or std.mem.eql(u8, suffix, "TiB")) {
        multiplier = 1024 * 1024 * 1024 * 1024;
    } else {
        return null;
    }
    return base_num * multiplier;
}

fn parseShortDisplayFlag(ch: u8, opt: *Options) bool {
    switch (ch) {
        'a' => {
            opt.all = true;
            opt.almost_all = false;
        },
        'A' => {
            opt.almost_all = true;
            opt.all = false;
        },
        'd' => opt.directory = true,
        'D' => {
            opt.dired = true;
            opt.format = .long;
        },
        'R' => opt.recursive = true,
        'L' => opt.dereference = true,
        'H' => opt.dereference_args = true,
        'B' => opt.ignore_backups = true,
        'z' => opt.zero = true,
        'Z' => opt.context = true,
        else => return false,
    }
    return true;
}

fn parseShortFormatFlag(ch: u8, opt: *Options) bool {
    switch (ch) {
        'l' => opt.format = .long,
        '1' => opt.format = .one_per_line,
        'C' => opt.format = .columns,
        'x' => opt.format = .across,
        'm' => opt.format = .comma,
        'n' => {
            opt.numeric_ids = true;
            opt.format = .long;
        },
        'g' => {
            opt.omit_owner = true;
            opt.format = .long;
        },
        'o' => {
            opt.omit_group = true;
            opt.format = .long;
        },
        'G' => opt.omit_group = true,
        else => return false,
    }
    return true;
}

fn parseShortStyleAndSort(ch: u8, opt: *Options) bool {
    switch (ch) {
        't' => opt.sort = .time,
        'S' => opt.sort = .size,
        'X' => opt.sort = .extension,
        'v' => opt.sort = .version,
        'U' => opt.sort = .none,
        'r' => opt.reverse_sort = true,
        'c' => {
            opt.time_type = .ctime;
            opt.sort = .time;
        },
        'u' => {
            opt.time_type = .atime;
            opt.sort = .time;
        },
        'b' => opt.quoting_style = .escape,
        'N' => {
            opt.quoting_style = .literal;
            opt.hide_control_chars = false;
        },
        'q' => opt.hide_control_chars = true,
        'k' => {
            opt.disk_block_size = 1024;
            opt.human_readable = false;
        },
        'h' => opt.human_readable = true,
        'Q' => {
            opt.quote_name = true;
            opt.quoting_style = .c_style;
        },
        'i' => opt.inode = true,
        's' => opt.size_blocks = true,
        'F' => opt.indicator = .classify,
        'p' => opt.indicator = .slash,
        else => return false,
    }
    return true;
}

pub fn parseShortFlag(ch: u8, opt: *Options) !void {
    if (parseShortDisplayFlag(ch, opt)) return;
    if (parseShortFormatFlag(ch, opt)) return;
    if (parseShortStyleAndSort(ch, opt)) return;
    return error.InvalidOption;
}
