# REFRACT Android v1 — coding-session handoff

This report is a handoff, not a release sign-off. It records the user's latest
v1 decisions, the implemented baseline, outstanding work, validation evidence,
and a concrete starting point for the next session. Read the repository and
current CI state again before making changes; older status documents describe the
state at their own date, not necessarily the latest implementation.

## 1. User objective and binding decisions

The user wants the **complete v1 product**, not a stream of tiny improvements
that are represented as closed roadmap areas. They selected:

- **Android first.** iOS and desktop are deferred for v1, not declared finished.
- **Capture:** the existing capture baseline, plus on-request OCR and an
  original-layout PDF view with extracted text separate.
- **Data protection:** both full encrypted backup/restore and app-level library
  encryption, including keys, recovery and migration.
- **Optional capabilities required for v1:** downloaded AI models,
  collaboration, provider connections, opt-in filtered Android notification
  capture, and advanced provenance. The user selected *all*, not a deferral.

These choices enlarge v1 substantially. They do not authorize automatic model
or resource downloads, broad permission grants, automatic collection, cloud
uploads, or bypassing per-use consent. Continue the prior local-first,
capture-first, explicit-review/save, original-preservation and evidence-labeling
requirements. Do not infer personal beliefs or identity from reading behavior.

Earlier directions also call for language resources explicitly chosen and
obtained in settings; OCR initially runs on request, and any online OCR provider
requires separately informed per-use consent. Users should control backup
secrets and destinations; restoration must preview its strategy and must not
silently replace the current library. Explain that losing secrets can make data
unrecoverable. Platform-protected unlocking versus app passphrase remains a
specific design choice, not an implemented feature. See
[direction decisions](24-open-work-direction-decisions.md) and
[Android v1 scope](47-android-v1-scope.md).

Exact models, model licensing and runtime, named providers, OCR engines and
languages, integration scopes, encryption/key design, backup coverage, restore
strategy, provenance trust model, and measurable acceptance thresholds remain
unresolved. Make sound, explicit engineering choices within the user's direction;
ask the user when a consequential product or trust choice cannot reasonably be
inferred. Do not present a scope decision as a completed implementation.

## 2. Repository and current evidence

- Repository: `m-cyber12/Refract`, workspace `/home/user/Refract`.
- Work at the time of this report is on `arena/04fef284-refract`, originally
  branched from `93ac3040d4a51a6e4424c30d7ee5511906cd3fe5` of `main`.
- Latest code commit before this report: `c8cfaea` (separate PDF views). Earlier
  relevant commits: `6eba82b`/`f400fc2` (Android PDF page rendering and type
  fix), `21e76b1` (v1 scope and partial JSON export consent), `90a5f96` and
  `8535f42`/`d5db5da` (library and search pagination), and `4a509ca` (INI
  intake, PDF labeling and native-scaffold guard). The report itself may be in
  a later documentation commit; inspect `git log`, `git status`, and the latest
  branch note in the new session rather than assuming the HEAD is unchanged.
