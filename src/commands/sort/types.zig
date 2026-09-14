const std = @import("std");

pub const KeySpec = struct {
    field_start: usize = 1,
    char_start: usize = 1,
    field_end: ?usize = null,
    char_end: ?usize = null,
    numeric: bool = false,
    general_numeric: bool = false,
    human_numeric: bool = false,
    month: bool = false,
    version: bool = false,
    random: bool = false,
    reverse: bool = false,
    skipsblanks: bool = false,
    skipeblanks: bool = false,
    ignore_case: bool = false,
    dictionary_order: bool = false,
    ignore_nonprinting: bool = false,
};

pub fn defaultKeyCompare(key: *const KeySpec) bool {
    return !(key.numeric or key.general_numeric or key.human_numeric or
        key.month or key.version or key.random or
        key.dictionary_order or key.ignore_nonprinting or
        key.ignore_case or key.skipsblanks or key.skipeblanks);
}

pub const Options = struct {
    reverse: bool = false,
    numeric: bool = false,
    general_numeric: bool = false,
    human_numeric: bool = false,
    month: bool = false,
    version: bool = false,
    random: bool = false,
    unique: bool = false,
    ignore_blanks: bool = false,
    ignore_case: bool = false,
    dictionary_order: bool = false,
    ignore_nonprinting: bool = false,
    stable: bool = false,
    check: bool = false,
    check_silent: bool = false,
    merge: bool = false,
    zero_terminated: bool = false,
    delimiter: ?u8 = null,
    output_file: ?[]const u8 = null,
    temp_dir: ?[]const u8 = null,
    files0_from: ?[]const u8 = null,
    batch_size: ?usize = null,
    parallel: ?usize = null,
    random_source: ?[]const u8 = null,
    random_seed: u64 = 0,
    compress_program: ?[]const u8 = null,
    keys: []const KeySpec = &.{},
    files: []const []const u8 = &.{},
};
