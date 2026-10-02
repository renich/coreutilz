========================================================
Functional Specification: Text Formatting & Padding
========================================================

:Domain: Text & Stream Processing
:Target Utilities: ``nl``, ``fmt``, ``pr``, ``expand``, ``unexpand``, ``od``, ``ptx``, ``numfmt``
:Specification ID: ``SPEC-FUNC-TEXT-FMT``

.. contents:: Table of Contents
   :depth: 2
   :backlinks: none

1. Overview
===========

The Text Formatting & Padding suite provides POSIX-compliant and GNU Coreutils-compatible utilities for line numbering, paragraph reflowing, printing preparation/pagination, tab/space bidirectional expansion, multi-radix byte dumping, permuted index generation, and human-readable numeric scaling.

Each utility strictly enforces GNU Coreutils CLI syntax, option parsing rules, exit codes, and diagnostic messages.

2. Functional Requirements: ``nl``
==================================

[FUNC-NL-001] Line Numbering Disciplines
----------------------------------------
* Number lines of files (or standard input if omitted/hyphen).
* **Numbering Styles**:
  - ``-b, --body-numbering=STYLE``: Body style (default ``t``).
  - ``-h, --header-numbering=STYLE``: Header style (default ``n``).
  - ``-f, --footer-numbering=STYLE``: Footer style (default ``n``).
  - Styles supported: ``a`` (all lines), ``t`` (non-empty lines), ``n`` (no lines), ``pBRE`` (lines matching POSIX Basic Regular Expression).
* **Section Delimiters**:
  - ``-d, --section-delimiter=CC``: delimiter string (default ``\:``). If single char ``C``, second char defaults to ``:``. If empty ``''``, disables delimiter detection.
  - Delimiter lines: 3 delimiters = header, 2 delimiters = body, 1 delimiter = footer. Emits newline and switches section type.
* **Line Number Formatting**:
  - ``-v, --starting-line-number=NUMBER``: Initial number (default 1).
  - ``-i, --line-increment=NUMBER``: Increment (default 1, allows negative).
  - ``-n, --number-format=FORMAT``: ``ln`` (left justified), ``rn`` (right justified, default), ``rz`` (right justified with leading zeros).
  - ``-w, --number-width=NUMBER``: Field width (default 6).
  - ``-s, --number-separator=STRING``: Separator following line number (default ``\t``).
  - ``-p, --no-renumber``: Do not reset line number at section delimiters.
  - ``-l, --join-blank-lines=NUMBER``: Group of ``NUMBER`` consecutive empty lines counted as one line for numbering.

3. Functional Requirements: ``fmt``
===================================

[FUNC-FMT-001] Paragraph Reflowing & Formatting
-----------------------------------------------
* Reformat input paragraphs to fit target width.
* **Width & Goal Controls**:
  - ``-w, --width=WIDTH``: Maximum line width (default 75, max 2500). Rejects >= 32768.
  - ``-g, --goal=GOAL``: Target line width (default roughly ``width * 7 / 8``).
  - Obsolete syntax: ``-WIDTH`` accepted as first argument (e.g., ``-72``).
* **Paragraph & Margin Modes**:
  - ``-c, --crown-margin``: Preserve indentation of first two lines, align remainder to second line.
  - ``-t, --tagged-paragraph``: Like crown margin, but first line indent must differ from second.
  - ``-s, --split-only``: Split lines longer than width without reflowing short lines.
  - ``-u, --uniform-spacing``: Normalize word spacing (one space between words, two spaces after sentence-ending punctuation ``.?!``).
  - ``-p, --prefix=STRING``: Only reformat lines starting with prefix, preserving prefix.

4. Functional Requirements: ``pr``
==================================

[FUNC-PR-001] Pagination & Multi-Column Formatting
--------------------------------------------------
* Paginate files for printing with headers and footers.
* **Multi-Column & Merging**:
  - ``-COLUMN, --columns=COLUMN``: Produce multi-column output down columns.
  - ``-a, --across``: Print columns across rather than down.
  - ``-m, --merge``: Print all input files in parallel, one per column.
