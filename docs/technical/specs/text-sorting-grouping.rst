=====================================================
Technical Blueprint: Text Sorting & Grouping
=====================================================

:Domain: Architecture & Systems Programming
:Target Modules: ``src/commands/sort.zig``, ``src/commands/uniq.zig``, ``src/commands/comm.zig``, ``src/commands/shuf.zig``, ``src/commands/tac.zig``
:Specification ID: ``SPEC-TECH-TEXT-SORT``

.. contents:: Table of Contents
   :depth: 2
   :backlinks: none

1. Architectural Overview
=========================

The Text Sorting & Grouping suite implements high-throughput, memory-bounded algorithms for line-oriented data processing. The design leverages Zig's explicit allocators (using arena allocators for per-batch lifecycles) and buffered I/O streams to minimize syscall overhead while guaranteeing strict GNU Coreutils compatibility.

2. Technical Requirements & Implementation Mapping
==================================================

[TECH-SORT-001] Sort Core Engine & Memory Management
----------------------------------------------------
* **Fulfills Requirement**: ``[FUNC-SORT-001]``, ``[FUNC-SORT-004]``
* The primary implementation resides in ``src/commands/sort.zig`` (with auxiliary modules in ``src/commands/sort/``).
* Line storage uses an arena allocator reading records into dynamic arrays of line slices.
* Sorting is performed using Zig's standard introspective sort (PDQ sort/block sort) ensuring $O(N \log N)$ worst-case time complexity.
* When ``-s`` (``--stable``) is active, stable merge sort is used to preserve original line sequence for equal keys.
* When ``-o FILE`` specifies an existing input file, output is written via an atomic temporary file or delayed stream flush to prevent reading from a truncated file.

[TECH-SORT-002] Multi-Field Key Parsing & Comparator Engine
-----------------------------------------------------------
* **Fulfills Requirement**: ``[FUNC-SORT-002]``, ``[FUNC-SORT-003]``
* Sorting comparisons are evaluated through a composable key pipeline represented by:

  .. code-block:: zig

     pub const KeySpec = struct {
         start_field: usize,
         start_char: usize,
         end_field: ?usize,
         end_char: ?usize,
         numeric: bool = false,
         general_numeric: bool = false,
         human_numeric: bool = false,
         month: bool = false,
         version: bool = false,
         random: bool = false,
         reverse: bool = false,
         ignore_blanks: bool = false,
         ignore_case: bool = false,
     };

* Line fields are extracted on demand based on the delimiter character or whitespace transitions.
* If all user-specified keys evaluate equal, lines are compared in full lexicographical order unless ``-s`` (stable sort) is active.

[TECH-SORT-003] Verification & Merge Disciplines
------------------------------------------------
* **Fulfills Requirement**: ``[FUNC-SORT-004b]``, ``[FUNC-SORT-004c]``, ``[FUNC-SORT-005]``
* Check mode (``-c``/``-C``) processes streams sequentially in $O(N)$ time with $O(1)$ memory by comparing each line only to its immediate predecessor.
* Merge mode (``-m``) merges $K$ pre-sorted streams using a min-heap priority queue of size $K$, streaming results in $O(N \log K)$ time.

[TECH-UNIQ-001] Streaming Group Dedup Engine
--------------------------------------------
* **Fulfills Requirement**: ``[FUNC-UNIQ-001]``, ``[FUNC-UNIQ-003]``
* Located in ``src/commands/uniq.zig``. Operates as an online single-pass filter with $O(1)$ auxiliary line storage.
* Tracks two line buffers (current line and previous line) allocated within a rotating buffer.
* Field skipping (``-f N``) and character skipping (``-s N``) compute slice sub-windows prior to equality comparison.
* Case folding (``-i``) executes byte-level ASCII case insensitivity on the target comparison slice.

[TECH-UNIQ-002] Frequency Counting & Selection Filters
------------------------------------------------------
* **Fulfills Requirement**: ``[FUNC-UNIQ-002]``, ``[FUNC-UNIQ-004]``
* Maintains an unsigned 64-bit counter of consecutive identical lines.
* When the line changes or EOF is reached, the group is evaluated against active filter flags:
  * ``-c`` (count): Formats counter via ``%7d {line}\n``.
  * ``-d`` (repeated): Emits if counter $> 1$.
  * ``-u`` (unique): Emits if counter $== 1$.
  * Default: Emits once per group.

[TECH-COMM-001] Synchronized Dual-Stream Step Engine
----------------------------------------------------
* **Fulfills Requirement**: ``[FUNC-COMM-001]``, ``[FUNC-COMM-004]``
* Located in ``src/commands/comm.zig``. Reads two input streams concurrently using buffered readers.
* At each step, compares line from ``FILE1`` and line from ``FILE2``:
  * If ``line1 < line2``: line1 is unique to FILE1 (Column 1); advance FILE1.
  * If ``line1 > line2``: line2 is unique to FILE2 (Column 2); advance FILE2.
  * If ``line1 == line2``: line is common to both (Column 3); advance both.
* Order checking maintains the last observed line for each file and asserts monotonic non-decreasing order.

[TECH-COMM-002] Masked Column Output Formatter
----------------------------------------------
* **Fulfills Requirement**: ``[FUNC-COMM-002]``, ``[FUNC-COMM-003]``
* Column emission respects suppression bitmasks (``-1``, ``-2``, ``-3``).
* Formatter prepends output delimiter (default ``\t`` or custom ``--output-delimiter=STR``) dynamically based on active columns.

[TECH-SHUF-001] Fisher-Yates Permutation & Reservoir Sampling
-------------------------------------------------------------
* **Fulfills Requirement**: ``[FUNC-SHUF-001]``, ``[FUNC-SHUF-002]``
* Located in ``src/commands/shuf.zig``.
* For bounded in-memory inputs, lines are gathered into a dynamic slice and randomized in-place using modern Fisher-Yates with `std.Random.DefaultPrng` seeded via system CSPRNG (`std.crypto.random`).
* For range mode (``-i LO-HI``), numbers are generated dynamically without instantiating strings in memory prior to shuffle.

[TECH-SHUF-002] Bounded Stream Generator
----------------------------------------
* **Fulfills Requirement**: ``[FUNC-SHUF-003]``, ``[FUNC-SHUF-004]``
* If ``-n COUNT`` is specified, output terminates after emitting ``COUNT`` lines.
* If ``-r`` (repeat) is active, randomly draws indices with replacement uniformly from $[0, N-1]$ indefinitely or until ``-n`` is satisfied.
* If ``-o FILE`` is specified, output is redirected to target file atomically.

[TECH-TAC-001] Reverse Chunked File Navigation
----------------------------------------------
* **Fulfills Requirement**: ``[FUNC-TAC-001]``, ``[FUNC-TAC-003]``
* Located in ``src/commands/tac.zig``.
* Seekable regular files use reverse block scanning:
  * Determines file size via ``fstat``.
  * Reads backward in $8 \text{ KiB}$ buffer chunks from end of file to beginning.
  * Identifies line boundaries and prints lines in reverse order without storing the whole file in RAM.
* Non-seekable streams (pipes/stdin) buffer input into an in-memory segment or temporary file before scanning backward.

[TECH-TAC-002] Separator Tokenizer & Placement Engine
-----------------------------------------------------
* **Fulfills Requirement**: ``[FUNC-TAC-002]``
* Matches custom multi-byte separator strings (``-s STR``) in the reverse stream.
* If ``-b`` (before) is active, attaches the trailing boundary delimiter to the beginning of the preceding record.
