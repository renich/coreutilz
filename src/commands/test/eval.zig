const std = @import("std");
const c = @import("../../compat/c.zig").c;

pub const EvalError = error{ Handled, Syntax };

pub fn statFile(path: []const u8, follow: bool) ?c.struct_stat {
    var p_z: [std.fs.max_path_bytes]u8 = undefined;
    const pz = std.fmt.bufPrintZ(&p_z, "{s}", .{path}) catch return null;
    var st: c.struct_stat = undefined;
    const rc = if (follow) c.stat(pz.ptr, &st) else c.lstat(pz.ptr, &st);
    return if (rc == 0) st else null;
}

pub fn isUnaryOp(op: []const u8) bool {
    if (op.len != 2 or op[0] != '-') return false;
    return switch (op[1]) {
        'b', 'c', 'd', 'e', 'f', 'g', 'h', 'L', 'k', 'n', 'N', 'p', 'r', 's', 'S', 't', 'u', 'w', 'x', 'z', 'G', 'O' => true,
        else => false,
    };
}

pub fn isBinaryOp(op: []const u8) bool {
    const ops = [_][]const u8{
        "=",   "==",  "!=",  ">",   "<",
        "-eq", "-ne", "-lt", "-le", "-gt",
        "-ge", "-ot", "-nt", "-ef",
    };
    for (ops) |o| if (std.mem.eql(u8, op, o)) return true;
    return false;
}

pub fn evalUnary(op: []const u8, arg: []const u8) ?bool {
    if (std.mem.eql(u8, op, "-z")) return arg.len == 0;
    if (std.mem.eql(u8, op, "-n")) return arg.len > 0;
    if (std.mem.eql(u8, op, "-t")) {
        const fd = std.fmt.parseInt(c_int, arg, 10) catch return false;
        return c.isatty(fd) == 1;
    }
    var p_z: [std.fs.max_path_bytes]u8 = undefined;
    const pz = std.fmt.bufPrintZ(&p_z, "{s}", .{arg}) catch return false;
    if (std.mem.eql(u8, op, "-r")) return c.access(pz.ptr, c.R_OK) == 0;
    if (std.mem.eql(u8, op, "-w")) return c.access(pz.ptr, c.W_OK) == 0;
    if (std.mem.eql(u8, op, "-x")) return c.access(pz.ptr, c.X_OK) == 0;

    const follow = !std.mem.eql(u8, op, "-L") and !std.mem.eql(u8, op, "-h");
    const st = statFile(arg, follow) orelse return false;

    if (std.mem.eql(u8, op, "-e") or std.mem.eql(u8, op, "-a")) return true;
    if (std.mem.eql(u8, op, "-f")) return (st.st_mode & c.S_IFMT) == c.S_IFREG;
    if (std.mem.eql(u8, op, "-d")) return (st.st_mode & c.S_IFMT) == c.S_IFDIR;
    if (std.mem.eql(u8, op, "-s")) return st.st_size > 0;
    if (std.mem.eql(u8, op, "-L") or std.mem.eql(u8, op, "-h")) return (st.st_mode & c.S_IFMT) == c.S_IFLNK;
    if (std.mem.eql(u8, op, "-b")) return (st.st_mode & c.S_IFMT) == c.S_IFBLK;
    if (std.mem.eql(u8, op, "-c")) return (st.st_mode & c.S_IFMT) == c.S_IFCHR;
    if (std.mem.eql(u8, op, "-p")) return (st.st_mode & c.S_IFMT) == c.S_IFIFO;
    if (std.mem.eql(u8, op, "-S")) return (st.st_mode & c.S_IFMT) == c.S_IFSOCK;
    if (std.mem.eql(u8, op, "-u")) return (st.st_mode & c.S_ISUID) != 0;
    if (std.mem.eql(u8, op, "-g")) return (st.st_mode & c.S_ISGID) != 0;
    if (std.mem.eql(u8, op, "-k")) return (st.st_mode & c.S_ISVTX) != 0;
    if (std.mem.eql(u8, op, "-O")) return st.st_uid == c.geteuid();
    if (std.mem.eql(u8, op, "-G")) return st.st_gid == c.getegid();
    if (std.mem.eql(u8, op, "-N")) {
        return st.st_mtim.tv_sec > st.st_atim.tv_sec or (st.st_mtim.tv_sec == st.st_atim.tv_sec and st.st_mtim.tv_nsec > st.st_atim.tv_nsec);
    }
    return null;
}

pub fn findInt(s_in: []const u8) ?[]const u8 {
    var s = std.mem.trim(u8, s_in, " \t\r\n");
    if (s.len == 0) return null;
    if (s[0] == '+') s = s[1..];
    const check_str = if (s.len > 0 and s[0] == '-') s[1..] else s;
    if (check_str.len == 0) return null;
    for (check_str) |ch| {
        if (ch < '0' or ch > '9') return null;
    }
    return s;
}

