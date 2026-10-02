const std = @import("std");
const options = @import("options.zig");

pub const Word = struct {
    text: []const u8,
    is_sentence_end: bool,
    space_after: usize,
};

pub fn formatParagraph(
    writer: anytype,
    words: []const Word,
    prefix: []const u8,
    first_indent: []const u8,
    other_indent: []const u8,
    opts: *const options.FmtOptions,
    allocator: std.mem.Allocator,
) !void {
    if (words.len == 0) return;

    const max_w = opts.max_width;
    const goal_w = opts.getGoal();

    var line_idx: usize = 0;
    var i: usize = 0;

    while (i < words.len) {
        const indent = if (line_idx == 0) first_indent else other_indent;
        try writer.writeAll(prefix);
        try writer.writeAll(indent);
        var cur_col = prefix.len + indent.len;

        var line_words: std.ArrayList(usize) = .empty;
        defer line_words.deinit(allocator);

        try line_words.append(allocator, i);
        cur_col += words[i].text.len;
        i += 1;

        while (i < words.len) {
            const spaces: usize = if (opts.uniform_spacing) (if (words[i - 1].is_sentence_end) 2 else 1) else words[i - 1].space_after;
            const next_len = spaces + words[i].text.len;
            if (cur_col + next_len <= max_w or (cur_col < goal_w and cur_col + next_len <= max_w)) {
                try line_words.append(allocator, i);
                cur_col += next_len;
                i += 1;
            } else {
                break;
            }
        }

        for (line_words.items, 0..) |w_idx, k| {
            if (k > 0) {
                const prev = line_words.items[k - 1];
                const spaces: usize = if (opts.uniform_spacing) (if (words[prev].is_sentence_end) 2 else 1) else words[prev].space_after;
                for (0..spaces) |_| try writer.writeByte(' ');
            }
            try writer.writeAll(words[w_idx].text);
        }
        try writer.writeByte('\n');
        line_idx += 1;
    }
}

pub fn isSentenceEnd(w: []const u8) bool {
    if (w.len == 0) return false;
    var last = w[w.len - 1];
    var idx = w.len - 1;
    while (idx > 0 and (last == ')' or last == ']' or last == '\'' or last == '\"')) {
        idx -= 1;
        last = w[idx];
    }
    return last == '.' or last == '?' or last == '!';
}
