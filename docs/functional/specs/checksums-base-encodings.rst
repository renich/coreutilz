============================================================
Functional Specification: Checksums & Base Encodings
============================================================

:Domain: Checksums & Base Encodings
:Target Utilities: ``cksum``, ``b2sum``, ``md5sum``, ``sha1sum``, ``sha224sum``, ``sha256sum``, ``sha384sum``, ``sha512sum``, ``base64``, ``base32``, ``basenc``
:Specification ID: ``SPEC-FUNC-CHECKSUMS-BASE``

.. contents:: Table of Contents
   :depth: 2
   :backlinks: none

1. Overview
===========

The Checksums & Base Encodings suite provides POSIX-compliant and GNU Coreutils-compatible utilities for calculating, formatting, and verifying cryptographic and cyclic checksums, as well as encoding and decoding streams using standard and alternate base representations.

Each utility conforms strictly to GNU Coreutils behavioral semantics, exit statuses, error diagnostics, quoting, and standard option conventions (including ``--help`` and ``--version``).

2. Functional Requirements: Base Encodings (``base64``, ``base32``, ``basenc``)
==============================================================================

[FUNC-BASE-001] Alphabet and Encoding Disciplines
-------------------------------------------------
* ``base64`` MUST implement standard Base64 encoding/decoding per RFC 4648 section 4.
* ``base32`` MUST implement standard Base32 encoding/decoding per RFC 4648 section 6.
* ``basenc`` MUST accept an explicit encoding flag selecting from:
  - ``--base64``: RFC 4648 section 4 (A-Z, a-z, 0-9, +, /).
  - ``--base64url``: RFC 4648 section 5 (A-Z, a-z, 0-9, -, _).
  - ``--base32``: RFC 4648 section 6 (A-Z, 2-7).
  - ``--base32hex``: RFC 4648 section 7 (0-9, A-V).
  - ``--base16`` (or ``--hex``): RFC 4648 section 8 (0-9, A-F).
  - ``--base2msbf``: Bit string with most significant bit first.
  - ``--base2lsbf``: Bit string with least significant bit first.
  - ``--z85``: ZeroMQ 32/Z85 encoding (4-byte blocks mapped to 5 characters). Input length must be a multiple of 4 when encoding, multiple of 5 when decoding.
  - ``--base58``: Bitcoin base58 encoding. Leading zero bytes mapped to '1's.
* If ``basenc`` is invoked without an encoding selector, it MUST emit ``basenc: missing encoding type``, suggest ``Try 'basenc --help' for more information.``, and exit with status 1.
* *Fulfills Technical Reference*: ``[TECH-BASE-001]``

[FUNC-BASE-002] Line Wrapping & Output Formatting
-------------------------------------------------
* Encoded streams MUST wrap lines at column 76 by default.
* The ``-w COLS`` (``--wrap=COLS``) option MUST set the maximum column width before inserting a newline.
* Specifying ``-w 0`` (or ``--wrap=0``) MUST disable line wrapping entirely and suppress any trailing newline.
* When ``wrap > 0`` and input is non-empty, the final line MUST terminate with a newline. When input is empty, no trailing newline is emitted.
* Invalid wrap arguments (such as negative numbers, non-decimals like ``0x0`` or ``1k``) MUST emit ``<cmd>: invalid wrap size: '<val>'`` and exit with status 1.
* *Fulfills Technical Reference*: ``[TECH-BASE-002]``

[FUNC-BASE-003] Decoding & Garbage Handling
-------------------------------------------
* When ``-d`` (``--decode``) is specified, input MUST be decoded back into binary data.
* By default, newlines (``\n`` and ``\r``) in the encoded input stream MUST be tolerated and ignored. Any other non-alphabet character MUST trigger ``<cmd>: invalid input`` and exit with status 1.
* When ``-i`` (``--ignore-garbage``) is specified, all non-alphabet characters in the input stream MUST be discarded.
* Missing padding at EOF for Base64 and Base32 MUST be automatically padded and resolved if the payload constitutes a valid prefix.
* *Fulfills Technical Reference*: ``[TECH-BASE-003]``

[FUNC-BASE-004] Operand Validation & Streaming Memory
-----------------------------------------------------
* Utilities accept at most one file operand. If more than one operand is provided, emit ``<cmd>: extra operand '<arg>'`` and exit with status 1.
* When no file is given, or when file is ``-``, read from standard input.
* Streaming encoding and decoding MUST execute in bounded memory (except base58 which requires whole-message buffering due to arbitrary precision arithmetic).
* *Fulfills Technical Reference*: ``[TECH-BASE-004]``

