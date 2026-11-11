# A5 — JSON and XML intake as plain text

The file picker and Android/iOS handoff recognize `.json` and `.xml` as
**plain UTF-8 text**. Android advertises `application/json`, `application/xml`
and `text/xml`; iOS handles JSON/XML file representations and recognized file
URLs. No structured JSON or XML parser, schema, entity expansion, code execution,
reference resolution, linked-resource retrieval or semantic validation is
performed. Even syntactically invalid input can be captured as text. The 2 MiB
limit and strict UTF-8 decoding still apply. This is not a general parser for
arbitrary file formats or encodings, and a provider may fail or transform its
representation before the app receives it.

The user still reviews and separately approves saving each item. Saving an
unedited selected source retains received UTF-8 bytes, including a BOM and line
endings; edits become the captured original. The UI warns about that distinction
and offers restoration before review. Structured syntax, filenames and original
format are not preserved as separate library metadata; source kind is plain text.
Android handoff is ephemeral; iOS staged copies require explicit handoff consent
and survive until decision. This does not change the lack of app-level
at-rest encryption or secure-erasure guarantees.

Tests cover picker decoding, malformed syntax accepted only as text, review
without automatic save, iOS provider representations, Android filters and a
synthetic Android content-provider share. These tests must pass CI before being
reported as verified; physical share sheets, providers, platforms, accessibility
and signed-device behavior remain unverified.

The preceding capture-integrity commit `0479d85` passed Flutter `42974118835`,
Rust `42974118864`, Android emulator `42974118859`, unsigned iOS `42974118890`
and docs `42974118799`. The corrected Android test exercised a synthetic CSV
preview and saved-byte comparison; it does not prove real-provider compatibility.
