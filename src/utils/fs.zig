const std = @import("std");

/// Copy file with metadata preservation
pub fn copyFile(src: []const u8, dst: []const u8, preserve: bool) !void {
    const src_file = try std.fs.cwd().openFile(src, .{});
    defer src_file.close();

    const dst_file = try std.fs.cwd().createFile(dst, .{});
    defer dst_file.close();

    const metadata = try src_file.metadata();
    const size = metadata.size();

    // Use sendfile for large files if available, otherwise buffered copy
    if (size > 1024 * 1024) {
        // Try sendfile for large files
        _ = try std.os.sendfile(dst_file.handle, src_file.handle, 0, size, &.{}, &.{}, 0);
    } else {
        // Buffered copy for small files
        var buffer: [8192]u8 = undefined;
        while (true) {
            const bytes_read = try src_file.read(&buffer);
            if (bytes_read == 0) break;
            try dst_file.writeAll(buffer[0..bytes_read]);
        }
    }

    if (preserve) {
        // Preserve permissions and timestamps
        try dst_file.chmod(metadata.permissions().inner);
        // Note: preserving timestamps requires platform-specific code
    }
}

/// Check if path is a directory
pub fn isDir(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .directory;
}

/// Check if path is a regular file
pub fn isFile(path: []const u8) bool {
    const stat = std.fs.cwd().statFile(path) catch return false;
    return stat.kind == .file;
}

/// Check if path exists
pub fn exists(path: []const u8) bool {
    std.fs.cwd().access(path, .{}) catch return false;
    return true;
}

/// Get absolute path
pub fn realpath(allocator: std.mem.Allocator, path: []const u8) ![]u8 {
    return try std.fs.cwd().realpathAlloc(allocator, path);
}

/// Create directory recursively
pub fn mkdirRecursive(path: []const u8, mode: u32) !void {
    try std.fs.cwd().makePath(path);
    _ = mode; // Mode handling is platform-specific
}

/// Remove directory recursively
pub fn rmdirRecursive(path: []const u8) !void {
    try std.fs.cwd().deleteTree(path);
}
