const std = @import("std");
const c = @import("../../compat/c.zig").c;
const types = @import("types.zig");
const FileEntry = types.FileEntry;
const Options = types.Options;

pub const ColorExt = struct {
    suffix: []const u8,
    seq: []const u8,
    exact_match: bool = false,
    ignored: bool = false,
};

pub fn isColored(seq: ?[]const u8) bool {
    const s = seq orelse return false;
    if (s.len == 0) return false;
    if (s.len > 2) return true;
    return (s[0] != '0') or (s[s.len - 1] != '0');
}

pub fn setNormalColor(
    writer: anytype,
    colors: *const Colors,
    use_color: bool,
    used_color: *bool,
) !void {
    if (use_color and isColored(colors.no)) {
        if (!used_color.*) {
            try writer.writeAll("\x1b[0m");
            used_color.* = true;
        }
        try writer.print("\x1b[{s}m", .{colors.no.?});
    }
}

pub const Colors = struct {
    di: ?[]const u8 = "01;34",
    ln: ?[]const u8 = "01;36",
    pi: ?[]const u8 = "33",
    so: ?[]const u8 = "01;35",
    bd: ?[]const u8 = "01;33",
    cd: ?[]const u8 = "01;33",
    or_col: ?[]const u8 = null,
    ex: ?[]const u8 = "01;32",
    su: ?[]const u8 = "37;41",
    sg: ?[]const u8 = "30;43",
    st: ?[]const u8 = "37;44",
    ow: ?[]const u8 = "34;42",
    tw: ?[]const u8 = "30;42",
    mh: ?[]const u8 = null,
    no: ?[]const u8 = null,
    fi: ?[]const u8 = null,
    mi: ?[]const u8 = null,
    cl: ?[]const u8 = "\x1b[K",
    color_symlink_target: bool = false,
    extensions: []const ColorExt = &.{},

    fn getSymlinkColor(self: *const Colors, entry: *const FileEntry) ?[]const u8 {
        if (entry.is_broken_link or entry.has_stat_error) {
            if (isColored(self.or_col)) return self.or_col;
            if (self.color_symlink_target) return self.or_col;
            return self.ln;
        }
        if (self.color_symlink_target) {
            if (entry.is_dir_or_link_to_dir) return self.di;
            return self.fi;
        }
        return self.ln;
    }

    fn getDirColor(self: *const Colors, m: c.mode_t) ?[]const u8 {
        const is_vtx = (m & c.S_ISVTX) != 0;
        const is_ow = (m & 0o002) != 0;
        if (is_vtx and is_ow and isColored(self.tw)) return self.tw;
        if (is_ow and isColored(self.ow)) return self.ow;
        if (is_vtx and isColored(self.st)) return self.st;
        return self.di;
    }

    fn getRegFileColor(self: *const Colors, entry: *const FileEntry) ?[]const u8 {
        const m = entry.stat.st_mode;
        if ((m & c.S_ISUID) != 0 and isColored(self.su)) return self.su;
        if ((m & c.S_ISGID) != 0 and isColored(self.sg)) return self.sg;
        if ((m & 0o111) != 0 and isColored(self.ex)) return self.ex;
        if (entry.stat.st_nlink > 1 and isColored(self.mh)) return self.mh;

        var i: usize = self.extensions.len;
        while (i > 0) {
            i -= 1;
            const ext = self.extensions[i];
            if (ext.ignored) continue;
            if (entry.name.len >= ext.suffix.len) {
                const tail = entry.name[entry.name.len - ext.suffix.len ..];
                const matches = if (ext.exact_match) std.mem.eql(u8, tail, ext.suffix) else std.ascii.eqlIgnoreCase(tail, ext.suffix);
                if (matches) return ext.seq;
            }
        }
        return self.fi;
    }

    pub fn getColor(self: *const Colors, entry: *const FileEntry) ?[]const u8 {
        if (entry.is_symlink) return self.getSymlinkColor(entry);

        if (entry.has_stat_error or entry.is_broken_link) {
            if (isColored(self.mi)) return self.mi;
            if (isColored(self.or_col)) return self.or_col;
            return null;
        }

        if (entry.is_dir) return self.getDirColor(entry.stat.st_mode);

        const fmt = entry.stat.st_mode & c.S_IFMT;
        if (fmt == c.S_IFIFO) return self.pi;
        if (fmt == c.S_IFSOCK) return self.so;
        if (fmt == c.S_IFBLK) return self.bd;
        if (fmt == c.S_IFCHR) return self.cd;
        if (fmt == c.S_IFREG) return self.getRegFileColor(entry);
        return null;
    }
};

