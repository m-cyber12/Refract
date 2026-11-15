# Capture extraction diagnostics in the reader

New reviewed captures persist the parser's extraction warnings alongside the
item and original in the same database transaction, including durable capture
jobs and original-only PDF saves. An empty recorded list means the parser
reported no warning, not that extraction is complete or accurate. Review-only
notices about privacy, duplicates and providers are not persisted. Warnings are
local library metadata, currently unencrypted like the rest of the library.

The reader displays the recorded warnings, or explains when no history was
recorded. Existing items and other legacy import paths have unknown history; the
migration does not fabricate warnings or reparse originals. Reusing an existing
item retains its own history. Keeping a separate copy records the new capture's
warnings. The stored diagnostics are produced at save time; a parser update
between preview and a delayed job may change them. They are not a complete audit
trail, evidence of authenticity, or a substitute for inspecting the original.

This does not implement OCR, encrypted storage, a complete backup, or parser
isolation. Tests cover migration, restart, direct and durable saves, rollback,
reuse, the bridge and reader labels. Device and full CI validation remain needed.
