=======================================================
Technical Specification: Text Formatting & Padding
=======================================================

:Domain: Text & Stream Processing
:Target Utilities: ``nl``, ``fmt``, ``pr``, ``expand``, ``unexpand``, ``od``, ``ptx``, ``numfmt``
:Specification ID: ``SPEC-TECH-TEXT-FMT``

.. contents:: Table of Contents
   :depth: 2
   :backlinks: none

1. Architecture & Memory Management
===================================

Every utility in the Text Formatting & Padding suite implements explicit memory allocations with `std.mem.Allocator`, bounded streaming buffers, and zero-allocation fast paths where possible.

* **Buffer Streaming**: Utilities process inputs using 16KB-64KB ring/linear buffers to ensure high throughput and minimal syscalls.
* **Line Ceiling & Function Complexity**: Every source file MUST not exceed 300 lines ceiling and functions MUST not exceed 40 lines. Larger tools (such as ``fmt``, ``pr``, ``od``, ``numfmt``) are partitioned into modular sub-packages under ``src/commands/<cmd>/``.
* **Error Handling & Flushes**: All output streams explicitly check write errors and flush before exit (handling ``/dev/full`` and write failure with exit code 1 or 2).

2. Module Decomposition
=======================

[TECH-NL-001] Line Numbering Engine
-----------------------------------
* Implemented in ``src/commands/nl.zig``.
* State machine tracking current section (header, body, footer) and logical page boundaries.
* POSIX regex matching via ``c.regcomp`` and ``c.regexec`` for ``-b pBRE``.
* Left/right justification and leading zero formatting using formatted buffer writes.

[TECH-FMT-001] Knuth-Plass Paragraph Reflower
---------------------------------------------
* Implemented in ``src/commands/fmt.zig`` (and ``src/commands/fmt/`` helper modules).
* Bounded word and paragraph tokenization.
* Dynamic cost evaluation minimizing raggedness and line overruns.
* Support for prefix matching, crown margins, tagged paragraphs, and uniform punctuation spacing.

[TECH-PR-001] Multi-Column Paginated Formatter
----------------------------------------------
* Implemented in ``src/commands/pr.zig`` (and ``src/commands/pr/`` submodules).
* Ring buffers and temporary page staging for column-down rendering.
* Streaming line-by-line interleaving for across and merge modes.
* Configurable header/footer emission, page numbering, and line indentation.

[TECH-EXPAND-001] Tab Stop Calculators
--------------------------------------
* Implemented in ``src/commands/expand.zig`` and ``src/commands/unexpand.zig``.
* Monotonic tab stop list parser supporting comma/space separation and trailing step increments (``+N``).
* Column tracking accounting for backspaces (``\b``) and non-printable control characters.

[TECH-OD-001] Multi-Radix Octal & Hex Engine
--------------------------------------------
* Implemented in ``src/commands/od.zig`` (and ``src/commands/od/`` submodules).
* Direct byte interpretation across native and foreign endianness.
* Line deduplication cache comparing adjacent 16/32-byte blocks for asterisk (``*``) output suppression.
* Comprehensive format dispatch for integer sizes (1, 2, 4, 8) and floats.

[TECH-PTX-001] Permuted Index Generator
---------------------------------------
* Implemented in ``src/commands/ptx.zig`` (and ``src/commands/ptx/`` submodules).
* Inverted index generation and word boundary extraction.
* Output formatting for standard text, TeX macro calls, and ROFF requests.

[TECH-NUMFMT-001] Engineering Units Parser & Formatter
------------------------------------------------------
* Implemented in ``src/commands/numfmt.zig`` (and ``src/commands/numfmt/`` submodules).
* Fixed/floating point conversion supporting SI (1000) and IEC (1024) suffixes.
* Delimited field replacement, column padding, and rounding disciplines (nearest, up, down, towards-zero).
