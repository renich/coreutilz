===================================================
Functional Specification: Text Sorting & Grouping
===================================================

:Domain: Text & Stream Processing
:Target Utilities: ``sort``, ``uniq``, ``comm``, ``shuf``, ``tac``
:Specification ID: ``SPEC-FUNC-TEXT-SORT``

.. contents:: Table of Contents
   :depth: 2
   :backlinks: none

1. Overview
===========

The Text Sorting & Grouping suite provides deterministic ordering, adjacent duplicate deduplication, two-way sorted stream reconciliation, pseudo-random line permutation, and line-by-line stream reversal.

Each utility operates on standard input and/or specified file operands, streaming processed records to standard output or specified destination paths with byte-level fidelity matching GNU Coreutils.

2. Functional Requirements: ``sort``
====================================

[FUNC-SORT-001] Stream & Operand Ingestion
------------------------------------------
* The utility MUST read and concatenate input from all specified file operands in command-line argument order.
* If zero operands are passed, or if an operand is ``-``, the utility MUST read from standard input.
* If ``-o FILE`` (``--output=FILE``) is specified, the utility MUST write the sorted result to ``FILE`` instead of standard output. ``FILE`` MAY safely match one of the input operands.

[FUNC-SORT-002] Collation & Sorting Disciplines
-----------------------------------------------
* **[FUNC-SORT-002a] Standard Lexicographical Sort**: By default, lines MUST be sorted in ascending byte-value (ASCII) order.
* **[FUNC-SORT-002b] Reverse Sort (``-r``, ``--reverse``)**: The ordering direction MUST be reversed (descending).
* **[FUNC-SORT-002c] Numeric Sort (``-n``, ``--numeric-sort``)**: Strings MUST be sorted according to their leading numerical value, including leading whitespace, optional ``+``/``-`` sign, and decimal digits. Non-numeric lines or prefixes sort as zero.
* **[FUNC-SORT-002d] General Numeric Sort (``-g``, ``--general-numeric-sort``)**: Strings MUST be converted to double-precision floating-point numbers (handling scientific exponential notation and ``NaN``/``Infinity``).
* **[FUNC-SORT-002e] Human Numeric Sort (``-h``, ``--human-numeric-sort``)**: Strings MUST be sorted by size with standard binary/decimal multiplier suffixes (``K``, ``M``, ``G``, ``T``, ``P``, ``E``, ``Z``, ``Y``).
* **[FUNC-SORT-002f] Month Sort (``-M``, ``--month-sort``)**: Strings MUST be compared according to standard abbreviated 3-letter calendar month names (``JAN`` through ``DEC``), case-insensitively, with unknown values sorting before ``JAN``.
* **[FUNC-SORT-002g] Version Sort (``-V``, ``--version-sort``)**: Strings MUST be sorted using natural version number ordering, comparing digit sequences numerically and non-digit characters lexicographically.
* **[FUNC-SORT-002h] Random Sort (``-R``, ``--random-sort``)**: Lines MUST be shuffled based on a cryptographically secure or seeded hash of their contents, grouping identical lines together.

[FUNC-SORT-003] Key & Delimiter Processing
------------------------------------------
* **[FUNC-SORT-003a] Field Separator (``-t CHAR``, ``--field-separator=CHAR``)**: The utility MUST split lines into fields delimited by single character ``CHAR``. By default, fields are separated by the boundary between non-blank and blank characters.
* **[FUNC-SORT-003b] Key Specification (``-k POS1[,POS2]``, ``--key=POS1[,POS2]``)**: The sort comparison MUST restrict evaluation to the field interval starting at ``POS1`` (1-indexed ``F.C``) and ending at ``POS2``. Keys MAY specify ordering flags (e.g. ``n``, ``r``, ``b``, ``f``) that override global options for that key.
* **[FUNC-SORT-003c] Ignore Leading Blanks (``-b``, ``--ignore-leading-blanks``)**: Leading whitespace within each key field MUST be ignored during comparison.
* **[FUNC-SORT-003d] Case Folding (``-f``, ``--ignore-case``)**: Lowercase characters MUST be folded to uppercase during comparison.
* **[FUNC-SORT-003e] Zero-Terminated Lines (``-z``, ``--zero-terminated``)**: Input and output records MUST be delimited by ASCII NUL (``\0``) instead of newline.

