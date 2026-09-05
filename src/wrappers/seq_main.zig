const std = @import("std");
const coreutilz = @import("coreutilz");

pub fn main(init: std.process.Init.Minimal) !void {
    var it = std.process.Args.Iterator.init(init.args);
    var list: std.ArrayListUnmanaged([]const u8) = .empty;
    defer list.deinit(std.heap.page_allocator);
    while (it.next()) |arg| {
        try list.append(std.heap.page_allocator, arg);
    }
    const exit_code = try coreutilz.seq_cmd.run(list.items, std.heap.page_allocator);
    std.process.exit(exit_code);
}
