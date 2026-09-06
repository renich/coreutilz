const std = @import("std");
const io = std.testing.io;

pub const EnvMap = std.process.Environ.Map;

/// Test context for running command tests.
pub const TestContext = struct {
    allocator: std.mem.Allocator,
    tmp_dir: std.testing.TmpDir,

    pub fn init(allocator: std.mem.Allocator) !TestContext {
        return TestContext{
            .allocator = allocator,
            .tmp_dir = std.testing.tmpDir(.{}),
        };
    }

    pub fn deinit(self: *TestContext) void {
        self.tmp_dir.cleanup();
    }

    /// Return the realpath of subpath inside the tmp dir (caller frees).
    /// The path must already exist. Use tmpPathRaw for nonexistent paths.
    pub fn tmpPath(self: *TestContext, subpath: []const u8) ![]u8 {
        var base_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const n = try self.tmp_dir.dir.realPathFile(io, subpath, &base_buf);
        return self.allocator.dupe(u8, base_buf[0..n]);
    }

    /// Build an absolute path for subpath inside the tmp dir without requiring
    /// it to exist (caller frees). Uses the realpath of "." as base.
    pub fn tmpPathRaw(self: *TestContext, subpath: []const u8) ![]u8 {
        var base_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const len = try self.tmp_dir.dir.realPath(io, &base_buf);
        return std.fs.path.join(self.allocator, &.{ base_buf[0..len], subpath });
    }

    /// Read a file from the tmp dir and compare to expected. Returns true if equal.
    pub fn compareContent(self: *TestContext, expected: []const u8, path: []const u8) !bool {
        const actual = self.readFile(path) catch return false;
        defer self.allocator.free(actual);
        return std.mem.eql(u8, expected, actual);
    }

    /// Write content to a file in the tmp dir.
    pub fn writeFile(self: *TestContext, path: []const u8, content: []const u8) !void {
        const file = try self.tmp_dir.dir.createFile(io, path, .{});
        defer file.close(io);
        try file.writeStreamingAll(io, content);
    }

    /// Read a file from the tmp dir (caller frees).
    pub fn readFile(self: *TestContext, path: []const u8) ![]u8 {
        return self.tmp_dir.dir.readFileAlloc(io, path, self.allocator, .limited(64 * 1024 * 1024));
    }

    /// Create a subdirectory inside the tmp dir.
    pub fn makeDir(self: *TestContext, path: []const u8) !void {
        try self.tmp_dir.dir.createDir(io, path, .default_dir);
    }

    /// Create a symlink inside the tmp dir (target is a path, link_name is the name to create).
    pub fn makeSymlink(self: *TestContext, target: []const u8, link_name: []const u8) !void {
        try self.tmp_dir.dir.symLink(io, target, link_name, .{});
    }

    /// Spawn a command with stdout/stderr captured. stdin is fed from input if non-null.
    /// The command runs with its cwd set to the tmp dir.
    pub fn runCommand(self: *TestContext, argv: []const []const u8, input: ?[]const u8) !CommandResult {
        var cwd_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const len = try self.tmp_dir.dir.realPath(io, &cwd_buf);
        return self.runCommandInDir(argv, input, cwd_buf[0..len], null);
    }

    /// Like runCommand but with an explicit working directory and optional env map.
    pub fn runCommandInDir(
        self: *TestContext,
        argv: []const []const u8,
        input: ?[]const u8,
        cwd: []const u8,
        env: ?*const std.process.Environ.Map,
    ) !CommandResult {
        if (input == null) {
            const run_res = try std.process.run(self.allocator, io, .{
                .argv = argv,
                .cwd = .{ .path = cwd },
                .environ_map = env,
            });
            const exit_code: u8 = switch (run_res.term) {
                .exited => |code| code,
                else => 1,
            };
            return CommandResult{
                .allocator = self.allocator,
                .exit_code = exit_code,
                .stdout = run_res.stdout,
                .stderr = run_res.stderr,
            };
        }

        var child = try std.process.spawn(io, .{
            .argv = argv,
            .cwd = .{ .path = cwd },
            .environ_map = env,
            .stdin = .pipe,
            .stdout = .pipe,
            .stderr = .pipe,
        });
        defer child.kill(io);

        child.stdin.?.writeStreamingAll(io, input.?) catch |err| switch (err) {
            error.BrokenPipe => {},
            else => return err,
        };
        child.stdin.?.close(io);
        child.stdin = null;

        const max = 50 * 1024 * 1024;
        var stdout_buf: [4096]u8 = undefined;
        var stdout_reader = child.stdout.?.readerStreaming(io, &stdout_buf);
        const stdout = try stdout_reader.interface.allocRemaining(self.allocator, .limited(max));
        errdefer self.allocator.free(stdout);
        child.stdout.?.close(io);
        child.stdout = null;

        var stderr_buf: [4096]u8 = undefined;
        var stderr_reader = child.stderr.?.readerStreaming(io, &stderr_buf);
        const stderr = try stderr_reader.interface.allocRemaining(self.allocator, .limited(max));
        errdefer self.allocator.free(stderr);
        child.stderr.?.close(io);
        child.stderr = null;

        const term = try child.wait(io);
        const exit_code: u8 = switch (term) {
            .exited => |code| code,
            else => 1,
        };

        return CommandResult{
            .allocator = self.allocator,
            .exit_code = exit_code,
            .stdout = stdout,
            .stderr = stderr,
        };
    }

    /// Run a command redirecting stdout to an existing file in the tmp dir.
    /// If append is true the file is opened in append mode, otherwise truncated.
    /// Returns a CommandResult with empty stdout (output went to file).
    pub fn runCommandWithStdoutFile(
        self: *TestContext,
        argv: []const []const u8,
        abs_stdout_path: []const u8,
        append: bool,
    ) !CommandResult {
        const out_file = try std.Io.Dir.createFileAbsolute(io, abs_stdout_path, .{ .truncate = !append });
        defer out_file.close(io);

        if (append) {
            _ = std.os.linux.lseek(out_file.handle, 0, std.os.linux.SEEK.END);
        }

        var cwd_buf: [std.Io.Dir.max_path_bytes]u8 = undefined;
        const len = try self.tmp_dir.dir.realPath(io, &cwd_buf);

        var child = try std.process.spawn(io, .{
            .argv = argv,
            .cwd = .{ .path = cwd_buf[0..len] },
            .stdin = .ignore,
            .stdout = .{ .file = out_file },
            .stderr = .pipe,
        });
        defer child.kill(io);

        const max = 50 * 1024 * 1024;
        var stderr_buf: [4096]u8 = undefined;
        var stderr_reader = child.stderr.?.readerStreaming(io, &stderr_buf);
        const stderr = try stderr_reader.interface.allocRemaining(self.allocator, .limited(max));
        errdefer self.allocator.free(stderr);
        child.stderr.?.close(io);
        child.stderr = null;

        const term = try child.wait(io);
        const exit_code: u8 = switch (term) {
            .exited => |code| code,
            else => 1,
        };

        const empty = try self.allocator.dupe(u8, "");
        return CommandResult{
            .allocator = self.allocator,
            .exit_code = exit_code,
            .stdout = empty,
            .stderr = stderr,
        };
    }

    /// Return true if path exists inside the tmp dir.
    pub fn pathExists(self: *TestContext, path: []const u8) bool {
        self.tmp_dir.dir.access(io, path, .{}) catch return false;
        return true;
    }

    /// Remove a file inside the tmp dir.
    pub fn removeFile(self: *TestContext, path: []const u8) !void {
        try self.tmp_dir.dir.deleteFile(io, path);
    }
};

pub const CommandResult = struct {
    allocator: std.mem.Allocator,
    exit_code: u8,
    stdout: []u8,
    stderr: []u8,

    pub fn deinit(self: *CommandResult) void {
        self.allocator.free(self.stdout);
        self.allocator.free(self.stderr);
    }
};

/// Return the absolute path to a built binary (caller frees).
/// Searches zig-out/bin relative to cwd.
pub fn getBinaryPath(allocator: std.mem.Allocator, name: []const u8) ![]u8 {
    const search_paths = [_][]const u8{
        "zig-out/bin",
        "../zig-out/bin",
        "../../zig-out/bin",
    };

    const cwd = try std.process.currentPathAlloc(io, allocator);
    defer allocator.free(cwd);

    for (search_paths) |base| {
        const path = try std.fs.path.join(allocator, &.{ cwd, base, name });
        std.Io.Dir.cwd().access(io, path, .{}) catch {
            allocator.free(path);
            continue;
        };
        return path;
    }

    return allocator.dupe(u8, name);
}

/// Return true if the process is running as root.
pub fn isRoot() bool {
    return std.os.linux.getuid() == 0;
}
