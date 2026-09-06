=========
Changelog
=========

All notable changes to this project will be documented in this file.

The format is based on `Keep a Changelog <https://keepachangelog.com/en/1.1.0/>`_,
and this project adheres to `Semantic Versioning <https://semver.org/spec/v2.0.0.html>`_.

[Unreleased]
============

* Initial planning and architecture for Track 4A advanced ``dd`` block conversions (``conv=ucase,lcase,unblock,block,sparse``) and byte multipliers (``ibs``, ``obs``, ``cflag``).

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
