const std = @import("std");
const c = @import("../../compat/c.zig").c;
const types = @import("types.zig");
const version_sort = @import("version_sort.zig");

const FileEntry = types.FileEntry;
const Options = types.Options;
const SortMode = types.SortMode;
const TimeType = types.TimeType;

pub const versionCompare = version_sort.versionCompare;

fn getExtension(name: []const u8) []const u8 {
    if (std.mem.lastIndexOfScalar(u8, name, '.')) |idx| {
        if (idx > 0) return name[idx + 1 ..];
    }
    return "";
}

const SortContext = struct {
    sort: SortMode,
    reverse: bool,
    group_dirs: bool,
    time_type: TimeType,
};

fn compareTime(a: c.struct_stat, b: c.struct_stat, time_type: TimeType) std.math.Order {
    const tim_a = switch (time_type) {
        .mtime => a.st_mtim,
        .ctime => a.st_ctim,
        .atime => a.st_atim,
    };
    const tim_b = switch (time_type) {
        .mtime => b.st_mtim,
        .ctime => b.st_ctim,
        .atime => b.st_atim,
    };
    const sec_ord = std.math.order(tim_b.tv_sec, tim_a.tv_sec);
    if (sec_ord != .eq) return sec_ord;
    return std.math.order(tim_b.tv_nsec, tim_a.tv_nsec);
}

fn entryLessThan(ctx: SortContext, a: FileEntry, b: FileEntry) bool {
    if (ctx.group_dirs and a.is_dir_or_link_to_dir != b.is_dir_or_link_to_dir) {
        return a.is_dir_or_link_to_dir;
    }

    const order: std.math.Order = switch (ctx.sort) {
        .none => .eq,
        .name => std.mem.order(u8, a.name, b.name),
        .time => blk: {
            const ord = compareTime(a.stat, b.stat, ctx.time_type);
            if (ord != .eq) break :blk ord;
            break :blk std.mem.order(u8, a.name, b.name);
        },
        .size => blk: {
            const size_ord = std.math.order(b.stat.st_size, a.stat.st_size);
            if (size_ord != .eq) break :blk size_ord;
            break :blk std.mem.order(u8, a.name, b.name);
        },
        .extension => blk: {
            const ext_a = getExtension(a.name);
            const ext_b = getExtension(b.name);
            const ext_ord = std.mem.order(u8, ext_a, ext_b);
            if (ext_ord != .eq) break :blk ext_ord;
            break :blk std.mem.order(u8, a.name, b.name);
        },
        .version => blk: {
            const ver_ord = versionCompare(a.name, b.name);
            if (ver_ord != .eq) break :blk ver_ord;
            break :blk std.mem.order(u8, a.name, b.name);
        },
        .width => blk: {
            const width_ord = std.math.order(a.name.len, b.name.len);
            if (width_ord != .eq) break :blk width_ord;
            break :blk std.mem.order(u8, a.name, b.name);
        },
    };
    if (ctx.reverse) return order == .gt else return order == .lt;
}

pub fn sortEntries(entries: []FileEntry, options: *const Options) void {
    if (options.sort == .none and !options.group_directories_first) return;
    const ctx = SortContext{
        .sort = options.sort,
        .reverse = options.reverse_sort,
        .group_dirs = options.group_directories_first,
        .time_type = options.time_type,
    };
    std.sort.pdq(FileEntry, entries, ctx, entryLessThan);
}
