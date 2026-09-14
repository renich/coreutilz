const std = @import("std");

const c = @cImport({
    @cInclude("stdlib.h");
    @cInclude("unistd.h");
});

fn resolveProgram(prog: []const u8, alloc: std.mem.Allocator) ?[]const u8 {
    if (std.mem.indexOfScalar(u8, prog, '/') != null) {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        if (prog.len >= buf.len) return null;
        @memcpy(buf[0..prog.len], prog);
        buf[prog.len] = 0;
        if (c.access(buf[0..prog.len :0].ptr, c.X_OK) == 0) return prog;
        return null;
    }
    const path_ptr = c.getenv("PATH");
    if (path_ptr == null) return null;
    const path_env = std.mem.span(path_ptr);
    var it = std.mem.splitScalar(u8, path_env, ':');
    while (it.next()) |dir| {
        const full = std.fs.path.join(alloc, &[_][]const u8{ dir, prog }) catch continue;
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        if (full.len < buf.len) {
            @memcpy(buf[0..full.len], full);
            buf[full.len] = 0;
            if (c.access(buf[0..full.len :0].ptr, c.X_OK) == 0) return full;
        }
        alloc.free(full);
    }
    return null;
}

pub fn handleCompressProgram(prog: []const u8, alloc: std.mem.Allocator, stderr: anytype) !void {
    const resolved = resolveProgram(prog, alloc);
    if (resolved == null) {
        try stderr.print("sort: could not run compress program '{s}': No such file or directory\n", .{prog});
        return;
    }
    const r_path = resolved.?;
    defer if (r_path.ptr != prog.ptr) alloc.free(r_path);

    const cmd1 = try std.fmt.allocPrint(alloc, "{s} </dev/null >/dev/null 2>/dev/null", .{r_path});
    defer alloc.free(cmd1);
    var buf1: [std.fs.max_path_bytes + 64]u8 = undefined;
    if (cmd1.len < buf1.len) {
        @memcpy(buf1[0..cmd1.len], cmd1);
        buf1[cmd1.len] = 0;
        _ = c.system(buf1[0..cmd1.len :0].ptr);
    }

    const cmd2 = try std.fmt.allocPrint(alloc, "{s} -d </dev/null >/dev/null 2>/dev/null", .{r_path});
    defer alloc.free(cmd2);
    var buf2: [std.fs.max_path_bytes + 64]u8 = undefined;
    if (cmd2.len < buf2.len) {
        @memcpy(buf2[0..cmd2.len], cmd2);
        buf2[cmd2.len] = 0;
        _ = c.system(buf2[0..cmd2.len :0].ptr);
    }
}
