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

/// Convert an error into standard POSIX/GNU strerror message
pub fn errorDescription(err: anyerror) []const u8 {
    return switch (err) {
        error.FileNotFound => "No such file or directory",
        error.IsDir => "Is a directory",
        error.NotDir => "Not a directory",
        error.AccessDenied, error.PermissionDenied => "Permission denied",
        error.NoSpaceLeft, error.DiskFull => "No space left on device",
        error.FileTooBig => "File too large",
        error.BrokenPipe => "Broken pipe",
        error.PathAlreadyExists => "File exists",
        error.NameTooLong => "File name too long",
        error.NotOpenForReading, error.NotOpenForWriting => "Bad file descriptor",
        error.SystemResources, error.OutOfMemory => "Cannot allocate memory",
        error.SharingViolation, error.DeviceBusy => "Device or resource busy",
        error.ReadOnlyFileSystem => "Read-only file system",
        error.SymLinkLoop => "Too many levels of symbolic links",
        error.FileBusy => "Text file busy",
        error.NoDevice => "No such device or address",
        error.ProcessNotFound => "No such process",
        error.NetworkUnreachable => "Network is unreachable",
        error.ConnectionRefused => "Connection refused",
        error.InvalidCharacter, error.InvalidArgument => "Invalid argument",
        else => @errorName(err),
    };
}

/// Print error with errno-style formatting
pub fn printErrorWithArg(writer: anytype, command: []const u8, arg: []const u8, err: anyerror) !void {
    try writer.print("{s}: {s}: {s}\n", .{ command, arg, errorDescription(err) });
}

/// Print error message followed by the GNU "Try '<command> --help' for more information." line
pub fn printErrorWithHelp(writer: anytype, command: []const u8, message: []const u8) !void {
    try writer.print("{s}: {s}\nTry '{s} --help' for more information.\n", .{ command, message, command });
}

/// Print missing operand error with help prompt
pub fn printMissingOperand(writer: anytype, command: []const u8) !void {
    try printErrorWithHelp(writer, command, "missing operand");
}

/// Print extra operand error with help prompt (e.g. "extra operand 'foo'")
pub fn printExtraOperand(writer: anytype, command: []const u8, operand: []const u8) !void {
    try writer.print("{s}: extra operand '{s}'\nTry '{s} --help' for more information.\n", .{ command, operand, command });
}

/// Print invalid short option error with help prompt (e.g. "invalid option -- 'x'")
pub fn printInvalidOption(writer: anytype, command: []const u8, opt: u8) !void {
    try writer.print("{s}: invalid option -- '{c}'\nTry '{s} --help' for more information.\n", .{ command, opt, command });
}

/// Print unrecognized long option error with help prompt (e.g. "unrecognized option '--foo'")
pub fn printUnrecognizedOption(writer: anytype, command: []const u8, opt: []const u8) !void {
    try writer.print("{s}: unrecognized option '{s}'\nTry '{s} --help' for more information.\n", .{ command, opt, command });
}

/// Print ambiguous option error with help prompt (e.g. "option '--ver' is ambiguous")
pub fn printAmbiguousOption(writer: anytype, command: []const u8, opt: []const u8) !void {
    try writer.print("{s}: option '{s}' is ambiguous\nTry '{s} --help' for more information.\n", .{ command, opt, command });
}

/// Standard version string format
pub fn printVersion(writer: anytype, command: []const u8, version: []const u8) !void {
    try writer.print("{s} (coreutilz) {s}\n", .{ command, version });
    try writer.print("Copyright (C) 2026 EVALinux\n", .{});
    try writer.print("License GPLv3+: GNU GPL version 3 or later <https://gnu.org/licenses/gpl.html>.\n", .{});
    try writer.print("This is free software: you are free to change and redistribute it.\n", .{});
    try writer.print("There is NO WARRANTY, to the extent permitted by law.\n", .{});
}

/// Check if running with POSIXLY_CORRECT environment variable
pub fn isPosixlyCorrect() bool {
    return std.c.getenv("POSIXLY_CORRECT") != null;
}
