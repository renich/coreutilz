============================================
Coreutilz: System Architecture Specification
============================================

:Version: v1.0
:Author: Coreutilz Architecture Team
:Date: 2026-09-05

.. contents:: Table of Contents
   :depth: 2

Executive Summary
=================

Coreutilz is a clean-room, idiomatic systems rewrite of GNU Coreutils in **Zig 0.16.0**. It delivers 100% behavioral, syntactic, and exit-status parity with upstream GNU Coreutils while providing sub-second build times, zero hidden control flow, explicit memory management, and tiny standalone binaries.

System Architecture
===================

Package & Codebase Structure
----------------------------

.. code-block:: text

   coreutilz/
   ├── build.zig                 # Unified declarative build definition
   ├── src/
   │   ├── main.zig              # Multicall multiplexer binary (coreutilz)
   │   ├── root.zig              # Root library export exposing all commands
   │   ├── commands/             # Individual command modules
   │   │   ├── cat.zig
   │   │   ├── chmod.zig
   │   │   ├── stat.zig
   │   │   └── ... (38 modules)
   │   ├── utils/                # Consolidated domain utilities
   │   │   ├── args.zig          # CLI parsing & GNU option permuter
   │   │   ├── errors.zig        # Error reporting & version/help formatters
   │   │   ├── mode.zig          # Octal/symbolic mode parser with umask & setgid
   │   │   └── ...
   │   └── wrappers/             # Standalone binary entrypoints
   │       ├── cat_main.zig
   │       └── ...
   ├── tests/                    # Hermetic unit and integration tests
   ├── scripts/                  # Operational, lint, and test scripts
   └── docs/                     # Architectural specifications and manuals

The Standard Command Contract
-----------------------------

Every command module in ``src/commands/<cmd>.zig`` satisfies the following interface:

.. code-block:: zig

   const std = @import("std");

   pub const name: []const u8 = "command_name";
   pub const version: []const u8 = "0.1.0";

   pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8

Dual-Mode Invocation Model
--------------------------

Coreutilz supports two execution models from a single codebase:

1. **Multicall Multiplexer Mode**:
   When compiled as ``coreutilz``, the executable inspects ``argv[0]``. If invoked as ``coreutilz <cmd>`` or via symlink (e.g. ``/bin/ls -> /bin/coreutilz``), it dynamically dispatches to the corresponding ``commands.<cmd>.run()`` without process re-exec overhead.

2. **Standalone Binary Mode**:
   Every command compiles into an independent executable in ``zig-out/bin/<cmd>`` via ``src/wrappers/<cmd>_main.zig``. These binaries have zero runtime dependencies on other commands and can be installed directly to ``/usr/bin/``.

I/O Buffering & Syscall Architecture
====================================

High-Throughput Streaming
-------------------------

Coreutilz utilities that handle high-volume data streams (``cat``, ``yes``, ``seq``, ``head``, ``cut``, ``tee``) utilize streaming buffered writers:

.. code-block:: zig

   var stdout_buffer: [16384]u8 = undefined;
   var stdout_writer: std.Io.File.Writer = .initStreaming(
       .stdout(),
       std.Options.debug_io,
       &stdout_buffer,
   );
   const stdout = &stdout_writer.interface;
   defer stdout.flush() catch {};

Write Failure & Flush Guarantees
--------------------------------

To satisfy GNU coreutils write error requirements (such as writing to full disks or ``/dev/full``):
- Every command flushes buffers before returning.
- On write failure (``error.DiskFull`` / ``error.NoSpaceLeft`` / ``EIO``), standard error diagnostic is printed and the binary returns exit status 1 (or 125 for ``env``, 2 for ``printenv``, 3 for ``tty``).

Signal Handling & Broken Pipes
------------------------------

For pipeline compatibility (e.g. ``yes | head -n 1``):
- Utilities restore standard ``SIGPIPE`` disposition using ``c.signal(c.SIGPIPE, c.SIG_DFL)`` or explicitly handle ``EPIPE`` without reporting spurious diagnostic errors on closed downstream readers.

C-ABI Interoperability
======================

Coreutilz uses direct C ABI interop via ``@cImport`` for POSIX/Linux kernel syscalls:
- Extended attributes, ``statx``, file descriptors, groups, passwords, directory streams (``dirent``), and terminal controls (``termios``).
- Zero wrapper crate overhead; direct integration with glibc/musl APIs.
