====================================================
Technical Blueprint: Text Splitting & Filtering
====================================================

:Domain: Text & Stream Processing
:Target Utilities: ``split``, ``csplit``, ``tail``, ``tr``, ``fold``
:Specification ID: ``SPEC-TECH-TEXT-SPLIT``
:Functional Reference: ``SPEC-FUNC-TEXT-SPLIT``

.. contents:: Table of Contents
   :depth: 2
   :backlinks: none

1. Architectural Overview
=========================

The Text Splitting & Filtering suite implements high-throughput stream processing algorithms using bounded chunking, buffered I/O, POSIX basic regular expressions, and zero-allocation lookup tables.

To enforce strict repository standards:
* Every source file MUST not exceed 300 lines.
* Every function MUST not exceed 40 lines of core logic.
* Branch nesting depth MUST not exceed 3 levels.
* Command execution MUST follow the standard Coreutilz entrypoint runner contract (``runner.runWrapper``).

2. Technical Architecture: ``split``
====================================

Module Decomposition
--------------------
* ``src/commands/split.zig``: CLI runner, stream dispatch, lifecycle management.
* ``src/commands/split/args.zig``: CLI option parsing, multiplier parsing, validation.
* ``src/commands/split/file_namer.zig``: Suffix generator (alpha, numeric, hex, auto-extending width).
* ``src/commands/split/chunk_writer.zig``: Output destination writer supporting disk files and ``--filter`` subprocesses.
* ``src/commands/split/strategy.zig``: Core chunking engine for lines, bytes, line-bytes, and round-robin.
* ``src/commands/split/temp_spill.zig``: Bounded temporary file spill for unseekable streams under numbered chunking.

[TECH-SPLIT-001] Entrypoint Dispatch & Suffix Generation
--------------------------------------------------------
* *Fulfills*: ``[FUNC-SPLIT-001]``
* Generates output file names using prefix (default ``x``) and suffix sequence.
* Alpha suffixes: Base-26 increment using letters ``a``-``z``.
* Numeric/Hex suffixes: Formatted with leading zeros to `suffix_len`.
* Fixed-length mode: If ``-a N`` is explicitly given, exhaustion of suffix permutations emits a fatal error (exit 1).
* Dynamic auto-extension: If ``-a`` is default, suffix length expands dynamically upon exhaustion to preserve alphabetical ordering.

[TECH-SPLIT-002] Fixed-Size Chunking Engines
--------------------------------------------
* *Fulfills*: ``[FUNC-SPLIT-002a]``, ``[FUNC-SPLIT-002b]``, ``[FUNC-SPLIT-002c]``, ``[FUNC-SPLIT-003b]``
* Uses 64 KiB page-aligned I/O buffers for streaming reads and writes.
* Line-split (``-l``): Scans buffer for delimiter (``\n`` or ``-t SEP``), tracking line counts and rotating output writers after ``N`` records.
* Byte-split (``-b``): Tracks accumulated bytes per file, rotating output files when byte threshold is reached.
* Line-byte split (``-C``): Accumulates complete lines in buffer up to ``SIZE`` bytes; flushes and rotates writer. Single lines exceeding ``SIZE`` bytes are broken across file boundaries.

[TECH-SPLIT-003] Numbered Chunking & Temporary File Spill
---------------------------------------------------------
* *Fulfills*: ``[FUNC-SPLIT-002d]``, ``[FUNC-SPLIT-003a]``
* For seekable regular files, obtains total file size via ``stat``/``fstat`` and computes chunk offsets directly.
* For non-seekable streams (pipes, ttys) under numbered byte chunking (``-n N``, ``-n k/N``, ``-n l/N``, ``-n l/k/N``), streams data to an unlinked temporary file using 64 KiB buffer blocks (preventing unbounded heap exhaustion) to determine total size before chunk dispatch.
* Round-robin chunking (``-n r/N``, ``-n r/k/N``) bypasses size pre-determination and streams lines directly across output writers.
* Option ``-e`` checks whether chunk output length is zero and elides file creation.

[TECH-SPLIT-004] Subprocess Filter Pipeline & Signal Isolation
--------------------------------------------------------------
* *Fulfills*: ``[FUNC-SPLIT-003c]``, ``[FUNC-SPLIT-003d]``, ``[FUNC-SPLIT-003e]``
* Spawns subshell executing ``COMMAND`` via ``/bin/sh -c`` with environment variable ``FILE`` exported.
* In round-robin mode across $N$ filters, maintains open child process handles, writes to pipe descriptors, and closes child stdin upon completion.
* Intercepts `SIGPIPE` to prevent premature parent abort; captures child process exit statuses via ``waitpid`` and returns exit code 1 if any child fails.

3. Technical Architecture: ``csplit``
=====================================

