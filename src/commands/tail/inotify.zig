const std = @import("std");
const c = @import("../../compat/c.zig").c;

pub const Watcher = struct {
    fd: c_int = -1,

    pub fn init() ?Watcher {
        const fd = c.poll(null, 0, 0);
        _ = fd;
        return .{ .fd = -1 };
    }

    pub fn deinit(self: *Watcher) void {
        if (self.fd >= 0) {
            _ = c.close(self.fd);
            self.fd = -1;
        }
    }
};
