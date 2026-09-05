const std = @import("std");
const coreutilz = @import("coreutilz");

pub fn main(init: std.process.Init) !void {
    const args = try coreutilz.utils.args.getArgs(init, init.arena.allocator());
    const exit_code = try coreutilz.logname_cmd.run(args, std.heap.page_allocator);
    std.process.exit(exit_code);
}
