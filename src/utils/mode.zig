const std = @import("std");

pub fn parseMode(spec: []const u8, initial_mode: u32, is_dir: bool, umask_val: u32) !u32 {
    if (spec.len == 0) return error.InvalidMode;

    if (spec[0] == ',' or spec[spec.len - 1] == ',') return error.InvalidMode;
    if (std.mem.indexOf(u8, spec, ",,") != null) return error.InvalidMode;

    var mode = initial_mode & 0o7777;
    var clause_it = std.mem.splitScalar(u8, spec, ',');

    while (clause_it.next()) |clause| {
        if (clause.len == 0) return error.InvalidMode;

        var clause_op: ?u8 = null;
        var digits = clause;
        if (clause[0] == '+' or clause[0] == '-' or clause[0] == '=') {
            clause_op = clause[0];
            digits = clause[1..];
        } else if (clause[0] >= '0' and clause[0] <= '7') {
            clause_op = '=';
            digits = clause;
        }

        var is_octal = false;
        if (clause_op != null and digits.len > 0) {
            is_octal = true;
            for (digits) |ch| {
                if (ch < '0' or ch > '7') {
                    is_octal = false;
                    break;
                }
            }
        }

        if (is_octal) {
            if (digits.len > 7) return error.InvalidMode;
            const num = std.fmt.parseInt(u32, digits, 8) catch return error.InvalidMode;
            if (num > 0o7777) return error.InvalidMode;
            var val = num & 0o7777;
            switch (clause_op.?) {
                '+' => mode |= val,
                '-' => mode &= ~val,
                '=' => {
                    if (clause[0] != '=' and digits.len < 5 and is_dir) {
                        val |= (mode & 0o6000);
                    }
                    mode = val;
                },
                else => unreachable,
            }
            continue;
        }

        var idx: usize = 0;

        var explicit_who = false;
        var who_mask: u32 = 0;

        while (idx < clause.len) : (idx += 1) {
            switch (clause[idx]) {
                'u' => {
                    explicit_who = true;
                    who_mask |= 0o4700;
                },
                'g' => {
                    explicit_who = true;
                    who_mask |= 0o2070;
                },
                'o' => {
                    explicit_who = true;
                    who_mask |= 0o1007;
                },
                'a' => {
                    explicit_who = true;
                    who_mask |= 0o7777;
                },
                '+', '-', '=' => break,
                else => return error.InvalidMode,
            }
        }

        if (!explicit_who) {
            who_mask = 0o7777 & ~umask_val;
        }

        if (idx >= clause.len) return error.InvalidMode;

        // Process one or more actions in this clause (e.g. "=+x", "=xX", "=x-w", "--")
        while (idx < clause.len) {
            const op = clause[idx];
            if (op != '+' and op != '-' and op != '=') return error.InvalidMode;
            idx += 1;

            var perm_val: u32 = 0;
            var copy_from: ?u8 = null;

            if (idx < clause.len and (clause[idx] == 'u' or clause[idx] == 'g' or clause[idx] == 'o')) {
                copy_from = clause[idx];
                idx += 1;
                if (idx < clause.len and clause[idx] != '+' and clause[idx] != '-' and clause[idx] != '=') {
                    return error.InvalidMode;
                }
            } else {
                while (idx < clause.len) : (idx += 1) {
                    const ch = clause[idx];
                    if (ch == '+' or ch == '-' or ch == '=') break;
                    switch (ch) {
                        'r' => perm_val |= 0o444,
                        'w' => perm_val |= 0o222,
                        'x' => perm_val |= 0o111,
                        'X' => {
                            if (is_dir or (mode & 0o111 != 0)) {
                                perm_val |= 0o111;
                            }
                        },
                        's' => perm_val |= 0o6000,
                        't' => perm_val |= 0o1000,
                        else => return error.InvalidMode,
                    }
                }
            }

            if (copy_from) |src| {
                const src_bits: u32 = switch (src) {
                    'u' => (mode >> 6) & 7,
                    'g' => (mode >> 3) & 7,
                    'o' => mode & 7,
                    else => unreachable,
                };
                perm_val = (src_bits << 6) | (src_bits << 3) | src_bits;
            }

            const affected = perm_val & who_mask;

            switch (op) {
                '+' => mode |= affected,
                '-' => mode &= ~affected,
                '=' => {
                    const clear_mask = if (explicit_who) who_mask else 0o7777;
                    mode = (mode & ~clear_mask) | affected;
                },
                else => return error.InvalidMode,
            }
        }
    }

    return mode;
}

