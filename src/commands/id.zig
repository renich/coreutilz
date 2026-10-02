const std = @import("std");
const c = @import("../compat/c.zig").c;

pub const name: []const u8 = "id";
pub const version: []const u8 = "0.1.0";

const IdOptions = struct {
    opt_u: bool = false,
    opt_g: bool = false,
    opt_G: bool = false,
    opt_n: bool = false,
    opt_r: bool = false,
    opt_z: bool = false,
    opt_Z: bool = false,
};

fn getContext(allocator: std.mem.Allocator) ?[]const u8 {
    const fd = c.open("/proc/self/attr/current", c.O_RDONLY);
    if (fd < 0) return null;
    defer _ = c.close(fd);
    var buf: [512]u8 = undefined;
    const n = c.read(fd, &buf, buf.len);
    if (n <= 0) return null;
    var len: usize = @intCast(n);
    while (len > 0 and (buf[len - 1] == 0 or buf[len - 1] == '\n')) len -= 1;
    return if (len > 0) allocator.dupe(u8, buf[0..len]) catch null else null;
}

fn parseShort(ch: u8, opts: *IdOptions) bool {
    switch (ch) {
        'a' => {},
        'u' => opts.opt_u = true,
        'g' => opts.opt_g = true,
        'G' => opts.opt_G = true,
        'n' => opts.opt_n = true,
        'r' => opts.opt_r = true,
        'z' => opts.opt_z = true,
        'Z' => opts.opt_Z = true,
        else => return false,
    }
    return true;
}

fn parseLong(arg: []const u8, opts: *IdOptions) bool {
    const map = [_]struct { []const u8, *bool }{
        .{ "--user", &opts.opt_u },    .{ "--group", &opts.opt_g },
        .{ "--groups", &opts.opt_G },  .{ "--name", &opts.opt_n },
        .{ "--real", &opts.opt_r },    .{ "--zero", &opts.opt_z },
        .{ "--context", &opts.opt_Z },
    };
    for (map) |m| if (std.mem.eql(u8, arg, m[0])) {
        m[1].* = true;
        return true;
    };
    return false;
}

fn parseOptions(args: [][]const u8, opts: *IdOptions, list: *std.ArrayListUnmanaged([]const u8), alloc: std.mem.Allocator, out: anytype) !?u8 {
    var i: usize = 1;
    var past = false;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (past or !std.mem.startsWith(u8, arg, "-") or std.mem.eql(u8, arg, "-")) {
            try list.append(alloc, arg);
        } else if (std.mem.eql(u8, arg, "--")) {
            past = true;
        } else if (std.mem.eql(u8, arg, "--help")) {
            try out.print("Usage: id [OPTION]... [USER]...\nPrint user and group information for each specified USER,\nor (when USER omitted) for the current process.\n", .{});
            return 0;
        } else if (std.mem.eql(u8, arg, "--version")) {
            try out.print("id (coreutilz) {s}\n", .{version});
            return 0;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            if (!parseLong(arg, opts)) return 1;
        } else for (arg[1..]) |ch| if (!parseShort(ch, opts)) return 1;
    }
    return null;
}

fn validateOptions(opts: *const IdOptions, n_ids: usize, err: anytype) ?u8 {
    const mc = @as(usize, if (opts.opt_u) 1 else 0) + @as(usize, if (opts.opt_g) 1 else 0) +
        @as(usize, if (opts.opt_G) 1 else 0) + @as(usize, if (opts.opt_Z) 1 else 0);
    const m: ?[]const u8 = if (n_ids > 0 and opts.opt_Z) "id: cannot print security context when user specified\n" else if (mc > 1) "id: cannot print \"only\" of more than one choice\n" else if (mc == 0 and (opts.opt_r or opts.opt_n)) "id: printing only names or real IDs requires -u, -g, or -G\n" else if (mc == 0 and opts.opt_z) "id: option --zero not permitted in default format\n" else null;
    if (m) |s| {
        err.print("{s}", .{s}) catch {};
        return 1;
    }
    return null;
}

const UserInfo = struct {
    ruid: c.uid_t,
    euid: c.uid_t,
    rgid: c.gid_t,
    egid: c.gid_t,
    name: []const u8,
    groups: [128]c.gid_t,
    group_count: usize,
};

fn addGroup(groups: *[128]c.gid_t, count: *usize, gid: c.gid_t) void {
    for (groups[0..count.*]) |g| if (g == gid) return;
    if (count.* < groups.len) {
        groups[count.*] = gid;
        count.* += 1;
    }
}

