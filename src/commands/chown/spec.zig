const std = @import("std");
const c = @import("../../compat/c.zig").c;

pub const ParsedSpec = struct {
    uid: ?u32 = null,
    gid: ?u32 = null,
    user_name: ?[]const u8 = null,
    group_name: ?[]const u8 = null,
};

pub fn parseUserSpec(
    spec: []const u8,
    is_chgrp: bool,
    allocator: std.mem.Allocator,
) !ParsedSpec {
    if (spec.len == 0) return ParsedSpec{};

    if (is_chgrp) {
        return parseGroupOnly(spec, allocator);
    }

    if (std.mem.indexOfScalar(u8, spec, ':')) |colon_idx| {
        return parseColonSpec(spec, colon_idx, allocator);
    }

    // Check if whole string matches a user with dot in username
    if (lookupUser(spec, allocator)) |u| {
        return ParsedSpec{
            .uid = u.uid,
            .user_name = u.name,
        };
    } else |_| {}

    if (std.mem.indexOfScalar(u8, spec, '.')) |dot_idx| {
        return parseDotSpec(spec, dot_idx, allocator);
    }

    // User only, no group
    const u = try lookupUser(spec, allocator);
    return ParsedSpec{
        .uid = u.uid,
        .user_name = u.name,
    };
}

fn parseGroupOnly(spec: []const u8, allocator: std.mem.Allocator) !ParsedSpec {
    const g = try lookupGroup(spec, allocator);
    return ParsedSpec{
        .gid = g.gid,
        .group_name = g.name,
    };
}

fn parseColonSpec(
    spec: []const u8,
    colon_idx: usize,
    allocator: std.mem.Allocator,
) !ParsedSpec {
    const user_part = spec[0..colon_idx];
    const group_part = spec[colon_idx + 1 ..];
    return resolveUserAndGroup(user_part, group_part, true, allocator);
}

fn parseDotSpec(
    spec: []const u8,
    dot_idx: usize,
    allocator: std.mem.Allocator,
) !ParsedSpec {
    const user_part = spec[0..dot_idx];
    const group_part = spec[dot_idx + 1 ..];
    return resolveUserAndGroup(user_part, group_part, true, allocator);
}

fn resolveUserAndGroup(
    user_part: []const u8,
    group_part: []const u8,
    has_separator: bool,
    allocator: std.mem.Allocator,
) !ParsedSpec {
    var result = ParsedSpec{};
    var pw_gid: ?u32 = null;

    if (has_separator and group_part.len == 0 and user_part.len > 0 and user_part[0] >= '0' and user_part[0] <= '9') {
        return error.InvalidSpec;
    }

    if (user_part.len > 0) {
        const u = try lookupUser(user_part, allocator);
        result.uid = u.uid;
        result.user_name = u.name;
        pw_gid = u.login_gid;
    }

    if (group_part.len > 0) {
        const g = try lookupGroup(group_part, allocator);
        result.gid = g.gid;
        result.group_name = g.name;
    } else if (has_separator and user_part.len > 0) {
        if (pw_gid) |lgid| {
            result.gid = lgid;
            result.group_name = try gidToName(lgid, allocator);
        }
    }
    return result;
}

pub fn lookupUser(
    name_or_id: []const u8,
    allocator: std.mem.Allocator,
) !struct { uid: u32, login_gid: ?u32, name: []const u8 } {
    const name_z = try allocator.dupeZ(u8, name_or_id);
    defer allocator.free(name_z);

    if (c.getpwnam(name_z.ptr)) |pw| {
        const uname = try allocator.dupe(u8, std.mem.span(pw.*.pw_name));
        return .{ .uid = pw.*.pw_uid, .login_gid = pw.*.pw_gid, .name = uname };
    }

    if (std.fmt.parseInt(u32, name_or_id, 10)) |numeric_uid| {
        if (c.getpwuid(numeric_uid)) |pw| {
            const uname = try allocator.dupe(u8, std.mem.span(pw.*.pw_name));
            return .{ .uid = numeric_uid, .login_gid = pw.*.pw_gid, .name = uname };
        }
        const uname = try allocator.dupe(u8, name_or_id);
        return .{ .uid = numeric_uid, .login_gid = null, .name = uname };
    } else |_| {}

    return error.InvalidUser;
}

pub fn lookupGroup(
    name_or_id: []const u8,
    allocator: std.mem.Allocator,
) !struct { gid: u32, name: []const u8 } {
    const name_z = try allocator.dupeZ(u8, name_or_id);
    defer allocator.free(name_z);

    if (c.getgrnam(name_z.ptr)) |gr| {
        const gname = try allocator.dupe(u8, std.mem.span(gr.*.gr_name));
        return .{ .gid = gr.*.gr_gid, .name = gname };
    }

    if (std.fmt.parseInt(u32, name_or_id, 10)) |numeric_gid| {
        if (c.getgrgid(numeric_gid)) |gr| {
            const gname = try allocator.dupe(u8, std.mem.span(gr.*.gr_name));
            return .{ .gid = numeric_gid, .name = gname };
        }
        const gname = try allocator.dupe(u8, name_or_id);
        return .{ .gid = numeric_gid, .name = gname };
    } else |_| {}

    return error.InvalidGroup;
}

pub fn uidToName(uid: u32, allocator: std.mem.Allocator) ![]const u8 {
    if (c.getpwuid(uid)) |pw| {
        return try allocator.dupe(u8, std.mem.span(pw.*.pw_name));
    }
    return try std.fmt.allocPrint(allocator, "{d}", .{uid});
}

pub fn gidToName(gid: u32, allocator: std.mem.Allocator) ![]const u8 {
    if (c.getgrgid(gid)) |gr| {
        return try allocator.dupe(u8, std.mem.span(gr.*.gr_name));
    }
    return try std.fmt.allocPrint(allocator, "{d}", .{gid});
}
