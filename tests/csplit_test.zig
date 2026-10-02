const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

// [FUNC-CSPLIT-001] Pattern-Based Splitting
test "csplit [FUNC-CSPLIT-001] missing operands failure" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "csplit");
    defer allocator.free(binary_path);

    var res0 = try ctx.runCommand(&[_][]const u8{binary_path}, null);
    defer res0.deinit();
    try testing.expectEqual(@as(u8, 1), res0.exit_code);
    try testing.expect(res0.stderr.len > 0);

    var res1 = try ctx.runCommand(&[_][]const u8{ binary_path, "file" }, null);
    defer res1.deinit();
    try testing.expectEqual(@as(u8, 1), res1.exit_code);
    try testing.expect(res1.stderr.len > 0);
}

test "csplit [FUNC-CSPLIT-001] split by line number INTEGER" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "csplit");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "1\n2\n3\n4\n5\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", input, "3" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("1\n2\n", "xx00"));
    try testing.expect(try ctx.compareContent("3\n4\n5\n", "xx01"));
}

test "csplit [FUNC-CSPLIT-001] split by BRE pattern /REGEXP/" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "csplit");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "alpha\nSECTION\nbeta\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", input, "/SECTION/" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("alpha\n", "xx00"));
    try testing.expect(try ctx.compareContent("SECTION\nbeta\n", "xx01"));
}

test "csplit [FUNC-CSPLIT-001] split by pattern with offset /REGEXP/+1" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "csplit");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "line1\nMARK\nline3\nline4\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", input, "/MARK/+1" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("line1\nMARK\n", "xx00"));
    try testing.expect(try ctx.compareContent("line3\nline4\n", "xx01"));
}

test "csplit [FUNC-CSPLIT-001] skip section with %REGEXP%" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "csplit");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "preamble\nSTART\nbody\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", input, "%START%" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("START\nbody\n", "xx00"));
}

test "csplit [FUNC-CSPLIT-001] repeat count {*} indefinite" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "csplit");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "SEC\n1\nSEC\n2\nSEC\n3\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", input, "/SEC/", "{*}" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("", "xx00"));
    try testing.expect(try ctx.compareContent("SEC\n1\n", "xx01"));
    try testing.expect(try ctx.compareContent("SEC\n2\n", "xx02"));
    try testing.expect(try ctx.compareContent("SEC\n3\n", "xx03"));
}

test "csplit [FUNC-CSPLIT-001] split by pattern with negative offset /REGEXP/-1" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "csplit");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "line1\nline2\nMARK\nline4\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", input, "/MARK/-1" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("line1\n", "xx00"));
    try testing.expect(try ctx.compareContent("line2\nMARK\nline4\n", "xx01"));
}

test "csplit [FUNC-CSPLIT-001] repeat count {N} premature EOF failure" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "csplit");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "SEC\n1\nSEC\n2\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", input, "/SEC/", "{5}" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
    try testing.expect(result.stderr.len > 0);
    try testing.expect(!try ctx.fileExists("xx00"));
}

test "csplit [FUNC-CSPLIT-001] line number out of bounds failure" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "csplit");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "1\n2\n3\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", input, "999" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
    try testing.expect(result.stderr.len > 0);
    try testing.expect(!try ctx.fileExists("xx00"));
}

test "csplit [FUNC-CSPLIT-001] stdin ingestion with -" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "csplit");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "-", "2" }, "alpha\nbeta\ngamma\n");
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("alpha\n", "xx00"));
    try testing.expect(try ctx.compareContent("beta\ngamma\n", "xx01"));
}

// [FUNC-CSPLIT-002] File Naming, Cleanup & Accounting
test "csplit [FUNC-CSPLIT-002] custom prefix -f and digits -n" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "csplit");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "a\nb\nc\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "-f", "chunk_", "-n", "3", input, "2" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("a\n", "chunk_000"));
    try testing.expect(try ctx.compareContent("b\nc\n", "chunk_001"));
}

test "csplit [FUNC-CSPLIT-002] byte count accounting to stdout" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "csplit");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "123\n4567\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, input, "2" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("4\n5\n", result.stdout);
}

test "csplit [FUNC-CSPLIT-002] -z elide empty files" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "csplit");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "MARK\nline\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "-z", input, "/MARK/" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("MARK\nline\n", "xx00"));
    try testing.expect(!try ctx.fileExists("xx01"));
}

test "csplit [FUNC-CSPLIT-002] --suppress-matched" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "csplit");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "head\nDELIM\ntail\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "--suppress-matched", input, "/DELIM/" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("head\n", "xx00"));
    try testing.expect(try ctx.compareContent("tail\n", "xx01"));
}

test "csplit [FUNC-CSPLIT-002] custom suffix format -b" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "csplit");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "1\n2\n3\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-s", "-b", "%03d.part", input, "2" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("1\n", "xx000.part"));
    try testing.expect(try ctx.compareContent("2\n3\n", "xx001.part"));
}

test "csplit [FUNC-CSPLIT-002] -k keep-files on error" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "csplit");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "1\n2\n3\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-k", "-s", input, "2", "999" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
    try testing.expect(result.stderr.len > 0);
    try testing.expect(try ctx.fileExists("xx00"));
}

// [FUNC-TEXT-DIAG-001] Diagnostics
test "csplit [FUNC-TEXT-DIAG-001] --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "csplit");
    defer allocator.free(binary_path);

    var h_res = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer h_res.deinit();
    try testing.expectEqual(@as(u8, 0), h_res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, h_res.stdout, 1, "Usage:"));

    var v_res = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer v_res.deinit();
    try testing.expectEqual(@as(u8, 0), v_res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, v_res.stdout, 1, "csplit"));
}
