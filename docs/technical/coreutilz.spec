Coreutilz Technical Specification
=================================

:Author: EVALinux Development Team
:Date: 2025-02-06
:Version: 0.1.0
:Language: Zig 0.15.2

Overview
--------

Coreutilz is a complete reimplementation of GNU Coreutils in Zig, designed for:

- **100% POSIX compliance** where applicable
- **Performance parity or better** compared to GNU Coreutils
- **Memory safety** through Zig's memory management
- **Cross-platform compatibility** (Linux, BSD, macOS)
- **Comprehensive test coverage** - all original coreutils tests pass

Architecture
------------

Project Structure
~~~~~~~~~~~~~~~~~

::

    coreutilz/
    ├── build.zig              # Build configuration
    ├── build.zig.zon          # Package manifest
    ├── src/
    │   ├── main.zig           # CLI dispatcher (optional multi-call binary)
    │   ├── root.zig           # Library exports
    │   ├── utils/             # Shared utility modules
    │   │   ├── args.zig       # Argument parsing
    │   │   ├── io.zig         # I/O utilities
    │   │   ├── fs.zig         # Filesystem utilities
    │   │   ├── str.zig        # String utilities
    │   │   └── errors.zig     # Error handling
    │   └── commands/          # Individual command implementations
    │       ├── true.zig
    │       ├── false.zig
    │       ├── echo.zig
    │       ├── cat.zig
    │       └── ...
    ├── tests/
    │   ├── init.zig           # Test framework
    │   ├── utils/             # Test utilities
    │   └── commands/          # Per-command tests
    │       ├── true_test.zig
    │       ├── false_test.zig
    │       └── ...
    └── docs/
        └── technical/
            └── coreutilz.spec  # This document

Implementation Strategy
~~~~~~~~~~~~~~~~~~~~~~~

Commands are implemented in **8 tiers** based on complexity:

**Tier 1: Trivial (50-200 lines)**
    - true, false, logname, tty, unlink, hostname, hostid, whoami, nproc, dirname, basename, printenv

**Tier 2: Simple (200-500 lines)**
    - echo, yes, sleep, sync, groups, users, uptime, pwd, readlink, link, nice, env

**Tier 3: Moderate (500-1000 lines)**
    - rmdir, mkdir, rm, mv, cp, ln, touch, chmod, chown, cat, wc, head, du, df, tee, mktemp, seq, test

**Tier 4: Complex (1000-2000 lines)**
    - tail, tr, dd, join, cut, paste, uniq, split, csplit, stat, date, printf

**Tier 5: Very Complex (2000+ lines)**
    - sort, ls, expr, factor, ptx, od

**Tier 6: Cryptographic/Checksum**
    - cksum, sum, md5sum, sha1sum, sha224sum, sha256sum, sha384sum, sha512sum, b2sum, basenc

**Tier 7: SELinux/Security**
    - chcon, runcon

**Tier 8: Terminal/Advanced**
    - stty, nohup, stdbuf, timeout, shred, chroot, pr, fmt, fold, nl, tac

Implementation Rules
--------------------

1. **Each command is a module** with the following interface:

   .. code:: zig

       pub const name: []const u8 = "command_name";
       pub const version: []const u8 = "0.1.0";
       pub const authors: []const u8 = "EVALinux Team";
       pub const license: []const u8 = "MIT";
       
       pub fn run(args: [][]const u8, allocator: std.mem.Allocator) !u8;
       pub fn printHelp(writer: anytype) !void;
       pub fn printVersion(writer: anytype) !void;

2. **Error handling** uses Zig's error unions with descriptive error messages

3. **Memory management** uses the passed allocator exclusively - no global allocators

4. **I/O operations** use buffered I/O for performance

5. **Testing requirements**:
   - 100% code coverage for each command
   - Property-based testing where applicable
   - Edge case testing (empty input, large files, special characters)
   - POSIX compliance tests
   - Integration tests matching coreutils test suite

Testing Framework
-----------------

Test Structure
~~~~~~~~~~~~~~

Each command has comprehensive tests in ``tests/commands/<command>_test.zig``:

.. code:: zig

    test "command basic functionality" {
        // Arrange
        const allocator = std.testing.allocator;
        const args = &[_][]const u8{"command"};
        
        // Act
        const result = try command.run(args, allocator);
        
        // Assert
        try std.testing.expectEqual(0, result);
    }

