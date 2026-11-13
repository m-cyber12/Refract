# REFRACT — Phase 0: Product Foundation & System Architecture

Status: Phase 0 deliverable (documentation only — no application code yet)
Date: 2026-11-06
Source spec: `Refract.md` (master product/design/engineering prompt)

---

## 1. What REFRACT is (one paragraph)

REFRACT is a **Sovereign Client Runtime**: a privacy-first, local-first, cross-platform
personal environment that takes fragmented digital input (URLs, PDFs, text, receipts,
contracts) and "refracts" it into structured, searchable, verifiable, user-controlled
information — with provenance preserved and AI assistance strictly optional and local.

It is **not** another RSS reader, chatbot, or note app. The prism metaphor drives both
the brand and the architecture: raw input enters, and REFRACT separates it into
meaningful, labeled layers (evidence vs. extraction vs. AI interpretation).

## 2. Product principles → architectural consequences

| Principle | Architectural consequence |
|---|---|
| Local-first | SQLite is the source of truth; cloud sync optional, never required |
| Privacy by architecture | No telemetry by default; AI inference on-device only; explicit consent gates |
| User sovereignty | Open export formats, inspectable DB, no mandatory proprietary cloud |
| Progressive intelligence | Deterministic parsing/rules first; local models behind an abstraction layer, fully optional |
| Evidence over confidence | Every AI/extracted claim carries a type label + source reference |
| Graceful degradation | Every subsystem has a no-AI / offline / no-network path |
| Platform honesty | Only OS-sanctioned integration surfaces (share sheets, SAF, WebView, BackgroundTasks) |

## 3. System context

```
                 ┌──────────────────────────────────────────────┐
                 │              REFRACT client (per device)     │
   Share Sheet / │  ┌────────────┐   ┌──────────────────────┐  │
   Share Ext ───►│  │ Flutter UI │──►│  Rust core (FFI)     │  │
   Files/SAF ───►│  │ Riverpod   │   │  compiler · search   │  │
   Clipboard ───►│  │ GoRouter   │   │  evidence · sync     │  │
                 │  └─────┬──────┘   └──────────┬───────────┘  │
                 │        │ FFI / platform chan. │              │
                 │  ┌─────▼──────┐   ┌──────────▼───────────┐  │
                 │  │ Kotlin/Swift│   │  SQLite + FTS5       │  │
                 │  │ native mods │   │  blob store + hashes │  │
                 │  └─────────────┘   └──────────────────────┘  │
                 └──────────────────────────────────────────────┘
                              │ optional, E2E-encrypted, user-initiated
                              ▼
                    ┌──────────────────┐     (Phase 5+)
                    │ P2P / relay sync │
                    └──────────────────┘
```

Out of scope by design: intercepting other apps' traffic or DOM, AccessibilityService
content scraping, automatic subscription cancellation, mandatory cloud, mandatory LLMs.

## 4. Component architecture (modular monolith)

Three product systems sharing one core, per the spec:

- **System A — Reality Compiler**: intake pipeline → extraction → sanitization →
  metadata → normalization → storage → reader rendering.
- **System B — Consumer X-Ray & Proof Vault**: subscription records, purchase/contract
  analysis, append-only evidence store with hashes, subscription calendar.
- **System C — Multiplayer Margins**: annotations with persistent anchors, CRDT
  collaboration, opportunistic P2P sync.

Shared intelligence layer: SQLite FTS5 + optional vector search, optional local AI
(llama.cpp / ONNX Runtime via abstraction), resource-aware inference.

### Layer responsibilities

| Layer | Technology | Owns |
|---|---|---|
| UI | Flutter (Dart), Material 3 base + custom design system, Riverpod, GoRouter | Screens, navigation, state, theming |
| Domain/systems core | Rust crates, C ABI via Dart FFI (+ UniFFI for Kotlin/Swift where suitable) | Parsing, extraction, sanitization, hashing, search index, CRDT, sync protocol |
| Platform glue | Kotlin (Android), Swift (iOS) | Share intents/extensions, SAF/documents, WorkManager/BackgroundTasks, notifications, WebView, Keystore/Keychain |
| Persistence | SQLite (+FTS5, optional sqlite-vec), file blobs with SHA-256 | All local state, migrations, evidence integrity |
| Sync (later phases) | Loro or Automerge CRDT, WebRTC/iroh, relay | Collaboration only — never required for core use |

### Data flow (core journey: Import → Transform → Understand → Organize → Retrieve)

1. Native share sheet/extension or in-app import hands URL/text/file to Flutter.
2. Flutter passes the input to the Rust core over FFI (isolate-safe, non-blocking).
3. Rust pipeline: acquire → extract → sanitize → metadata → structure → classify noise → normalize.
4. Original representation stored as an immutable blob + hash; transformed representation stored as structured rows.
5. SQLite is updated transactionally; FTS5 index updated in the same transaction.
6. UI observes via reactive queries (Riverpod streams over a thin DB-access FFI surface).
7. Reader renders the transformed representation; every derived/AI layer is labeled.

## 5. Core data model (high level)

- `Item` (id, source_url, source_type, import_ts, content_hash, title, author, language, extraction_confidence, status)
- `Blob` (item_id, kind: original|transformed, path, sha256)
- `Block` (item_id, type: heading|paragraph|image|list|table|quote, order, text, attrs)
- `Annotation` (id, item_id, anchor, quote, note, visibility, crdt_doc_id)
- `Subscription` (id, service, plan, price, currency, frequency, renewal_date, trial_end, status: confirmed|imported|suspected|unverified, confidence)
- `EvidenceRecord` (id, kind, blob path, sha256, imported_ts, claims[] each linked to evidence offsets)
- `Anchor` (content_hash, quote, prefix, suffix, heading, version, rel_position, url)

Full schema lands in Phase 0 doc `04-database-schema.md` (DDL + migration policy).

## 6. Cross-language contract strategy

- Rust core exposes a **stable, versioned C ABI** (`refract_core` crate, `platform_bridge`).
- Dart consumes it via `dart:ffi`; calls run on background isolates; no UI blocking.
- Kotlin/Swift native modules use UniFFI-generated bindings where a Rust feature needs
  native access (e.g., sync engine), otherwise communicate via platform channels.
- Every FFI function returns a structured `RefractResult<T>` (ok/err), never panics across the boundary.
- Contract tests live in `shared/api_contracts` + `tests/`.
