const std = @import("std");
const coreutilz = @import("coreutilz");

pub fn main(init: std.process.Init.Minimal) u8 {
    return coreutilz.utils.runner.runWrapper("pinky", coreutilz.pinky_cmd.run, init);
}
