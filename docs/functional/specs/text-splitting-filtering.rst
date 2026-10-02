=======================================================
Functional Specification: Text Splitting & Filtering
=======================================================

:Domain: Text & Stream Processing
:Target Utilities: ``split``, ``csplit``, ``tail``, ``tr``, ``fold``
:Specification ID: ``SPEC-FUNC-TEXT-SPLIT``

.. contents:: Table of Contents
   :depth: 2
   :backlinks: none

1. Overview
===========

The Text Splitting & Filtering suite provides deterministic fixed-size chunking, regular-expression and line-based contextual splitting, tail-end stream extraction and live filesystem following, character-set translation/deletion/squeezing, and column/byte-constrained line wrapping.

Utilities ``split``, ``csplit``, ``tail``, and ``fold`` accept standard input and/or specified file operands, whereas ``tr`` operates strictly on standard input and rejects all file operands with a fatal operand diagnostic. Each utility streams processed records to standard output or specified destination paths with byte-level fidelity matching GNU Coreutils.

2. Functional Requirements: ``split``
=====================================

[FUNC-SPLIT-001] Input Ingestion & Output File Naming
-----------------------------------------------------
* The utility MUST accept an optional input file operand. If omitted or if ``-`` is specified, it MUST read from standard input.
* The utility MUST accept an optional output prefix operand (default ``x``).
* Output file names MUST be formed by concatenating the prefix with a generated suffix.
* Suffixes by default MUST consist of alphabetic lowercase letters (``aa``, ``ab``, ..., ``zz``).
* When ``-a N`` (``--suffix-length=N``) is specified, suffixes MUST be generated with fixed length ``N`` (default 2). Exhausting suffixes in fixed-length mode MUST emit ``split: output file suffixes exhausted`` and exit with status 1.
* When ``-a`` is omitted, suffix length MUST dynamically auto-extend upon exhaustion such that alphabetical sort order is preserved.
* When ``-d`` (``--numeric-suffixes[=FROM]``) is specified, suffixes MUST be generated as decimal numbers starting at 0 (or ``FROM``) formatted with leading zeros to length ``N``.
* When ``-x`` (``--hex-suffixes[=FROM]``) is specified, suffixes MUST be generated as lowercase hexadecimal numbers starting at 0 (or ``FROM``) formatted with leading zeros to length ``N``.
* When ``--additional-suffix=SUFFIX`` is specified, ``SUFFIX`` MUST be appended after the generated suffix.
* *Fulfills Technical Reference*: ``[TECH-SPLIT-001]``

[FUNC-SPLIT-002] Splitting Disciplines
--------------------------------------
* **[FUNC-SPLIT-002a] Line-Based Split (``-l N``, ``--lines=N``)**: Output files MUST contain at most ``N`` lines (default 1000).
* **[FUNC-SPLIT-002b] Byte-Based Split (``-b SIZE``, ``--bytes=SIZE``)**: Output files MUST contain at most ``SIZE`` bytes. Standard multipliers MUST be supported:
  - Blocks: ``b`` (512 bytes), ``c`` (1 byte), ``w`` (2 bytes).
  - SI Decimal (powers of 1000): ``KB``, ``MB``, ``GB``, ``TB``, ``PB``, ``EB``, ``ZB``, ``YB``.
  - IEC Binary (powers of 1024): ``K``/``KiB``, ``M``/``MiB``, ``G``/``GiB``, ``T``/``TiB``, ``P``/``PiB``, ``E``/``EiB``, ``Z``/``ZiB``, ``Y``/``YiB``.
  - Arithmetic overflow exceeding $2^{64}-1$ MUST emit ``split: invalid number of bytes`` and exit 1.
* **[FUNC-SPLIT-002c] Line-Byte Split (``-C SIZE``, ``--line-bytes=SIZE``)**: Output files MUST contain at most ``SIZE`` bytes of complete lines, unless an individual line exceeds ``SIZE`` bytes, in which case that line is split across files.
* **[FUNC-SPLIT-002d] Chunk Count Split (``-n CHUNKS``, ``--number=CHUNKS``)**:
  - ``N``: Split input into ``N`` equal-sized byte chunks. For non-seekable streams, input MUST be staged to a bounded temporary file to determine input size.
  - ``k/N``: Output only the ``k``-th chunk of ``N`` to standard output.
  - ``l/N``: Split input into ``N`` chunks without splitting lines/records.
  - ``l/k/N``: Output only the ``k``-th line-respecting chunk of ``N`` to standard output.
  - ``r/N``: Round-robin line distribution across ``N`` output files. Operates directly on streaming pipes without requiring total input size.
  - ``r/k/N``: Output only lines assigned to chunk ``k`` of ``N`` in round-robin mode to standard output.
