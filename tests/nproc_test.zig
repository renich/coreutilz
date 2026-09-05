const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

fn parseNproc(s: []const u8) !u32 {
    return std.fmt.parseInt(u32, std.mem.trimEnd(u8, s, "\n"), 10);
}

test "nproc returns positive number" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "nproc");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{binary_path}, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    const n = try parseNproc(result.stdout);
    try testing.expect(n > 0);
}

test "nproc --all returns positive number" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "nproc");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--all" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    const n = try parseNproc(result.stdout);
    try testing.expect(n > 0);
}

test "nproc is less than or equal to nproc --all" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "nproc");
    defer allocator.free(binary_path);

    const cwd = try ctx.tmpPath(".");
    defer allocator.free(cwd);

    var env_empty = framework.EnvMap.init(allocator);
    defer env_empty.deinit();

    var avail_result = try ctx.runCommandInDir(
        &[_][]const u8{binary_path},
        null,
        cwd,
        &env_empty,
    );
    defer avail_result.deinit();
    const avail = try parseNproc(avail_result.stdout);

    var all_result = try ctx.runCommand(&[_][]const u8{ binary_path, "--all" }, null);
    defer all_result.deinit();
    const all = try parseNproc(all_result.stdout);

    try testing.expect(avail <= all);
}

test "nproc OMP_NUM_THREADS negative gives positive result" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "nproc");
    defer allocator.free(binary_path);

    const cwd = try ctx.tmpPath(".");
    defer allocator.free(cwd);

    var env = framework.EnvMap.init(allocator);
    defer env.deinit();
    try env.put("OMP_NUM_THREADS", "-1000");

    var result = try ctx.runCommandInDir(&[_][]const u8{binary_path}, null, cwd, &env);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    const n = try parseNproc(result.stdout);
    try testing.expect(n > 0);
}

test "nproc OMP_NUM_THREADS zero gives positive result" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "nproc");
    defer allocator.free(binary_path);

    const cwd = try ctx.tmpPath(".");
    defer allocator.free(cwd);

    var env = framework.EnvMap.init(allocator);
    defer env.deinit();
    try env.put("OMP_NUM_THREADS", "0");

    var result = try ctx.runCommandInDir(&[_][]const u8{binary_path}, null, cwd, &env);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    const n = try parseNproc(result.stdout);
    try testing.expect(n > 0);
}

test "nproc --ignore=1 gives positive result" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "nproc");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--ignore=1" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    const n = try parseNproc(result.stdout);
    try testing.expect(n > 0);
}

test "nproc --ignore=-1 exits 1" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "nproc");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--ignore=-1" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "nproc --ignore=N exits 1" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "nproc");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--ignore=N" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
}

test "nproc OMP_NUM_THREADS=42 --ignore=40 equals 2" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "nproc");
    defer allocator.free(binary_path);

    const cwd = try ctx.tmpPath(".");
    defer allocator.free(cwd);

    var env = framework.EnvMap.init(allocator);
    defer env.deinit();
    try env.put("OMP_NUM_THREADS", "42");

    var result = try ctx.runCommandInDir(
        &[_][]const u8{ binary_path, "--ignore=40" },
        null,
        cwd,
        &env,
    );
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    const n = try parseNproc(result.stdout);
    try testing.expectEqual(@as(u32, 2), n);
}

test "nproc OMP_THREAD_LIMIT=1 gives 1" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "nproc");
    defer allocator.free(binary_path);

    const cwd = try ctx.tmpPath(".");
    defer allocator.free(cwd);

    var env = framework.EnvMap.init(allocator);
    defer env.deinit();
    try env.put("OMP_THREAD_LIMIT", "1");

    var result = try ctx.runCommandInDir(&[_][]const u8{binary_path}, null, cwd, &env);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    const n = try parseNproc(result.stdout);
    try testing.expectEqual(@as(u32, 1), n);
}

test "nproc --help exits 0" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "nproc");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}

test "nproc --version exits 0" {
    const allocator = testing.allocator;

    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "nproc");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
}
