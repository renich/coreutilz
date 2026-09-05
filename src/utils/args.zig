const std = @import("std");

/// Parse command line arguments into a structured format
pub const Args = struct {
    allocator: std.mem.Allocator,
    program: []const u8,
    options: std.StringHashMap(?[]const u8),
    positionals: std.ArrayList([]const u8),

    pub fn init(allocator: std.mem.Allocator, args: [][]const u8) !Args {
        var result = Args{
            .allocator = allocator,
            .program = args[0],
            .options = std.StringHashMap(?[]const u8).init(allocator),
            .positionals = std.ArrayList([]const u8).init(allocator),
        };

        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (std.mem.eql(u8, arg, "--")) {
                // End of options
                i += 1;
                while (i < args.len) : (i += 1) {
                    try result.positionals.append(args[i]);
                }
                break;
            } else if (std.mem.startsWith(u8, arg, "--")) {
                // Long option
                const eq_index = std.mem.indexOf(u8, arg, "=");
                if (eq_index) |idx| {
                    const key = arg[2..idx];
                    const value = arg[idx + 1 ..];
                    try result.options.put(key, value);
                } else {
                    try result.options.put(arg[2..], null);
                }
            } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
                // Short options
                for (arg[1..]) |c| {
                    const key = try std.fmt.allocPrint(allocator, "{c}", .{c});
                    try result.options.put(key, null);
                }
            } else {
                // Positional argument
                try result.positionals.append(arg);
            }
        }

        return result;
    }

    pub fn deinit(self: *Args) void {
        self.options.deinit();
        self.positionals.deinit();
    }

    pub fn hasOption(self: Args, name: []const u8) bool {
        return self.options.contains(name);
    }

    pub fn getOption(self: Args, name: []const u8) ?[]const u8 {
        return self.options.get(name) orelse null;
    }
};

/// Simple flag parser for commands with basic options
pub fn parseFlags(args: [][]const u8, flags: *std.StringHashMap(bool)) !void {
    for (args[1..]) |arg| {
        if (std.mem.eql(u8, arg, "--")) {
            break;
        } else if (std.mem.startsWith(u8, arg, "--")) {
            try flags.put(arg[2..], true);
        } else if (std.mem.startsWith(u8, arg, "-") and arg.len > 1) {
            for (arg[1..]) |c| {
                const key = try std.fmt.allocPrint(flags.allocator, "{c}", .{c});
                try flags.put(key, true);
            }
        }
    }
}

/// Collect command line arguments into a slice of slices using the given allocator.
pub fn getArgs(init: std.process.Init, allocator: std.mem.Allocator) ![][]const u8 {
    var it = std.process.Args.Iterator.init(init.minimal.args);
    var list: std.ArrayListUnmanaged([]const u8) = .empty;
    errdefer list.deinit(allocator);
    while (it.next()) |arg| {
        try list.append(allocator, arg);
    }
    return list.toOwnedSlice(allocator);
}
