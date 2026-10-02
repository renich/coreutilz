const std = @import("std");
const types = @import("types.zig");

pub const Occurrence = struct {
    keyword: []const u8,
    before: []const u8,
    after: []const u8,
    line_idx: usize,
};

pub fn lessThanOccurs(ctx: bool, a: Occurrence, b: Occurrence) bool {
    if (ctx) {
        // case insensitive
        var i: usize = 0;
        while (i < a.keyword.len and i < b.keyword.len) : (i += 1) {
            const ca = std.ascii.toLower(a.keyword[i]);
            const cb = std.ascii.toLower(b.keyword[i]);
            if (ca < cb) return true;
            if (ca > cb) return false;
        }
        return a.keyword.len < b.keyword.len;
    } else {
        return std.mem.order(u8, a.keyword, b.keyword) == .lt;
    }
}

pub fn renderOutput(writer: anytype, occurs: []const Occurrence, cfg: *const types.PtxConfig) !void {
    const width = cfg.getWidth();
    const gap = cfg.gap_size;
    const half_line_width = width / 2;

    for (occurs) |occ| {
        switch (cfg.format) {
            .roff => {
                try writer.print(".{s} \"\" \"{s}\" \"{s}\" \"{s}\"\n", .{
                    cfg.macro_name,
                    occ.before,
                    occ.keyword,
                    occ.after,
                });
            },
            .tex => {
                try writer.print("\\{s} {{}}{{{s}}}{{{s}}}{{{s}}}{{}}\n", .{
                    cfg.macro_name,
                    occ.before,
                    occ.keyword,
                    occ.after,
                });
            },
            .dumb => {
                // Reference prefix (if !right_reference, GNU ptx emits reference_max_width + gap_size spaces)
                for (0..gap) |_| try writer.writeByte(' ');

                // Left context padding
                const left_len = occ.before.len + (if (occ.before.len > 0) cfg.truncation_string.len else 0);
                const before_max_width = if (half_line_width > gap) half_line_width - gap else 0;
                const lead_spaces = if (before_max_width > left_len) before_max_width - left_len else 0;

                for (0..lead_spaces) |_| try writer.writeByte(' ');
                if (occ.before.len > 0) {
                    try writer.writeAll(occ.before);
                    try writer.writeAll(cfg.truncation_string);
                }
                for (0..gap) |_| try writer.writeByte(' ');
                try writer.writeAll(occ.keyword);
                if (occ.after.len > 0) {
                    try writer.writeAll(cfg.truncation_string);
                    try writer.writeAll(occ.after);
                }
                try writer.writeByte('\n');
            },
        }
    }
}