fn initUserInfo(r_u: c.uid_t, e_u: c.uid_t, r_g: c.gid_t, e_g: c.gid_t, uname: []const u8, prim: c.gid_t, raw: []const c.gid_t) UserInfo {
    var info = UserInfo{ .ruid = r_u, .euid = e_u, .rgid = r_g, .egid = e_g, .name = uname, .groups = undefined, .group_count = 0 };
    addGroup(&info.groups, &info.group_count, prim);
    for (raw) |g| addGroup(&info.groups, &info.group_count, g);
    return info;
}

fn resolveFromPw(pw: *c.struct_passwd, un: []const u8) UserInfo {
    var raw: [128]c.gid_t = undefined;
    var ngroups: c_int = 128;
    _ = c.getgrouplist(pw.*.pw_name, pw.*.pw_gid, &raw, &ngroups);
    const n: usize = if (ngroups >= 0) @intCast(ngroups) else 0;
    const nm = if (pw.*.pw_name != null) std.mem.span(pw.*.pw_name) else un;
    return initUserInfo(pw.*.pw_uid, pw.*.pw_uid, pw.*.pw_gid, pw.*.pw_gid, nm, pw.*.pw_gid, raw[0..n]);
}

fn resolveUser(user_name: ?[]const u8, allocator: std.mem.Allocator) ?UserInfo {
    if (user_name) |un| {
        if (un.len == 0) return null;
        if (un[0] == '+') {
            const uid = std.fmt.parseInt(c.uid_t, un[1..], 10) catch return null;
            return resolveFromPw(c.getpwuid(uid) orelse return null, un);
        }
        const un_z = allocator.dupeZ(u8, un) catch return null;
        defer allocator.free(un_z);
        if (c.getpwnam(un_z.ptr)) |pw| return resolveFromPw(pw, un);
        const uid = std.fmt.parseInt(c.uid_t, un, 10) catch return null;
        return resolveFromPw(c.getpwuid(uid) orelse return null, un);
    }
    var raw: [128]c.gid_t = undefined;
    const count = c.getgroups(128, &raw);
    const n: usize = if (count >= 0) @intCast(count) else 0;
    const pw = c.getpwuid(c.geteuid());
    const nm = if (pw != null and pw.*.pw_name != null) std.mem.span(pw.*.pw_name) else "";
    return initUserInfo(c.getuid(), c.geteuid(), c.getgid(), c.getegid(), nm, c.getegid(), raw[0..n]);
}

fn printGroup(out: anytype, err: anytype, gid: c.gid_t, opt_n: bool) !bool {
    if (opt_n) {
        const gr = c.getgrgid(gid);
        if (gr != null and gr.*.gr_name != null) {
            try out.print("{s}", .{std.mem.span(gr.*.gr_name)});
            return true;
        }
        try err.print("id: cannot find name for group ID {d}\n", .{gid});
        try out.print("{d}", .{gid});
        return false;
    }
    try out.print("{d}", .{gid});
    return true;
}

fn printGroupList(opts: *const IdOptions, info: *const UserInfo, multi: bool, out: anytype, err: anytype) !bool {
    var ok = true;
    const delim: u8 = if (opts.opt_z) 0 else ' ';
    ok = (try printGroup(out, err, info.rgid, opts.opt_n)) and ok;
    if (info.egid != info.rgid) {
        try out.writeByte(delim);
        ok = (try printGroup(out, err, info.egid, opts.opt_n)) and ok;
    }
    for (info.groups[0..info.group_count]) |gid| {
        if (gid != info.rgid and gid != info.egid) {
            try out.writeByte(delim);
            ok = (try printGroup(out, err, gid, opts.opt_n)) and ok;
        }
    }
    if (opts.opt_z and multi) {
        try out.writeByte(0);
        try out.writeByte(0);
    } else {
        try out.writeByte(if (opts.opt_z) 0 else '\n');
    }
    return ok;
}

fn printSingle(opts: *const IdOptions, info: *const UserInfo, ctx: ?[]const u8, multi: bool, out: anytype, err: anytype) !bool {
    if (opts.opt_Z) {
        if (ctx) |s| try out.print("{s}", .{s});
        try out.writeByte(if (opts.opt_z) 0 else '\n');
        return true;
    }
    if (opts.opt_u) {
        const u = if (opts.opt_r) info.ruid else info.euid;
        var ok = true;
        if (opts.opt_n) {
            const pw = c.getpwuid(u);
            if (pw != null and pw.*.pw_name != null) try out.print("{s}", .{std.mem.span(pw.*.pw_name)}) else {
                try err.print("id: cannot find name for user ID {d}\n", .{u});
                try out.print("{d}", .{u});
                ok = false;
            }
        } else try out.print("{d}", .{u});
        try out.writeByte(if (opts.opt_z) 0 else '\n');
        return ok;
    }
    if (opts.opt_g) {
        const ok = try printGroup(out, err, if (opts.opt_r) info.rgid else info.egid, opts.opt_n);
        try out.writeByte(if (opts.opt_z) 0 else '\n');
        return ok;
    }
    return printGroupList(opts, info, multi, out, err);
}

