# REFRACT — Phase 0 output: Detailed Phase 1 MVP Plan (Reality Compiler MVP)

Scope per spec §13 Phase 1 (est. 3–5 weeks for a small team). Goal: one complete,
polished, demonstrable journey — **Import → Transform → Understand → Organize → Retrieve**.

## 1. Phase 1 scope (in)

1. **Flutter foundation** — app bootstrap, GoRouter, Riverpod, design system v1
   (Obsidian/Graphite palette, prism mark, Inter/Manrope + serif reading font + mono).
2. **Rust core PoC → real pipeline** — FFI bridge, `content_compiler` + `document_parser`
   for HTML/text/Markdown/PDF, allowlist sanitizer, metadata extraction.
3. **Intake** — Android Share Intent + iOS Share Extension for URLs; in-app paste text;
   file import via SAF/document provider (PDF, HTML, txt, md).
4. **Storage** — SQLite schema v1 (Item, Blob, Block, FTS5 index), migrations,
   original blob + SHA-256 preserved untouched alongside transformed representation.
5. **Reader** — Clean Reader mode with typography controls, reading progress,
   source/provenance panel (original URL, import time, hash, confidence).
6. **Library** — list of imported items, filters, import history, processing status.
7. **Search** — FTS5 full-text over extracted text + metadata.
8. **"Refraction Transition"** — real staged processing indicator (acquire → extract →
   sanitize → structure → store → render), honest completion/failure states.

## 2. Phase 1 scope (out — explicitly deferred)

Local AI, semantic search, annotations/CRDT/sync, X-Ray/Vault, Daily Edition,
notifications, encrypted storage, any network sync, WebView browsing mode.

## 3. Work breakdown

| # | Workstream | Key deliverables | Depends on |
|---|---|---|---|
| 1.1 | Repo + CI bootstrap | workspace layout, `rust.yml`, `flutter.yml`, branch rules | — |
| 1.2 | Design system v1 | tokens (colors per spec §8.2), typography, prism logo, theme | 1.1 |
| 1.3 | Rust core skeleton | `refract_core` C ABI, error type, ABI version check, FFI smoke test | 1.1 |
| 1.4 | DB layer | migrations v1, Item/Blob/Block/FTS5, contract tests | 1.3 |
| 1.5 | Compiler pipeline | parsers (HTML/text/md/PDF), sanitizer, metadata, confidence | 1.3 |
| 1.6 | Flutter app shell | router, home/library/reader routes, Riverpod wiring to FFI | 1.2, 1.3 |
| 1.7 | Intake (native) | Android share intent, iOS share extension, SAF import | 1.6 |
| 1.8 | Reader + Library UI | clean reader, progress, provenance panel, library, search | 1.4–1.6 |
| 1.9 | Refraction transition | staged processing UX bound to real pipeline events | 1.5, 1.6 |
| 1.10 | Polish + tests | unit/integration/UI tests, offline verification, perf pass | all |

## 4. Acceptance criteria (from spec §13, verbatim intent)

- A user can share an article into REFRACT (Android + iOS).
- The article is converted into a readable representation (Clean Reader).
- The original source is preserved (immutable blob + hash + URL).
- Content remains available **offline**.
- The user can search imported content locally.
- The app works with **no AI and no cloud account**.
- No fake progress: processing stages shown are real.
- 60 FPS navigation, non-blocking extraction, measured startup time.

## 5. Testing plan for Phase 1

- **Unit (Rust):** extraction, sanitizer, metadata, hashing, migrations, FTS queries.
- **Contract tests:** Dart↔Rust FFI calls against `shared/api_contracts` fixtures.
- **Integration:** share-sheet flow end-to-end on emulator/simulator, PDF import, offline reopen.
- **UI (Flutter integration_test):** import → reader → library → search navigation, themes, a11y.
- **Reliability:** interrupted import, malformed HTML/PDF, storage pressure, app suspension.

## 6. Risks (top Phase 1 entries — full register in `docs/phase-0/05-risk-and-quality.md`)

- Rust↔Flutter FFI ergonomics slow development → keep ABI surface tiny, invest in contract tests early.
- PDF extraction quality varies → memory-bounded parser, honest confidence labels, graceful fallback to raw text.
- iOS share extension build complexity → prototype in Phase 0 week 1, before UI work.
