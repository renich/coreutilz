const std = @import("std");
const c = @import("../../compat/c.zig").c;

var global_file_manager: ?*FileManager = null;

fn csplitSignalHandler(sig: c_int) callconv(.c) void {
    if (global_file_manager) |fm| {
        fm.cleanupFiles();
    }
    _ = c.signal(sig, c.SIG_DFL);
    _ = c.raise(sig);
}

pub const FileManager = struct {
    allocator: std.mem.Allocator,
    prefix: []const u8,
    suffix_format: ?[:0]const u8,
    digits: usize,
    keep_files: bool,
    silent: bool,
    elide_empty: bool,

    files_created: std.ArrayList([:0]const u8),
    current_fd: c_int = -1,
    current_filename: ?[:0]const u8 = null,
    bytes_written: u64 = 0,
    file_counter: usize = 0,

    pub fn init(
        allocator: std.mem.Allocator,
        prefix: []const u8,
        suffix_format: ?[:0]const u8,
        digits: usize,
        keep_files: bool,
        silent: bool,
        elide_empty: bool,
    ) FileManager {
        var fm = FileManager{
            .allocator = allocator,
            .prefix = prefix,
            .suffix_format = suffix_format,
            .digits = digits,
            .keep_files = keep_files,
            .silent = silent,
            .elide_empty = elide_empty,
            .files_created = .empty,
        };
        global_file_manager = &fm;
        registerSignals();
        return fm;
    }

    pub fn deinit(self: *FileManager) void {
        if (self.current_fd >= 0) {
            _ = c.close(self.current_fd);
            self.current_fd = -1;
        }
        for (self.files_created.items) |name| {
            self.allocator.free(name);
        }
        self.files_created.deinit(self.allocator);
        if (global_file_manager == self) {
            global_file_manager = null;
            restoreSignals();
        }
    }

    fn registerSignals() void {
        const signals = [_]c_int{ c.SIGINT, c.SIGTERM, c.SIGHUP, c.SIGQUIT };
        for (signals) |sig| {
            _ = c.signal(sig, csplitSignalHandler);
        }
    }

    fn restoreSignals() void {
        const signals = [_]c_int{ c.SIGINT, c.SIGTERM, c.SIGHUP, c.SIGQUIT };
        for (signals) |sig| {
            _ = c.signal(sig, c.SIG_DFL);
        }
    }

    pub fn cleanupFiles(self: *FileManager) void {
        if (self.keep_files) return;
        for (self.files_created.items) |name| {
            _ = c.unlink(name.ptr);
        }
    }

    pub fn makeFilename(self: *FileManager, num: usize) ![:0]const u8 {
        var buf: [4096]u8 = undefined;
        if (self.suffix_format) |fmt| {
            var suff_buf: [1024]u8 = undefined;
            const written = c.snprintf(&suff_buf, suff_buf.len, fmt.ptr, @as(c_int, @intCast(num)));
            if (written < 0) return error.FormatError;
            const suff_slice = suff_buf[0..@intCast(written)];
            const full = try std.fmt.bufPrint(&buf, "{s}{s}", .{ self.prefix, suff_slice });
            return self.allocator.dupeZ(u8, full);
        }
        var suff_buf: [64]u8 = undefined;
        const suff = try formatDecimal(num, self.digits, &suff_buf);
        const full = try std.fmt.bufPrint(&buf, "{s}{s}", .{ self.prefix, suff });
        return self.allocator.dupeZ(u8, full);
    }

    fn formatDecimal(num: usize, min_digits: usize, buf: *[64]u8) ![]const u8 {
        var temp: [64]u8 = undefined;
        const num_str = try std.fmt.bufPrint(&temp, "{d}", .{num});
        if (num_str.len >= min_digits) {
            @memcpy(buf[0..num_str.len], num_str);
            return buf[0..num_str.len];
        }
        const pad = min_digits - num_str.len;
        @memset(buf[0..pad], '0');
        @memcpy(buf[pad .. pad + num_str.len], num_str);
        return buf[0..min_digits];
    }

    pub fn createOutputFile(self: *FileManager, stdout: anytype, stderr: anytype) !void {
        if (self.current_fd >= 0) {
            try self.closeOutputFile(stdout, stderr);
        }
        const fname = try self.makeFilename(self.file_counter);
        errdefer self.allocator.free(fname);

        const fd = c.open(fname.ptr, c.O_WRONLY | c.O_CREAT | c.O_TRUNC, @as(c_uint, 0o666));
        if (fd < 0) {
            const err_msg = std.mem.sliceTo(c.strerror(c.__errno_location().*), 0);
            try stderr.print("csplit: {s}: {s}\n", .{ fname, err_msg });
            self.cleanupFiles();
            return error.OpenFailed;
        }

        self.current_fd = fd;
        self.current_filename = fname;
        self.bytes_written = 0;
        self.file_counter += 1;
        try self.files_created.append(self.allocator, fname);
    }

    pub fn writeLine(self: *FileManager, line: []const u8, stderr: anytype) !void {
        if (self.current_fd < 0) return error.NoOpenFile;
        var written: usize = 0;
        while (written < line.len) {
            const n = c.write(self.current_fd, line.ptr + written, line.len - written);
            if (n < 0) {
                const name = self.current_filename orelse "output";
                const err_msg = std.mem.sliceTo(c.strerror(c.__errno_location().*), 0);
                try stderr.print("csplit: {s}: {s}\n", .{ name, err_msg });
                self.cleanupFiles();
                return error.WriteFailed;
            }
            written += @intCast(n);
        }
        self.bytes_written += line.len;
    }

    pub fn closeOutputFile(self: *FileManager, stdout: anytype, stderr: anytype) !void {
        if (self.current_fd < 0) return;
        _ = c.close(self.current_fd);
        self.current_fd = -1;

        const fname = self.current_filename orelse return;
        self.current_filename = null;

        if (self.bytes_written == 0 and self.elide_empty) {
            if (c.unlink(fname.ptr) != 0 and c.__errno_location().* != c.ENOENT) {
                const err_msg = std.mem.sliceTo(c.strerror(c.__errno_location().*), 0);
                try stderr.print("csplit: {s}: {s}\n", .{ fname, err_msg });
            }
            if (self.files_created.items.len > 0) {
                const last_idx = self.files_created.items.len - 1;
                self.allocator.free(self.files_created.items[last_idx]);
                _ = self.files_created.pop();
            }
            if (self.file_counter > 0) self.file_counter -= 1;
        } else {
            if (!self.silent) {
                try stdout.print("{d}\n", .{self.bytes_written});
            }
        }
        self.bytes_written = 0;
    }
};
