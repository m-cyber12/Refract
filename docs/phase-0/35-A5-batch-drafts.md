# A5 — temporary batch drafts

The batch page selects multiple supported files into a **process-memory-only**
queue: at most 16 items and 24 MiB of received source bytes, with the existing
2 MiB text and 10 MiB PDF per-file limits. Metadata and actual streamed bytes
are checked; malformed UTF-8, empty, unsupported, oversized or unreadable input
rejects the entire new selection, leaving existing drafts unchanged. Picker cache
cleanup must be confirmed on mobile before accepting that selection. Providers
may download or cache data before checks, and the limits are not a hard RAM/CPU
sandbox; base64 and decoded representations have additional memory overhead.

Selection does not preview, stage or save. The user explicitly opens each file
and uses the existing independent review and durable-save approval. A saved item
is deliberately not removed from the batch automatically; the user discards its
temporary draft when ready, individually or with a separate discard-all
confirmation. Discard-all applies to the displayed snapshot only and does not
delete saved originals or approved jobs. Edits in the review screen do not change the queued
original. The queue is lost when the process ends and is not secure erasure of
memory, provider caches or backups. No app-level encryption or automatic recovery
is claimed. This is file selection, not recursive folder import or unsupported
original-only saving.

Tests cover bounded multi-selection, byte identity, atomic rejection, cache
cleanup, explicit item navigation and discard. Real platform picker/provider,
large-library performance, memory exhaustion, accessibility, lifecycle and
physical-device testing remain outstanding. CI evidence must be checked before
claiming the new tests passed.

Individual batch-draft discard now asks for confirmation, as bulk discard
already did. Declining leaves the draft untouched. This only removes the
in-memory draft, not saved originals or approved jobs; it is not secure erasure.
