const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "yes basic output is 'y'" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "yes");
    defer allocator.free(binary_path);

    var child = try std.process.spawn(std.testing.io, .{
        .argv = &[_][]const u8{binary_path},
        .stdout = .pipe,
        .stderr = .ignore,
    });
    defer child.kill(std.testing.io);

    var buf: [4]u8 = undefined;
    const n = try child.stdout.?.readStreaming(std.testing.io, &.{&buf});
    child.kill(std.testing.io);

    try testing.expect(n >= 2);
    try testing.expectEqualStrings("y\n", buf[0..2]);
}

test "yes with custom single argument" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "yes");
    defer allocator.free(binary_path);

    var child = try std.process.spawn(std.testing.io, .{
        .argv = &[_][]const u8{ binary_path, "hello" },
        .stdout = .pipe,
        .stderr = .ignore,
    });
    defer child.kill(std.testing.io);

    var buf: [16]u8 = undefined;
    const n = try child.stdout.?.readStreaming(std.testing.io, &.{&buf});
    child.kill(std.testing.io);

    try testing.expect(n >= 6);
    try testing.expectEqualStrings("hello\n", buf[0..6]);
}

test "yes with multiple arguments joins with space" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "yes");
    defer allocator.free(binary_path);

    var child = try std.process.spawn(std.testing.io, .{
        .argv = &[_][]const u8{ binary_path, "hello", "world" },
        .stdout = .pipe,
        .stderr = .ignore,
    });
    defer child.kill(std.testing.io);

    var buf: [32]u8 = undefined;
    const n = try child.stdout.?.readStreaming(std.testing.io, &.{&buf});
    child.kill(std.testing.io);

    try testing.expect(n >= 12);
    try testing.expectEqualStrings("hello world\n", buf[0..12]);
}

test "yes output repeats consistently" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "yes");
    defer allocator.free(binary_path);

    var child = try std.process.spawn(std.testing.io, .{
        .argv = &[_][]const u8{binary_path},
        .stdout = .pipe,
        .stderr = .ignore,
    });
    defer child.kill(std.testing.io);

    var buf: [8]u8 = undefined;
    var total: usize = 0;
    while (total < 8) {
        const chunk = buf[total..];
        const n = try child.stdout.?.readStreaming(std.testing.io, &.{chunk});
        if (n == 0) break;
        total += n;
    }
    child.kill(std.testing.io);

    try testing.expect(total >= 4);
    try testing.expectEqualStrings("y\ny\ny\n", buf[0..6]);
}

test "yes to /dev/full exits 1 with diagnostic" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "yes");
    defer allocator.free(binary_path);

    const dev_full = std.Io.Dir.openFileAbsolute(std.testing.io, "/dev/full", .{}) catch return;
    dev_full.close(std.testing.io);

    const cmd_str = try std.fmt.allocPrint(allocator, "{s} >/dev/full 2>&1; echo $?", .{binary_path});
    defer allocator.free(cmd_str);

    const cwd_path = try ctx.tmpPath(".");
    defer allocator.free(cwd_path);

    var result = try ctx.runCommandInDir(
        &[_][]const u8{ "sh", "-c", cmd_str },
        null,
        cwd_path,
        null,
    );
    defer result.deinit();

    try testing.expect(std.mem.indexOf(u8, result.stdout, "1") != null);
}
