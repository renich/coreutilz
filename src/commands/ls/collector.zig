const std = @import("std");
const c = @import("../../compat/c.zig").c;
const types = @import("types.zig");
const colors_mod = @import("colors.zig");
const sort_mod = @import("sort.zig");

const FileEntry = types.FileEntry;
const Options = types.Options;
const SortMode = types.SortMode;
const TimeType = types.TimeType;
const Colors = colors_mod.Colors;

pub const versionCompare = sort_mod.versionCompare;
pub const sortEntries = sort_mod.sortEntries;

fn patternMatches(patterns: []const []const u8, name: []const u8) bool {
    var name_buf: [1024]u8 = undefined;
    if (name.len >= name_buf.len) return false;
    @memcpy(name_buf[0..name.len], name);
    name_buf[name.len] = 0;

    for (patterns) |pat| {
        var pat_buf: [1024]u8 = undefined;
        if (pat.len >= pat_buf.len) continue;
        @memcpy(pat_buf[0..pat.len], pat);
        pat_buf[pat.len] = 0;

        if (c.fnmatch(&pat_buf, &name_buf, c.FNM_PERIOD) == 0) return true;
    }
    return false;
}

pub fn shouldIncludeEntry(name: []const u8, options: *const Options) bool {
    if (patternMatches(options.ignore_patterns, name)) return false;
    if (options.all) return true;
    if (options.almost_all) {
        return !std.mem.eql(u8, name, ".") and !std.mem.eql(u8, name, "..");
    }
    if (name.len > 0 and name[0] == '.') return false;
    if (patternMatches(options.hide_patterns, name)) return false;
    if (options.ignore_backups and std.mem.endsWith(u8, name, "~")) return false;
    return true;
}

pub fn entryNeedsStat(
    d_type: u8,
    options: *const Options,
    colors: *const Colors,
    use_color: bool,
) bool {
    if (d_type == c.DT_UNKNOWN) return true;
    if (options.formatNeedsStat()) return true;

    if (d_type == c.DT_DIR) {
        if (use_color and (colors_mod.isColored(colors.st) or colors_mod.isColored(colors.ow) or colors_mod.isColored(colors.tw))) return true;
        return false;
    }

    if (d_type == c.DT_LNK) {
        if (options.dereference and (options.recursive or options.indicator != .none or use_color or options.group_directories_first)) return true;
        if (colors.color_symlink_target) return true;
        if (options.group_directories_first) return true;
        if (use_color and colors_mod.isColored(colors.or_col)) return true;
        return false;
    }

    if (d_type == c.DT_REG) {
        if (options.indicator == .classify) return true;
        if (use_color and (colors_mod.isColored(colors.ex) or colors_mod.isColored(colors.su) or colors_mod.isColored(colors.sg) or colors_mod.isColored(colors.mh))) return true;
        return false;
    }

    return false;
}

fn synthesizeEntry(
    parent_path: []const u8,
    entry_name: []const u8,
    d_type: u8,
    arena: std.mem.Allocator,
) !FileEntry {
    const full_path = if (std.mem.eql(u8, parent_path, "."))
        try arena.dupe(u8, entry_name)
    else if (std.mem.endsWith(u8, parent_path, "/"))
        try std.fmt.allocPrint(arena, "{s}{s}", .{ parent_path, entry_name })
    else
        try std.fmt.allocPrint(arena, "{s}/{s}", .{ parent_path, entry_name });

    const mode_val: c.mode_t = switch (d_type) {
        c.DT_DIR => c.S_IFDIR,
        c.DT_REG => c.S_IFREG,
        c.DT_LNK => c.S_IFLNK,
        c.DT_FIFO => c.S_IFIFO,
        c.DT_SOCK => c.S_IFSOCK,
        c.DT_CHR => c.S_IFCHR,
        c.DT_BLK => c.S_IFBLK,
        else => 0,
    };
    var fake_st = std.mem.zeroes(c.struct_stat);
    fake_st.st_mode = mode_val;

    return FileEntry{
        .name = try arena.dupe(u8, entry_name),
        .full_path = full_path,
        .stat = fake_st,
        .is_dir = (d_type == c.DT_DIR),
        .is_symlink = (d_type == c.DT_LNK),
        .link_target = null,
        .has_stat_error = false,
        .is_dir_or_link_to_dir = (d_type == c.DT_DIR),
        .is_broken_link = false,
    };
}

fn makeFullPath(parent_path: []const u8, entry_name: []const u8, arena: std.mem.Allocator) ![]const u8 {
    if (std.mem.eql(u8, parent_path, ".")) return try arena.dupe(u8, entry_name);
    if (std.mem.endsWith(u8, parent_path, "/")) return try std.fmt.allocPrint(arena, "{s}{s}", .{ parent_path, entry_name });
    return try std.fmt.allocPrint(arena, "{s}/{s}", .{ parent_path, entry_name });
}