- At `c8cfaea`, all five GitHub workflows succeeded: Rust
  [43449265156](https://github.com/m-cyber12/Refract/actions/runs/43449265156),
  Flutter [43449265310](https://github.com/m-cyber12/Refract/actions/runs/43449265310),
  Android emulator [43449265250](https://github.com/m-cyber12/Refract/actions/runs/43449265250),
  docs [43449265286](https://github.com/m-cyber12/Refract/actions/runs/43449265286),
  and unsigned iOS [43449265363](https://github.com/m-cyber12/Refract/actions/runs/43449265363).
  These are CI results for that commit, not production validation. Check later
  commits' runs independently. Android is an emulator, iOS is unsigned.
- This coding environment has historically lacked locally installed Rust and
  Flutter SDKs. CI runs full checks. Flutter CI is pinned to 3.44.9; do not
  silently change the SDK pin. `git diff --check` and available small scripts
  can still be run locally.

## 3. Implemented capture and reader baseline

- Explicit text, Markdown, HTML, PDF and URL-reference capture; strict UTF-8
  text intake up to 2 MiB and PDFs up to 10 MiB. Pickable text formats include
  TXT, LOG, INI, CSV, TSV, JSON, XML and YAML/YML as **unparsed plain text**;
  Markdown/HTML use their lightweight parsers. Unedited text preserves BOM and
  line endings in the stored original. The parser/reader normalizes derived
  text. No universal format support, structured validation or redaction claim.
- Each item gets a separate preview and save approval. The review binds input,
  format and source URL; duplicate reuse/keep-copy is explicit. Originals are
  stored separately and verified by size and SHA-256 for approved reads/reuse.
  The hash is a consistency check, not authenticity or a complete filesystem
  security boundary. A different input for the same address remains separate.
- Bounded per-item batch drafts, maximum 16 files and 24 MiB, are temporary
  process memory; items require independent review. Picker streams have bounded
  reads and best-effort timeouts/cleanup; provider and OS caches may persist.
  Approved durable capture jobs can be recovered or explicitly canceled, but
  interruption does not prove a hard cleanup or power-loss guarantee. Job status
  queries avoid loading payloads and retry input is bounded at 16 MiB.
- Android sharing uses temporary, bounded process-memory drafts before review;
  unreviewed shares may be lost on process death. The iOS explicit handoff
  staging design exists but is deferred for v1. Physical provider, lifecycle,
  signing and lock-state validation remain open.
- Static web capture is explicitly initiated, staged separately from library
  save, subject to host/IP/DNS/redirect/HTTP policies and visible approvals.
  Tests include deterministic mocked fetch-to-save, not full hostile-network or
  physical-device evidence. DNS uses bounded workers, but blocking OS resolver
  calls cannot necessarily be canceled. The Firefox URL-only prototype is not
  verified on a physical browser/device.
- PDF extraction is bounded and warns about pages with no extractable text.
  Original-only PDF saving is an explicit separate mode with its own review;
  it does not validate the file or produce OCR/searchable text. Export of a PDF
  original requires consent and destination selection. PDF size/page/content
  caps are **not** parser isolation or hard RAM/CPU/time limits.
- Android now offers original layout first and separately selected extracted
  text. Following a specific evidence block opens text view. Original rendering
  requires explicit consent, verifies stored original bytes, uses Android
  `PdfRenderer`, and renders one bounded page at a time. The app uses a private
  temporary cache file unlinked before parsing; process death before unlink can
  leave a copy. Deletion is not secure erasure. Platform parsing is not an
  app-controlled sandbox and has no hard timeout or memory guarantee. No OCR,
  password handling or signature/authenticity verification is implied. See
  [PDF layout details](48-android-pdf-layout.md).
- Capture warnings are shown during review; many are not persisted as durable
  reader annotations. Inspect the individual capture documents in `docs/phase-0`
  before changing retention, review, duplicate or handoff behavior.

## 4. Other implemented increments and their limits

- Library browsing and full-text search have bounded 50-item pages plus one
  lookahead. A stable `(import_ts, id)` order is used, but offset pages are not
  a snapshot: concurrent insertions/deletions can cause skips/repeats. Queries
  still run synchronously through the Dart-side repository. Legacy search API
  remains capped at 100 results. Scale measurements/background work are open.
  See [pagination](46-library-pagination.md).
- The legacy settings JSON action is now explicitly confirmed and labeled
  **partial, plaintext, not a backup**. It includes up to 10,000 items with
  extracted blocks plus tag/collection lists, omits original files and other
  library data, and overwrites its prior local JSON copy. It is not encryption,
  full restore, secure erasure or a replacement for B1/B2.
- Existing deterministic analysis, memory, signal, knowledge and manual
  collaboration/integration foundations are not proof that the selected advanced
  v1 capabilities are complete. For example, existing Multiplayer Margins
  limitations include manual foreground exchange and private keys in the local
  database; it is not a reviewed direct/relay production collaboration system.
  A selected email-copy flow is not a provider account connection.
- CI scaffolds Android/iOS platform project shells using Flutter; guards check
  that tracked integration files were not overwritten. This is **not** a
  committed, maintained, reproducible native-project migration. Android v1
  requires that work; iOS production project/signing is deferred.

## 5. Outstanding v1 work, grouped by area

The prior inventory described 23 labeled areas with some remaining work, plus F2
as the desktop-priority direction. That is not a precise count of individual
engineering tasks, and the number should not be decremented because a small
increment landed. Some inventory text predates the latest PDF viewer or search
pagination; use this report and the linked newer documents for current details.

1. **A1–A5 capture:** finish Android real-provider/share/picker and lifecycle
   handling and physical validation; real approved web fetch and hostile
   DNS/redirect/TLS/VPN validation; settle supported file/folder scope and
   original-only options. A4 browser handoff beyond the prototype remains open.
2. **A6 OCR:** implement separately requested local OCR and the separately
   selected, separately consented online option per prior direction; language
   resources, provider handling, limits, provenance of derived output, errors,
   lifecycle and security are not implemented.
3. **A7–A10:** harden original PDF layout, separation and accessibility; research
   local PDF passwords without storing them by default; isolate untrusted
   parsing with defensible resource controls; improve consented quick capture and
   any explicitly enabled pre-storage screening. A platform PDF render is not
   itself parser isolation.
4. **B1–B4:** design, implement and test full encrypted backup/restore and
   library encryption, secrets/recovery/migration and crash/data-loss behavior;
   maintain Android native project/build/signing configuration. Security review,
   physical-device, accessibility, lifecycle and performance gates are mandatory.
5. **C1–C3 / D1–D2:** measured large-library operation, background work and
   robust pagination; optional explicitly downloaded embeddings/generated
   answers, evidence links and deterministic fallback; reviewed extraction,
   timeline, knowledge and individually confirmed reminder/calendar flows.
6. **E1–E3:** selected-material collaboration with explicitly chosen direct or
   relay transport and secure keys; narrow individually authorized provider
   connections; opt-in filtered Android notification listener and review before
   capture. No permission or connector is enabled merely by the scope decision.
7. **F1–F2:** evaluate trusted timestamps and C2PA for the selected advanced
   provenance scope; research TLSNotary/zkTLS separately with accurate trust
   assumptions. None proves factual truth. Desktop is deferred for v1.

Independent security review, signed Android builds, actual devices/providers,
accessibility and performance, release/privacy disclosures, and release
approval are external gates. Passing CI is not a substitute. Do not claim all
areas complete or ready for a wider release while these remain open.

## 6. Recommended continuation

1. Confirm the latest branch note and inspect `git status`, `git log`, current
   CI and the files below. Avoid claiming the work is done based on this report.
2. Work capture-first on the v1 requirements. Define a concrete vertical slice
   with acceptance criteria and implement it end to end, including privacy,
   recovery and tests. The next especially consequential work is an Android OCR
   design/implementation with explicit resources and derived-text labeling, and
   hardening/isolation of the existing PDF reader. The exact OCR engine and
   language/download mechanism have not been selected.
3. In parallel planning, establish a threat model and testable design for B1/B2
   before building cryptography. Full backup requires original files and relevant
   library data, authenticated encryption, bounded and validated restore,
   interruption and migration handling, key recovery, no silent replacement, and
   external review. Do not substitute the existing partial JSON export.
4. Implement the chosen optional capabilities with separate consent and a real
   provider/model selection, rather than merely surfacing placeholder toggles.
5. Verify CI for each code increment, document genuine limitations and keep the
   user informed of which selected requirements remain incomplete. Carry out
   signed device tests and independent review when resources are supplied.

A new session may receive a different current-branch instruction from its own
system context. Follow that session's current branch and restrictions rather
than switching branches based solely on this historical report.

## 7. Relevant files

- `docs/phase-0/24-open-work-direction-decisions.md`, `43-remaining-work-inventory.md`,
  `47-android-v1-scope.md`, `48-android-pdf-layout.md`: prior directions,
  inventory, v1 scope and PDF design/limitations.
- `crates/document_parser/src/`, `crates/content_compiler/src/`,
  `crates/personal_memory/src/capture/`, `crates/personal_memory/src/web_previews.rs`:
  parsing, compilation, originals, capture jobs and web previews.
- `crates/platform_bridge/src/`, `apps/mobile/lib/core/{ffi.dart,repository.dart,library_refresh.dart}`:
  Rust ABI, Flutter bindings, repository and refresh invalidation.
- `apps/mobile/lib/features/import/`, `apps/mobile/lib/features/reader/`,
  `apps/mobile/lib/features/library/`, `apps/mobile/lib/features/settings/`:
  reviewed capture, PDF views, paging and partial JSON UI.
- `apps/mobile/android/app/src/main/kotlin/dev/refract/{MainActivity.kt,PdfPageRenderer.kt}`:
  Android sharing and bounded original PDF page rendering.
- `apps/mobile/test/{pdf_layout_test.dart,pdf_views_test.dart,pdf_reader_notice_test.dart,original_export_test.dart,library_pagination_test.dart,settings_export_test.dart}`:
  targeted widget and flow tests. `apps/mobile/test/capture_native_test.dart`
  exercises the real host FFI when CI provides the native library.
- `.github/scripts/test_android_shares.py` and `.github/fixtures/android-share/`:
  synthetic real emulator handoff and PDF-layout flow. `.github/workflows/`
  contains Rust, Flutter, emulator and unsigned iOS checks.
- `crates/personal_memory/src/{integrations,margins,knowledge,provenance.rs}`,
  `crates/{crypto_provenance,sync_engine,ai_runtime}/`: existing foundations;
  inspect their documented security and availability limitations before reuse.
