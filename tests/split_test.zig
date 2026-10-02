const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

// [FUNC-SPLIT-001] Input Ingestion & Output File Naming
test "split [FUNC-SPLIT-001] default alphabetic suffixes and prefix" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "line1\nline2\nline3\nline4\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-l", "2", input, "out" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("line1\nline2\n", "outaa"));
    try testing.expect(try ctx.compareContent("line3\nline4\n", "outab"));
}

test "split [FUNC-SPLIT-001] stdin ingestion with -" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-l", "1", "-", "stdin_out_" }, "alpha\nbeta\n");
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("alpha\n", "stdin_out_aa"));
    try testing.expect(try ctx.compareContent("beta\n", "stdin_out_ab"));
}

test "split [FUNC-SPLIT-001] numeric suffixes -d and suffix length -a" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "1\n2\n3\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-l", "1", "-d", "-a", "3", input, "num" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("1\n", "num000"));
    try testing.expect(try ctx.compareContent("2\n", "num001"));
    try testing.expect(try ctx.compareContent("3\n", "num002"));
}

test "split [FUNC-SPLIT-001] hexadecimal suffixes -x" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "a\nb\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-l", "1", "-x", input, "hex" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("a\n", "hex00"));
    try testing.expect(try ctx.compareContent("b\n", "hex01"));
}

test "split [FUNC-SPLIT-001] additional suffix" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "one\ntwo\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-l", "1", "--additional-suffix=.part", input, "chunk" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("one\n", "chunkaa.part"));
    try testing.expect(try ctx.compareContent("two\n", "chunkab.part"));
}

test "split [FUNC-SPLIT-001] fixed suffix length exhaustion error" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    // Provide 15 lines with -l 1 -d -a 1 (max 10 files 0..9). 11th line triggers exhaustion
    var lines_content: std.ArrayList(u8) = .empty;
    defer lines_content.deinit(allocator);
    var line_buf: [64]u8 = undefined;
    for (0..15) |idx| {
        const line = try std.fmt.bufPrint(&line_buf, "line{d}\n", .{idx});
        try lines_content.appendSlice(allocator, line);
    }
    try ctx.writeFile("input.txt", lines_content.items);
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-l", "1", "-a", "1", "-d", input, "exhaust" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 1), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stderr, 1, "output file suffixes exhausted"));
}

// [FUNC-SPLIT-002] Splitting Disciplines
test "split [FUNC-SPLIT-002a] default 1000 lines split" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    // Create 1500 lines: default must produce xaa (1000 lines) and xab (500 lines)
    var list: std.ArrayList(u8) = .empty;
    defer list.deinit(allocator);
    var num_buf: [64]u8 = undefined;
    for (0..1500) |i| {
        const line = try std.fmt.bufPrint(&num_buf, "record {d}\n", .{i});
        try list.appendSlice(allocator, line);
    }
    try ctx.writeFile("input.txt", list.items);
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, input }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.fileExists("xaa"));
    try testing.expect(try ctx.fileExists("xab"));
}

test "split [FUNC-SPLIT-002b] -b byte split with multiplier" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    // 2048 bytes with -b 1K should split into two 1024-byte chunks
    const data = "a" ** 2048;
    try ctx.writeFile("input.txt", data);
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-b", "1K", input, "kb_" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("a" ** 1024, "kb_aa"));
    try testing.expect(try ctx.compareContent("a" ** 1024, "kb_ab"));
}

test "split [FUNC-SPLIT-002c] -C line bytes split" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "short\nlonger_line\nend\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-C", "10", input, "lbytes" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("short\n", "lbytesaa"));
    try testing.expect(try ctx.compareContent("longer_lin", "lbytesab"));
    try testing.expect(try ctx.compareContent("e\nend\n", "lbytesac"));
}

test "split [FUNC-SPLIT-002d] -n numbered chunks" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "123456");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-n", "2", input, "chunk" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("123", "chunkaa"));
    try testing.expect(try ctx.compareContent("456", "chunkab"));
}

test "split [FUNC-SPLIT-002d] -n k/N chunk extraction to stdout" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "abcdef");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-n", "2/3", input }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expectEqualStrings("cd", result.stdout);
}

test "split [FUNC-SPLIT-002d] -n l/N line-respecting chunks" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "line1\nline2\nline3\nline4\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-n", "l/2", input, "lchk_" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("line1\nline2\n", "lchk_aa"));
    try testing.expect(try ctx.compareContent("line3\nline4\n", "lchk_ab"));
}

test "split [FUNC-SPLIT-002d] -n r/N round-robin distribution" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "1\n2\n3\n4\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-n", "r/2", input, "rr" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("1\n3\n", "rraa"));
    try testing.expect(try ctx.compareContent("2\n4\n", "rrab"));
}

// [FUNC-SPLIT-003] Filtering & Control
test "split [FUNC-SPLIT-003a] -e elide empty files" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "1");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-e", "-n", "3", input, "elide" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("1", "elideaa"));
    try testing.expect(!try ctx.fileExists("elideab"));
    try testing.expect(!try ctx.fileExists("elideac"));
}

test "split [FUNC-SPLIT-003b] -t custom record separator" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "rec1:rec2:rec3:");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-t", ":", "-l", "2", input, "sep" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("rec1:rec2:", "sepaa"));
    try testing.expect(try ctx.compareContent("rec3:", "sepab"));
}

test "split [FUNC-SPLIT-003c] --filter shell execution" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "hello\nworld\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-l", "1", "--filter=cat > $FILE.filtered", input, "flt_" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(try ctx.compareContent("hello\n", "flt_aa.filtered"));
    try testing.expect(try ctx.compareContent("world\n", "flt_ab.filtered"));
}

test "split [FUNC-SPLIT-003e] --verbose diagnostic emission" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    try ctx.writeFile("input.txt", "a\nb\n");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "input.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, "-l", "1", "--verbose", input, "verb" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "creating file 'verbaa'"));
    try testing.expect(std.mem.containsAtLeast(u8, result.stdout, 1, "creating file 'verbab'"));
}

// [FUNC-TEXT-DIAG-001] Diagnostics & Help
test "split [FUNC-TEXT-DIAG-001] empty input produces zero files without error" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    try ctx.writeFile("empty.txt", "");
    const tmp_path = try ctx.tmpPath(".");
    defer allocator.free(tmp_path);
    const input = try std.fs.path.join(allocator, &[_][]const u8{ tmp_path, "empty.txt" });
    defer allocator.free(input);

    var result = try ctx.runCommand(&[_][]const u8{ binary_path, input, "emp_" }, null);
    defer result.deinit();

    try testing.expectEqual(@as(u8, 0), result.exit_code);
    try testing.expect(!try ctx.fileExists("emp_aa"));
}

test "split [FUNC-TEXT-DIAG-001] --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const binary_path = try getBinaryPath(allocator, "split");
    defer allocator.free(binary_path);

    var h_res = try ctx.runCommand(&[_][]const u8{ binary_path, "--help" }, null);
    defer h_res.deinit();
    try testing.expectEqual(@as(u8, 0), h_res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, h_res.stdout, 1, "Usage:"));

    var v_res = try ctx.runCommand(&[_][]const u8{ binary_path, "--version" }, null);
    defer v_res.deinit();
    try testing.expectEqual(@as(u8, 0), v_res.exit_code);
    try testing.expect(std.mem.containsAtLeast(u8, v_res.stdout, 1, "split"));
}
