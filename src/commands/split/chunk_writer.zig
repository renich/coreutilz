const std = @import("std");
const file_namer = @import("file_namer.zig");
const c = @import("../../compat/c.zig").c;

extern "c" fn setenv(name: [*:0]const u8, value: [*:0]const u8, overwrite: c_int) c_int;

pub const ChunkWriter = struct {
    filter_cmd: ?[]const u8 = null,
    verbose: bool = false,
    allocator: std.mem.Allocator,
    input_stat: ?c.struct_stat = null,
    current_file: ?std.Io.File = null,
    child_pid: ?c.pid_t = null,
    pipe_fd: ?c_int = null,
    name_buf: std.ArrayList(u8),
    current_name: []const u8 = "",
    has_opened: bool = false,

    pub fn init(allocator: std.mem.Allocator, filter_cmd: ?[]const u8, verbose: bool, in_st: ?c.struct_stat) ChunkWriter {
        return .{
            .filter_cmd = filter_cmd,
            .verbose = verbose,
            .allocator = allocator,
            .input_stat = in_st,
            .name_buf = std.ArrayList(u8).empty,
        };
    }

    pub fn deinit(self: *ChunkWriter) void {
        self.closeCurrent() catch {};
        self.name_buf.deinit(self.allocator);
    }

    pub fn closeCurrent(self: *ChunkWriter) !void {
        if (self.current_file) |f| {
            f.close(std.Options.debug_io);
            self.current_file = null;
        }
        if (self.pipe_fd) |pfd| {
            _ = c.close(pfd);
            self.pipe_fd = null;
        }
        if (self.child_pid) |pid| {
            var status: c_int = 0;
            _ = c.waitpid(pid, &status, 0);
            self.child_pid = null;
            const u_status: u32 = @bitCast(status);
            if (std.posix.W.IFEXITED(u_status)) {
                if (std.posix.W.EXITSTATUS(u_status) != 0) return error.FilterFailed;
            } else if (std.posix.W.IFSIGNALED(u_status)) {
                if (std.posix.W.TERMSIG(u_status) != std.posix.SIG.PIPE) return error.FilterFailed;
            } else {
                return error.FilterFailed;
            }
        }
    }

    pub fn openNew(self: *ChunkWriter, namer: *file_namer.FileNamer, stdout: anytype, stderr: anytype) !void {
        try self.closeCurrent();
        try namer.next(&self.name_buf);
        const name = self.name_buf.items;
        self.current_name = name;
        self.has_opened = true;

        if (self.verbose) {
            stdout.print("creating file '{s}'\n", .{name}) catch {};
        }

        if (self.filter_cmd) |cmd| {
            const name_z = try self.allocator.dupeZ(u8, name);
            defer self.allocator.free(name_z);
            const cmd_z = try self.allocator.dupeZ(u8, cmd);
            defer self.allocator.free(cmd_z);

            var fds: [2]c_int = undefined;
            if (c.pipe(&fds) != 0) return error.PipeFailed;
            const pid = c.fork();
            if (pid < 0) {
                _ = c.close(fds[0]);
                _ = c.close(fds[1]);
                return error.ForkFailed;
            }
            if (pid == 0) {
                _ = c.close(fds[1]);
                if (c.dup2(fds[0], c.STDIN_FILENO) < 0) {
                    c._exit(1);
                }
                _ = c.close(fds[0]);
                _ = setenv("FILE", name_z.ptr, 1);
                const sh_z = "/bin/sh";
                const c_flag = "-c";
                const argv = [_:null]?[*:0]const u8{ sh_z, c_flag, cmd_z.ptr, null };
                _ = c.execv("/bin/sh", @ptrCast(&argv));
                c._exit(127);
            }
            _ = c.close(fds[0]);
            self.pipe_fd = fds[1];
            self.child_pid = pid;
        } else {
            const name_z = try self.allocator.dupeZ(u8, name);
            defer self.allocator.free(name_z);
            const fd = c.open(name_z.ptr, c.O_WRONLY | c.O_CREAT, @as(c_uint, 0o666));
            if (fd < 0) {
                const err_str = std.mem.span(c.strerror(c.__errno_location().*));
                stderr.print("split: {s}: {s}\n", .{ name, err_str }) catch {};
                return error.OpenFailed;
            }
            if (self.input_stat) |in_st| {
                var out_st: c.struct_stat = undefined;
                if (c.fstat(fd, &out_st) == 0) {
                    if (out_st.st_dev == in_st.st_dev and out_st.st_ino == in_st.st_ino) {
                        _ = c.close(fd);
                        stderr.print("split: '{s}' would overwrite input; aborting\n", .{name}) catch {};
                        return error.OverwriteInput;
                    }
                }
            }
            _ = c.ftruncate(fd, 0);
            self.current_file = std.Io.File{ .handle = fd, .flags = .{ .nonblocking = false } };
        }
    }

    pub fn writeAll(self: *ChunkWriter, bytes: []const u8, stderr: anytype) !void {
        if (self.current_file) |f| {
            var written: usize = 0;
            while (written < bytes.len) {
                const nw = c.write(f.handle, bytes[written..].ptr, bytes.len - written);
                if (nw <= 0) {
                    const err_str = std.mem.span(c.strerror(c.__errno_location().*));
                    stderr.print("split: {s}: {s}\n", .{ self.current_name, err_str }) catch {};
                    return error.WriteFailed;
                }
                written += @intCast(nw);
            }
        } else if (self.pipe_fd) |pfd| {
            var written: usize = 0;
            while (written < bytes.len) {
                const nw = c.write(pfd, bytes[written..].ptr, bytes.len - written);
                if (nw <= 0) {
                    const err_no = c.__errno_location().*;
                    if (err_no == c.EPIPE) return error.BrokenPipe;
                    const err_str = std.mem.span(c.strerror(err_no));
                    stderr.print("split: {s}: {s}\n", .{ self.current_name, err_str }) catch {};
                    return error.WriteFailed;
                }
                written += @intCast(nw);
            }
        }
    }
};
