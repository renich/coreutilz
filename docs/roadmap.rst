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
     - **IN PROGRESS**
   * - Phase 5
     - Expanded GNU Suite
     - ``ls``, ``sort``, ``uniq``, ``tail``, ``df``, ``du``, ``chown``, ``chgrp``, ``mknod``, ``mkfifo``, etc.
     - **PLANNED**

Phase 4: Advanced Stream & File Operators (Active Track)
========================================================

Track 4A: ``dd`` Data Duplicator
---------------------------------

* **Scope**: Block-level stream translation, I/O conversion, status telemetry.
* **Requirements**:
  - Exact handling of ``ibs=BYTES``, ``obs=BYTES``, ``bs=BYTES``.
  - Conversion modes: ``conv=ucase,lcase,unblock,block,sparse,sync,noerror,notrunc``.
  - Flag parsing: ``count_bytes``, ``skip_bytes``, ``seek_bytes``.
  - Accurate record and byte accounting (``X+Y records in / out``).
  - Dynamic status telemetry (``status=progress,none,noxfer`` and ``SIGUSR1`` / ``SIGINFO``).
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
  - Reflink / copy-on-write support (``--reflink=auto,always,never``).
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

* **Batch A (Directory & Listing)**: ``ls``, ``dir``, ``vdir``.
* **Batch B (Text Sorting & Grouping)**: ``sort``, ``uniq``, ``comm``, ``shuf``, ``tac``.
* **Batch C (Splitting & Filtering)**: ``split``, ``csplit``, ``tail``, ``tr``, ``fold``.
* **Batch D (Storage Inspection)**: ``df``, ``du``, ``chown``, ``chgrp``, ``mknod``, ``mkfifo``.
