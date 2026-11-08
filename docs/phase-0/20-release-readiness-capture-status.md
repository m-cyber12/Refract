# Release-readiness increment — capture integrity

This is **not a new numbered roadmap phase or a production-readiness sign-off**.
It follows completed Phase 9 and addresses reproducible capture/storage defects
against the master specification's §24 test matrix. Live provider integrations
remain disabled/research-only. No telemetry, fetch client, credentials, listeners
or new background service is introduced.

## Implemented scope

- Fix compiler dispatch: binary PDFs no longer pass through a UTF-8 decoder.
  Resolve valid inherited inline PDF resource dictionaries for lopdf 0.34's
  extraction path without changing original bytes. Only text inputs require UTF-8; reject NUL/binary-as-text and empty extraction.
  Original bytes and SHA-256 stay separate from normalized reader text. A UTF-8
  BOM is ignored for parsing but remains in the captured original.
- Explicit plain text / Markdown / HTML / PDF / URL-reference capture. Angle
  brackets do not guess HTML. URL references have a distinct persisted
  `url_reference` source kind and visible not-fetched wording in the reader.
  Validate HTTP(S), host, port, whitespace, backslashes and credentials without
  resolving hosts or fetching anything. Source URLs are supplied, not verified.
- One selected TXT/MD/HTML/PDF file, with metadata and actual-byte stream limits;
  reject unsupported, empty, unavailable-stream or invalid UTF-8 files. No scan
  of other files. Request mobile picker temporary-copy cleanup on success,
  cancel and errors; unconfirmed cleanup blocks acceptance. Original selected
  files are not deleted. OS/provider caching can precede app limits; cleanup is
  neither secure erasure nor control of provider caches or memory copies.
- Local preview with extracted excerpt, byte count, hash, format and warnings.
  Preview does not persist source content. Saving requires a binding to the
  exact bytes, chosen parser and source address; edits invalidate the preview.
  The binding is local consistency, not independent authenticity or trusted time.
- Exact duplicate matching on original hash, parser/source kind and source URL.
  Explicit use-existing or keep-separate-copy actions; no overwrite or merge.
  Reuse verifies the retained original bytes still match. An immediate SQLite
  transaction serializes ordinary-save duplicate checks across connections;
  a competing save fails for re-review rather than silently adding a copy.
  Legacy direct import ABI calls remain compatible and may intentionally save
  additional copies; duplicate review applies to the new capture flow.
- Different supplied input for the same address is a separate capture, retaining
  prior originals and explicit user organization. This does **not** prove that a
  remote webpage changed; remote pages are not fetched or compared here.
- Exclusive-create originals (0600 on Unix), file/directory sync before SQL
  publication, SQL rollback and best-effort cleanup of newly created blobs on ordinary
  write/transaction errors. Duplicate item IDs cannot truncate retained files;
  unsafe file identifiers are rejected. Migration 14 adds lookup indexes only.
- Capture FFI runs on a Dart worker isolate with its own store handle/connection,
  SQLite WAL and a five-second busy timeout. No native pointer crosses isolates.
  This improves UI-thread responsiveness, not process isolation or durability of
  a draft. Shared projection invalidations cover library/search/memory/Signal/
  X-Ray/knowledge views after capture.
- Shares actually delivered to the existing Dart method channel open a review
  draft instead of auto-saving or claiming success before bootstrap. Source text
  stays out of route URLs. A second share during an open capture is explicitly
  rejected with a re-share instruction, not silently substituted or queued.
- HTML extraction excludes blocked descendants, including scripts nested inside
  paragraphs and paragraphs nested in navigation/hidden containers; nested
  quote/code/list text is not duplicated. Bare main/body text and `og:title`
  metadata are supported. Original HTML can still contain sensitive scripts and
  metadata: it is retained unchanged, never executed or fetched by this parser.