* *Fulfills Technical Reference*: ``[TECH-SPLIT-002]``, ``[TECH-SPLIT-003]``

[FUNC-SPLIT-003] Filtering & Control
------------------------------------
* **[FUNC-SPLIT-003a] Elide Empty Files (``-e``, ``--elide-empty-files``)**: The utility MUST NOT create empty output files when splitting with ``-n``.
* **[FUNC-SPLIT-003b] Record Separator (``-t CHAR``, ``--separator=CHAR``)**: Use ``CHAR`` as the record delimiter instead of newline.
* **[FUNC-SPLIT-003c] Shell Filter (``--filter=COMMAND``)**: Instead of creating disk files, output for each split MUST be piped to a subshell executing ``COMMAND`` with environment variable ``$FILE`` set to the would-be filename.
* **[FUNC-SPLIT-003d] Unbuffered Mode (``-u``, ``--unbuffered``)**: When ``-u`` is specified, output MUST be immediately flushed on every line/record under round-robin chunking.
* **[FUNC-SPLIT-003e] Diagnostic Verbosity (``--verbose``)**: The utility MUST output a diagnostic to standard error (``creating file '...'``) just prior to opening each output file.
* *Fulfills Technical Reference*: ``[TECH-SPLIT-002]``, ``[TECH-SPLIT-003]``, ``[TECH-SPLIT-004]``

3. Functional Requirements: ``csplit``
======================================

[FUNC-CSPLIT-001] Pattern-Based Splitting
-----------------------------------------
* The utility MUST accept a mandatory ``FILE`` operand and at least one ``PATTERN`` operand. Passing zero operands or only ``FILE`` MUST emit a diagnostic and exit 1.
* Standard input is read ONLY when ``-`` is explicitly specified as ``FILE``.
* Supported pattern formats:
  - ``INTEGER``: Split at the specified 1-indexed line number. If ``INTEGER`` is less than or equal to current line, or exceeds total lines, exit 1.
  - ``/REGEXP/[OFFSET]``: Split up to but not including the line matching POSIX Basic Regular Expression (BRE) ``REGEXP``. Optional offset ``+N`` or ``-N`` shifts the split point by ``N`` lines.
  - ``%REGEXP%[OFFSET]``: Skip input up to the line matching BRE ``REGEXP`` (with optional offset) without generating an output file for the skipped section.
  - ``{INTEGER}``: Repeat the preceding pattern the specified number of times. Reaching EOF before completing the specified repetitions is a fatal error (exit 1).
  - ``{*}``: Repeat the preceding pattern as many times as possible until input is exhausted. Reaching EOF during indefinite repeat is normal successful termination (exit 0).
* *Fulfills Technical Reference*: ``[TECH-CSPLIT-001]``, ``[TECH-CSPLIT-002]``

[FUNC-CSPLIT-002] File Naming, Cleanup & Accounting
---------------------------------------------------
* Output file names MUST default to prefix ``xx`` followed by a two-digit decimal number starting at ``00`` (e.g., ``xx00``, ``xx01``).
* When ``-f PREFIX`` (``--prefix=PREFIX``) is specified, ``PREFIX`` MUST replace ``xx``.
* When ``-n DIGITS`` (``--digits=DIGITS``) is specified, the decimal sequence MUST use ``DIGITS`` width with leading zeros.
* When ``-b FORMAT`` (``--suffix-format=FORMAT``) is specified, the filename suffix MUST be generated using the printf-style ``FORMAT`` string (which must contain a conversion specification for an unsigned integer).
* By default, the byte count of each created output file MUST be written to standard output, one per line.
* When ``-s``, ``-q``, or ``--silent``/``--quiet`` is specified, file byte counts MUST NOT be printed.
* When ``-z`` (``--elide-empty-files``) is specified, empty output files MUST be removed or not created.
* When an error occurs during splitting, or upon receiving terminating signals (``SIGINT``, ``SIGTERM``, ``SIGHUP``, ``SIGQUIT``), all generated files MUST be deleted unless ``-k`` (``--keep-files``) is specified.
* When ``--suppress-matched`` is specified, lines matching split patterns MUST NOT be included in any output file.
* *Fulfills Technical Reference*: ``[TECH-CSPLIT-003]``