pub fn formatMode(mode: u32, buf: *[9]u8) []const u8 {
    buf[0] = if (mode & 0o400 != 0) 'r' else '-';
    buf[1] = if (mode & 0o200 != 0) 'w' else '-';
    buf[2] = if (mode & 0o4000 != 0)
        (if (mode & 0o100 != 0) 's' else 'S')
    else
        (if (mode & 0o100 != 0) 'x' else '-');

    buf[3] = if (mode & 0o040 != 0) 'r' else '-';
    buf[4] = if (mode & 0o020 != 0) 'w' else '-';
    buf[5] = if (mode & 0o2000 != 0)
        (if (mode & 0o010 != 0) 's' else 'S')
    else
        (if (mode & 0o010 != 0) 'x' else '-');

    buf[6] = if (mode & 0o004 != 0) 'r' else '-';
    buf[7] = if (mode & 0o002 != 0) 'w' else '-';
    buf[8] = if (mode & 0o1000 != 0)
        (if (mode & 0o001 != 0) 't' else 'T')
    else
        (if (mode & 0o001 != 0) 'x' else '-');

    return buf;
}

test "mode parsing" {
    const m1 = try parseMode("u=rwx,g=rx,o=w,-s,+t", 0o777, true, 0o022);
    try std.testing.expectEqual(@as(u32, 0o1752), m1);

    const m2 = try parseMode("=+x", 0o777, true, 0o027);
    try std.testing.expectEqual(@as(u32, 0o110), m2);

    const m3 = try parseMode("o-w", 0o777, true, 0o022);
    try std.testing.expectEqual(@as(u32, 0o775), m3);

    const m4 = try parseMode("a-r", 0o777, true, 0o022);
    try std.testing.expectEqual(@as(u32, 0o333), m4);

    const m5 = try parseMode("=,u=rwx", 0o777, true, 0o077);
    try std.testing.expectEqual(@as(u32, 0o700), m5);
}

test "more mode tests" {
    // Octal string
    const m1 = try parseMode("755", 0o777, true, 0o022);
    try std.testing.expectEqual(@as(u32, 0o755), m1);

    const m2 = try parseMode("016", 0o777, true, 0o000);
    try std.testing.expectEqual(@as(u32, 0o016), m2);

    const m_eq = try parseMode("=777", 0o777, true, 0o022);
    try std.testing.expectEqual(@as(u32, 0o777), m_eq);

    // =+X on directory with umask 027
    const m3 = try parseMode("=+X", 0o777, true, 0o027);
    try std.testing.expectEqual(@as(u32, 0o110), m3);

    // u=rwx,go=rx
    const m4 = try parseMode("u=rwx,go=rx", 0, true, 0o022);
    try std.testing.expectEqual(@as(u32, 0o755), m4);

    // equals test from upstream equals.sh
    const m5 = try parseMode("a=,u=rwx,g=u,u=", 0, false, 0o022);
    try std.testing.expectEqual(@as(u32, 0o070), m5);

    // =u with umask 027
    const m6 = try parseMode("a=,u=rwx,=u", 0, false, 0o027);
    try std.testing.expectEqual(@as(u32, 0o750), m6);

    // equal-x test from upstream equal-x.sh
    const m7 = try parseMode("a=r,=x", 0, false, 0o005);
    try std.testing.expectEqual(@as(u32, 0o110), m7);

    // -- no-op
    const m8 = try parseMode("--", 0o644, false, 0o022);
    try std.testing.expectEqual(@as(u32, 0o644), m8);

    // relative octal modes from setgid.sh
    const m9 = try parseMode("-2000", 0o2755, true, 0o022);
    try std.testing.expectEqual(@as(u32, 0o0755), m9);

    const m10 = try parseMode("+2000", 0o0755, true, 0o022);
    try std.testing.expectEqual(@as(u32, 0o2755), m10);

    const m11 = try parseMode("=7777,-5022", 0, true, 0o022);
    try std.testing.expectEqual(@as(u32, 0o2755), m11);
}

test "formatMode" {
    var buf: [9]u8 = undefined;
    try std.testing.expectEqualStrings("rwxr--r--", formatMode(0o744, &buf));
    try std.testing.expectEqualStrings("rwxrwxr--", formatMode(0o774, &buf));
    try std.testing.expectEqualStrings("rwsr-xr-x", formatMode(0o4755, &buf));
    try std.testing.expectEqualStrings("rwSr-xr-x", formatMode(0o4655, &buf));
    try std.testing.expectEqualStrings("rwxr-sr-x", formatMode(0o2755, &buf));
    try std.testing.expectEqualStrings("rwxr-xr-t", formatMode(0o1755, &buf));
}
