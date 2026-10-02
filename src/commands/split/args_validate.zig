const std = @import("std");
const errors = @import("../../utils/errors.zig");
const args_mod = @import("args.zig");

pub fn validateOptions(opts: *args_mod.Options, stderr: anytype) !void {
    if (std.mem.indexOfScalar(u8, opts.additional_suffix, '/') != null) {
        errors.printError(stderr, "split", "invalid suffix: contains directory separator") catch {};
        return error.InvalidArgs;
    }

    if (opts.filter_cmd != null and opts.mode == .number) {
        switch (opts.mode.number.mode) {
            .bytes_stdout, .lines_stdout, .round_robin_stdout => {
                errors.printError(stderr, "split", "cannot use --filter when extracting a single chunk to stdout") catch {};
                return error.InvalidArgs;
            },
            else => {},
        }
    }

    const alphabet_len: usize = switch (opts.suffix_type) {
        .alpha => 26,
        .numeric => 10,
        .hex => 16,
    };

    if (opts.mode == .number) {
        const n_units = opts.mode.number.n;
        var n_end = if (n_units > 0) n_units - 1 else 0;
        if (opts.start_from > 0 and opts.start_from < n_units) {
            n_end += opts.start_from;
        }
        var needed: usize = 0;
        while (true) {
            needed += 1;
            n_end /= alphabet_len;
            if (n_end == 0) break;
        }

        if (opts.suffix_len_explicit) {
            if (opts.suffix_len < needed) {
                stderr.print("split: the suffix length needs to be at least {d}\n", .{needed}) catch {};
                return error.InvalidArgs;
            }
        } else {
            opts.suffix_len = @max(2, needed);
        }
    }

    if (opts.start_from > 0) {
        var val = opts.start_from;
        var digits: usize = 0;
        while (val > 0) : (val /= alphabet_len) {
            digits += 1;
        }
        if (digits > opts.suffix_len) {
            stderr.print("split: numerical suffix start value is too large for the suffix length\n", .{}) catch {};
            return error.InvalidArgs;
        }
    }
}
