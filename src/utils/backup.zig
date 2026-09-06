const std = @import("std");
const c = @import("../compat/c.zig").c;

pub const BackupType = enum {
    none,
    simple,
    numbered,
    existing,
};

pub fn parseBackupType(str: []const u8) ?BackupType {
    if (std.mem.eql(u8, str, "none") or std.mem.eql(u8, str, "off")) return .none;
    if (std.mem.eql(u8, str, "simple") or std.mem.eql(u8, str, "never")) return .simple;
    if (std.mem.eql(u8, str, "existing") or std.mem.eql(u8, str, "nil")) return .existing;
    if (std.mem.eql(u8, str, "numbered") or std.mem.eql(u8, str, "t")) return .numbered;
    return null;
}

pub fn getVersionControl() BackupType {
    if (std.c.getenv("VERSION_CONTROL")) |val| {
        const s = std.mem.span(val);
        if (parseBackupType(s)) |bt| return bt;
    }
    return .existing;
}

pub fn getSimpleBackupSuffix() []const u8 {
    if (std.c.getenv("SIMPLE_BACKUP_SUFFIX")) |val| {
        const s = std.mem.span(val);
        if (s.len > 0) return s;
    }
    return "~";
}

/// Computes the backup file path for a destination according to backup_type and suffix.
/// Returns null if backup_type is .none. Caller owns returned memory.
pub fn findBackupPath(
    allocator: std.mem.Allocator,
    path: []const u8,
    backup_type: BackupType,
    suffix: []const u8,
) !?[]const u8 {
    if (backup_type == .none) return null;

    // Trim trailing slashes from path (e.g. "E/" -> "E")
    var trimmed_path = path;
    while (trimmed_path.len > 1 and trimmed_path[trimmed_path.len - 1] == '/') {
        trimmed_path = trimmed_path[0 .. trimmed_path.len - 1];
    }

    var actual_type = backup_type;
    if (actual_type == .existing) {
        // Check if path.~1~ exists
        const test_path = try std.fmt.allocPrint(allocator, "{s}.~1~", .{trimmed_path});
        defer allocator.free(test_path);
        const test_z = try allocator.dupeZ(u8, test_path);
        defer allocator.free(test_z);
        var st: c.struct_stat = undefined;
        if (c.lstat(test_z.ptr, &st) == 0) {
            actual_type = .numbered;
        } else {
            actual_type = .simple;
        }
    }

    if (actual_type == .simple) {
        return try std.fmt.allocPrint(allocator, "{s}{s}", .{ trimmed_path, suffix });
    }

    // Numbered backup: find lowest N starting from 1 that doesn't exist
    var n: usize = 1;
    while (true) : (n += 1) {
        const test_path = try std.fmt.allocPrint(allocator, "{s}.~{d}~", .{ trimmed_path, n });
        defer allocator.free(test_path);
        const test_z = try allocator.dupeZ(u8, test_path);
        defer allocator.free(test_z);
        var st: c.struct_stat = undefined;
        if (c.lstat(test_z.ptr, &st) != 0) {
            return try std.fmt.allocPrint(allocator, "{s}.~{d}~", .{ trimmed_path, n });
        }
    }
}

/// Checks if backing up dest would destroy the source file.
pub fn isBackupSource(
    backup_path: []const u8,
    source_path: []const u8,
) bool {
    var b_st: c.struct_stat = undefined;
    var s_st: c.struct_stat = undefined;

    // Use a stack buffer for null termination
    var b_buf: [4096]u8 = undefined;
    var s_buf: [4096]u8 = undefined;
    if (backup_path.len >= b_buf.len or source_path.len >= s_buf.len) return false;

    @memcpy(b_buf[0..backup_path.len], backup_path);
    b_buf[backup_path.len] = 0;
    @memcpy(s_buf[0..source_path.len], source_path);
    s_buf[source_path.len] = 0;

    if (c.stat(&b_buf, &b_st) == 0 and c.stat(&s_buf, &s_st) == 0) {
        return (b_st.st_dev == s_st.st_dev and b_st.st_ino == s_st.st_ino);
    }
    return false;
}
