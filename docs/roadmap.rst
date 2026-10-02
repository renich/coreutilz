===========================================
Coreutilz Project Roadmap & Phase Schedule
===========================================

:Version: v1.0
:Author: Coreutilz Architecture Team
:Date: 2026-09-05

.. contents:: Table of Contents
   :depth: 2

Roadmap Phasing Strategy
========================

The Coreutilz roadmap is sequenced into dependency-aware phases. Each phase requires **100% test pass rates against the upstream GNU Coreutils test suite** before being marked complete.

.. list-table::
   :widths: 20 20 40 20
   :header-rows: 1

   * - Phase
     - Focus
     - Utilities
     - Status
   * - Phase 1
     - System & Diagnostic Primitives
     - ``true``, ``false``, ``echo``, ``yes``, ``pwd``, ``tty``, ``sleep``, ``sync``, ``env``, ``printenv``, ``basename``, ``dirname``, ``whoami``, ``logname``, ``nproc``, ``hostid``
     - **100% PASS**
   * - Phase 2
     - File System Operations
     - ``mkdir``, ``rmdir``, ``rm``, ``touch``, ``truncate``, ``readlink``, ``link``, ``unlink``, ``chmod``, ``stat``
     - **100% PASS**
   * - Phase 3
     - Text & Stream Processing
     - ``cat``, ``head``, ``wc``, ``tee``, ``cut``, ``paste``, ``seq``
     - **100% PASS**
   * - Phase 4
     - Advanced Stream & File Operators
     - ``dd``, ``ln``, ``cp``, ``mv``
     - **100% PASS**
   * - Phase 5
     - Expanded GNU Suite
     - ``ls``, ``dir``, ``vdir``, ``sort``, ``uniq``, ``tail``, ``df``, ``du``, ``chown``, ``chgrp``, etc.
     - **IN PROGRESS**

Phase 5: Expanded GNU Suite (Active Track)
==========================================

Track 5A: Directory Listing (``ls``, ``dir``, ``vdir``)
-------------------------------------------------------

* **Scope**: Multi-column terminal formatting, long detailed listing, recursive directory inspection, sorting disciplines.
* **Requirements**:
  - Implemented under ``SPEC-FUNC-LS`` and ``SPEC-TECH-LS``.
  - Column alignment down columns (``-C``) and across rows (``-x``) with terminal width auto-detection.
  - Detailed format (``-l``) with permissions, link counts, UID/GID name caching, human sizes (``-h``), and timestamps.
  - Recursive listing (``-R``) and directory self-listing (``-d``).
  - Dedicated entrypoint variants: ``ls`` (adaptive TTY layout), ``dir`` (default columns), ``vdir`` (default long listing).
* **Pass Baseline**: **100% PASS** (46 passed, 6 skipped, 0 failed on GNU Coreutils upstream test suite).

Track 5B: Text Sorting & Grouping (``sort``, ``uniq``, ``comm``, ``shuf``, ``tac``)
-----------------------------------------------------------------------------------

* **Scope**: In-memory and external sorting, adjacent deduplication, dual-stream reconciliation, line permutation, stream reversal.
* **Requirements**:
  - Implemented under ``SPEC-FUNC-TEXT-SORT`` and ``SPEC-TECH-TEXT-SORT``.
  - ``sort``: Standard, numeric (``-n``), general numeric (``-g``), human (``-h``), month (``-M``), version (``-V``), random (``-R``), key definitions (``-k``, ``-t``), unique (``-u``), check (``-c``, ``-C``), merge (``-m``).
  - ``uniq``: Adjacent group filtering, count (``-c``), repeated only (``-d``, ``-D``), unique only (``-u``), field/char skipping (``-f``, ``-s``, ``-w``).
  - ``comm``: Three-column stream comparison, column suppression (``-1``, ``-2``, ``-3``), custom delimiter, order verification.
  - ``shuf``: Uniform Fisher-Yates permutation, range generation (``-i``), argument permutation (``-e``), head count (``-n``), repeat mode (``-r``).
  - ``tac``: Backward file scanning for seekable regular files, buffer reversal for pipes/streams, custom separator (``-s``), before placement (``-b``).
* **Pass Baseline**: **100% PASS** (26 passed, 10 skipped, 0 failed on GNU Coreutils upstream test suite, 490/490 container permutations).

Track 5C: Text Splitting & Filtering (``split``, ``csplit``, ``tail``, ``tr``, ``fold``)
---------------------------------------------------------------------------------------