fn resolveSymlinkTarget(
    full_path_z: [*:0]const u8,
    need_target: bool,
    is_long: bool,
    arena: std.mem.Allocator,
    is_dir_or_link_to_dir: *bool,
    is_broken_link: *bool,
) !?[]const u8 {
    var link_target: ?[]const u8 = null;
    if (need_target or is_long) {
        var link_buf: [std.fs.max_path_bytes]u8 = undefined;
        const len = c.readlink(full_path_z, &link_buf, link_buf.len);
        if (len > 0) link_target = try arena.dupe(u8, link_buf[0..@intCast(len)]);
    }
    if (need_target) {
        var target_st: c.struct_stat = undefined;
        if (c.stat(full_path_z, &target_st) == 0) {
            if ((target_st.st_mode & c.S_IFMT) == c.S_IFDIR) is_dir_or_link_to_dir.* = true;
        } else {
            is_broken_link.* = true;
        }
    }
    return link_target;
}

pub fn createFileEntryFromStat(
    parent_path: []const u8,
    entry_name: []const u8,
    st: c.struct_stat,
    dereference: bool,
    had_deref_error: bool,
    colors: *const Colors,
    use_color: bool,
    options: *const Options,
    arena: std.mem.Allocator,
) !FileEntry {
    const full_path = try makeFullPath(parent_path, entry_name, arena);
    const is_symlink = (st.st_mode & c.S_IFMT) == c.S_IFLNK;
    const is_dir = (st.st_mode & c.S_IFMT) == c.S_IFDIR;
    var link_target: ?[]const u8 = null;
    var is_dir_or_link_to_dir = is_dir;
    var is_broken_link = had_deref_error;
    if (is_symlink) {
        const full_path_z = try arena.dupeZ(u8, full_path);
        const need_target = dereference or options.group_directories_first or (use_color and (colors.color_symlink_target or colors_mod.isColored(colors.or_col) or (options.format == .long and (colors_mod.isColored(colors.mi) or colors_mod.isColored(colors.or_col)))));
        link_target = try resolveSymlinkTarget(full_path_z.ptr, need_target, options.format == .long, arena, &is_dir_or_link_to_dir, &is_broken_link);
    }

    return FileEntry{
        .name = try arena.dupe(u8, entry_name),
        .full_path = full_path,
        .stat = st,
        .is_dir = is_dir,
        .is_symlink = is_symlink,
        .link_target = link_target,
        .has_stat_error = had_deref_error,
        .is_dir_or_link_to_dir = is_dir_or_link_to_dir,
        .is_broken_link = is_broken_link,
    };
}

pub fn readFileEntry(
    parent_path: []const u8,
    entry_name: []const u8,
    dereference: bool,
    colors: *const Colors,
    use_color: bool,
    options: *const Options,
    arena: std.mem.Allocator,
) !FileEntry {
    const full_path = try makeFullPath(parent_path, entry_name, arena);
    var st: c.struct_stat = undefined;
    const full_path_z = try arena.dupeZ(u8, full_path);
    var stat_res: c_int = -1;
    var had_deref_error = false;
    if (dereference) {
        stat_res = c.stat(full_path_z.ptr, &st);
        if (stat_res != 0) {
            had_deref_error = true;
            stat_res = c.lstat(full_path_z.ptr, &st);
        }
    } else {
        stat_res = c.lstat(full_path_z.ptr, &st);
    }

    if (stat_res != 0) {
        return FileEntry{
            .name = try arena.dupe(u8, entry_name),
            .full_path = full_path,
            .stat = std.mem.zeroes(c.struct_stat),
            .is_dir = false,
            .is_symlink = false,
            .has_stat_error = true,
        };
    }
    return createFileEntryFromStat(parent_path, entry_name, st, dereference, had_deref_error, colors, use_color, options, arena);
}

pub fn readDirEntries(
    dir_path: []const u8,
    options: *const Options,
    colors: *const Colors,
    use_color: bool,
    arena: std.mem.Allocator,
) ![]FileEntry {
    const dir_path_z = try arena.dupeZ(u8, dir_path);
    const dir = c.opendir(dir_path_z.ptr);
    if (dir == null) return error.OpenDirFailed;
    defer _ = c.closedir(dir);

    var entries: std.ArrayList(FileEntry) = .empty;
    defer entries.deinit(arena);

    while (c.readdir(dir)) |ent| {
        const name_slice = std.mem.span(@as([*:0]const u8, @ptrCast(&ent.*.d_name)));
        if (!shouldIncludeEntry(name_slice, options)) continue;

        if (!entryNeedsStat(ent.*.d_type, options, colors, use_color)) {
            const entry = try synthesizeEntry(dir_path, name_slice, ent.*.d_type, arena);
            try entries.append(arena, entry);
        } else {
            const entry = try readFileEntry(dir_path, name_slice, options.dereference, colors, use_color, options, arena);
            try entries.append(arena, entry);
        }
    }

    sortEntries(entries.items, options);
    return entries.toOwnedSlice(arena);
}