Test Categories
~~~~~~~~~~~~~~~

1. **Unit Tests**: Test individual functions
2. **Integration Tests**: Test command execution
3. **Edge Cases**: Empty files, large buffers, special characters
4. **Error Handling**: Invalid arguments, permission errors
5. **POSIX Compliance**: POSIXLY_CORRECT behavior
6. **Performance Tests**: Benchmark against GNU coreutils

Build System
------------

The project uses Zig's native build system:

- ``zig build`` - Build all commands
- ``zig build test`` - Run all tests
- ``zig build install`` - Install to prefix
- ``zig build <command>`` - Build specific command

Each command is built as both:
1. Standalone executable: ``zig build <command>``
2. Library module: ``@import("coreutilz").commands.<command>``

Performance Requirements
------------------------

1. **Memory usage**: ≤ 110% of GNU coreutils
2. **CPU performance**: ≥ 90% of GNU coreutils
3. **Binary size**: ≤ 150% of GNU coreutils (acceptable for safety)

Porting Guidelines
------------------

When porting from C:

1. Study the C implementation in ``/tmp/coreutils/src/<command>.c``
2. Identify the core algorithm and edge cases
3. Rewrite in idiomatic Zig:
   - Use slices instead of pointers
   - Use error unions instead of errno
   - Use comptime for compile-time logic
   - Use defer/errdefer for cleanup
4. Port the corresponding tests from ``/tmp/coreutils/tests/``
5. Verify behavior matches exactly (byte-for-byte output)

Command Reference
-----------------

Full list of 105 commands to implement:

File Operations
~~~~~~~~~~~~~~~

- arch
- b2sum  
- base32
- base64
- basename
- basenc
- cat
- chcon
- chgrp
- chmod
- chown
- chroot
- cksum
- comm
- cp
- csplit
- cut
- date
- dd
- df
- dir
- dircolors
- dirname
- du
- echo
- env
- expand
- expr
- factor
- false
- fmt
- fold
- groups
- head
- hostid
- hostname
- id
- install
- join
- kill
- link
- ln
- logname
- ls
- md5sum
- mkdir
- mkfifo
- mknod
- mktemp
- mv
- nice
- nl
- nohup
- nproc
- numfmt
- od
- paste
- pathchk
- pinky
- pr
- printenv
- printf
- ptx
- pwd
- readlink
- realpath
- rm
- rmdir
- runcon
- seq
- sha1sum
- sha224sum
- sha256sum
- sha384sum
- sha512sum
- shred
- shuf
- sleep
- sort
- split
- stat
- stdbuf
- stty
- sum
- sync
- tac
- tail
- tee
- test
- timeout
- touch
- tr
- true
- truncate
- tsort
- tty
- uname
- unexpand
- uniq
- unlink
- uptime
- users
- vdir
- wc
- who
- whoami
- yes

Timeline
--------

Phase 1: Foundation (Week 1-2)
    - Build system setup
    - Test framework
    - Shared utilities
    - Tier 1 commands (12 commands)

Phase 2: Core Shell Utils (Week 3-4)
    - Tier 2 commands (12 commands)
    - Tier 3 basic file ops (10 commands)

Phase 3: File Operations (Week 5-6)
    - Remaining Tier 3 commands (18 commands)
    - Tier 4 commands (12 commands)

Phase 4: Complex Tools (Week 7-8)
    - Tier 5 commands (6 commands)
    - Tier 6 cryptographic (10 commands)

Phase 5: Advanced Features (Week 9-10)
    - Tier 7 SELinux (2 commands)
    - Tier 8 advanced (13 commands)

Phase 6: Polish (Week 11-12)
    - Performance optimization
    - Documentation
    - CI/CD setup
    - Cross-platform testing

Success Criteria
----------------

1. All 105 commands implemented
2. 100% test coverage (all original coreutils tests pass)
3. Performance within 10% of GNU coreutils
4. Zero memory leaks (verified with valgrind/Zig's allocator)
5. Complete POSIX compliance
6. Cross-platform (Linux, BSD, macOS)

References
----------

- `GNU Coreutils Manual <https://www.gnu.org/software/coreutils/manual/coreutils.html>`_
- `Zig Language Reference <https://ziglang.org/documentation/0.15.2/>`_
- `Coreutils Source <file:///tmp/coreutils/>`_
- `POSIX.1-2017 <https://pubs.opengroup.org/onlinepubs/9699919799/>`_
