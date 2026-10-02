const std = @import("std");
const coreutilz = @import("coreutilz");

pub fn main(init: std.process.Init.Minimal) u8 {
    return coreutilz.utils.runner.runWrapper("printf", coreutilz.printf_cmd.run, init);
}
