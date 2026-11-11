# A5 — CSV and TSV as plain text

The single-file picker now accepts `.csv` and `.tsv` alongside existing formats.
These are treated as **UTF-8 plain text**, not parsed spreadsheets or tables:
there is no column interpretation, schema, formula evaluation, formatting or
validation. This is not support for XLSX or arbitrary encodings, and does not
extend Android/iOS share-provider format handling. A file picker/provider may
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
