const std = @import("std");

/// In coreutilz, all standalone binary wrappers and multicall main use
/// `std.process.Init.Minimal`. This avoids Threaded I/O background worker threads
/// and preserves pure native Unix signal semantics:
/// 1. Default pipeline: unhandled SIGPIPE terminates with signal 13 (exit status 141).
/// 2. Trapped/ignored pipeline (e.g. `trap "" PIPE`): EPIPE write errors are reported to stderr with exit status 1.
pub fn restoreDefaultSignals() void {}
