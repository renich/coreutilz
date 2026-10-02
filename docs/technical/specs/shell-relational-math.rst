========================================================
Technical Specification: Advanced Shell, Relational & Math
========================================================

:Domain: Shell Scripting, Relational Primitives & Math
:Target Utilities: ``test`` / ``[``, ``expr``, ``factor``, ``printf``, ``join``, ``tsort``, ``shred``, ``mktemp``, ``realpath``, ``pathchk``, ``install``, ``dircolors``
:Specification ID: ``SPEC-TECH-SHELL-REL-MATH``

.. contents:: Table of Contents
   :depth: 2
   :backlinks: none

1. Architecture & Standards
===========================

All utilities are implemented in Zig 0.16.0 adhering to:
- Strict modularity: <= 300 lines per file, <= 40 lines per function.
- Explicit memory allocation using ``std.mem.Allocator``.
- Standardized buffered streaming I/O with flush error checking.
- Zero external dependencies beyond glibc / POSIX C ABI headers.

2. Module Decomposition
=======================

* ``src/commands/pathchk.zig``: POSIX portability validation, path length calculation, illegal byte checking.
* ``src/commands/realpath.zig``: Canonical path resolution using ``std.fs.path.resolve`` and ``c.realpath``.
* ``src/commands/mktemp.zig``: CSPRNG-driven temporary file creation with atomic ``O_CREAT | O_EXCL`` and ``c.mkdtemp``.
* ``src/commands/tsort.zig``: Adjacency list directed graph with cycle detection using Kahn's algorithm or DFS.
* ``src/commands/factor.zig``: Prime factorization with small prime sieving and Pollard's rho algorithm.
* ``src/commands/dircolors.zig``: Embedded default color database with configuration file parsing.
* ``src/commands/test.zig``: Standard POSIX n-ary grammar evaluator with binary symlink dispatch for ``[``.
* ``src/commands/expr.zig``: Shunting-yard expression parser with integer arithmetic and POSIX regex matching.
* ``src/commands/printf.zig``: Format parser supporting standard escape sequences and specifier loop recycling.
* ``src/commands/join.zig``: Line-by-line relational merger with field splitting and case-insensitive comparison.
* ``src/commands/shred.zig``: Pseudorandom pass generation using ChaCha20/OS entropy, sync flushing, and file unlinking.
* ``src/commands/install.zig``: Directory creation, atomic file copying, metadata application, and strip binary invoking.
