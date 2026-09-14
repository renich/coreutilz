=========
Changelog
=========

All notable changes to this project will be documented in this file.

The format is based on `Keep a Changelog <https://keepachangelog.com/en/1.1.0/>`_,
and this project adheres to `Semantic Versioning <https://semver.org/spec/v2.0.0.html>`_.

[Unreleased]
============

Added
-----

* Added Phase 5 Batch B text sorting and grouping utilities: ``sort``, ``uniq``, ``comm``, ``shuf``, and ``tac`` in Zig 0.16.0 achieving 100% behavioral parity with GNU Coreutils upstream test suites (26 passed, 10 skipped, 0 failed across all 5 utilities).
* Full-featured ``sort`` utility supporting Gnulib-grade numeric string comparisons (``-n``) via custom ``numcmp``, general numeric floating-point sorting (``-g``) supporting IEEE 80bit/128bit values with strict weak ordering for NaNs, human-readable numeric values (``-h``), multilingual month sorting (``-M``) with locale awareness via ``nl_langinfo``, natural version sort (``-V``), Wyhash seeded pseudorandom sort (``-R``), field and character range specifiers (``-k POS1,POS2``), obsolete syntax (``+POS1 -POS2``), locale decimal point and thousands separator recognition, checking mode (``-c``, ``-C``), external compress program integration (``--compress-program``), and batch merging (``-m``).
* Complete ``uniq`` utility supporting case folding (``-i``), field skipping (``-f``), char skipping (``-s``), unique (``-u``) and duplicate (``-d``, ``-D``) filtering with delimiters (``none``, ``prepend``, ``separate``), count prefixing (``-c``), zero-terminated mode (``-z``), and multibyte/collation parity.
* Complete ``comm`` utility supporting selective column suppression (``-1``, ``-2``, ``-3``), order verification (``--check-order``, ``--nocheck-order``), custom column output delimiters (``--output-delimiter``), and zero-terminated mode (``-z``).
* High-performance ``shuf`` utility with Fisher-Yates shuffle algorithm seeded by CSPRNG/Wyhash, reservoir sampling, head count limit (``-n``), repeat mode (``-r``), echo mode (``-e``), integer range mode (``-i LO-HI``), custom random sources (``--random-source``), and zero-terminated mode (``-z``).
* Complete ``tac`` utility supporting reverse file concatenations across seekable and non-seekable streams, custom separator regexes (``-r``), before-mode (``-b``), and binary zero-terminated streams.
* Added Phase 5 Batch A directory listing utilities: ``ls``, ``dir``, and ``vdir`` in Zig 0.16.0 achieving 100% behavioral parity with GNU Coreutils upstream test suite (46 passed, 6 skipped, 0 failed).
* Complete multi-column down-columns (``-C``), across-columns (``-x``), comma-separated (``-m``), one-per-line (``-1``), and detailed long listing (``-l``) formatting engines.
* Full GNU ``LS_COLORS`` parsing with support for normal, file, directory, symlink, orphaned, socket, pipe, block, char, setuid, setgid, sticky, other-writable, executable, and wildcard/exact file extensions.
* Automatic ANSI-C quoting styles (``literal``, ``shell``, ``shell-always``, ``shell-escape``, ``c``, ``escape``, ``clocale``, ``locale``) and non-graphic character hiding/escaping (``-q``, ``--hide-control-chars``).
* Advanced glob pattern filtering (``--ignore=PATTERN``, ``--hide=PATTERN``) via ``fnmatch`` with period semantics.
* Recursive directory traversal (``-R``) with cycle detection against directory loops (``LOOP_DETECT``).
* Dired Emacs integration (``-D``, ``--dired``) with byte offset marker subtrees and subdired tracking.
* Terminal OSC 8 hyperlink emission (``--hyperlink``) and time-style formats (``full-iso``, ``long-iso``, ``iso``, ``locale``, ``+FORMAT``).

[0.1.0] - 2026-09-05
====================

Added
-----

* Initial release of 38 core utilities rewritten in Zig 0.16.0:
  ``basename``, ``cat``, ``chmod``, ``cp``, ``cut``, ``dd``, ``dirname``, ``echo``, ``env``, ``false``, ``head``, ``hostid``, ``hostname``, ``link``, ``ln``, ``logname``, ``mkdir``, ``mv``, ``nproc``, ``paste``, ``printenv``, ``pwd``, ``readlink``, ``rm``, ``rmdir``, ``seq``, ``sleep``, ``stat``, ``sync``, ``tee``, ``touch``, ``true``, ``truncate``, ``tty``, ``unlink``, ``wc``, ``whoami``, and ``yes``.
* Multicall super-binary ``coreutilz`` supporting direct dispatch, symlink execution, and command listing via ``--help`` and ``--version``.
* Rootless Podman container support with ``Containerfile`` targeting Fedora 43.
* Deterministic container permutation testing suite (``scripts/test-container.bash``) validating standalone binaries, multicall dispatch, symlink dispatch, and functional parity across 404 deterministic checks.
* Direct upstream GNU Coreutils test harness (``scripts/test-upstream.bash``) validating binaries against the GNU Coreutils 9.7 test suite (25 suites passing at 100%).
* Static analysis and linting gate (``scripts/lint.bash``) integrated into ``zig build lint`` enforcing formatting, AST validation, architecture contract adherence, and ShellCheck.
* Authoritative governance and specification documentation:

  * `docs/code_of_honor.rst`: The Engineer's Code of Honor.
  * `docs/procedure.rst`: Crucible & Echelon Development Procedure.
  * `docs/spec.rst`: System Architecture & Implementation Specification.
  * `docs/roadmap.rst`: Phased Project Roadmap.
  * `AGENTS.md`: Antigravity multi-agent operational guide.

Changed
-------

* Hardened build system in `build.zig` supporting ReleaseFast builds with a multicall binary footprint of 5.7 MB.
* Standardized all repository Bash scripts to follow strict standards (``#!/usr/bin/bash``, ``set -euo pipefail``, ``IFS=$'\n\t'``, ShellCheck clean).

Fixed
-----

* Fixed ``wc`` compilation in ReleaseFast mode by declaring explicit ``extern "c" fn btowc`` to circumvent glibc header inline alias redirection (``__btowc_alias``).
* Fixed ``chmod`` ``-f`` option semantics to suppress diagnostic output while preserving exit status 1 on stat/permission errors to match POSIX/GNU specification.
* Fixed ``hostname`` ``-s``/``--short`` option to truncate output at the first period delimiter.
* Fixed ``coreutilz`` multicall binary handling of top-level ``--help`` and ``--version`` arguments.
* Fixed ``env`` empty environment handling (``-i``), variable unsetting (``-u``), and null-delimiter formatting (``-0``).