fn printDiffId(out: anytype, tag: []const u8, id_val: c.uid_t, is_user: bool) !void {
    const nm = if (is_user) blk: {
        const p = c.getpwuid(id_val);
        break :blk if (p != null and p.*.pw_name != null) std.mem.span(p.*.pw_name) else "";
    } else blk: {
        const g = c.getgrgid(id_val);
        break :blk if (g != null and g.*.gr_name != null) std.mem.span(g.*.gr_name) else "";
    };
    try out.print(" {s}={d}({s})", .{ tag, id_val, nm });
}

fn printDefaultFormat(info: *const UserInfo, ctx: ?[]const u8, opts: *const IdOptions, out: anytype) !void {
    const pw = c.getpwuid(info.ruid);
    const gr = c.getgrgid(info.rgid);
    const un = if (pw != null and pw.*.pw_name != null) std.mem.span(pw.*.pw_name) else "";
    const gn = if (gr != null and gr.*.gr_name != null) std.mem.span(gr.*.gr_name) else "";
    try out.print("uid={d}({s}) gid={d}({s})", .{ info.ruid, un, info.rgid, gn });
    if (info.euid != info.ruid) try printDiffId(out, "euid", info.euid, true);
    if (info.egid != info.rgid) try printDiffId(out, "egid", info.egid, false);
    if (info.group_count > 0) {
        try out.print(" groups=", .{});
        for (info.groups[0..info.group_count], 0..) |gid, idx| {
            if (idx > 0) try out.writeByte(',');
            const g = c.getgrgid(gid);
            try out.print("{d}({s})", .{ gid, if (g != null and g.*.gr_name != null) std.mem.span(g.*.gr_name) else "" });
        }
    }
    if (ctx) |c_str| try out.print(" context={s}", .{c_str});
    try out.writeByte(if (opts.opt_z) 0 else '\n');
}

fn runUser(un: ?[]const u8, opts: *const IdOptions, ctx: ?[]const u8, multi: bool, def: bool, alloc: std.mem.Allocator, out: anytype, err: anytype) !bool {
    if (un) |u| if (u.len == 0) {
        try err.print("id: '': no such user\n", .{});
        return false;
    };
    const info = resolveUser(un, alloc) orelse {
        if (un) |u| try err.print("id: '{s}': no such user\n", .{u}) else try err.print("id: cannot find current user\n", .{});
        return false;
    };
    if (def) try printDefaultFormat(&info, ctx, opts, out) else return printSingle(opts, &info, ctx, multi, out, err);
    return true;
}

fn executeUsers(list: [][]const u8, opts: *const IdOptions, ctx: ?[]const u8, def: bool, alloc: std.mem.Allocator, out: anytype, err: anytype) !bool {
    if (list.len == 0) return runUser(null, opts, ctx, false, def, alloc, out, err);
    var ok = true;
    for (list) |u| ok = (try runUser(u, opts, null, list.len > 1, def, alloc, out, err)) and ok;
    return ok;
}

pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8 {
    var stdout_buf: [4096]u8 = undefined;
    var stderr_buf: [4096]u8 = undefined;
    var out_w = std.Io.File.Writer.initStreaming(.stdout(), std.Options.debug_io, &stdout_buf);
    var err_w = std.Io.File.Writer.initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stdout = &out_w.interface;
    const stderr = &err_w.interface;

    var opts = IdOptions{};
    var user_list: std.ArrayListUnmanaged([]const u8) = .empty;
    defer user_list.deinit(allocator);

    if (try parseOptions(args, &opts, &user_list, allocator, stdout)) |rc| {
        stdout.flush() catch return 1;
        return rc;
    }
    if (validateOptions(&opts, user_list.items.len, stderr)) |err_rc| {
        stderr.flush() catch {};
        return err_rc;
    }
    const def = !(opts.opt_u or opts.opt_g or opts.opt_G or opts.opt_Z);
    const ctx = if (user_list.items.len == 0 and (opts.opt_Z or (def and c.getenv("POSIXLY_CORRECT") == null))) getContext(allocator) else null;
    defer if (ctx) |s| allocator.free(s);

    if (opts.opt_Z and ctx == null) {
        try stderr.print("id: --context (-Z) works only on an SELinux/SMACK-enabled kernel\n", .{});
        stderr.flush() catch {};
        return 1;
    }

    const ok = try executeUsers(user_list.items, &opts, ctx, def, allocator, stdout, stderr);
    stdout.flush() catch return 1;
    stderr.flush() catch {};
    return if (ok) 0 else 1;
}
