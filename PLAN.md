# Coreutilz: Porting GNU Coreutils Tests to Zig

## Goal

Port the shell tests from ``tmp/coreutils/tests/`` into Zig integration tests
under ``tests/``, then make all of them pass against the Zig implementations
in ``src/commands/``.

## How It Works

- Source tests live in ``tmp/coreutils/tests/<command>/*.sh``
- Each shell script uses the GNU coreutils test harness
  (``init.sh``, ``compare``, ``path_prepend_``, etc.)
- We re-express each shell test as a Zig test in
  ``tests/<command>_test.zig`` using the ``framework.zig`` helpers
- Tests spawn the built binary from ``zig-out/bin/<command>`` and assert
  on stdout, stderr, and exit code

## Current State (2026-09-05)

- **Zig version**: 0.16.0
- **Build**: passes (``zig build`` exits 0 for all 33 binaries + multicall ``coreutilz``)
- **Target Commands Completed**: 33/33 (359/359 tests passing, 100% pass rate)
- **Formatting**: passes (``zig fmt --check src/ tests/`` clean)

### 33 Ported Commands (100% Passing Tests):
1. ``true`` (5/5)
2. ``false`` (5/5)
3. ``basename`` (12/12)
4. ``dirname`` (11/11)
5. ``echo`` (22/22)
6. ``hostid`` (4/4)
7. ``hostname`` (6/6)
8. ``logname`` (4/4)
9. ``whoami`` (5/5)
10. ``tty`` (4/4)
11. ``nproc`` (12/12)
12. ``sleep`` (13/13)
13. ``sync`` (10/10)
14. ``env`` (8/8)
15. ``printenv`` (8/8)
16. ``yes`` (5/5)
17. ``link`` (6/6)
18. ``unlink`` (7/7)
19. ``pwd`` (8/8)
20. ``readlink`` (15/15)
21. ``mkdir`` (14/14)
22. ``rmdir`` (12/12)
23. ``cat`` (15/15)
24. ``stat`` (10/10)
25. ``chmod`` (15/15)
26. ``ln`` (13/13)
27. ``mv`` (11/11)
28. ``cp`` (12/12)
29. ``rm`` (12/12)
30. ``dd`` (22/22)
31. ``head`` (17/17)
32. ``wc`` (16/16)
33. ``tee`` (9/9)
- **shred.zig**: wrong output file size
- **basenc.zig**: base64url wrong output
- **pathchk.zig**: ``-P`` and invalid char detection broken
- **truncate_test.zig**: segfault/double-free
- **cksum.zig**: wrong checksum
- **ptx.zig**: ``-w`` and ``-r`` options broken
- **stdbuf.zig**: exits 125
- **chown_test.zig**: invalid user error message wrong
- **yes_test.zig**: minor memory leak

### Phase 2: Implement Missing Commands + Port Their Tests

Commands with upstream tests but **no** Zig implementation yet.
Implement the command first, then port its tests.

| Command  | Tests | Priority |
|----------|-------|----------|
| ls       | 51    | High     |
| sort     | 23    | High     |
| tail     | 36    | High     |
| head     | 3     | High     |
| wc       | 6     | High     |
| split    | 15    | Medium   |
| cut      | 2     | Medium   |
| paste    | 1     | Medium   |
| touch    | 15    | Medium   |
| du       | 29    | Medium   |
| df       | 14    | Medium   |
| truncate | 9     | Medium   |
| seq      | 6     | Medium   |
| tac      | 3     | Medium   |
| tee      | 2     | Medium   |
| uniq     | 2     | Medium   |
| od       | 7     | Low      |
| printf   | 6     | Low      |
| numfmt   | 1     | Low      |
| fold     | 4     | Low      |
| expand   | 1     | Low      |
| unexpand | 1     | Low      |
| factor   | 3     | Low      |
| shuf     | 2     | Low      |
| shred    | 4     | Low      |
| pr       | 1     | Low      |
| ptx      | 1     | Low      |
| join     | 1     | Low      |
| tr       | 1     | Low      |
| csplit   | 4     | Low      |
| fmt      | 4     | Low      |

### Phase 3: System / Privilege Commands

These require root or system features; implement with appropriate skip logic
when not running as root.

| Command | Tests |
|---------|-------|
| chown   | 4     |
| chgrp   | 7     |
| chcon   | 2     |
| chroot  | 2     |
| install | 9     |
| mknod   | 1     |
| runcon  | 2     |
| id      | 7     |
| groups  | 3     |

### Phase 4: Out-of-Scope / Skip List

These will be documented as explicitly skipped with rationale:

- ``stty`` (5) — requires a real TTY
- ``timeout`` (4) — requires signal infrastructure
- ``nice`` (2) — requires process priority API
- ``nohup`` (2) — daemon behavior
- ``stdbuf`` (4) — LD_PRELOAD mechanism, Linux-specific
- ``kill`` (misc) — signal sending
- ``selinux`` (misc) — SELinux-specific
- ``date`` (10) — complex locale/timezone, deferred
- ``help`` (2) — generic, covered per-command

### Phase 5: Quality Gate

- [ ] ``zig build`` passes with zero warnings
- [ ] ``zig build integration-test`` — all ported tests pass
- [ ] ``zig fmt src/ tests/`` — no diffs
- [ ] No memory leaks (``std.testing.allocator`` used in all tests)
- [ ] ``PLAN.md`` updated to reflect final status

## Implementation Rules

#. Each upstream ``*.sh`` test case → one Zig ``test`` block with a
   descriptive name matching the shell test intent
#. Use ``framework.TestContext`` for temp dirs; ``getBinaryPath`` for
   binary lookup
#. Tests must be hermetic — no reliance on system state outside tmp dir
#. Skip tests requiring root with ``if (std.os.geteuid() != 0) return``
#. Preserve the exact expected outputs from the shell scripts

## Command Status Matrix

| Command   | Impl | Tests written | Upstream tests | Bugs remaining        |
|-----------|------|---------------|----------------|-----------------------|
| basename  | ✓    | ✓             | ~2             | none known            |
| basenc    | ✓    | ✓             | 2              | base64url wrong       |
| cat       | ✓    | ✓             | 4              | none known            |
| chmod     | ✓    | ✓             | 14             | symbolic modes broken |
| chcon     | ✓    | ✓             | 2              | test setup bug        |
| chgrp     | ✓    | ✓             | 7              | needs root            |
| chown     | ✓    | ✓             | 4              | error message wrong   |
| chroot    | ✓    | ✓             | 2              | needs root            |
| cksum     | ✓    | ✓             | 10             | wrong checksum        |
| cp        | ✓    | ✓             | 64             | partial               |
| csplit    | ✓    | ✓             | 4              | partial               |
| cut       | ✓    | ✓             | 2              | partial               |
| dd        | ✓    | ✓             | 19             | partial               |
| dirname   | ✓    | ✓             | ~2             | none known            |
| echo      | ✓    | ✓             | ~10            | octal \0033, --       |
| env       | ✓    | ✓             | 4              | partial               |
| expand    | ✓    | ✓             | 1              | partial               |
| expr      | ✓    | ✓             | ~5             | partial               |
| factor    | ✓    | ✓             | 3              | partial               |
| false     | ✓    | ✓             | 1              | none known            |
| fmt       | ✓    | ✓             | 4              | partial               |
| fold      | ✓    | ✓             | 4              | partial               |
| groups    | ✓    | ✓             | 3              | needs root            |
| head      | ✓    | ✓             | 17             | none known            |
| hostid    | ✓    | ✓             | 1              | none known            |
| hostname  | ✓    | ✓             | ~2             | none known            |
| id        | ✓    | ✓             | 7              | partial               |
| install   | ✓    | ✓             | 9              | partial               |
| join      | ✓    | ✓             | 1              | partial               |
| kill      | ✓    | ✓             | ~1             | skipped               |
| link      | ✓    | ✓             | ~2             | none known            |
| ln        | ✓    | ✓             | 8              | none known            |
| logname   | ✓    | ✓             | ~1             | none known            |
| ls        | ✗    | ✓             | 51             | not implemented       |
| mkdir     | ✓    | ✓             | 16             | -pv exits 1           |
| mktemp    | ✓    | ✓             | 1              | partial               |
| mknod     | ✓    | ✓             | 1              | needs root            |
| mv        | ✓    | ✓             | 45             | partial               |
| nice      | ✓    | ✓             | 2              | skipped               |
| nl        | ✓    | ✓             | ~3             | empty line spaces     |
| nohup     | ✓    | ✓             | 2              | skipped               |
| nproc     | ✓    | ✓             | 5              | OMP_* vars not read   |
| numfmt    | ✓    | ✓             | 1              | SI suffix, --header   |
| od        | ✓    | ✓             | 7              | partial               |
| paste     | ✓    | ✓             | 1              | partial               |
| pathchk   | ✓    | ✓             | ~2             | -P, invalid chars     |
| printenv  | ✓    | ✓             | ~2             | none known            |
| printf    | ✓    | ✓             | 6              | partial               |
| pr        | ✓    | ✓             | 1              | partial               |
| ptx       | ✓    | ✓             | 1              | -w and -r broken      |
| pwd       | ✓    | ✓             | 2              | none known            |
| readlink  | ✓    | ✓             | 8              | none known            |
| realpath  | ✓    | ✓             | ~5             | test uses wrong fn    |
| rm        | ✓    | ✓             | 47             | none known            |
| rmdir     | ✓    | ✓             | 4              | -p slash, --ignore    |
| runcon    | ✓    | ✓             | 2              | needs SELinux         |
| seq       | ✓    | ✓             | 6              | partial               |
| shred     | ✓    | ✓             | 4              | wrong file size       |
| shuf      | ✓    | ✓             | 2              | partial               |
| sleep     | ✓    | ✓             | ~3             | none known            |
| sort      | ✓    | ✓             | 23             | partial               |
| split     | ✓    | ✓             | 15             | partial               |
| stat      | ✓    | ✓             | 6              | no output             |
| stdbuf    | ✓    | ✓             | 4              | exits 125             |
| stty      | ✓    | ✓             | 5              | skipped (TTY)         |
| sync      | ✓    | ✓             | ~2             | none known            |
| tac       | ✓    | ✓             | 3              | -r ordering wrong     |
| tail      | ✓    | ✓             | 36             | partial               |
| tee       | ✓    | ✓             | 9              | none known            |
| test      | ✓    | ✓             | 2              | partial               |
| timeout   | ✓    | ✓             | 4              | skipped               |
| touch     | ✓    | ✓             | 15             | partial               |
| tr        | ✓    | ✓             | 1              | partial               |
| true      | ✓    | ✓             | 1              | none known            |
| truncate  | ✓    | ✓             | 9              | segfault              |
| tsort     | ✓    | ✓             | ~2             | partial               |
| tty       | ✓    | ✓             | 1              | none known            |
| unexpand  | ✓    | ✓             | 1              | partial               |
| uniq      | ✓    | ✓             | 2              | partial               |
| unlink    | ✓    | ✓             | ~2             | none known            |
| users     | ✓    | ✓             | ~1             | partial               |
| vdir      | ✓    | ✓             | ~1             | partial               |
| wc        | ✓    | ✓             | 16             | none known            |
| whoami    | ✓    | ✓             | ~1             | none known            |
| yes       | ✓    | ✓             | ~2             | minor memory leak     |

## Build & Test Commands

.. code-block:: bash

   # Build all binaries
   zig build

   # Run integration tests
   zig build integration-test

   # Format all source
   zig fmt src/ tests/

   # Clean build cache
   rm -rf .zig-cache && zig build

---

**Last updated**: 2026-02-25
**Status**: Phase 1 — fixing implementation bugs
**Zig version**: 0.15.2