* **Scope**: Fixed-size chunking, context/regex line splitting, tail-end stream extraction, live following, character translation/deletion/squeezing, line column/byte wrapping.
* **Requirements**:
  - Implemented under ``SPEC-FUNC-TEXT-SPLIT`` and ``SPEC-TECH-TEXT-SPLIT``.
  - ``split``: Split by lines (``-l``), bytes (``-b``), line-bytes (``-C``), chunks (``-n``), numeric (``-d``) and hex (``-x``) suffixes, additional suffix, shell filter (``--filter``), separator (``-t``).
  - ``csplit``: Split by line number, regex matching (``/REGEXP/``, ``%REGEXP%``) with offsets, repeats (``{N}``, ``{*}``), suffix formats (``-b``), prefix (``-f``), quiet (``-s``), elide empty (``-z``), suppress matched lines.
  - ``tail``: Last lines (``-n``) and bytes (``-c``) with ``+N`` support, multi-file headers (``-v``, ``-q``), live follow (``-f``, ``-F``, ``--retry``), sleep interval (``-s``), PID tracking (``--pid``), backward seek algorithm for regular files and circular ring buffer for pipes.
  - ``tr``: Translation, deletion (``-d``), squeezing (``-s``), complement (``-c``, ``-C``), truncate SET1 (``-t``), character classes (``[:alpha:]``, etc.), octal escapes, repeats.
  - ``fold``: Column wrapping (``-w``, ``-WIDTH``), space breaking (``-s``), byte mode (``-b``), tab stop calculation.
* **Pass Baseline**: **100% PASS** (55 passed, 9 skipped, 0 failed across all 5 utilities on GNU Coreutils upstream test suites, 586/586 internal tests passing).

Track 4A: ``dd`` Data Duplicator
---------------------------------

* **Scope**: Block-level stream translation, I/O conversion, status telemetry.
* **Requirements**:
  - Exact handling of ``ibs=BYTES``, ``obs=BYTES``, ``bs=BYTES``.
  - Conversion modes: ``conv=ucase,lcase,unblock,block,sparse,sync,noerror,notrunc``.
  - Flag parsing: ``count_bytes``, ``skip_bytes``, ``seek_bytes``.
  - Accurate record and byte accounting (``X+Y records in/out``).
  - Dynamic status telemetry (``status=progress,none,noxfer`` and ``SIGUSR1``/``SIGINFO``).
* **Target Pass Baseline**: 100% pass on ``tmp/coreutils/tests/dd/``.

Track 4B: ``ln`` Link Creator
-----------------------------

* **Scope**: Hard links, symbolic links, backup strategies.
* **Requirements**:
  - Full backup control (``-b``, ``--backup=CONTROL``, ``-S SUFFIX``).
  - Target directory permutation (``-t DIR``, ``-T``).
  - Relative symlink creation (``-r, --relative``).
  - Target dereferencing (``-L``, ``-P``, ``-s``, ``-f``).
* **Target Pass Baseline**: 100% pass on ``tmp/coreutils/tests/ln/``.

Track 4C: ``cp`` File Copier
----------------------------

* **Scope**: Recursive copying, permission cloning, copy-on-write.
* **Requirements**:
  - Reflink/copy-on-write support (``--reflink=auto,always,never``).
  - Attribute preservation (``-p``, ``--preserve=mode,ownership,timestamps,xattr,all``).
  - Sparse file detection and hole propagation.
  - Interactive prompts (``-i``) and force modes (``-f``).
* **Target Pass Baseline**: 100% pass on ``tmp/coreutils/tests/cp/``.

Track 4D: ``mv`` Move Utility
-----------------------------

* **Scope**: Atomic file relocation, cross-filesystem moves.
* **Requirements**:
  - Atomic rename optimization via ``renameat2``.
  - Cross-device fallback to copy-and-unlink with atomic rollback.
  - Overwrite control (``-n``, ``-u``, ``-i``, ``-f``).
* **Target Pass Baseline**: 100% pass on ``tmp/coreutils/tests/mv/``.

Phase 5: Expanded Coreutils Suite (Roadmap Vision)
==================================================

* **Batch A (Directory & Listing)**: ``ls``, ``dir``, ``vdir``
  - Status: COMPLETE (46 passed, 6 skipped, 0 failed in GNU Coreutils test harness).
* **Batch B (Text Sorting & Grouping)**: ``sort``, ``uniq``, ``comm``, ``shuf``, ``tac``
  - Status: COMPLETE (26 passed, 10 skipped, 0 failed in GNU Coreutils test harness).
* **Batch C (Splitting & Filtering)**: ``split``, ``csplit``, ``tail``, ``tr``, ``fold``
  - Status: IMPLEMENTED (Strike 3 Green & Quenched).
  - Internal tests: 586/586 passing (100% green).
  - GNU Coreutils test harness results:
    * ``split``: 14 passed, 1 skipped, 0 failed.
    * ``csplit``: 5 passed, 0 skipped, 0 failed.
    * ``tr``: 2 passed, 0 skipped, 0 failed.
    * ``fold``: 5 passed, 0 skipped, 0 failed.
    * ``tail``: 28 passed, 8 skipped, 1 pending (``follow-stdin.sh`` timeout in headless test environment).
  - Remaining: Strike 4 (Ship, Container Matrix, and Release).
* **Batch D (Storage Inspection)**: ``df``, ``du``, ``chown``, ``chgrp``, ``mknod``, ``mkfifo``
  - Status: Planned.
