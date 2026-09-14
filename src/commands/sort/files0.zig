const std = @import("std");

pub fn checkInputs(files: []const []const u8, stderr: anytype) !bool {
    for (files) |path| {
        if (std.mem.eql(u8, path, "-")) continue;
        const file = std.Io.Dir.cwd().openFile(std.Options.debug_io, path, .{ .mode = .read_only }) catch |err| {
            const msg = if (err == error.FileNotFound) "No such file or directory" else "Permission denied";
            try stderr.print("sort: cannot read: {s}: {s}\n", .{ path, msg });
            return false;
        };
        file.close(std.Options.debug_io);
    }
    return true;
}

pub fn checkOutput(out_path: ?[]const u8, stderr: anytype) !bool {
    if (out_path) |path| {
        const file = std.Io.Dir.cwd().openFile(std.Options.debug_io, path, .{ .mode = .write_only }) catch |err| {
            if (err == error.FileNotFound) {
                const created = std.Io.Dir.cwd().createFile(std.Options.debug_io, path, .{}) catch |create_err| {
                    const msg = if (create_err == error.FileNotFound) "No such file or directory" else "Permission denied";
                    try stderr.print("sort: open failed: {s}: {s}\n", .{ path, msg });
                    return false;
                };
                created.close(std.Options.debug_io);
                return true;
            }
            try stderr.print("sort: open failed: {s}: Permission denied\n", .{path});
            return false;
        };
        file.close(std.Options.debug_io);
    }
    return true;
}

fn readStreamAll(file: std.Io.File, allocator: std.mem.Allocator) ![]u8 {
    var list: std.ArrayList(u8) = .empty;
    var buf: [4096]u8 = undefined;
    var r = file.readerStreaming(std.Options.debug_io, &buf);
    const reader = &r.interface;
    var in_b: [4096]u8 = undefined;
    while (true) {
        const n = try reader.readSliceShort(&in_b);
        if (n == 0) break;
        try list.appendSlice(allocator, in_b[0..n]);
    }
    return try list.toOwnedSlice(allocator);
}

pub fn readFiles0From(
    files_from: []const u8,
    files_list: *std.ArrayList([]const u8),
    allocator: std.mem.Allocator,
    stderr: anytype,
) !bool {
    const is_stdin = std.mem.eql(u8, files_from, "-");
    const content = if (is_stdin)
        try readStreamAll(std.Io.File.stdin(), allocator)
    else blk: {
        const file = std.Io.Dir.cwd().openFile(std.Options.debug_io, files_from, .{ .mode = .read_only }) catch |err| {
            const msg = if (err == error.FileNotFound) "No such file or directory" else "Permission denied";
            try stderr.print("sort: open failed: {s}: {s}\n", .{ files_from, msg });
            return false;
        };
        defer file.close(std.Options.debug_io);
        break :blk try readStreamAll(file, allocator);
    };

    if (content.len == 0) {
        try stderr.print("sort: no input from '{s}'\n", .{files_from});
        return false;
    }

    var line_num: usize = 1;
    var start: usize = 0;
    var i: usize = 0;
    while (i <= content.len) : (i += 1) {
        if (i == content.len or content[i] == 0) {
            const item = content[start..i];
            if (item.len == 0 and (i < content.len or start == 0)) {
                try stderr.print("sort: {s}:{d}: invalid zero-length file name\n", .{ files_from, line_num });
                return false;
            }
            if (item.len > 0) {
                if (is_stdin and std.mem.eql(u8, item, "-")) {
                    try stderr.writeAll("sort: when reading file names from standard input, no file name of '-' allowed\n");
                    return false;
                }
                try files_list.append(allocator, item);
                line_num += 1;
            }
            start = i + 1;
        }
    }
    return true;
}
