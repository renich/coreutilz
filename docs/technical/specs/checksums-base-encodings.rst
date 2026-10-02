==========================================================
Technical Specification: Checksums & Base Encodings
==========================================================

:Domain: Checksums & Base Encodings
:Target Utilities: ``cksum``, ``b2sum``, ``md5sum``, ``sha1sum``, ``sha224sum``, ``sha256sum``, ``sha384sum``, ``sha512sum``, ``base64``, ``base32``, ``basenc``
:Specification ID: ``SPEC-TECH-CHECKSUMS-BASE``

.. contents:: Table of Contents
   :depth: 2
   :backlinks: none

1. Architectural Overview
=========================

The Checksums and Base Encodings architecture provides high-performance, memory-bounded, zero-leak streaming data transformation and verification. The subsystem is structured into two modular domains:

1. ``src/commands/basenc/``: Unified multi-base encoder and decoder suite implementing standard RFC 4648 (Base64, Base64url, Base32, Base32hex, Base16), Base2 (MSBF/LSBF), ZeroMQ Z85, and Bitcoin Base58.
2. ``src/commands/cksum/``: Unified checksum calculation, verification, and formatting engine supporting POSIX CRC, CRC32b, BSD/SysV sums, SM3, and cryptographically secure message digests via ``std.crypto.hash`` (MD5, SHA-1, SHA-2, SHA-3, BLAKE2b).

2. Technical Requirements: Base Encodings
=========================================

[TECH-BASE-001] Alphabet Coding Tables & Conversions
----------------------------------------------------
* Base64 / Base64url: Comptime-generated 64-byte forward lookup tables and 256-byte reverse lookup decode tables.
* Base32 / Base32hex: Standard 32-byte forward lookup tables and 256-byte reverse tables.
* Base16: Upper-case hexadecimal emission; case-insensitive nibble decode.
* Base2: Bit extraction loops supporting MSBF (bit 7 down to 0) and LSBF (bit 0 up to 7).
* Z85: 4-byte big-endian integers converted to 5-character radix-85 strings using the ZeroMQ alphabet.
* Base58: In-place big-endian byte-to-radix-58 conversion algorithm with exact leading zero count preservation.
* *Fulfills Functional Requirement*: ``[FUNC-BASE-001]``

[TECH-BASE-002] Streaming Line Wrap Buffer
------------------------------------------
* Line wrapping is implemented via a bounded wrapping writer wrapper struct.
* Accumulates emitted characters and injects newline delimiters precisely at ``wrap_column`` boundaries.
* Slices exceeding remaining column space are written in chunks to avoid intermediate allocations.
* *Fulfills Functional Requirement*: ``[FUNC-BASE-002]``

[TECH-BASE-003] Streaming Decoding & Garbage Filtering
------------------------------------------------------
* Stream chunk ingestion uses a 32 KB sliding buffer.
* When ``ignore_garbage`` is active, non-alphabet characters are filtered out of the read buffer before decoding.
* In strict mode, only ``\n`` and ``\r`` are skipped; any foreign byte triggers immediate error abort.
* Partial blocks at EOF are resolved with auto-padding logic where permitted.
* *Fulfills Functional Requirement*: ``[FUNC-BASE-003]``

[TECH-BASE-004] Resource Limits & Error Recovery
------------------------------------------------
* All encode and decode engines (except Base58) stream with strict $O(1)$ memory overhead.
* File descriptors are flushed safely handling `/dev/full` writes (`flush() catch return 1;`).
* *Fulfills Functional Requirement*: ``[FUNC-BASE-004]``

3. Technical Requirements: Checksum Engines
===========================================

[TECH-CKSUM-001] Hash Engine Dispatcher & Dynamic Algorithms
------------------------------------------------------------
* Hash implementations encapsulate streaming `.init()`, `.update()`, and `.final()` lifecycles.
* POSIX CRC: Standard generating polynomial ``0x04C11DB7`` with length appended byte-by-byte in little-endian order, inverted at completion.
* BSD Sum: 16-bit right-rotation accumulator: ``(sum >> 1) + ((sum & 1) << 15) + byte``.
* SysV Sum: 32-bit addition with end-around carry: ``(s & 0xFFFF) + (s >> 16)`` repeated twice.
* SM3: Standard 32-byte digest computed with 64-round compression function.
* BLAKE2b: Variable length support from 8 to 512 bits in multiples of 8 bits.
* *Fulfills Functional Requirement*: ``[FUNC-CKSUM-001]``

[TECH-CKSUM-002] Formatter & Escaping Pipeline
----------------------------------------------
* Formatter writes atomic output lines directly to standard output writer.
* Escaping detection scans filename bytes for `\n`, `\r`, or `\`. If present, emits leading `\` and escapes internal characters.
* Base64 checksum mode transforms binary digest bytes to RFC 4648 Base64 string before printing.
* *Fulfills Functional Requirement*: ``[FUNC-CKSUM-002]``

[TECH-CKSUM-003] Verification State Machine
-------------------------------------------
* Parser inspects each input line:
  - Skips comments (`#`) and whitespace.
  - Matches tagged format: `TAG [(]FILENAME[)] = DIGEST`.
  - Matches untagged format: `DIGEST [ *]FILENAME`.
* Resolves filename unescaping if line has leading `\`.
* Compares computed digest against expected digest in constant-time byte comparison.
* Tracks tally of matched, mismatched, unreadable, and improperly formatted lines.
* *Fulfills Functional Requirement*: ``[FUNC-CKSUM-003]``
