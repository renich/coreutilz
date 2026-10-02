const std = @import("std");
const c = @import("../../compat/c.zig").c;

pub fn spillStreamToTemp(file: std.Io.File) !std.Io.File {
    var template = "/tmp/split_spill_XXXXXX".*;
    const fd = c.mkstemp(&template);
    if (fd < 0) return error.TempFileCreationFailed;
    _ = c.unlink(&template);

    const temp_file = std.Io.File{ .handle = fd, .flags = .{ .nonblocking = false } };
    var buf: [65536]u8 = undefined;
    while (true) {
        const n = c.read(file.handle, &buf, buf.len);
        if (n <= 0) break;
        var written: usize = 0;
        const total: usize = @intCast(n);
        while (written < total) {
            const nw = c.write(temp_file.handle, buf[written..total].ptr, total - written);
            if (nw <= 0) return error.WriteFailed;
            written += @intCast(nw);
        }
    }

    _ = c.lseek(temp_file.handle, 0, c.SEEK_SET);
    return temp_file;
}
