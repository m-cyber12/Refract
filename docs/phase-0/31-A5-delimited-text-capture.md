# A5 — CSV and TSV as plain text

The single-file picker now accepts `.csv` and `.tsv` alongside existing formats.
These are treated as **UTF-8 plain text**, not parsed spreadsheets or tables:
there is no column interpretation, schema, formula evaluation, formatting or
validation. This is not support for XLSX or arbitrary encodings, and does not
interpret spreadsheet binaries. Android and iOS handoff code also recognizes
CSV and TSV as text, subject to sender/provider representation and platform
availability; unrecognized representations can still fail. A file picker/provider may
still decline these extensions or cache/download files before app checks.

The normal 2 MiB text limit and strict UTF-8 decoding apply. The existing
explicit preview and separate durable-save approval remain required. An
unedited selected file is intended to preserve its exact UTF-8 bytes including a
BOM and line endings. The editor warns that edits become the captured original;
this is not a separate preserved-original-plus-edit feature. The stored source
kind is plain text, and the current library does not preserve the selected
filename as original-format metadata. No original is stored by merely selecting
or previewing. Existing staging, backup, encryption and deletion limitations
continue to apply.

Tests cover picker decoding and invalid input, review without auto-save, and a
host-native capture/reopen comparison against exact original bytes. Automated
host tests do not demonstrate real Android/iOS provider behavior, accessibility,
large-file memory behavior or signed-device readiness. Full structured table
support, separate original and edits, batch review, unsupported original-only
saving and device tests remain open.

## Handoff extension

Android advertises `text/csv` and `text/tab-separated-values` and accepts those
MIME types or `.csv`/`.tsv` names from a granted content URI. iOS recognizes
their file extensions and registered delimited-text file representations.
Existing Android ephemeral-draft and iOS explicitly consented staging policies
are unchanged; receiving a file is not library approval. Providers can vend
different representations and may transform data before REFRACT receives it.
Original-byte claims apply to received bytes, not necessarily the sender's
pre-transformation file. Physical share-sheet and provider compatibility remain
unverified.

For picker work at `3414773`, Flutter `42965955267` (including the real native
worker test), Rust `42965955162`, Android emulator `42965955186`, unsigned iOS
`42965955209`, and docs `42965955151` passed. The handoff changes are separate
and require their own CI and device evidence.