Module Decomposition
--------------------
* ``src/commands/csplit.zig``: Core loop, pattern dispatch, stdout byte accounting.
* ``src/commands/csplit/args.zig``: Argument validator, format parser, pattern compiler.
* ``src/commands/csplit/pattern.zig``: Pattern execution engine (line numbers, BRE regex, repeats).
* ``src/commands/csplit/buffer.zig``: Sliding line buffer supporting lookahead and lookback offsets.
* ``src/commands/csplit/file_manager.zig``: Output file creation, byte count tracking, signal-safe cleanup rollback.

[TECH-CSPLIT-001] Pattern Match Engine & POSIX BRE Compilation
--------------------------------------------------------------
* *Fulfills*: ``[FUNC-CSPLIT-001]``
* Pre-compiles regular expressions using POSIX Basic Regular Expression (BRE) flags via libc C ABI (``regcomp(&preg, pattern, 0)``).
* Distinguishes repeat types:
  - Fixed repeat ``{N}``: Increments repeat counter; reaching EOF prior to completing $N$ matches triggers a fatal error and unlinks generated files (unless ``-k``).
  - Indefinite repeat ``{*}``: Continues until EOF; reaching EOF terminates loop cleanly with exit code 0.

[TECH-CSPLIT-002] Sliding Line Window & Offset Lookahead Buffer
---------------------------------------------------------------
* *Fulfills*: ``[FUNC-CSPLIT-001]``
* Maintains a ring buffer of line references to allow backward and forward offsets (``/REGEXP/+N``, ``/REGEXP/-N``).
* Offsets shifting the split point backward copy lines from the lookback buffer into the preceding output file.
* Lines matching patterns are omitted from output files when ``--suppress-matched`` is enabled.

[TECH-CSPLIT-003] File Lifecycle, Suffix Formatting & Rollback
--------------------------------------------------------------
* *Fulfills*: ``[FUNC-CSPLIT-002]``
* Validates ``-b FORMAT`` string using safe format inspector (ensuring exactly one integer conversion specifier such as ``%d``, ``%u``, ``%x``).
* Tracks created output file paths in an arena-allocated list.
* Registers signal handler for ``SIGINT``, ``SIGTERM``, ``SIGHUP``, ``SIGQUIT``: unless ``-k`` (``--keep-files``) is active, all created files are removed via ``unlink`` prior to process termination.
* Tracks cumulative byte counts per output file and writes counts to standard output unless ``-s``/``-q`` is specified.

4. Technical Architecture: ``tail``
===================================

Module Decomposition
--------------------
* ``src/commands/tail.zig``: Main entrypoint, multi-file coordinator.
* ``src/commands/tail/args.zig``: Option parsing, signed offset decoding (``+N`` vs ``-N``).
* ``src/commands/tail/ring_buffer.zig``: Circular ring buffer for pipes and unseekable streams.
* ``src/commands/tail/seek_reader.zig``: Reverse block seeker for seekable regular files.
* ``src/commands/tail/follow.zig``: Live file observation coordinator and sleep loop.
* ``src/commands/tail/inotify.zig``: Inotify event monitoring with filesystem type detection.

[TECH-TAIL-001] Backward Block Seek & Circular Ring Buffer
----------------------------------------------------------
* *Fulfills*: ``[FUNC-TAIL-001]``
* **Seekable Regular Files**: Obtains file size via ``lseek``; scans backward in 8 KiB blocks counting record delimiters (``\n`` or ``\0`` under ``-z``). Properly accounts for trailing newline semantics without off-by-one errors. Seeks forward to line boundary and streams remainder to stdout.
* **Non-Seekable Streams (Pipes/TTYs)**: Accumulates lines/bytes into a circular ring buffer with bounded capacity; upon EOF, flushes buffer contents to standard output.
* **Positive Offsets (``+N``)**: Skips the first $N-1$ lines or bytes from input stream, writing remainder to stdout.

[TECH-TAIL-002] Multi-File Header Coordinator
---------------------------------------------
* *Fulfills*: ``[FUNC-TAIL-002]``
* Formats standard banner ``==> FILE <==\n`` before each file's output when processing multiple files (or under ``-v``).
* Suppresses banner headers when ``-q``/``-s`` is active.
* Inserts newline separator between consecutive file outputs.

