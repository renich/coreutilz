=========================
Coreutilz Style Guide
=========================

This document outlines the coding style and development practices for the
Coreutilz project. As a Zig implementation of GNU Coreutils, we aim to combine
the rigorous standards of the GNU project with the modern, safe, and explicit
nature of the Zig programming language.

General Principles
==================

1. **Communicate Intent Precisely**: Code should be readable and its purpose
   obvious.
2. **No Hidden Control Flow**: No macros or hidden jumps.
3. **No Hidden Memory Allocations**: Allocations must be explicit and use
   provided allocators.
4. **Edge Cases Matter**: Always handle potential errors and boundary conditions.

Zig Coding Style
================

We follow the standard Zig style conventions, enforced by the compiler and
tooling.

Formatting
----------

* **zig fmt**: All source code must be formatted using ``zig fmt``. This ensures
  consistent indentation (spaces), line endings, and spacing.
* **Line Length**: Aim for a maximum of 80 characters. If a line exceeds this,
  consider refactoring or using Zig's multi-line string/expression support.

Naming Conventions
------------------

* **Types/Structs/Enums**: ``PascalCase`` (e.g., ``FileBuffer``).
* **Functions/Variables**: ``snake_case`` (e.g., ``read_file``, ``bytes_read``).
* **Constants/Global Variables**: ``snake_case`` (often prefixed with ``k_`` if
  appropriate, but standard ``snake_case`` is preferred).
* **Error Sets**: ``PascalCase`` (e.g., ``ReadError``).

Memory Management
-----------------

* **Explicit Allocators**: Always pass an ``Allocator`` to functions that
  perform allocations.
* **Defer for Cleanup**: Use the ``defer`` keyword to ensure resources (memory,
  file handles) are released as soon as they are no longer needed.
* **Testing Allocator**: Use ``std.testing.allocator`` in tests to detect leaks
  automatically.

Error Handling
--------------

* **Return Errors**: Use error unions (``!T``) for functions that can fail.
* **Try/Catch**: Use the ``try`` keyword to propagate errors or ``catch`` to
  handle them locally.
* **No Unhandled Errors**: Never ignore an error. If a failure is impossible,
  use ``unreachable`` or handle it explicitly.

Documentation
=============

* **Doc Comments**: Use ``///`` for documentation comments on public functions,
  structs, and variables.
* **Active Voice**: Use the active voice in documentation and comments (e.g.,
  "Print the message" instead of "The message is printed").
* **RST Format**: Technical documentation should be written in
  reStructuredText (.rst).

GNU Coreutils Traditions
========================

While we use Zig, we maintain several conventions from the original GNU
Coreutils project to ensure consistency in contribution and history.

Commit Messages
---------------

We use a specific format for commit messages:

1. A concise one-line summary (max 50-70 characters).
2. A blank line.
3. A detailed description, including ChangeLog-style entries for affected files.

Example::

    cat: add support for --number-nonblank

    * src/commands/cat.zig (run): Implement line numbering logic for
      non-blank lines.
    * tests/cat.test.zig: Add test case for -b option.

Documentation & Help
--------------------

* Every command must provide a ``--help`` and ``--version`` output.
* The ``--help`` output should be the primary source of truth for command
  usage.

Arithmetic Comparisons
----------------------

Following GNU preference, favor the use of ``<`` and ``<=`` over ``>`` and
``>=`` where possible, as it often matches how we think about ranges and
sequences.

Testing
=======

* **Mandatory Coverage**: No feature or bug fix is accepted without
  corresponding tests.
* **Unit Tests**: Place tests in the same file as the implementation or in a
  corresponding ``.test.zig`` file.
* **Integration Tests**: Use the ``tests/`` directory for end-to-end command
  testing.
