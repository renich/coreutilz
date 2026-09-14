=========================================
Technical Blueprint: Directory Listing
=========================================

:Domain: Architecture & Systems Programming
:Target Module: ``src/commands/ls.zig``
:Specification ID: ``SPEC-TECH-LS``

.. contents:: Table of Contents
   :depth: 2
   :backlinks: none

1. Architectural Overview
=========================

The Directory Listing engine implements a unified, allocation-bounded architecture capable of powering ``ls``, ``dir``, and ``vdir``. The system minimizes heap churn by tracking file entries in a local directory arena and streaming output through a buffered writer.

2. Technical Requirements & Implementation Mapping
==================================================

[TECH-LS-001] Unified Entrypoint & Variant Profiles
---------------------------------------------------
* **Fulfills Requirement**: ``[FUNC-LS-001]``, ``[FUNC-LS-004]``
* The primary implementation resides in ``src/commands/ls.zig`` exposing the standard interface:

  .. code-block:: zig

     pub const name: []const u8 = "ls";
     pub const version: []const u8 = "0.1.0";
     pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8

* Variant entrypoints for ``dir`` (``src/commands/dir.zig``) and ``vdir`` (``src/commands/vdir.zig``) wrap the shared engine with pre-configured profile defaults:
  * ``ls``: Default format is ``.columns`` when ``c.isatty(1) != 0``, otherwise ``.one_per_line``.
  * ``dir``: Default format is always ``.columns`` (unconditional multi-column layout).
  * ``vdir``: Default format is always ``.long`` (unconditional detailed listing).

[TECH-LS-002] File System Stream Traversal & Inode Sampling
-----------------------------------------------------------
* **Fulfills Requirement**: ``[FUNC-LS-002]``, ``[FUNC-LS-006]``
* Directory reading uses POSIX ``opendir``, ``readdir``, and ``closedir`` via ``src/compat/c.zig`` for zero-overhead native libc interop.
* To support sorting and columnar alignment, directory entries are accumulated in a slice of ``FileEntry`` structures allocated within a per-directory arena.
* Recursive traversal (``-R``) pushes directories to a deterministic processing queue, preventing unbounded stack frame recursion and eliminating stack overflow risks.

[TECH-LS-003] Entry Data Structure & Stat Extraction
----------------------------------------------------
* **Fulfills Requirement**: ``[FUNC-LS-003]``, ``[FUNC-LS-007]``
* Each directory entry is captured in the following compact structure:

  .. code-block:: zig

     pub const FileEntry = struct {
         name: []const u8,
         full_path: []const u8,
         stat: c.struct_stat,
         is_dir: bool,
         is_symlink: bool,
         link_target: ?[]const u8,
         has_stat_error: bool,
     };

* Permissions are formatted into the 10-character string using ``src/utils/mode.zig`` (``formatMode``) prepended with the appropriate file type character.
* UID and GID resolution caches user and group names using an internal fixed-size LRU buffer wrapping POSIX ``getpwuid`` and ``getgrgid``.

[TECH-LS-004] In-Memory Sorting Engine
--------------------------------------
* **Fulfills Requirement**: ``[FUNC-LS-005]``
* Entries are sorted using ``std.sort.pdq`` with custom comparators:
  * Alphabetical: byte collation via ``std.mem.order(u8, a.name, b.name)``.
  * Time: comparison of ``stat.st_mtim.tv_sec`` and ``stat.st_mtim.tv_nsec``.
  * Size: comparison of ``stat.st_size``.
  * Extension: comparison of slice following the last period delimiter.
  * Inversion: if reverse mode (``-r``) is active, comparator logic is inverted.

[TECH-LS-005] Terminal Dimensions & Column Calculation
------------------------------------------------------
* **Fulfills Requirement**: ``[FUNC-LS-004b]``, ``[FUNC-LS-004c]``
* Terminal column width is determined by calling ``c.ioctl(c.STDOUT_FILENO, c.TIOCGWINSZ, &ws)``. If standard output is not a terminal or the ioctl fails, width defaults to 80 characters.
* For column formatting (``-C``), the engine calculates:
  * Maximum entry name display width.
  * Number of columns = ``(term_width + 2) / (max_width + 2)``.
  * Number of rows = ``ceil(entry_count / columns)``.
  * Traverses entries down columns to emit vertically aligned tabbed output.

[TECH-LS-006] Buffered Output Streaming & Error Flushing
---------------------------------------------------------
* **Fulfills Requirement**: ``[FUNC-LS-008]``
* All text rendering streams into a stack-allocated buffer (16KB) managed by ``std.Io.File.Writer``.
* On write errors or disk-full conditions, the engine flushes remaining buffers, emits a standardized error diagnostic to ``stderr`` via ``src/utils/errors.zig``, and returns exit code 1 or 2.
