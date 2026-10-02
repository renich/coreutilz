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

* Added Phase 5 Batch J system inspection and process control utilities: ``sum``, ``kill``, and ``uptime`` in Zig 0.16.0 achieving 100% behavioral parity across upstream GNU Coreutils test harness (3 passed, 0 skipped, 0 failed), internal test suites (441/441 steps passing with 0 leaks), 1100/1100 deterministic container permutations, and static analysis linting gates.
* Complete ``sum`` checksum and block counting utility supporting BSD 16-bit 1K-block algorithm (``-r``, default) and System V 16-bit 512-byte block algorithm (``-s``, ``--sysv``) across files and standard input streams.
* Complete ``kill`` process signaling and signal inspection utility supporting process group targets, numeric and named signal specifications (``-s``, ``-n``, ``-SIGNAL``), case-insensitive uppercase-validated options, shell status translation (``128 + sig``, ``256 + sig``), signal table generation (``-t``, ``-L``), and signal listing (``-l``).
* Complete ``uptime`` system activity reporter displaying formatted current time, days/hours/minutes elapsed uptime, active user session count via POSIX/glibc ``utmpx`` database, boot timestamp reporting (``-s``, ``--since``), and 1, 5, and 15-minute system load averages.
* Added Phase 5 Batch I advanced shell, relational, and math utilities: ``test`` / ``[``, ``expr``, ``factor``, ``printf``, ``join``, ``tsort``, ``shred``, ``mktemp``, ``realpath``, ``pathchk``, ``install``, and ``dircolors`` in Zig 0.16.0 achieving 100% behavioral parity across upstream GNU Coreutils test harness (34 passed, 2 skipped, 0 failed), internal test suites (429/429 steps passing with 0 leaks), 1080/1080 deterministic container permutations, and static analysis linting gates.

* Complete ``test`` and ``[`` expression evaluation utilities supporting POSIX 1-to-4 argument grammars, unary file and string tests, binary comparisons, algebraic comparisons, and exit code 2 write error parity on ``/dev/full``.
* Complete ``expr`` arbitrary-precision expression evaluator supporting arithmetic, comparison, logical, substring, and pattern operations with exit code 3 on write errors.
* Complete ``factor`` prime factorizer with Pollard's rho, trial division, Miller-Rabin primality testing, atomic line buffer output, and multi-process pipeline safety.
* Complete ``printf`` formatted output utility with format specifier validation, POSIX escape conversions, octal/hex conversions, shell escaping (``%q``), and variable argument recycling.
* Complete ``join`` relational database joiner supporting arbitrary field delimiters, custom join fields, unpairable line emission (``-a``, ``-v``), empty field fillers (``-e``), and zero-terminated mode (``-z``).
* Complete ``tsort`` topological sorter resolving directed acyclic graphs and reporting cycles to stderr while emitting legal orderings.
* Complete ``shred`` secure file wiper supporting multi-pass pseudo-random overwriting, pattern cycling, exact size truncation (``-x``), zeroing passes (``-z``), and atomic unlink removal (``-u``).
* Complete ``mktemp`` secure temporary file/directory provisioning with template validation, prefix/suffix handling, and atomic open creation.
* Complete ``realpath`` path canonicalization utility supporting symlink resolution, missing path handling (``-m``, ``-e``), logical canonicalization (``-s``), relative path resolution (``--relative-to``, ``--relative-base``), and zero termination (``-z``).
* Complete ``pathchk`` path validity and portability checker validating filename length, path length, and POSIX portable character set adherence (``-p``, ``-P``).
* Complete ``install`` file installation utility supporting permission/mode setting (``-m``), owner/group assignment (``-o``, ``-g``), directory creation (``-d``), strip execution (``-s``), backup versions (``-b``), and SELinux context preservation (``-Z``).
* Complete ``dircolors`` LS_COLORS setup generator parsing internal database and external configuration files, supporting Bourne and C shell syntax, and terminal matching.
* Added Phase 5 Batch H identity, security, and environment utilities: ``id``, ``groups``, ``who``, ``users``, ``pinky``, ``uname``, ``arch``, ``chcon``, and ``runcon`` in Zig 0.16.0 achieving 100% behavioral parity across upstream GNU Coreutils test harness (10 passed, 5 skipped, 0 failed), internal test suites (377/377 steps passing with 0 leaks), 950/950 deterministic container permutations, and static analysis linting gates.
* Complete ``id`` utility with real/effective UID/GID resolution, multi-user operands, option mutual exclusion (-u, -g, -G, -Z), name lookup (-n), real identity (-r), zero-delimited entries (-z), double-NUL record delimiters for multi-user group lists, POSIXLY_CORRECT compliance, and kernel security context retrieval via ``/proc/self/attr/current``.
* Complete ``groups`` utility reporting primary and supplementary group names/IDs for the calling process and arbitrary specified users with colon-separated record formatting and ``--`` option terminator handling.
* Complete ``who`` session inspection utility reading POSIX/glibc ``utmpx`` records with user counting (``-q``), system boot time (``-b``), short/default listing, line and host parsing, and time formatting.
* Complete ``users`` utility extracting distinct active login sessions sorted lexicographically with custom input file support.
* Complete ``pinky`` lightweight finger protocol utility formatting short and long user session records, plan and project file inspection (``~/.plan``, ``~/.project``), idle time calculation, and header/field suppression options.
* Complete ``uname`` system identification utility querying kernel utsname metadata with field selection flags (``-s``, ``-n``, ``-r``, ``-v``, ``-m``, ``-p``, ``-i``, ``-o``, ``-a``) and unrecognized option gating.
* Complete ``arch`` hardware architecture reporter emitting kernel machine architecture string.
* Complete ``chcon`` security context changer supporting full context strings, component overrides (``-u``, ``-r``, ``-t``, ``-l``), reference context copying (``--reference``), recursive filesystem traversal (``-R``), symlink traversal flags (``-H``, ``-L``, ``-P``), and root preservation security guard (``--preserve-root``).
* Complete ``runcon`` security context runner supporting full context execution, transition context computation (``-c``), component overrides (``-u``, ``-r``, ``-t``, ``-l``), command execution via ``execve``, and child exit status propagation.
* Added Phase 5 Batch G execution, process, and system state utilities: ``timeout``, ``nice``, ``nohup``, ``stdbuf``, ``stty``, ``date``, and ``chroot`` in Zig 0.16.0 achieving 100% behavioral parity across upstream GNU Coreutils test harness (16 passed, 12 skipped, 0 failed), internal test suites (341/341 steps passing with 0 leaks), 860/860 deterministic container permutations, and static analysis linting gates.
* Complete ``timeout`` execution guard supporting duration parsing with fractional and scientific notation, suffix multipliers (s/m/h/d), signal delivery (``-s``), kill-after escalations (``-k``), foreground process group control (``--foreground``), and preserve status flag (``--preserve-status``).
* Complete ``nice`` priority scheduler supporting niceness adjustments (``-n``), process execution, and error code conformity (125/126/127).
* Complete ``nohup`` immune execution utility with atomic ``nohup.out`` creation with restricted permissions (0600), background redirection fallback, and diagnostic warnings on stderr redirection.
* Complete ``stdbuf`` stream buffer modifier with ``libstdbuf.so`` dynamic injection via ``LD_PRELOAD``, supporting input/output/error stream buffering adjustment (unbuffered, line-buffered, block-buffered with memory size prefixes).
* Complete ``stty`` terminal line discipline interface implementing termios manipulation, speed configuration, character setting, special modes, and readable status reporting.
* Complete ``date`` timestamp formatter and parser with full format string expansion, RFC 2822/RFC 3339/ISO 8601 formatting, custom nanosecond subsecond substitution (``%N``, ``%-N``), timezone offsets, relative interval arithmetic (years/months/days), weekday parsing, military timezones, and ``--resolution``.
* Complete ``chroot`` root directory changer with optional user/group credential switching and primary group auto-resolution.
* Added Phase 5 Batch F text formatting and padding utilities: ``nl``, ``fmt``, ``pr``, ``expand``, ``unexpand``, ``od``, ``ptx``, and ``numfmt`` in Zig 0.16.0 passing 713/713 internal unit and integration tests with zero memory leaks, 790/790 deterministic container permutations, and static analysis linting gates.
* Complete ``nl`` line numbering utility supporting body/header/footer numbering styles (all, non-empty, none, and regex), section delimiters, line number increments, formats (left-justified, right-justified, leading zeros), width, and blank line coalescing.
* Complete ``fmt`` paragraph reflower supporting Knuth-Plass style optimal paragraph wrapping, crown margins, tagged paragraphs, split-only mode, uniform punctuation spacing, and prefix preservation.
* Complete ``pr`` text paginator and multi-column formatter supporting single and multi-column across/down layouts, custom page lengths, header/footer emission, margin indentation, double spacing, and column separators.
* Complete ``expand`` and ``unexpand`` tab conversion utilities supporting arbitrary custom tab stop specifications, auto-increments, initial-only blanks, and bounded streaming buffers.
* Complete ``od`` multi-radix byte dumper supporting octal, hexadecimal, decimal, char, and named byte interpretations, address radix selection, skip offsets, byte count limits, and duplicate line asterisk suppression.
* Complete ``ptx`` permuted index generator supporting dumb terminal layout, roff, and TeX macros, custom line width, gap sizing, and case-folding sorting.
* Complete ``numfmt`` number reformatting utility supporting SI and IEC binary units, custom scaling, rounding methods (up, down, from-zero, towards-zero, nearest), field selection, and padding.
* Added Phase 5 Batch E checksums and base encoding utilities: ``cksum``, ``b2sum``, ``md5sum``, ``sha1sum``, ``sha224sum``, ``sha256sum``, ``sha384sum``, ``sha512sum``, ``base64``, ``base32``, and ``basenc`` in Zig 0.16.0 achieving 100% behavioral parity with upstream GNU Coreutils test harness (23 passed, 3 skipped, 0 failed across all 11 utilities), deterministic container permutations (710 passed, 0 failed), and internal test suites (281 test runners passing with 0 leaks).
* Unified cryptographic and cyclic checksum engine (``cksum``) supporting POSIX 32-bit CRC, CRC32b, BSD/SysV sums, SM3, and cryptographically secure message digests via ``std.crypto.hash`` (MD5, SHA-1, SHA-2 family: SHA224, SHA256, SHA384, SHA512; SHA-3 family: SHA3-224, SHA3-256, SHA3-384, SHA3-512; and BLAKE2b with arbitrary bit lengths up to 512 bits). Support for tagged BSD/OpenSSL formatting (``--tag``), raw binary emission (``--raw``), Base64 digest strings (``--base64``), zero-delimited lines (``-z``), and filename escaping.
* Robust checksum verification engine (``-c``, ``--check``) supporting automatic dialect detection across tagged BSD/OpenSSL, GNU Coreutils text/binary, and BSD reversed formats; robust status filtering (``--quiet``, ``--status``), warning diagnostics (``--warn``), strict exit gating (``--strict``), and missing file tolerance (``--ignore-missing``) with standard input designation (``'standard input'``).
* Dedicated standalone digest utilities (``b2sum``, ``md5sum``, ``sha1sum``, ``sha224sum``, ``sha256sum``, ``sha384sum``, ``sha512sum``) wrapping the unified engine with algorithm defaults and text/binary mode handling.
* Unified multi-base stream encoding and decoding suite (``base64``, ``base32``, ``basenc``) implementing standard RFC 4648 (Base64, Base64url, Base32, Base32hex, Base16), Base2 (MSBF/LSBF), ZeroMQ 32/Z85, and Bitcoin Base58 with bounded-memory streaming, configurable line wrapping (``-w``, ``--wrap``), and garbage character discarding (``-i``, ``--ignore-garbage``).
* Added Phase 5 Batch D storage and device primitives: ``mkfifo``, ``mknod``, ``chown``, ``chgrp``, ``df``, and ``du`` in Zig 0.16.0 achieving 100% behavioral parity with upstream GNU Coreutils test harness (43 passed, 14 skipped, 0 failed across all 6 utilities) and internal test suites (624/624 tests passing).
* Complete ``mkfifo`` and ``mknod`` utilities with symbolic/octal permission parsing (``-m``, ``--mode``), FIFO special file creation, and block/character/unbuffered device node provisioning with major/minor number validation.
* Robust ``chown`` and ``chgrp`` utilities supporting user/group spec parsing with colon/dot delimiters (``user:group``, ``user.group``), recursive hierarchy traversal (``-R``), physical/logical/command-line dereferencing (``-P``, ``-L``, ``-H``), root preservation security guard (``--preserve-root``), and reference file spec copying (``--reference``).
* High-precision ``df`` utility reading filesystem mount tables via ``/proc/self/mountinfo`` and ``getmntent``, supporting POSIX portability format (``-P``), human-readable scaling (``-h``, ``-H``), inode reporting (``-i``), filesystem type filtering/exclusion (``-t``, ``-x``, ``-T``), grand total calculation (``--total``), and customized field formatting (``--output``).
* Full-featured ``du`` utility with relative directory descriptor traversal (``dirfd``, ``openat``, ``fstatat``, ``fdopendir``) supporting arbitrary directory depths exceeding ``PATH_MAX``, cycle/loop detection, GNU-compliant hardlink deduplication (``seen_hardlinks`` and ``hash_all``), apparent size calculation (``--apparent-size``, ``-b``), human-readable/SI scaling (``-h``, ``--si``), time tracking and ISO time-style formatting (``--time``, ``--time-style``), null-terminated output (``-0``), stream operand input (``--files0-from``), and threshold filtering (``-t``, ``--threshold``).
* Added Phase 5 Batch C text splitting and filtering utilities: ``split``, ``csplit``, ``tail``, ``tr``, and ``fold`` in Zig 0.16.0 achieving behavioral parity across internal test suites (586/586 tests passing) and upstream GNU Coreutils test harness.
* Full-featured ``split`` utility supporting line chunking (``-l``), byte chunking (``-b``), line-byte constraints (``-C``), and chunk count partition (``-n``). Dynamic alphabetical suffix auto-extension, fixed suffix length (``-a``), numeric (``-d``) and hexadecimal (``-x``) suffixes with custom start indices, additional suffixes (``--additional-suffix``), routing through child filter processes (``--filter``), and temporary file spooling for non-seekable streams under ``-n``.
* Complete ``csplit`` utility supporting context-based splitting using POSIX Basic Regular Expressions (``/REGEXP/``, ``%REGEXP%``), line offsets (``+N``, ``-N``), integer line numbers, match repetition limits (``{N}``, ``{*}``), output prefixing (``-f``), suffix digits formatting (``-n``), silent size suppression (``-q``), and cleanup rollback on errors/signals unless ``-k`` (``--keep-files``).
* High-performance ``tail`` utility featuring backward seek optimization for seekable files and bounded ring buffer for streaming inputs. Saturated integer unit parsing with unit multipliers (``K``, ``M``, ``G``, etc.), live filesystem following (``-f``, ``-F``), PID heartbeat tracking (``--pid``), safe file descriptor allocation (``fdSafer``) preventing low descriptor collisions, output pipe monitor (``iopoll``/``poll``) for prompt termination on closed stdout, and inotify warning gating.
* Complete ``tr`` streaming utility supporting character translation, complementation (``-c``, ``-C``), deletion (``-d``), and duplicate squeezing (``-s``). POSIX/GNU escape sequences (``\a``, ``\b``, ``\f``, ``\n``, ``\r``, ``\t``, ``\v``, octal ``\000``), character classes (``[:alpha:]``, ``[:digit:]``, ``[:alnum:]``, etc.), character ranges (``a-z``), repeat notation (``[c*n]``), and strict operand validation.
* Complete ``fold`` utility supporting column-constrained and byte-constrained line wrapping (``-w``, ``--width``). Spaces-only break mode (``-s``), raw byte mode (``-b``), standard 8-column tab stop expansion, backspace column decrement, carriage return column reset, and zero-terminated line processing (``-z``).
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