* **Page Layout**:
  - ``-l, --length=PAGE_LENGTH``: Page length in lines (default 66).
  - ``-w, --width=PAGE_WIDTH``: Page width (default 72 for multi-column).
  - ``-h, --header=HEADER``: Replace filename in header with custom text.
  - ``-t, --omit-header``: Omit 5-line header and 5-line footer.
  - ``-d, --double-space``: Double space output.
  - ``-n[SEP[DIGITS]]``: Line numbering (default 5 digits, tab separator).
  - ``-o, --indent=MARGIN``: Indent each line by MARGIN spaces.
  - ``+FIRST_PAGE[:LAST_PAGE]``: Output only specified page range.

5. Functional Requirements: ``expand`` & ``unexpand``
=====================================================

[FUNC-EXPAND-001] Tab/Space Conversions
---------------------------------------
* ``expand``: Convert tab characters to spaces.
  - ``-t, --tabs=N`` or comma-separated list of tab stops.
  - ``-i, --initial``: Only convert tabs before first non-blank character.
  - Obsolete ``-N`` supported (e.g. ``-3``).
* ``unexpand``: Convert space characters to tabs.
  - ``-a, --all``: Convert all spaces, not just initial whitespace.
  - ``--first-only``: Only convert initial whitespace (default without ``-t``).
  - ``-t, --tabs=N`` or tab stop list (implies ``-a``).

6. Functional Requirements: ``od``
==================================

[FUNC-OD-001] Multi-Radix Octal & Hex Dumper
--------------------------------------------
* Dump input bytes in specified human-readable representations.
* **Radix & Offsets**:
  - ``-A, --address-radix=RADIX``: ``d`` (decimal), ``o`` (octal, default), ``x`` (hex), ``n`` (none).
  - ``-j, --skip-bytes=BYTES``: Skip initial input bytes.
  - ``-N, --read-bytes=BYTES``: Limit total dumped bytes.
  - ``-w, --width=BYTES``: Number of bytes per output line.
  - ``-v, --output-duplicates``: Do not compress identical lines with ``*``.
* **Types**:
  - ``-t TYPE``: ``a`` (named char), ``c`` (escaped char), ``o[SIZE]``, ``d[SIZE]``, ``u[SIZE]``, ``x[SIZE]``, ``f[SIZE]``.
  - Traditional aliases: ``-b`` (``-t o1``), ``-c`` (``-t c``), ``-d`` (``-t u2``), ``-o`` (``-t o2``), ``-s`` (``-t d2``), ``-x`` (``-t x2``).

7. Functional Requirements: ``ptx``
===================================

[FUNC-PTX-001] Permuted Index Generator
---------------------------------------
* Generate permuted index of words in text files.
* **Formatting Options**:
  - ``-f, --ignore-case``: Case insensitive indexing.
  - ``-g, --gap-size=NUMBER``: Column gap size.
  - ``-w, --width=NUMBER``: Output line width (default 72 or 100 for tex).
  - ``-t, --format=tex``: TeX format output.
  - ``-r, --format=roff``: ROFF format output.
  - ``-b, --break-file=FILE``: Word break characters.
  - ``-i, --ignore-file=FILE``: Words to ignore.
  - ``-o, --only-file=FILE``: Words to include exclusively.

8. Functional Requirements: ``numfmt``
======================================

[FUNC-NUMFMT-001] Numeric Conversion & Scaling
----------------------------------------------
* Transform numbers between plain text and scaled engineering units.
* **Scaling Modes**:
  - ``--from=UNIT``: ``none``, ``auto``, ``si`` (powers of 1000), ``iec`` (powers of 1024), ``iec-i`` (Ki, Mi, etc.).
  - ``--to=UNIT``: ``none``, ``si``, ``iec``, ``iec-i``.
* **Field & Formatting**:
  - ``--field=N``: Target field (default 1).
  - ``--header[=N]``: Pass-through first N lines untouched.
  - ``--delimiter=X``: Field delimiter character.
  - ``--round=METHOD``: ``up``, ``down``, ``from-zero``, ``towards-zero``, ``nearest``.
  - ``--padding=N``: Column padding (positive = right aligned, negative = left aligned).
  - ``--format=FORMAT``: Custom floating point format.
  - ``--invalid=MODE``: ``abort`` (exit 2), ``fail`` (exit 2), ``warn`` (exit 0), ``ignore`` (exit 0).
