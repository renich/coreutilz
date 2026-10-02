const std = @import("std");
const coreutilz = @import("coreutilz");

pub fn main(init: std.process.Init.Minimal) u8 {
    return coreutilz.utils.runner.runWrapper("sha384sum", coreutilz.sha384sum_cmd.run, init);
}