4. Functional Requirements: ``tail``
====================================

[FUNC-TAIL-001] Line & Byte Window Extraction
---------------------------------------------
* The utility MUST read each specified file (or standard input if none or ``-`` is specified) and output the trailing portion.
* By default, the last 10 lines of each file MUST be written to standard output.
* **[FUNC-TAIL-001a] Line Count (``-n NUM``, ``--lines=NUM``)**:
  - If ``NUM`` is preceded by ``+`` (``+N``), output lines starting from line ``N`` (1-indexed) to EOF.
  - Otherwise, output the last ``NUM`` lines.
* **[FUNC-TAIL-001b] Byte Count (``-c NUM``, ``--bytes=NUM``)**:
  - If ``NUM`` is preceded by ``+`` (``+N``), output bytes starting from byte ``N`` (1-indexed) to EOF.
  - Otherwise, output the last ``NUM`` bytes. Multiplier suffixes (``b``, ``K``, ``M``, ``G``, etc.) MUST be supported.
* **[FUNC-TAIL-001c] Zero-Terminated (``-z``, ``--zero-terminated``)**: Lines MUST be delimited by ASCII NUL (``\0``) instead of newline.
* *Fulfills Technical Reference*: ``[TECH-TAIL-001]``

[FUNC-TAIL-002] Multi-File Headers
----------------------------------
* When multiple files are given, each file's output MUST be preceded by a header banner: ``==> FILE <==\n`` (separated from previous output by a blank line).
* When ``-q``, ``-s``, ``--quiet``, or ``--silent`` is specified, header banners MUST be omitted.
* When ``-v`` or ``--verbose`` is specified, header banners MUST always be emitted, even for a single file.
* *Fulfills Technical Reference*: ``[TECH-TAIL-002]``

[FUNC-TAIL-003] Live Follow Mode
--------------------------------
* When ``-f`` or ``--follow[={descriptor|name}]`` is specified, the utility MUST not exit at EOF, but continue reading and printing appended data.
* ``--follow=descriptor`` (default): track the open file descriptor across renames/unlinks.
* ``--follow=name``: track the file by path name, reopening if the file is replaced or rotated.
* ``-F``: shorthand equivalent to ``--follow=name --retry``.
* ``--retry``: keep attempting to open the target file if it does not exist or becomes temporarily inaccessible.
* ``-s N`` (``--sleep-interval=N``): sleep ``N`` seconds (supports fractional floating point) between iterations.
* ``--pid=PID``: monitor process ID ``PID``. The process is considered alive if ``kill(pid, 0) == 0`` or ``errno == EPERM``. The utility MUST terminate only when ``kill(pid, 0)`` returns -1 with ``errno == ESRCH``.
* *Fulfills Technical Reference*: ``[TECH-TAIL-003]``

5. Functional Requirements: ``tr``
==================================

[FUNC-TR-001] Character Set Specifications & Operand Validation
---------------------------------------------------------------
* The utility operates exclusively on standard input and writes to standard output. File path operands are strictly rejected with exit 1.
* Operands MUST conform to the exact validation rules:
  - 0 operands: exit 1 with ``tr: missing operand``.
  - Translation mode (no ``-d``): exactly 2 operands; 1 operand emits ``tr: missing operand after '...'``.
  - Deletion mode (``-d`` without ``-s``): exactly 1 operand; 2 operands emits ``tr: extra operand '...' Only one string may be given when deleting without squeezing repeats.``.
  - Delete & squeeze (``-d -s``): exactly 2 operands.
  - Squeeze mode (``-s`` without ``-d``): 1 or 2 operands. With 2 operands, it translates ``SET1`` to ``SET2`` AND squeezes ``SET2``.
