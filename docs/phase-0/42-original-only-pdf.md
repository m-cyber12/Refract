# Explicit original-only PDF capture

A selected PDF candidate can be captured in the separately chosen **PDF original
only** mode. Preview and durable-save approval remain separate. The app retains
at most 10 MiB of selected bytes unchanged, without opening or validating them
as PDF. It extracts no text, runs no OCR, and creates no searchable content.
The reader labels this and provides the existing separately consented original
export. A file chosen as a PDF may be invalid, encrypted, malicious or contain
private metadata; neither format validity nor authenticity is asserted.

This mode is never an automatic fallback after parser failure. Its review
binding differs from text-extraction mode, preventing one mode's review from
approving the other. An existing copy with the same bytes and source address
may have been processed differently; users explicitly choose reuse or a separate
copy. Shared handoff cleanup still requires the exact original bytes to be saved.
The original is not app-level encrypted and logical deletion is not secure
erasure. OS providers may retain copies. Existing capture-job recovery rules
and explicit consent apply; no OCR, layout viewer or password handling is added.

Tests exercise no-save-before-review, mode binding, textless fixture, durable
job, zero text blocks and byte-exact original retrieval. Real devices, external
viewers, provider behavior and security review remain release gates.
