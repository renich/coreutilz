const std = @import("std");
const coreutilz = @import("coreutilz");

pub fn main(init: std.process.Init.Minimal) u8 {
    return coreutilz.utils.runner.runWrapper("csplit", coreutilz.csplit_cmd.run, init);
}