* The utility MUST interpret:
  - Literal characters and ranges: ``a-z``, ``0-9``. Descending ranges (e.g. ``z-a``) are rejected as invalid.
  - Octal escapes: ``\NNN`` (1 to 3 octal digits).
  - Standard escapes: ``\a``, ``\b``, ``\f``, ``\n``, ``\r``, ``\t``, ``\v``, ``\\``.
  - Character classes: ``[:alnum:]``, ``[:alpha:]``, ``[:blank:]``, ``[:cntrl:]``, ``[:digit:]``, ``[:graph:]``, ``[:lower:]``, ``[:print:]``, ``[:punct:]``, ``[:space:]``, ``[:upper:]``, ``[:xdigit:]``.
  - Equivalence classes: ``[=c=]``.
  - Repeats in ``SET2``: ``[c*N]`` (repeat ``c`` ``N`` times; prefix ``0`` denotes octal count) and ``[c*]`` (repeat ``c`` to pad ``SET2`` to length of ``SET1``).
* *Fulfills Technical Reference*: ``[TECH-TR-001]``

[FUNC-TR-002] Translation, Deletion & Squeezing Modes
-----------------------------------------------------
* **[FUNC-TR-002a] Translation (Default)**: Each character in ``SET1`` read from standard input MUST be replaced by the corresponding character in ``SET2``. If ``SET2`` is shorter than ``SET1``, the last character of ``SET2`` is repeated to match length.
* **[FUNC-TR-002b] Deletion (``-d``, ``--delete``)**: All characters present in ``SET1`` MUST be removed from standard input.
* **[FUNC-TR-002c] Squeezing (``-s``, ``--squeeze-repeats``)**: Sequences of repeated characters matching the last specified set MUST be collapsed into a single character.
* **[FUNC-TR-002d] Delete & Squeeze (``-d -s``)**: Characters in ``SET1`` MUST be deleted first, and remaining characters matching ``SET2`` MUST be squeezed.
* **[FUNC-TR-002e] Complement (``-c``, ``-C``, ``--complement``)**: The utility MUST use the byte-level complement of ``SET1`` (all 256 byte values not in ``SET1``, ordered ascendingly).
* **[FUNC-TR-002f] Truncate SET1 (``-t``, ``--truncate-set1``)**: Truncate ``SET1`` to the length of ``SET2`` before translating.
* *Fulfills Technical Reference*: ``[TECH-TR-002]``

6. Functional Requirements: ``fold``
====================================

[FUNC-FOLD-001] Column & Byte Wrapping
--------------------------------------
* The utility MUST break long lines from input files (or standard input) to fit within a specified maximum width (default 80 columns).
* When ``-w WIDTH`` (``--width=WIDTH``) or legacy ``-WIDTH`` is specified, ``WIDTH`` MUST be used as the limit.
* By default, column width MUST be calculated:
  - Printable characters increment column position by their character display width (supporting multi-byte UTF-8, zero-width combining characters, and double-width CJK).
  - Tab (``\t``) advances column position to the next multiple of 8 (columns 8, 16, 24, ...).
  - Backspace (``\b``) decrements column position by 1 (minimum 0).
  - Carriage return (``\r``) resets column position to 0.
* When ``-b`` (``--bytes``) is specified, every byte MUST count as 1 column, regardless of control characters or tabs.
* *Fulfills Technical Reference*: ``[TECH-FOLD-001]``

[FUNC-FOLD-002] Space-Aware Word Breaking
-----------------------------------------
* When ``-s`` (``--spaces``) is specified, the line break MUST occur immediately after the last blank character (ASCII space ``0x20`` or horizontal tab ``0x09``) that falls within the width limit.
* If a line contains no blanks before the width limit, the line MUST be broken at the width limit without losing content.
* *Fulfills Technical Reference*: ``[TECH-FOLD-002]``

7. Diagnostics & Exit Codes
===========================

[FUNC-TEXT-DIAG-001] Standard Diagnostic & Exit Conventions
-----------------------------------------------------------
* All utilities MUST exit 0 on success.
* All utilities MUST exit 1 on operational errors (e.g., missing operands, syntax errors, regex compilation errors, non-existent files, or write failure on ``/dev/full``).
* Write errors on standard output MUST propagate immediately, emit a diagnostic to standard error, and exit with status 1.
* *Fulfills Technical Reference*: ``[TECH-TEXT-DIAG-001]``
