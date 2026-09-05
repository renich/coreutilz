const std = @import("std");
const testing = std.testing;
const framework = @import("framework");
const TestContext = framework.TestContext;
const getBinaryPath = framework.getBinaryPath;

test "seq basic one arg" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "seq");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "5" }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("1\n2\n3\n4\n5\n", res.stdout);
}

test "seq two args" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "seq");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "3", "7" }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("3\n4\n5\n6\n7\n", res.stdout);
}

test "seq three args with step" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "seq");
    defer allocator.free(bin);

    var res = try ctx.runCommand(&[_][]const u8{ bin, "1", "2", "6" }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    try testing.expectEqualStrings("1\n3\n5\n", res.stdout);
}

test "seq negative numbers and descending" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "seq");
    defer allocator.free(bin);

    // neg-1: -10 10 10 -> -10 0 10
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "-10", "10", "10" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("-10\n0\n10\n", res.stdout);
    }

    // neg-3: 1 -1 0 -> 1 0
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "1", "-1", "0" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("1\n0\n", res.stdout);
    }

    // neg-4: 1 -1 -1 -> 1 0 -1
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "1", "-1", "-1" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("1\n0\n-1\n", res.stdout);
    }

    // empty-rev: 1 -1 3 -> empty
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "1", "-1", "3" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("", res.stdout);
    }

    // onearg-2: -1 -> empty
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "-1" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("", res.stdout);
    }
}

test "seq floating point precision" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "seq");
    defer allocator.free(bin);

    // float-1: 0.8 0.1 0.9 -> 0.8 0.9
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "0.8", "0.1", "0.9" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("0.8\n0.9\n", res.stdout);
    }

    // float-2: 0.1 0.99 1.99 -> 0.10 1.09
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "0.1", "0.99", "1.99" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("0.10\n1.09\n", res.stdout);
    }

    // float-3: 10.8 0.1 10.95 -> 10.8 10.9
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "10.8", "0.1", "10.95" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("10.8\n10.9\n", res.stdout);
    }

    // float-4: 0.1 -0.1 -0.2 -> 0.1 0.0 -0.1 -0.2
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "0.1", "-0.1", "-0.2" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("0.1\n0.0\n-0.1\n-0.2\n", res.stdout);
    }

    // float-5: 0.8 1e-1 0.9 -> 0.8 0.9
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "0.8", "1e-1", "0.9" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("0.8\n0.9\n", res.stdout);
    }

    // wid-1: .8 1e-2 .81 -> 0.80 0.81
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, ".8", "1e-2", ".81" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("0.80\n0.81\n", res.stdout);
    }
}

test "seq equal width (-w)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "seq");
    defer allocator.free(bin);

    // eq-wid-1: -w 1 -1 -1 -> 01 00 -1
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "-w", "1", "-1", "-1" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("01\n00\n-1\n", res.stdout);
    }

    // eq-wid-2: -w -.1 .1 .11 -> -0.1 00.0 00.1
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "-w", "-.1", ".1", ".11" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("-0.1\n00.0\n00.1\n", res.stdout);
    }

    // eq-wid-5: -w 1 .5 2 -> 1.0 1.5 2.0
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "-w", "1", ".5", "2" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("1.0\n1.5\n2.0\n", res.stdout);
    }

    // eq-wid-8: -w 9 0.5 10 -> 09.0 09.5 10.0
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "-w", "9", "0.5", "10" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("09.0\n09.5\n10.0\n", res.stdout);
    }

    // eq-wid-9: -w -1e-3 1 -> -0.001 00.999
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "-w", "-1e-3", "1" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("-0.001\n00.999\n", res.stdout);
    }

    // eq-wid-13: -w 999 1e3 -> 0999 1000
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "-w", "999", "1e3" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("0999\n1000\n", res.stdout);
    }
}

test "seq custom format (-f)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "seq");
    defer allocator.free(bin);

    // fmt-1: -f %2.1f 1.5 .5 2 -> 1.5 2.0
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "-f", "%2.1f", "1.5", ".5", "2" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("1.5\n2.0\n", res.stdout);
    }

    // fmt-4: -f %3.0f 1 2 -> '  1\n  2\n'
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "-f", "%3.0f", "1", "2" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("  1\n  2\n", res.stdout);
    }

    // fmt-5: -f %-3.0f 1 2 -> '1  \n2  \n'
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "-f", "%-3.0f", "1", "2" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("1  \n2  \n", res.stdout);
    }

    // fmt-7: -f %0+3.0f 1 2 -> '+01\n+02\n'
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "-f", "%0+3.0f", "1", "2" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("+01\n+02\n", res.stdout);
    }

    // fmt-b: -f %%%g%% 1 -> '%1%\n'
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "-f", "%%%g%%", "1" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("%1%\n", res.stdout);
    }
}

