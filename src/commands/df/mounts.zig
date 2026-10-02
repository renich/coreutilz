const std = @import("std");
const types = @import("types.zig");
const c = @import("../../compat/c.zig").c;

pub fn readMountTable(allocator: std.mem.Allocator) !std.ArrayList(types.MountInfo) {
    var list = std.ArrayList(types.MountInfo).empty;
    errdefer {
        for (list.items) |item| freeMountInfo(&item, allocator);
        list.deinit(allocator);
    }

    const fp = if (c.fopen("/proc/self/mountinfo", "r")) |probe_fp| blk: {
        _ = c.fclose(probe_fp);
        break :blk c.setmntent("/etc/mtab", "r") orelse c.setmntent("/proc/mounts", "r");
    } else c.setmntent("/etc/mtab", "r") orelse c.setmntent("/proc/mounts", "r");
    const mnt_fp = fp orelse return list;
    defer _ = c.endmntent(mnt_fp);

    while (c.getmntent(mnt_fp)) |ent| {
        if (try parseMntEnt(ent, allocator)) |info| {
            try list.append(allocator, info);
        }
    }
    return list;
}

pub fn freeMountInfo(info: *const types.MountInfo, allocator: std.mem.Allocator) void {
    allocator.free(info.fsname);
    allocator.free(info.dir);
    allocator.free(info.fstype);
}

fn parseMntEnt(ent: *c.struct_mntent, allocator: std.mem.Allocator) !?types.MountInfo {
    const fsname = if (ent.mnt_fsname != null) std.mem.span(ent.mnt_fsname) else "";
    const dir = if (ent.mnt_dir != null) std.mem.span(ent.mnt_dir) else "";
    const fstype = if (ent.mnt_type != null) std.mem.span(ent.mnt_type) else "";

    // Ignore relative mount points (e.g. net:[1234567] network namespaces)
    if (dir.len == 0 or dir[0] != '/') return null;

    const fsname_dupe = try allocator.dupe(u8, fsname);
    errdefer allocator.free(fsname_dupe);
    const dir_dupe = try allocator.dupe(u8, dir);
    errdefer allocator.free(dir_dupe);
    const fstype_dupe = try allocator.dupe(u8, fstype);
    errdefer allocator.free(fstype_dupe);

    var info = types.MountInfo{
        .fsname = fsname_dupe,
        .dir = dir_dupe,
        .fstype = fstype_dupe,
        .dev = 0,
        .is_dummy = isDummyType(fstype),
        .is_remote = isRemoteFs(fsname, fstype),
        .stat_ok = false,
        .f_frsize = 1024,
        .f_blocks = 0,
        .f_bfree = 0,
        .f_bavail = 0,
        .f_files = 0,
        .f_ffree = 0,
        .f_favail = 0,
    };
    queryMountStats(&info, allocator);
    return info;
}

fn queryMountStats(info: *types.MountInfo, allocator: std.mem.Allocator) void {
    const dir_z = allocator.dupeZ(u8, info.dir) catch return;
    defer allocator.free(dir_z);

    var st: c.struct_stat = undefined;
    if (c.stat(dir_z.ptr, &st) == 0) {
        info.dev = @intCast(st.st_dev);
    }

    var vfs: c.struct_statvfs = undefined;
    if (c.statvfs(dir_z.ptr, &vfs) == 0) {
        info.stat_ok = true;
        const frsize: u64 = if (vfs.f_frsize != 0) @intCast(vfs.f_frsize) else if (vfs.f_bsize != 0) @intCast(vfs.f_bsize) else 1024;
        info.f_frsize = frsize;
        info.f_blocks = @intCast(vfs.f_blocks);
        info.f_bfree = @intCast(vfs.f_bfree);
        info.f_bavail = @intCast(vfs.f_bavail);
        info.f_files = @intCast(vfs.f_files);
        info.f_ffree = @intCast(vfs.f_ffree);
        info.f_favail = @intCast(vfs.f_favail);
        if (info.f_blocks == 0) info.is_dummy = true;
    } else {
        info.is_dummy = true;
    }
}

pub fn filterAndDeduplicate(
    raw_list: []const types.MountInfo,
    cfg: *const types.DfConfig,
    allocator: std.mem.Allocator,
) !std.ArrayList(types.MountInfo) {
    var out = std.ArrayList(types.MountInfo).empty;
    if (cfg.all) {
        try filterAllMode(raw_list, &out, allocator);
    } else {
        try filterNormalMode(raw_list, cfg, &out, allocator);
    }
    return out;
}

fn filterAllMode(
    raw: []const types.MountInfo,
    out: *std.ArrayList(types.MountInfo),
    allocator: std.mem.Allocator,
) !void {
    var winners = std.AutoHashMap(u64, usize).init(allocator);
    defer winners.deinit();

    for (raw, 0..) |item, i| {
        if (item.dev == 0) continue;
        if (winners.get(item.dev)) |w_idx| {
            if (shouldReplace(&raw[w_idx], &item)) {
                try winners.put(item.dev, i);
            }
        } else {
            try winners.put(item.dev, i);
        }
    }

    for (raw) |item| {
        var cloned = try cloneMountInfo(&item, allocator);
        if (item.dev != 0) {
            if (winners.get(item.dev)) |w_idx| {
                const w = &raw[w_idx];
                const both_remote = item.is_remote and w.is_remote;
                if (!std.mem.eql(u8, item.fsname, w.fsname) and !both_remote) {
                    cloned.stat_ok = false;
                }
            }
        }
        try out.append(allocator, cloned);
    }
}

