# A5 — UTF-8 log intake

The file picker accepts `.log` as plain UTF-8 text, not as a structured or
verified log format. It uses the existing 2 MiB per-file limit, batch limit,
provider cleanup and separate preview/save approval. Unedited input retains its
UTF-8 bytes, including a BOM and line endings; edits become the saved original.
The filename and log format are not retained as original-format metadata.
Invalid UTF-8 is rejected. No automatic redaction or secret detection is claimed.
The review screen warns that logs can contain credentials and personal information.

Android handoff recognizes a `.log` extension where the sender's MIME type is
already accepted (such as `text/plain`); iOS recognizes it on the existing file
URL and plain-text paths. This does not promise that arbitrary log MIME types or
all providers will offer the file. Tests use synthetic picker and provider input;
physical devices, provider caching, lifecycle and accessibility remain release
gates. Storage is not claimed to have app-level encryption, and deletion is not
secure erasure.