- Reject PDFs over 200 pages or with a known page-extraction failure, rather than
  silently truncating or skipping failed pages. Encrypted PDFs are unsupported.
  Input limits: PDF 10 MiB, text 2 MiB; extracted text 2 MiB / 20,000 blocks,
  decoded PDF page content 16 MiB. Check unfinished/nested PDF text objects;
  the upstream decoder can otherwise accept a valid prefix of a broken stream.
  Ordinary PDF parser panics become errors, not a resource sandbox.

- Packaging checks now fail on missing required Rust ABI entries or wrong ELF
  architectures; an echoed error is no longer treated as a successful gate.

## Validation

Pending source validation; replace this section with actual CI results once
available. Local tree-sitter syntax checks and SQLite migration exercises are
supplemental only; the authoring sandbox has no Rust or Flutter SDK.

Regression coverage added:

- Synthetic binary/Flate-compressed PDF compiler, store/restart and legacy ABI
  roundtrips; 201-page rejection and corrupt-second-page no-partial-save test.
- Explicit formats, strict URL validation, empty/unsupported/binary-as-text input,
  BOM preservation, preview-without-persistence, changed-review rejection,
  duplicate choices, missing/damaged existing original, competing connections,
  same-address capture preservation, duplicate-ID non-overwrite, simulated SQL
  failure cleanup, and migration 13→14/reopen preservation.
- Picker actual-byte caps/UTF-8/failure/cancel/cache-cleanup cases; widget capture,
  review invalidation, duplicate choice, selected format, error retention and
  disposal regressions. Real host Dart FFI worker roundtrip is a separate CI step
  after building the Rust library, not a fake-repository test.

## Remaining release gates — not claimed complete

1. **Durable intake/jobs:** no persisted draft/queue, restart retry, background
   completion or automatic recovery of a killed process. A kill between file
   creation and SQL commit, or failed filesystem cleanup, can leave an orphan original. No automatic deletion
   or recovery of such files is attempted. Ordinary error rollback/restart of
   committed captures is not a power-loss or process-kill guarantee.
2. **Hostile parser isolation:** lopdf loads object graphs and decompresses streams
   before some output limits can be checked. Size/page caps and a Dart isolate
   do not cap native RAM/CPU or contain allocation failure/stack overflow/abort.
   Need adversarial corpus, measured budgets and a platform-appropriate strategy.
3. **PDF fidelity:** no OCR, scanned-page completeness, layout/image rendering,
   password support, signature verification or comprehensive PDF compatibility.
   Text-object checks are conservative, not complete syntax/semantic validation;
   upstream handling of malformed/unsupported streams needs further auditing.
   Scanned portions of a mixed PDF may be absent in reader text; the original
   remains separate. Confidence is heuristic, not factual completeness.
4. **OS capture:** this repository does not implement/test a native Android share
   receiver or iOS extension/cold-start handoff end-to-end. The Dart channel alone
   is not evidence of working OS share capture; late/unobserved shares can be
   missed. No URL acquisition, redirects, offline fetch retry, deduced publication
   date or remote changed-webpage detection is provided.
5. **Privacy/security:** library SQLite, WAL and original blobs are not encrypted
   by this app; rely on OS app-storage protection, not a new cryptographic claim.
   HTML originals and URL query parameters can be sensitive. Picker/provider
   caches, memory copies, backups and logs need device/security review. No secure
   deletion, screenshot prevention or broad retention guarantee is established.
6. **Real platforms/UX:** host FFI tests and Android launch/native-load smoke are
   not physical-provider picker/cleanup tests, mid-save kill/background tests,
   accessibility, latency/RAM measurements, iOS validation or a security audit.
   Derived analyses remain best-effort after original publication; their failure
   does not remove the retained source or make an interpretation verified.

7. **Portable originals:** Settings currently exports up to 10,000 items with
   reader blocks, tags and collections as JSON (`memory.rs::export_all`), not
   original blob bytes or a full restorable database. Do not treat that export as
   a complete source backup. Original-file export/restore and full backup coverage
   remain separate work, not supplied by this capture integrity increment.

Next priority: durable capture staging, interruption tests and explicit recovery
states, followed by physical-device/provider and adversarial parser testing.
