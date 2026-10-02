const std = @import("std");
const types = @import("types.zig");
const c = @import("../../compat/c.zig").c;

pub fn computeEntryStats(cfg: *const types.DuConfig, st: *const c.struct_stat) types.DuStats {
    var stats: types.DuStats = .{};
    if (cfg.inodes_mode) {
        stats.inodes = 1;
    } else if (cfg.apparent_size) {
        const is_reg_or_link = ((st.st_mode & c.S_IFMT) == c.S_IFREG) or ((st.st_mode & c.S_IFMT) == c.S_IFLNK);
        stats.size = if (is_reg_or_link and st.st_size > 0) @intCast(st.st_size) else 0;
    } else {
        const blocks: u64 = if (st.st_blocks > 0) @intCast(st.st_blocks) else 0;
        stats.size = blocks * 512;
    }

    switch (cfg.time_type) {
        .mtime => {
            stats.tmax = st.st_mtim.tv_sec;
            stats.tmax_nsec = st.st_mtim.tv_nsec;
        },
        .atime => {
            stats.tmax = st.st_atim.tv_sec;
            stats.tmax_nsec = st.st_atim.tv_nsec;
        },
        .ctime => {
            stats.tmax = st.st_ctim.tv_sec;
            stats.tmax_nsec = st.st_ctim.tv_nsec;
        },
        .none => {},
    }
    return stats;
}

pub fn shouldPrint(cfg: *const types.DuConfig, is_dir: bool, level: usize, stats: types.DuStats) bool {
    const within_depth = if (cfg.max_depth) |md| level <= md else true;
    const type_allowed = is_dir or cfg.all_files or level == 0;
    if (!within_depth or !type_allowed) return false;

    if (cfg.threshold) |th| {
        const v = if (cfg.inodes_mode) stats.inodes else stats.size;
        if (th < 0) {
            const limit: u64 = @intCast(-th);
            if (v > limit) return false;
        } else {
            const limit: u64 = @intCast(th);
            if (v < limit) return false;
        }
    }
    return true;
}

pub fn isExcluded(cfg: *const types.DuConfig, path: []const u8, name: []const u8) bool {
    if (cfg.excludes.items.len == 0) return false;
    for (cfg.excludes.items) |rule| {
        if (matchExcludeRule(rule, path, name)) return true;
    }
    return false;
}

fn matchExcludeRule(rule: types.ExcludeRule, path: []const u8, name: []const u8) bool {
    var pat_buf: [4096]u8 = undefined;
    if (rule.pattern.len >= pat_buf.len) return false;
    @memcpy(pat_buf[0..rule.pattern.len], rule.pattern);
    pat_buf[rule.pattern.len] = 0;

    if (!rule.has_slash) {
        var name_buf: [4096]u8 = undefined;
        if (name.len >= name_buf.len) return false;
        @memcpy(name_buf[0..name.len], name);
        name_buf[name.len] = 0;
        return c.fnmatch(&pat_buf, &name_buf, 0) == 0;
    }

    var path_buf: [4096]u8 = undefined;
    if (path.len >= path_buf.len) return false;
    @memcpy(path_buf[0..path.len], path);
    path_buf[path.len] = 0;

    if (c.fnmatch(&pat_buf, &path_buf, 0) == 0) return true;

    var idx: usize = 0;
    while (idx < path.len) : (idx += 1) {
        if (path[idx] == '/' and idx + 1 < path.len) {
            if (c.fnmatch(&pat_buf, path_buf[idx + 1 ..].ptr, 0) == 0) return true;
        }
    }
    return false;
}