3. Functional Requirements: Checksum Engines (``cksum``, ``*sum``)
==================================================================

[FUNC-CKSUM-001] Algorithm Selection & Default Semantics
--------------------------------------------------------
* ``cksum`` MUST default to POSIX 32-bit CRC calculation unless ``-a`` (``--algorithm=TYPE``) is provided.
* Default ``cksum`` output format is: ``<crc> <bytes> [<filename>]`` (filename omitted when reading standard input).
* Supported algorithms for ``cksum -a``:
  - ``crc``: POSIX CRC checksum with byte length polynomial encoding.
  - ``crc32b``: Standard PKZIP/ISO-HDLC 32-bit CRC.
  - ``bsd``: Traditional BSD rotated 16-bit sum (equivalent to ``sum -r``).
  - ``sysv``: Traditional System V 16-bit sum (equivalent to ``sum -s``).
  - ``md5``: 128-bit MD5 message digest.
  - ``sha1``: 160-bit SHA-1 message digest.
  - ``sha224``, ``sha256``, ``sha384``, ``sha512``: SHA-2 family.
  - ``sha2``: Requires explicit ``--length`` (224, 256, 384, or 512).
  - ``sha3-224``, ``sha3-256``, ``sha3-384``, ``sha3-512``: SHA-3 family.
  - ``sha3``: Requires explicit ``--length`` (224, 256, 384, or 512).
  - ``blake2b``: BLAKE2b digest with optional length up to 512 bits (multiple of 8). Default 512 bits.
  - ``sm3``: Chinese SM3 256-bit hash.
* Standalone checksum commands (``b2sum``, ``md5sum``, ``sha1sum``, ``sha224sum``, ``sha256sum``, ``sha384sum``, ``sha512sum``) default to their dedicated digest algorithm in untagged text mode.
* *Fulfills Technical Reference*: ``[TECH-CKSUM-001]``

[FUNC-CKSUM-002] Output Formatting & Modes
------------------------------------------
* Untagged format (default for standalone utilities, or ``cksum --untagged``):
  - Text mode (default): ``<digest>  <filename>``
  - Binary mode (``-b``, ``--binary``): ``<digest> *<filename>``
* Tagged format (default for ``cksum -a <algo>``, or standalone with ``--tag``):
  - Format: ``<TAG> (<filename>) = <digest>``
  - When length is custom: ``<TAG>-<LEN> (<filename>) = <digest>``
* Raw binary format (``--raw``):
  - Emits the raw binary digest bytes in big-endian network byte order.
  - Permitted only with a single input stream. Specifying multiple operands MUST emit ``cksum: the --raw option is not supported with multiple files`` and exit 1.
* Base64 format (``--base64``):
  - Emits Base64-encoded digest characters instead of hexadecimal.
  - Mutually exclusive with ``--raw`` (emits error and exits 1).
* Zero-terminated lines (``-z``, ``--zero``):
  - Emits NUL byte delimiters instead of newlines, and disables filename escaping.
* Filename escaping:
  - If a filename contains newlines, carriage returns, or backslashes, a leading backslash ``\`` MUST be prefixed to the line, and internal characters escaped (``\\``, ``\n``, ``\r``).
* *Fulfills Technical Reference*: ``[TECH-CKSUM-002]``

[FUNC-CKSUM-003] Verification & Check Engine (``-c``, ``--check``)
------------------------------------------------------------------
* Reads checksum files and verifies referenced file contents against expected digests.
* Supports autodetection across tagged BSD/OpenSSL, standard GNU Coreutils (text and binary), and BSD reversed single-space formats.
* Allows comment lines beginning with ``#`` and empty lines.
* Status and error reporting options:
  - ``--quiet``: Suppresses ``<filename>: OK`` lines on success.
  - ``--status``: Suppresses all output; exit code indicates status.
  - ``--warn``: Emits line-numbered diagnostic for each improperly formatted line.
  - ``--strict``: Causes non-zero exit (1) if any line is improperly formatted.
  - ``--ignore-missing``: Ignores missing files without failing, failing only if zero files were verified.
* Exit code 0 if all verified files matched; 1 if any checksum failed to match, file was unreadable, or strict syntax violation occurred.
* *Fulfills Technical Reference*: ``[TECH-CKSUM-003]``