[FUNC-SORT-004] Operational Modes
---------------------------------
* **[FUNC-SORT-004a] Unique Mode (``-u``, ``--unique``)**: The utility MUST output only the first line of any run of lines comparing equal.
* **[FUNC-SORT-004b] Check Mode (``-c``, ``--check``, ``-C``, ``--check=silent``)**: The utility MUST check whether the input stream is already sorted without producing sorted output. If unsorted, ``-c`` MUST emit a diagnostic specifying the out-of-order line number and filename and exit with status 1. ``-C`` MUST remain silent and exit with status 1.
* **[FUNC-SORT-004c] Merge Mode (``-m``, ``--merge``)**: The utility MUST merge pre-sorted files into a single sorted stream without performing a full internal sort.
* **[FUNC-SORT-004d] Stable Sort (``-s``, ``--stable``)**: The utility MUST preserve the original input order of lines that compare equal.

[FUNC-SORT-005] Diagnostics & Exit Codes
----------------------------------------
* The utility MUST exit 0 on successful completion.
* The utility MUST exit 1 when ``-c``/``-C`` detects an out-of-order line.
* The utility MUST exit 2 on syntax, permission, or file I/O errors.

3. Functional Requirements: ``uniq``
====================================

[FUNC-UNIQ-001] Adjacent Duplicate Line Filtering
-------------------------------------------------
* The utility MUST filter adjacent matching lines from the input stream.
* If zero operands are passed, or if the input operand is ``-``, the utility MUST read from standard input.
* If an output operand is specified as the second argument, the utility MUST write filtered output to that file path instead of standard output.
* If more than two operands are passed, the utility MUST emit an error and exit with status 1.

[FUNC-UNIQ-002] Output Selection Modes
--------------------------------------
* **Default Mode**: Output the first occurrence of each adjacent matching group.
* **[FUNC-UNIQ-002a] Prefix Count (``-c``, ``--count``)**: Precede each line by the count of adjacent occurrences formatted as ``%7d %s\n``.
* **[FUNC-UNIQ-002b] Repeated Only (``-d``, ``--repeated``)**: Print only duplicate lines, outputting exactly one instance per repeated group.
* **[FUNC-UNIQ-002c] All Repeated (``-D``, ``--all-repeated[=METHOD]``)**: Print all duplicate lines across groups, optionally separated by group delimiters.
* **[FUNC-UNIQ-002d] Unique Only (``-u``, ``--unique``)**: Print only non-repeated lines (lines occurring exactly once).

[FUNC-UNIQ-003] Field & Character Comparison Rules
--------------------------------------------------
* **[FUNC-UNIQ-003a] Skip Fields (``-f N``, ``--skip-fields=N``)**: Avoid comparing the first ``N`` fields. A field is a run of non-blank characters preceded by whitespace.
* **[FUNC-UNIQ-003b] Skip Characters (``-s N``, ``--skip-chars=N``)**: Avoid comparing the first ``N`` characters of the line (or remaining portion after field skipping).
* **[FUNC-UNIQ-003c] Check Characters (``-w N``, ``--check-chars=N``)**: Compare no more than ``N`` characters in lines.
* **[FUNC-UNIQ-003d] Case Insensitive (``-i``, ``--ignore-case``)**: Fold characters case-insensitively during comparison.
* **[FUNC-UNIQ-003e] Zero-Terminated (``-z``, ``--zero-terminated``)**: Delimit records by NUL instead of newline.

4. Functional Requirements: ``comm``
====================================

[FUNC-COMM-001] Three-Column Stream Comparison
----------------------------------------------
* The utility MUST read two sorted input files line by line and produce three tab-delimited columns:
  * Column 1: Lines unique to ``FILE1``.
  * Column 2: Lines unique to ``FILE2``.
  * Column 3: Lines common to both files.
* Either ``FILE1`` or ``FILE2`` (but not both) MAY be ``-`` to read from standard input.

