const std = @import("std");

/// Collect command-line arguments into an allocated slice of slices using the given allocator.
pub fn getArgs(args: anytype, allocator: std.mem.Allocator) ![][]const u8 {
    const raw_args: std.process.Args = switch (@TypeOf(args)) {
        std.process.Args => args,
        std.process.Init => args.minimal.args,
        std.process.Init.Minimal => args.args,
        else => args,
    };
    var it = std.process.Args.Iterator.init(raw_args);
    var list: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer list.deinit(allocator);
    while (it.next()) |arg| {
        try list.append(allocator, arg);
    }
    return list.toOwnedSlice(allocator);
}

pub const MatchResult = union(enum) {
    found: []const u8,
    ambiguous: void,
    none: void,
};

/// Match a long option against a slice of candidates.
/// Supports exact match, unique prefix abbreviation, and detects ambiguity.
pub fn matchLongOption(arg_name: []const u8, candidates: []const []const u8) MatchResult {
    const stripped = if (std.mem.startsWith(u8, arg_name, "--")) arg_name[2..] else arg_name;

    // 1. Exact match check
    for (candidates) |cand| {
        const cand_stripped = if (std.mem.startsWith(u8, cand, "--")) cand[2..] else cand;
        if (std.mem.eql(u8, stripped, cand_stripped)) {
            return .{ .found = cand };
        }
    }

    // 2. Unique prefix abbreviation check
    var matched: ?[]const u8 = null;
    for (candidates) |cand| {
        const cand_stripped = if (std.mem.startsWith(u8, cand, "--")) cand[2..] else cand;
        if (std.mem.startsWith(u8, cand_stripped, stripped)) {
            if (matched != null) {
                return .ambiguous;
            }
            matched = cand;
        }
    }

    if (matched) |m| {
        return .{ .found = m };
    }
    return .none;
}

test "matchLongOption exact, prefix, ambiguous, none" {
    const candidates = &[_][]const u8{
        "--backup",
        "--target-directory",
        "--no-target-directory",
        "--verbose",
        "--version",
        "--parents",
    };

    // Exact match
    try std.testing.expectEqualStrings("--backup", matchLongOption("--backup", candidates).found);
    try std.testing.expectEqualStrings("--backup", matchLongOption("backup", candidates).found);

    // Prefix abbreviation
    try std.testing.expectEqualStrings("--backup", matchLongOption("--b", candidates).found);
    try std.testing.expectEqualStrings("--target-directory", matchLongOption("--target", candidates).found);
    try std.testing.expectEqualStrings("--parents", matchLongOption("--parent", candidates).found);

    // Ambiguous prefix
    try std.testing.expect(matchLongOption("--ver", candidates) == .ambiguous);

    // Unrecognized
    try std.testing.expect(matchLongOption("--unknown", candidates) == .none);
}