[TECH-TAIL-003] Real-Time Event Loop & PID Monitoring
-----------------------------------------------------
* *Fulfills*: ``[FUNC-TAIL-003]``
* Uses Linux ``inotify`` (``inotify_init1(IN_CLOEXEC)``, ``inotify_add_watch``) for instantaneous notification of file modifications and truncations.
* Inspects filesystem magic via ``fstatfs``; for remote (NFS, CIFS) or virtual (``/proc``, ``/sys``) filesystems where inotify does not generate events, automatically falls back to interval polling.
* Follow by name (``--follow=name``): Detects file rotation/replacement by periodic ``stat`` comparisons on inode numbers.
* PID heartbeat check: Verifies target PID status via ``std.posix.kill(pid, 0)``. The process is alive if call returns 0 or ``error.PermissionDenied`` (``EPERM``); terminates follow loop only when call returns ``error.ProcessNotFound`` (``ESRCH``).

5. Technical Architecture: ``tr``
=================================

Module Decomposition
--------------------
* ``src/commands/tr.zig``: CLI runner, mode selector, high-throughput streaming loop.
* ``src/commands/tr/args.zig``: Operand validation matrix, flag parsing.
* ``src/commands/tr/set_parser.zig``: Character set compiler (ranges, octal escapes, classes, repeats).
* ``src/commands/tr/char_class.zig``: POSIX character class tables (alnum, alpha, blank, etc.).
* ``src/commands/tr/filter.zig``: Specialized branchless stream filtering routines.

[TECH-TR-001] Operand Validation & 256-Byte Array Synthesis
-----------------------------------------------------------
* *Fulfills*: ``[FUNC-TR-001]``
* Enforces strict operand count validation: rejects all file operands; requires exactly 2 operands for translation and ``-d -s``; exactly 1 operand for ``-d``; 1 or 2 operands for ``-s``.
* Compiles ``SET1`` and ``SET2`` into three static 256-byte lookup arrays:
  - ``map_table: [256]u8`` (direct byte replacement mapping).
  - ``delete_table: [256]bool`` (fast deletion filter).
  - ``squeeze_table: [256]bool`` (fast consecutive duplicate collapse).
* When ``-c``/``-C`` is specified, inverts the boolean selection table across all 256 byte values.

[TECH-TR-002] Specialized Branchless Stream Transformation
----------------------------------------------------------
* *Fulfills*: ``[FUNC-TR-002]``
* Replaces monolithic inner loop with distinct, optimized transformation functions:
  - ``translateStream``: Direct table lookup ``out[i] = map[in[i]]``.
  - ``deleteStream``: Single check against ``delete_table[in[i]]``.
  - ``squeezeStream``: Checks ``squeeze_table[in[i]]`` against persistent ``last_char: ?u8 = null``.
  - ``deleteAndSqueezeStream``: First drops characters in ``delete_table``, then squeezes matches in ``squeeze_table``.
  - ``translateAndSqueezeStream``: Translates via ``map_table``, then squeezes matches in ``squeeze_table``.
* State ``last_char`` is maintained across 64 KiB buffer boundaries, correctly handling leading ``\x00`` bytes.

6. Technical Architecture: ``fold``
===================================

Module Decomposition
--------------------
* ``src/commands/fold.zig``: Stream processing runner, line buffering, output writer.
* ``src/commands/fold/args.zig``: Option parsing, width validation (supporting legacy ``-WIDTH``).

[TECH-FOLD-001] Column Geometry & Control Character Accounting
--------------------------------------------------------------
* *Fulfills*: ``[FUNC-FOLD-001]``
* In standard mode, parses UTF-8 sequences and queries character display width via ``c32width`` (handling zero-width combining marks and double-width CJK characters).
* Control characters:
  - Tab (``\t``): Advances column to next multiple of 8: ``col = (col + 8) & ~@as(usize, 7)``.
  - Backspace (``\b``): Decrements column: ``col = if (col > 0) col - 1 else 0``.
  - Carriage return (``\r``): Resets column: ``col = 0``.
* In byte mode (``-b``), every byte strictly increments column count by 1.

[TECH-FOLD-002] Space-Aware Line Breaking
-----------------------------------------
* *Fulfills*: ``[FUNC-FOLD-002]``
* Maintains sliding line buffer of characters up to width limit.
* Tracks byte and column index of the most recent blank (ASCII space ``0x20`` or tab ``0x09``).
* When width limit is reached:
  - If ``-s`` is active and a blank exists within the current line window, breaks immediately after the blank and emits newline.
  - If no blank exists or ``-s`` is omitted, breaks at the exact width threshold without dropping characters.

7. Technical Architecture: Diagnostics & Exit Codes
===================================================

[TECH-TEXT-DIAG-001] Error Handling & Flush Propagation
-------------------------------------------------------
* *Fulfills*: ``[FUNC-TEXT-DIAG-001]``
* Standard exit codes: 0 for clean success, 1 for errors.
* Prior to process termination, all streaming output writers MUST execute ``stdout.flush() catch return 1;`` (or return exit status 1 on write error to ``/dev/full``).
* Errors written to standard error are formatted consistently as ``<utility>: <error description>\n``.