[FUNC-COMM-002] Column Suppression Modes
----------------------------------------
* **[FUNC-COMM-002a] Suppress Column 1 (``-1``)**: Omit lines unique to ``FILE1``.
* **[FUNC-COMM-002b] Suppress Column 2 (``-2``)**: Omit lines unique to ``FILE2``.
* **[FUNC-COMM-002c] Suppress Column 3 (``-3``)**: Omit lines common to both files.
* Options MAY be combined (e.g. ``-12`` prints only lines common to both files without leading tabs).

[FUNC-COMM-003] Delimiter & Delimitation Control
------------------------------------------------
* **[FUNC-COMM-003a] Custom Output Delimiter (``--output-delimiter=STR``)**: Use ``STR`` as the column delimiter instead of the default tab (``\t``).
* **[FUNC-COMM-003b] Zero-Terminated (``-z``, ``--zero-terminated``)**: Delimit records with NUL instead of newline.

[FUNC-COMM-004] Input Order Verification
----------------------------------------
* **[FUNC-COMM-004a] Check Order (``--check-order``)**: Verify that both input files are sorted. If out-of-order lines occur, emit a diagnostic to stderr and exit with status 1.
* **[FUNC-COMM-004b] No Check Order (``--nocheck-order``)**: Do not verify sort order of input streams.

5. Functional Requirements: ``shuf``
====================================

[FUNC-SHUF-001] Random Line Permutation
---------------------------------------
* The utility MUST generate a random permutation of input lines and write the result to standard output or specified destination file.
* Randomization MUST follow uniform distribution across all possible permutations using the Fisher-Yates shuffle algorithm.

[FUNC-SHUF-002] Source Input Modes
----------------------------------
* **[FUNC-SHUF-002a] Standard Input & File Operand**: Read lines from standard input (if zero operands or ``-``) or named file operand.
* **[FUNC-SHUF-002b] Integer Range (``-i LO-HI``, ``--input-range=LO-HI``)**: Generate pseudo-random numbers in the inclusive integer range ``LO`` through ``HI``.
* **[FUNC-SHUF-002c] Command Line Arguments (``-e [ARG...]``, ``--echo``)**: Treat each specified positional argument as an individual line.

[FUNC-SHUF-003] Output Bounds & Repetition
------------------------------------------
* **[FUNC-SHUF-003a] Head Count (``-n COUNT``, ``--head-count=COUNT``)**: Output at most ``COUNT`` lines.
* **[FUNC-SHUF-003b] Repeat Mode (``-r``, ``--repeat``)**: Select lines with replacement, producing an infinite random stream unless bounded by ``-n COUNT``.
* **[FUNC-SHUF-003c] Output File (``-o FILE``, ``--output=FILE``)**: Write output to ``FILE`` instead of standard output.
* **[FUNC-SHUF-003d] Zero-Terminated (``-z``, ``--zero-terminated``)**: Delimit records by NUL instead of newline.

6. Functional Requirements: ``tac``
===================================

[FUNC-TAC-001] Stream Record Reversal
-------------------------------------
* The utility MUST write the records of each file operand in reverse order (last record first) to standard output.
* If zero operands are passed, or if an operand is ``-``, the utility MUST read from standard input.

[FUNC-TAC-002] Separator & Placement Disciplines
------------------------------------------------
* **[FUNC-TAC-002a] Default Separator**: By default, records are delimited by ASCII newline (``\n``).
* **[FUNC-TAC-002b] Custom Separator (``-s STR``, ``--separator=STR``)**: Use ``STR`` as the record separator instead of newline.
* **[FUNC-TAC-002c] Attached Before (``-b``, ``--before``)**: The separator is attached before the record rather than after it.
* **[FUNC-TAC-002d] Regex Separator (``-r``, ``--regex``)**: Interpret ``STR`` as a regular expression.

[FUNC-TAC-003] Storage Strategy & Seekability
---------------------------------------------
* For seekable regular files, the utility MUST scan backwards from the end of the file in buffered chunks without reading the entire file into memory upfront.
* For non-seekable streams (pipes, sockets, fifos, standard input), the utility MUST buffer the stream into memory or a temporary disk file to perform reversal.
