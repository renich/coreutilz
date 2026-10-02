=========================================================
Functional Specification: Advanced Shell, Relational & Math
=========================================================

:Domain: Shell Scripting, Relational Primitives & Math
:Target Utilities: ``test`` / ``[``, ``expr``, ``factor``, ``printf``, ``join``, ``tsort``, ``shred``, ``mktemp``, ``realpath``, ``pathchk``, ``install``, ``dircolors``
:Specification ID: ``SPEC-FUNC-SHELL-REL-MATH``

.. contents:: Table of Contents
   :depth: 2
   :backlinks: none

1. Overview
===========

Batch 5I implements shell evaluation, relational joining, topological graph ordering, arbitrary math factoring, path and temporary resource manipulation, secure disk erasure, and file installation primitives required for POSIX.1-2024 and GNU Coreutils compliance.

2. Functional Requirements: ``pathchk``
======================================

[FUNC-PATHCHK-001] File Name Validity & Portability
---------------------------------------------------
* Verify whether each argument is a valid and portable file path.
* **Flags**:
  - ``-p``: Check for POSIX portability (max file length 14, max path length 256, portable filename characters: alphanumeric, ``.``, ``_``, ``-``).
  - ``-P``: Reject empty names and names with leading ``-``.
  - ``--portability``: Equivalent to ``-p -P``.
* **Exit Status**:
  - Exit 0 if all file names are valid.
  - Exit 1 if any path fails checks, with diagnostic to stderr.

3. Functional Requirements: ``realpath``
=======================================

[FUNC-REALPATH-001] Absolute Canonical Path Resolution
------------------------------------------------------
* Resolve and print canonicalized absolute paths for one or more operands.
* **Flags**:
  - ``-e, --canonicalize-existing``: All components must exist.
  - ``-m, --canonicalize-missing``: Path components do not need to exist.
  - ``-s, --strip, --no-symlinks``: Only resolve ``.`` and ``..`` components, do not follow symlinks.
  - ``-z, --zero``: Delimit outputs with NUL byte.
  - ``-q, --quiet``: Suppress error diagnostics.
  - ``--relative-to=DIR``: Print resolved path relative to ``DIR``.
  - ``--relative-base=DIR``: Print relative path if inside ``DIR``, otherwise absolute.
* **Exit Status**:
  - Exit 0 on success.
  - Exit 1 if any file cannot be resolved.

4. Functional Requirements: ``mktemp``
=====================================

[FUNC-MKTEMP-001] Temporary File & Directory Creation
-----------------------------------------------------
* Safely create unique temporary files or directories.
* **Flags**:
  - ``-d, --directory``: Create directory instead of regular file.
  - ``-u, --dry-run``: Do not create any file/directory; print candidate name only.
  - ``-q, --quiet``: Suppress diagnostics on failure.
  - ``-p DIR, --tmpdir[=DIR]``: Use ``DIR`` (or ``$TMPDIR`` or ``/tmp``) as base directory.
  - ``--suffix=SUFF``: Append ``SUFF`` after the random pattern.
* **Template Generation**:
  - Default template: ``tmp.XXXXXXXXXX``.
  - Trailing consecutive ``X`` characters are replaced with cryptographically random alphanumeric characters.

5. Functional Requirements: ``tsort``
====================================

[FUNC-TSORT-001] Topological Graph Sorting
-----------------------------------------
* Perform topological sort on directed acyclic graph given as pairs of tokens.
* Input: Space/newline-separated pairs ``A B`` indicating ``A`` precedes ``B``. Single pair ``A A`` declares vertex existence.
* Loop detection: If a cycle is detected, emit diagnostic ``tsort: input contains a loop:`` to stderr, print loop elements, and exit 1 after processing.

6. Functional Requirements: ``factor``
=====================================

[FUNC-FACTOR-001] Prime Factorization
------------------------------------
* Compute and print prime factors for numbers given as arguments or on standard input.
* Output format: ``<number>: <prime1> <prime2> ...\n``.
* Support positive integers up to unsigned 64-bit and 128-bit integers.
* On non-numeric argument: Report diagnostic to stderr and exit 1.

7. Functional Requirements: ``dircolors``
========================================

[FUNC-DIRCOLORS-001] LS_COLORS Configuration
--------------------------------------------
* Generate shell setup code for ``LS_COLORS`` environment variable.
* **Flags**:
  - ``-b, --sh, --bourne-shell``: Output Bourne shell commands (``LS_COLORS='...'; export LS_COLORS;``).
  - ``-c, --csh, --c-shell``: Output C shell commands (``setenv LS_COLORS '...';``).
  - ``-p, --print-database``: Print built-in default color database.

8. Functional Requirements: ``test`` / ``[``
============================================

[FUNC-TEST-001] POSIX Expression Evaluation
-------------------------------------------
* Evaluate expression and exit 0 (true) or 1 (false).
* Handle POSIX 0, 1, 2, 3, 4 operand rules deterministically.
* Unary file tests: ``-e``, ``-f``, ``-d``, ``-r``, ``-w``, ``-x``, ``-s``, ``-L``, ``-h``, ``-b``, ``-c``, ``-p``, ``-S``, ``-u``, ``-g``, ``-k``, ``-t``.
* Unary string tests: ``-z`` (empty), ``-n`` (non-empty).
* Binary tests: ``=``, ``!=``, ``-eq``, ``-ne``, ``-lt``, ``-le``, ``-gt``, ``-ge``, ``-nt``, ``-ot``, ``-ef``.
* Logical: ``!`` (not), ``-a`` (and), ``-o`` (or), ``(`` ``)`` grouping.
* When invoked as ``[``, require final argument to be ``]``, exiting 2 on error.

9. Functional Requirements: ``expr``
===================================

[FUNC-EXPR-001] Expression Evaluator
------------------------------------
* Evaluate expressions: arithmetic (``+``, ``-``, ``*``, ``/``, ``%``), comparisons (``=``, ``!=``, ``<``, ``<=``, ``>``, ``>=``), boolean (``|``, ``&``), regex matching (``:``, ``match``), string slicing (``substr``, ``index``, ``length``).
* Exit 0 if result is non-null and non-zero; exit 1 if result is null or 0; exit 2 on syntax error; exit 3 on arithmetic error.

10. Functional Requirements: ``printf``
======================================

[FUNC-PRINTF-001] Formatted Printing
------------------------------------
* Format arguments according to format string.
* Support specifiers: ``%s``, ``%q``, ``%d``, ``%i``, ``%o``, ``%u``, ``%x``, ``%X``, ``%c``, ``%b``, ``%%``.
* Escape sequences: ``\n``, ``\r``, ``\t``, ``\\``, ``\0NNN``, ``\xHH``, ``\c``.
* Re-cycle format string when extra operands remain.

11. Functional Requirements: ``join``
====================================

[FUNC-JOIN-001] Relational File Join
------------------------------------
* Join lines of two sorted files on a common field.
* Options: ``-1 FIELD``, ``-2 FIELD``, ``-j FIELD``, ``-a FILENUM``, ``-v FILENUM``, ``-e EMPTY``, ``-o FORMAT``, ``-t CHAR``, ``-i``, ``-z``.

12. Functional Requirements: ``shred``
=====================================

[FUNC-SHRED-001] Secure File Erasure
------------------------------------
* Overwrite file contents repeatedly with pseudorandom patterns, zeros, and optionally unlink.
* Options: ``-n, --iterations=N``, ``-u, --remove``, ``-z, --zero``, ``-v, --verbose``, ``-f, --force``, ``-s, --size=N``, ``-x, --exact``.

13. Functional Requirements: ``install``
=======================================

[FUNC-INSTALL-001] File Installation
------------------------------------
* Copy files to destination, setting permissions, ownership, and creating directory trees.
* Options: ``-d, --directory``, ``-D``, ``-m, --mode=MODE``, ``-o, --owner=OWNER``, ``-g, --group=GROUP``, ``-s, --strip``, ``-t, --target-directory=DIR``, ``-v, --verbose``, ``-p, --preserve-timestamps``, ``-C, --compare``.