fn stripZeros(s: []const u8) []const u8 {
    var i: usize = 0;
    while (i < s.len and s[i] == '0') : (i += 1) {}
    return s[i..];
}

pub fn strIntCmp(l_in: []const u8, r_in: []const u8) std.math.Order {
    const l_neg = l_in.len > 0 and l_in[0] == '-';
    const r_neg = r_in.len > 0 and r_in[0] == '-';
    const l_mag = stripZeros(if (l_neg) l_in[1..] else l_in);
    const r_mag = stripZeros(if (r_neg) r_in[1..] else r_in);
    if (l_mag.len == 0 and r_mag.len == 0) return .eq;
    if (l_neg != r_neg) return if (l_neg) .lt else .gt;
    const mag_order = if (l_mag.len != r_mag.len)
        std.math.order(l_mag.len, r_mag.len)
    else
        std.mem.order(u8, l_mag, r_mag);
    return if (l_neg) mag_order.invert() else mag_order;
}

fn evalIntBinary(op: []const u8, l: []const u8, r: []const u8, prog: []const u8, stderr: anytype) EvalError!?bool {
    const int_ops = [_][]const u8{ "-eq", "-ne", "-lt", "-le", "-gt", "-ge" };
    for (int_ops) |io| if (std.mem.eql(u8, op, io)) {
        const l_clean = findInt(l) orelse {
            stderr.print("{s}: invalid integer '{s}'\n", .{ prog, l }) catch {};
            return error.Handled;
        };
        const r_clean = findInt(r) orelse {
            stderr.print("{s}: invalid integer '{s}'\n", .{ prog, r }) catch {};
            return error.Handled;
        };
        const ord = strIntCmp(l_clean, r_clean);
        if (std.mem.eql(u8, op, "-eq")) return ord == .eq;
        if (std.mem.eql(u8, op, "-ne")) return ord != .eq;
        if (std.mem.eql(u8, op, "-lt")) return ord == .lt;
        if (std.mem.eql(u8, op, "-le")) return ord == .lt or ord == .eq;
        if (std.mem.eql(u8, op, "-gt")) return ord == .gt;
        if (std.mem.eql(u8, op, "-ge")) return ord == .gt or ord == .eq;
    };
    return null;
}

pub fn evalBinary(op: []const u8, l: []const u8, r: []const u8, prog: []const u8, stderr: anytype) EvalError!?bool {
    if (std.mem.eql(u8, op, "=") or std.mem.eql(u8, op, "==")) return std.mem.eql(u8, l, r);
    if (std.mem.eql(u8, op, "!=")) return !std.mem.eql(u8, l, r);
    if (std.mem.eql(u8, op, "<") or std.mem.eql(u8, op, ">")) {
        var l_buf: [1024]u8 = undefined;
        var r_buf: [1024]u8 = undefined;
        const l_z = std.fmt.bufPrintZ(&l_buf, "{s}", .{l}) catch return error.Syntax;
        const r_z = std.fmt.bufPrintZ(&r_buf, "{s}", .{r}) catch return error.Syntax;
        const cmp = c.strcoll(l_z.ptr, r_z.ptr);
        return if (std.mem.eql(u8, op, "<")) cmp < 0 else cmp > 0;
    }
    if (try evalIntBinary(op, l, r, prog, stderr)) |res| return res;
    if (std.mem.eql(u8, op, "-ef")) {
        const s1 = statFile(l, true) orelse return false;
        const s2 = statFile(r, true) orelse return false;
        return s1.st_dev == s2.st_dev and s1.st_ino == s2.st_ino;
    }
    if (std.mem.eql(u8, op, "-nt")) {
        const s1 = statFile(l, true);
        const s2 = statFile(r, true);
        if (s1 == null) return false;
        if (s2 == null) return true;
        return s1.?.st_mtim.tv_sec > s2.?.st_mtim.tv_sec or (s1.?.st_mtim.tv_sec == s2.?.st_mtim.tv_sec and s1.?.st_mtim.tv_nsec > s2.?.st_mtim.tv_nsec);
    }
    if (std.mem.eql(u8, op, "-ot")) {
        const s1 = statFile(l, true);
        const s2 = statFile(r, true);
        if (s2 == null) return false;
        if (s1 == null) return true;
        return s1.?.st_mtim.tv_sec < s2.?.st_mtim.tv_sec or (s1.?.st_mtim.tv_sec == s2.?.st_mtim.tv_sec and s1.?.st_mtim.tv_nsec < s2.?.st_mtim.tv_nsec);
    }
    return null;
}