pub fn shouldUseColor(options: *const Options) bool {
    if (options.color == .never) return false;

    const term = if (c.getenv("TERM")) |ptr| std.mem.span(ptr) else null;
    const colorterm = if (c.getenv("COLORTERM")) |ptr| std.mem.span(ptr) else null;
    const has_color = (colorterm != null and colorterm.?.len > 0) or
        (term != null and term.?.len > 0 and !std.mem.eql(u8, term.?, "dumb"));

    if (!has_color) return false;
    if (options.color == .always) return true;
    return (c.isatty(c.STDOUT_FILENO) != 0);
}

fn setBuiltinColor(key: []const u8, val: []const u8, col: *Colors) bool {
    if (std.mem.eql(u8, key, "di")) {
        col.di = val;
    } else if (std.mem.eql(u8, key, "ln")) {
        if (std.mem.eql(u8, val, "target")) {
            col.color_symlink_target = true;
            col.ln = null;
        } else {
            col.ln = val;
        }
    } else if (std.mem.eql(u8, key, "pi")) col.pi = val else if (std.mem.eql(u8, key, "so")) col.so = val else if (std.mem.eql(u8, key, "bd")) col.bd = val else if (std.mem.eql(u8, key, "cd")) col.cd = val else if (std.mem.eql(u8, key, "or")) col.or_col = val else if (std.mem.eql(u8, key, "ex")) col.ex = val else if (std.mem.eql(u8, key, "su")) col.su = val else if (std.mem.eql(u8, key, "sg")) col.sg = val else if (std.mem.eql(u8, key, "st")) col.st = val else if (std.mem.eql(u8, key, "ow")) col.ow = val else if (std.mem.eql(u8, key, "tw")) col.tw = val else if (std.mem.eql(u8, key, "mh")) col.mh = val else if (std.mem.eql(u8, key, "no")) col.no = val else if (std.mem.eql(u8, key, "fi")) col.fi = val else if (std.mem.eql(u8, key, "mi")) col.mi = val else return false;
    return true;
}

fn dedupColorExtensions(items: []ColorExt) void {
    var i: usize = items.len;
    while (i > 0) {
        i -= 1;
        const e1 = &items[i];
        if (e1.ignored) continue;
        var case_ignored = false;
        var j = i;
        while (j > 0) {
            j -= 1;
            const e2 = &items[j];
            if (e2.ignored or e1.suffix.len != e2.suffix.len) continue;
            if (std.mem.eql(u8, e1.suffix, e2.suffix)) {
                e2.ignored = true;
            } else if (std.ascii.eqlIgnoreCase(e1.suffix, e2.suffix)) {
                if (case_ignored) {
                    e2.ignored = true;
                } else if (std.mem.eql(u8, e1.seq, e2.seq)) {
                    e2.ignored = true;
                    case_ignored = true;
                } else {
                    e1.exact_match = true;
                    e2.exact_match = true;
                }
            }
        }
    }
}

pub fn parseLsColors(arena: std.mem.Allocator) Colors {
    var col = Colors{};
    const ls_colors_raw = c.getenv("LS_COLORS") orelse return col;
    const ls_colors = std.mem.span(ls_colors_raw);
    if (ls_colors.len == 0) return col;

    var ext_list: std.ArrayList(ColorExt) = .empty;
    defer ext_list.deinit(arena);

    var it = std.mem.splitScalar(u8, ls_colors, ':');
    while (it.next()) |part| {
        if (part.len == 0) continue;
        const eq_idx = std.mem.indexOfScalar(u8, part, '=') orelse continue;
        const key = part[0..eq_idx];
        const val = part[eq_idx + 1 ..];
        if (std.mem.startsWith(u8, key, "*.")) {
            ext_list.append(arena, .{ .suffix = key[1..], .seq = val }) catch {};
        } else {
            _ = setBuiltinColor(key, val, &col);
        }
    }

    if (ext_list.items.len > 0) {
        dedupColorExtensions(ext_list.items);
        col.extensions = ext_list.toOwnedSlice(arena) catch &.{};
    }
    return col;
}
