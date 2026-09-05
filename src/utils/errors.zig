const std = @import("std");

/// Common error types for coreutilz commands
pub const CoreutilzError = error{
    InvalidArgument,
    MissingOperand,
    InvalidOperation,
    PermissionDenied,
    FileNotFound,
    OutOfMemory,
    IoError,
};

/// Print error message to stderr in coreutils-compatible format
pub fn printError(writer: anytype, command: []const u8, message: []const u8) !void {
    try writer.print("{s}: {s}\n", .{ command, message });
}

/// Print error with errno-style formatting
pub fn printErrorWithArg(writer: anytype, command: []const u8, arg: []const u8, err: anyerror) !void {
    try writer.print("{s}: {s}: {s}\n", .{ command, arg, @errorName(err) });
}

/// Standard version string format
pub fn printVersion(writer: anytype, command: []const u8, version: []const u8) !void {
    try writer.print("{s} (coreutilz) {s}\n", .{ command, version });
    try writer.print("Copyright (C) 2025 EVALinux\n", .{});
    try writer.print("License MIT: The MIT License <https://opensource.org/licenses/MIT>\n", .{});
    try writer.print("This is free software: you are free to change and redistribute it.\n", .{});
    try writer.print("There is NO WARRANTY, to the extent permitted by law.\n", .{});
}

/// Check if running with POSIXLY_CORRECT environment variable
pub fn isPosixlyCorrect() bool {
    const env = std.process.getEnvVarOwned(std.heap.page_allocator, "POSIXLY_CORRECT") catch return false;
    defer std.heap.page_allocator.free(env);
    return true;
}