fn filterNormalMode(
    raw: []const types.MountInfo,
    cfg: *const types.DfConfig,
    out: *std.ArrayList(types.MountInfo),
    allocator: std.mem.Allocator,
) !void {
    var seen = std.AutoHashMap(u64, usize).init(allocator);
    defer seen.deinit();

    for (raw) |item| {
        if (!shouldIncludeMount(&item, cfg)) continue;
        if (item.dev != 0) {
            if (seen.get(item.dev)) |idx| {
                const seen_item = &out.items[idx];
                if (!cfg.grand_total and item.is_remote and seen_item.is_remote and !std.mem.eql(u8, seen_item.fsname, item.fsname)) {
                    // Distinct remote filesystems on same dev kept when not grand_total
                    const cloned = try cloneMountInfo(&item, allocator);
                    try out.append(allocator, cloned);
                    try seen.put(item.dev, out.items.len - 1);
                    continue;
                } else if (shouldReplace(seen_item, &item)) {
                    freeMountInfo(seen_item, allocator);
                    out.items[idx] = try cloneMountInfo(&item, allocator);
                    continue;
                } else {
                    continue;
                }
            }
            try seen.put(item.dev, out.items.len);
        }
        const cloned = try cloneMountInfo(&item, allocator);
        try out.append(allocator, cloned);
    }
}

fn shouldReplace(old: *const types.MountInfo, new: *const types.MountInfo) bool {
    const old_has_slash = std.mem.indexOf(u8, old.fsname, "/") != null;
    const new_has_slash = std.mem.indexOf(u8, new.fsname, "/") != null;
    if (new_has_slash and !old_has_slash) return true;
    if (old_has_slash and !new_has_slash) return false;
    if (new.dir.len < old.dir.len) return true;
    if (old.dir.len < new.dir.len) return false;
    if (!std.mem.eql(u8, old.fsname, new.fsname) and std.mem.eql(u8, old.dir, new.dir)) return true;
    return false;
}

pub fn shouldIncludeMount(item: *const types.MountInfo, cfg: *const types.DfConfig) bool {
    if (cfg.local_only and item.is_remote) return false;
    if (!cfg.all and item.is_dummy) return false;
    if (cfg.include_types.items.len > 0) {
        var matched = false;
        for (cfg.include_types.items) |t| {
            if (std.mem.eql(u8, item.fstype, t)) {
                matched = true;
                break;
            }
        }
        if (!matched) return false;
    }
    for (cfg.exclude_types.items) |t| {
        if (std.mem.eql(u8, item.fstype, t)) return false;
    }
    return true;
}

pub fn cloneMountInfo(src: *const types.MountInfo, allocator: std.mem.Allocator) !types.MountInfo {
    return .{
        .fsname = try allocator.dupe(u8, src.fsname),
        .dir = try allocator.dupe(u8, src.dir),
        .fstype = try allocator.dupe(u8, src.fstype),
        .dev = src.dev,
        .is_dummy = src.is_dummy,
        .is_remote = src.is_remote,
        .stat_ok = src.stat_ok,
        .f_frsize = src.f_frsize,
        .f_blocks = src.f_blocks,
        .f_bfree = src.f_bfree,
        .f_bavail = src.f_bavail,
        .f_files = src.f_files,
        .f_ffree = src.f_ffree,
        .f_favail = src.f_favail,
        .file_operand = src.file_operand,
    };
}

const operand_mod = @import("operand.zig");
pub const findMountForOperand = operand_mod.findMountForOperand;
pub const findMountFallback = operand_mod.findMountFallback;

fn isDummyType(fstype: []const u8) bool {
    const dummy_types = [_][]const u8{
        "autofs", "proc",   "subfs",   "devpts",    "fusectl",     "mqueue",     "rpc_pipefs", "sysfs",
        "devfs",  "kernfs", "ignore",  "none",      "rootfs",      "securityfs", "cgroup",     "cgroup2",
        "pstore", "bpf",    "tracefs", "hugetlbfs", "binfmt_misc", "configfs",   "debugfs",    "efivarfs",
        "nsfs",   "ramfs",
    };
    for (dummy_types) |dt| {
        if (std.mem.eql(u8, fstype, dt)) return true;
    }
    return false;
}

fn isRemoteFs(fsname: []const u8, fstype: []const u8) bool {
    if (std.mem.indexOf(u8, fsname, ":") != null) return true;
    if (std.mem.startsWith(u8, fsname, "//")) return true;
    const remote_types = [_][]const u8{ "nfs", "nfs4", "cifs", "smbfs", "afs", "glusterfs", "ceph", "lustre", "sshfs", "fuse.sshfs" };
    for (remote_types) |rt| {
        if (std.mem.eql(u8, fstype, rt)) return true;
    }
    return false;
}
