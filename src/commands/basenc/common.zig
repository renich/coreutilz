const std = @import("std");

pub const EncodingType = enum {
    base64,
    base64url,
    base32,
    base32hex,
    base16,
    base2msbf,
    base2lsbf,
    z85,
    base58,
};

pub const Options = struct {
    decode: bool = false,
    ignore_garbage: bool = false,
    wrap_column: usize = 76,
    encoding: ?EncodingType = null,
    file_path: ?[]const u8 = null,
};

pub const WrapWriter = struct {
    writer: *std.Io.Writer,
    wrap_column: usize,
    current_col: usize = 0,
    has_written: bool = false,

    pub fn init(writer: *std.Io.Writer, wrap_column: usize) WrapWriter {
        return .{
            .writer = writer,
            .wrap_column = wrap_column,
            .current_col = 0,
            .has_written = false,
        };
    }

    pub fn writeChunk(self: *WrapWriter, bytes: []const u8) !void {
        if (bytes.len == 0) return;
        self.has_written = true;
        if (self.wrap_column == 0) {
            try self.writer.writeAll(bytes);
            return;
        }

        var offset: usize = 0;
        while (offset < bytes.len) {
            const avail = self.wrap_column - self.current_col;
            if (avail == 0) {
                try self.writer.writeByte('\n');
                self.current_col = 0;
                continue;
            }
            const to_write = @min(avail, bytes.len - offset);
            try self.writer.writeAll(bytes[offset .. offset + to_write]);
            self.current_col += to_write;
            offset += to_write;
        }
    }

    pub fn finish(self: *WrapWriter) !void {
        if (self.wrap_column > 0 and self.has_written) {
            try self.writer.writeByte('\n');
        }
    }
};

pub fn parseWrapArg(cmd_name: []const u8, arg: []const u8) !usize {
    if (arg.len == 0) {
        emitInvalidWrap(cmd_name, arg);
        return error.InvalidWrap;
    }
    for (arg) |c| {
        if (c < '0' or c > '9') {
            emitInvalidWrap(cmd_name, arg);
            return error.InvalidWrap;
        }
    }
    return std.fmt.parseInt(usize, arg, 10) catch {
        emitInvalidWrap(cmd_name, arg);
        return error.InvalidWrap;
    };
}

fn emitInvalidWrap(cmd_name: []const u8, arg: []const u8) void {
    var stderr_buf: [256]u8 = undefined;
    var writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stderr = &writer.interface;
    stderr.print("{s}: invalid wrap size: '{s}'\n", .{ cmd_name, arg }) catch {};
    writer.interface.flush() catch {};
}

pub fn emitTryHelp(cmd_name: []const u8) void {
    var stderr_buf: [256]u8 = undefined;
    var writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stderr = &writer.interface;
    stderr.print("Try '{s} --help' for more information.\n", .{cmd_name}) catch {};
    writer.interface.flush() catch {};
}

pub fn emitExtraOperand(cmd_name: []const u8, op: []const u8) void {
    var stderr_buf: [256]u8 = undefined;
    var writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stderr = &writer.interface;
    stderr.print("{s}: extra operand '{s}'\n", .{ cmd_name, op }) catch {};
    writer.interface.flush() catch {};
    emitTryHelp(cmd_name);
}

pub fn emitOptionRequiresArgLong(cmd_name: []const u8, opt: []const u8) void {
    var stderr_buf: [256]u8 = undefined;
    var writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stderr = &writer.interface;
    stderr.print("{s}: option '{s}' requires an argument\n", .{ cmd_name, opt }) catch {};
    writer.interface.flush() catch {};
    emitTryHelp(cmd_name);
}

pub fn emitInvalidInput(cmd_name: []const u8) void {
    var stderr_buf: [256]u8 = undefined;
    var writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stderr = &writer.interface;
    stderr.print("{s}: invalid input\n", .{cmd_name}) catch {};
    writer.interface.flush() catch {};
}

pub fn emitZ85InvalidLength(cmd_name: []const u8) void {
    var stderr_buf: [256]u8 = undefined;
    var writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
    const stderr = &writer.interface;
    stderr.print("{s}: invalid input (length must be multiple of 4 characters)\n", .{cmd_name}) catch {};
    writer.interface.flush() catch {};
}

pub fn openInputFile(cmd_name: []const u8, path: ?[]const u8) !std.Io.File {
    if (path == null or std.mem.eql(u8, path.?, "-")) {
        return std.Io.File.stdin();
    }
    return std.Io.Dir.cwd().openFile(std.Options.debug_io, path.?, .{ .mode = .read_only }) catch |err| {
        var stderr_buf: [256]u8 = undefined;
        var writer: std.Io.File.Writer = .initStreaming(.stderr(), std.Options.debug_io, &stderr_buf);
        const stderr = &writer.interface;
        const c = @import("../../compat/c.zig").c;
        const errno_val = c.__errno_location().*;
        if (errno_val != 0) {
            const err_str = std.mem.span(c.strerror(errno_val));
            stderr.print("{s}: {s}: {s}\n", .{ cmd_name, path.?, err_str }) catch {};
        } else {
            stderr.print("{s}: {s}: {s}\n", .{ cmd_name, path.?, @errorName(err) }) catch {};
        }
        writer.interface.flush() catch {};
        return err;
    };
}