test "seq separator (-s)" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "seq");
    defer allocator.free(bin);

    // sep-1: -s, 1 3 -> 1,2,3
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "-s,", "1", "3" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("1,2,3\n", res.stdout);
    }

    // sep-2: -s, 1 1 -> 1
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "-s,", "1", "1" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("1\n", res.stdout);
    }

    // sep-3: -s,, 1 3 -> 1,,2,,3
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "-s,,", "1", "3" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("1,,2,,3\n", res.stdout);
    }
}

test "seq arbitrarily large numbers and fast path" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "seq");
    defer allocator.free(bin);

    // 81-digit integers
    const p = "999999999999999999999999999999999999999999999999999999999999999999999999999999999";
    const q = "1000000000000000000000000000000000000000000000000000000000000000000000000000000000";
    const r = "1000000000000000000000000000000000000000000000000000000000000000000000000000000001";

    var res = try ctx.runCommand(&[_][]const u8{ bin, p, r }, null);
    defer res.deinit();
    try testing.expectEqual(@as(u8, 0), res.exit_code);
    const expected = try std.fmt.allocPrint(allocator, "{s}\n{s}\n{s}\n", .{ p, q, r });
    defer allocator.free(expected);
    try testing.expectEqualStrings(expected, res.stdout);

    // Leading zeros trimming in fast path
    var res_lz = try ctx.runCommand(&[_][]const u8{ bin, "000", "02" }, null);
    defer res_lz.deinit();
    try testing.expectEqual(@as(u8, 0), res_lz.exit_code);
    try testing.expectEqualStrings("0\n1\n2\n", res_lz.stdout);
}

test "seq extra number rounding logic" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "seq");
    defer allocator.free(bin);

    // seq 0 0.000001 0.000003
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "0", "0.000001", "0.000003" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("0.000000\n0.000001\n0.000002\n0.000003\n", res.stdout);
    }

    // seq -f "%g=" 1000000 1000000
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "-f", "%g=", "1000000", "1000000" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("1e+06=\n", res.stdout);
    }
}

test "seq hex and exponents precision" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "seq");
    defer allocator.free(bin);

    // Hex float auto precision
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "1", "0x1p-1", "2" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("1\n1.5\n2\n", res.stdout);
    }

    // Exponents
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "1.1e1", "12" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("11\n12\n", res.stdout);
    }

    // Huge negative exponent (no undefined behavior / crash)
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "1e-9223372036854775808" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expectEqualStrings("", res.stderr);
    }
}

test "seq error handling" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "seq");
    defer allocator.free(bin);

    // Missing operand
    {
        var res = try ctx.runCommand(&[_][]const u8{bin}, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 1), res.exit_code);
        try testing.expect(std.mem.indexOf(u8, res.stderr, "missing operand") != null);
    }

    // Extra operand
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "1", "2", "3", "4" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 1), res.exit_code);
        try testing.expect(std.mem.indexOf(u8, res.stderr, "extra operand '4'") != null);
    }

    // Zero increment
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "1", "0", "10" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 1), res.exit_code);
        try testing.expect(std.mem.indexOf(u8, res.stderr, "invalid Zero increment value: '0'") != null);
    }

    // NaN argument
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "nan" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 1), res.exit_code);
        try testing.expect(std.mem.indexOf(u8, res.stderr, "invalid 'not-a-number' argument: 'nan'") != null);
    }

    // Format string conflict with equal width
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "-f", "%g", "-w", "1", "10" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 1), res.exit_code);
        try testing.expect(std.mem.indexOf(u8, res.stderr, "format string may not be specified when printing equal width strings") != null);
    }

    // Format errors
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "-f", "%%g", "1" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 1), res.exit_code);
        try testing.expectEqualStrings("seq: format '%%g' has no % directive\n", res.stderr);
    }
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "-f", "%", "1" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 1), res.exit_code);
        try testing.expectEqualStrings("seq: format '%' ends in %\n", res.stderr);
    }
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "-f", "%g%", "1" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 1), res.exit_code);
        try testing.expectEqualStrings("seq: format '%g%' has too many % directives\n", res.stderr);
    }
    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "-f", "%d", "1" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 1), res.exit_code);
        try testing.expectEqualStrings("seq: format '%d' has unknown %d directive\n", res.stderr);
    }
}

test "seq --help and --version" {
    const allocator = testing.allocator;
    var ctx = try TestContext.init(allocator);
    defer ctx.deinit();

    const bin = try getBinaryPath(allocator, "seq");
    defer allocator.free(bin);

    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "--help" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expect(std.mem.indexOf(u8, res.stdout, "Usage: seq") != null);
    }

    {
        var res = try ctx.runCommand(&[_][]const u8{ bin, "--version" }, null);
        defer res.deinit();
        try testing.expectEqual(@as(u8, 0), res.exit_code);
        try testing.expect(std.mem.indexOf(u8, res.stdout, "seq") != null);
    }
}
