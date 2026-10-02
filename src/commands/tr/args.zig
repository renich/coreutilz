const std = @import("std");
const errors = @import("../../utils/errors.zig");

pub const Options = struct {
    complement: bool = false,
    delete: bool = false,
    squeeze: bool = false,
    truncate_set1: bool = false,
    set1: []const u8 = "",
    set2: ?[]const u8 = null,
};

pub const ParseResult = union(enum) {
    ok: Options,
    help,
    version,
    err: u8,
};

fn handleLongOption(arg: []const u8, opts: *Options, stderr: anytype) ?ParseResult {
    if (std.mem.eql(u8, arg, "--help")) return .help;
    if (std.mem.eql(u8, arg, "--version")) return .version;
    if (std.mem.eql(u8, arg, "--complement")) {
        opts.complement = true;
        return null;
    }
    if (std.mem.eql(u8, arg, "--delete")) {
        opts.delete = true;
        return null;
    }
    if (std.mem.eql(u8, arg, "--squeeze-repeats")) {
        opts.squeeze = true;
        return null;
    }
    if (std.mem.eql(u8, arg, "--truncate-set1")) {
        opts.truncate_set1 = true;
        return null;
    }
    errors.printUnrecognizedOption(stderr, "tr", arg) catch {};
    return .{ .err = 1 };
}

fn handleShortOptions(arg: []const u8, opts: *Options, stderr: anytype) ?ParseResult {
    var j: usize = 1;
    while (j < arg.len) : (j += 1) {
        switch (arg[j]) {
            'c', 'C' => opts.complement = true,
            'd' => opts.delete = true,
            's' => opts.squeeze = true,
            't' => opts.truncate_set1 = true,
            else => {
                errors.printInvalidOption(stderr, "tr", arg[j]) catch {};
                return .{ .err = 1 };
            },
        }
    }
    return null;
}

fn validateOperands(operands: [][]const u8, opts: *Options, stderr: anytype) ?ParseResult {
    if (operands.len == 0) {
        errors.printMissingOperand(stderr, "tr") catch {};
        return .{ .err = 1 };
    }
    if (opts.delete and !opts.squeeze) {
        if (operands.len > 1) {
            stderr.print("tr: extra operand '{s}'\nOnly one string may be given when deleting without squeezing repeats.\nTry 'tr --help' for more information.\n", .{operands[1]}) catch {};
            return .{ .err = 1 };
        }
        opts.set1 = operands[0];
        return null;
    }
    if (opts.delete and opts.squeeze) {
        if (operands.len == 1) {
            stderr.print("tr: missing operand after '{s}'\nTwo strings must be given when both deleting and squeezing repeats.\nTry 'tr --help' for more information.\n", .{operands[0]}) catch {};
            return .{ .err = 1 };
        }
        if (operands.len > 2) {
            errors.printExtraOperand(stderr, "tr", operands[2]) catch {};
            return .{ .err = 1 };
        }
        opts.set1 = operands[0];
        opts.set2 = operands[1];
        return null;
    }
    if (opts.squeeze and !opts.delete) {
        if (operands.len == 1) {
            opts.set1 = operands[0];
            return null;
        }
        if (operands.len == 2) {
            opts.set1 = operands[0];
            opts.set2 = operands[1];
            return null;
        }
        errors.printExtraOperand(stderr, "tr", operands[2]) catch {};
        return .{ .err = 1 };
    }
    // Translation mode (default)
    if (operands.len == 1) {
        stderr.print("tr: missing operand after '{s}'\nTry 'tr --help' for more information.\n", .{operands[0]}) catch {};
        return .{ .err = 1 };
    }
    if (operands.len > 2) {
        errors.printExtraOperand(stderr, "tr", operands[2]) catch {};
        return .{ .err = 1 };
    }
    opts.set1 = operands[0];
    opts.set2 = operands[1];
    return null;
}

pub fn parseArgs(args: [][]const u8, allocator: std.mem.Allocator, stderr: anytype) ParseResult {
    var opts = Options{};
    var operands = std.ArrayList([]const u8).empty;
    defer operands.deinit(allocator);

    var i: usize = 1;
    while (i < args.len) : (i += 1) {
        const arg = args[i];
        if (std.mem.eql(u8, arg, "--")) {
            i += 1;
            while (i < args.len) : (i += 1) {
                operands.append(allocator, args[i]) catch return .{ .err = 1 };
            }
            break;
        }
        if (operands.items.len == 0) {
            if (std.mem.startsWith(u8, arg, "--") and arg.len > 2) {
                if (handleLongOption(arg, &opts, stderr)) |res| return res;
                continue;
            }
            if (arg.len > 1 and arg[0] == '-') {
                if (handleShortOptions(arg, &opts, stderr)) |res| return res;
                continue;
            }
        }
        operands.append(allocator, arg) catch return .{ .err = 1 };
    }

    if (validateOperands(operands.items, &opts, stderr)) |res| return res;
    return .{ .ok = opts };
}
