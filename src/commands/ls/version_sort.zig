const std = @import("std");

fn orderChar(c_opt: ?u8) u16 {
    const byte = c_opt orelse return 1; // empty string rank
    if (byte == '~') return 0;
    const val: u16 = byte;
    if (std.ascii.isAlphabetic(byte)) return 2 + val;
    return 300 + val;
}

fn verrevcmp(a: []const u8, b: []const u8) std.math.Order {
    var i: usize = 0;
    var j: usize = 0;
    while (i < a.len or j < b.len) {
        var first_diff: std.math.Order = .eq;
        while ((i < a.len and !std.ascii.isDigit(a[i])) or (j < b.len and !std.ascii.isDigit(b[j]))) {
            const ca = if (i < a.len and !std.ascii.isDigit(a[i])) a[i] else null;
            const cb = if (j < b.len and !std.ascii.isDigit(b[j])) b[j] else null;
            const rank_a = orderChar(ca);
            const rank_b = orderChar(cb);
            if (rank_a != rank_b) return std.math.order(rank_a, rank_b);
            if (ca != null) i += 1;
            if (cb != null) j += 1;
        }

        while (i < a.len and a[i] == '0') : (i += 1) {}
        while (j < b.len and b[j] == '0') : (j += 1) {}
        const i_num_start = i;
        const j_num_start = j;
        while (i < a.len and std.ascii.isDigit(a[i])) : (i += 1) {}
        while (j < b.len and std.ascii.isDigit(b[j])) : (j += 1) {}
        const len_a = i - i_num_start;
        const len_b = j - j_num_start;
        if (len_a != len_b) return std.math.order(len_a, len_b);
        var k: usize = 0;
        while (k < len_a) : (k += 1) {
            if (a[i_num_start + k] != b[j_num_start + k]) {
                if (first_diff == .eq) first_diff = std.math.order(a[i_num_start + k], b[j_num_start + k]);
            }
        }
        if (first_diff != .eq) return first_diff;
    }
    return std.mem.order(u8, a, b);
}

fn findSuffix(s: []const u8) usize {
    var i = s.len;
    var best = s.len;
    while (i > 0) {
        const dot = std.mem.lastIndexOfScalar(u8, s[0..i], '.') orelse break;
        if (dot == 0 or dot + 1 >= s.len) break;
        const next = s[dot + 1];
        if (!std.ascii.isAlphabetic(next) and next != '~') break;
        var k = dot + 2;
        var valid = true;
        while (k < i) : (k += 1) {
            const ch = s[k];
            if (!std.ascii.isAlphanumeric(ch) and ch != '~') {
                valid = false;
                break;
            }
        }
        if (!valid) break;
        best = dot;
        i = dot;
    }
    return best;
}

pub fn versionCompare(a: []const u8, b: []const u8) std.math.Order {
    if (std.mem.eql(u8, a, b)) return .eq;
    if (a.len == 0) return .lt;
    if (b.len == 0) return .gt;
    if (std.mem.eql(u8, a, ".")) return .lt;
    if (std.mem.eql(u8, b, ".")) return .gt;
    if (std.mem.eql(u8, a, "..")) return .lt;
    if (std.mem.eql(u8, b, "..")) return .gt;
    if (a[0] == '.' and b[0] != '.') return .lt;
    if (a[0] != '.' and b[0] == '.') return .gt;

    const s_a = findSuffix(a);
    const s_b = findSuffix(b);
    const pref_cmp = verrevcmp(a[0..s_a], b[0..s_b]);
    if (pref_cmp != .eq) return pref_cmp;
    return verrevcmp(a, b);
}
