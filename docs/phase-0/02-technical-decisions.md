# REFRACT — Phase 0: Technical Decision Records (ADRs)

## ADR-001 — Flutter as the UI framework
**Decision:** Flutter/Dart with Material 3 as a *foundation*, extended by a custom
"Prismatic Intelligence" design system. Riverpod for state, GoRouter for navigation.
**Why:** Single codebase for Android+iOS, strong performance, mature share-sheet and
platform-channel ecosystem. Spec mandates it.
**Consequences:** Native modules still required for share extensions, background work,
keystore; we accept that boundary rather than fighting it.

## ADR-002 — Rust as the shared domain core
**Decision:** All parsing, extraction, sanitization, hashing, search indexing, CRDT and
sync protocol logic lives in Rust crates behind a stable C ABI; Dart reaches it via FFI.
**Why:** Performance, memory safety, testability, and reuse across Kotlin/Swift later.
**Consequences:** FFI boundary must be small, versioned, and panic-free; build complexity
(Rust toolchains per target) is handled in CI.

## ADR-003 — UniFFI for native bindings where needed
**Decision:** Use UniFFI-generated Kotlin/Swift bindings for Rust modules that native code
must call directly (initially: sync engine). Do **not** assume UniFFI covers Dart — Dart
uses hand-written FFI against the C ABI.
**Why:** Keeps one source of truth for domain logic.

## ADR-004 — SQLite as the sole primary datastore
**Decision:** SQLite (via `sqlx`/`rusqlite` in Rust) with FTS5 for full-text search and
optional sqlite-vec for embeddings. DuckDB only for optional analytics, never transactional.
**Why:** Local-first, offline, zero-server, inspectable by the user (sovereignty), mature
migration tooling. Encryption of sensitive tables via SQLCipher-style extension later.

## ADR-005 — Modular monolith, not microservices
**Decision:** One Flutter app + one Rust core, logically split into crates/features as
listed in the spec. No network services in the MVP.
**Why:** Team size, latency, privacy, and the local-first principle all favor in-process.

## ADR-006 — Local-first AI, strictly optional
**Decision:** AI capabilities sit behind an `ai_runtime` abstraction (llama.cpp / ONNX
Runtime / future platform backends). No model is downloaded by default; every AI output is
labeled as interpretation with source references where possible.
**Why:** Privacy by architecture + graceful degradation.

## ADR-007 — CRDT choice deferred between Loro and Automerge
**Decision:** Phase 5 evaluation spike; interface behind `sync_engine` trait so the choice
is swappable. Not needed for Phase 1.
**Why:** Avoid premature commitment; both are viable.

## ADR-008 — HTML sanitization and safe document processing
**Decision:** Imported HTML is parsed and re-serialized through an allowlist sanitizer in
Rust; scripts never execute; PDFs processed memory-bounded. WebView (when used) is
configured with JS disabled for untrusted content unless explicitly scoped.
**Why:** Malicious imported documents are a named threat.

## ADR-009 — Evidence model: hash ≠ authenticity
**Decision:** Proof Vault stores SHA-256 hashes and an append-only log. UI copy and docs
must state precisely what each check proves (integrity since hashing) and what it does
not (origin authenticity, legal validity). TLSNotary/zkTLS are research modules only.
**Why:** Evidence-over-confidence principle; avoids overclaiming.

## ADR-010 — Platform constraints are features, not obstacles
**Decision:** Android uses Share Intents, SAF, WorkManager, notifications, WebView.
iOS uses Share Extension, document providers, BackgroundTasks, App Groups. No
AccessibilityService scraping, no VPN-based content access, no sandbox bypasses.
**Why:** Platform honesty; store approval and longevity.

## ADR-011 — CI/CD via GitHub Actions
**Decision:** GitHub Actions pipelines for: Rust `cargo test/clippy/fmt` on all targets,
Flutter `analyze`/`test`, Android & iOS builds on tags, artifact signing for releases,
docs checks. Branch protection on `main`; PRs required.
**Why:** User explicitly wants Actions for builds; keeps releases reproducible.

## ADR-012 — No telemetry by default
**Decision:** Zero analytics in code. If ever added, opt-in, minimal, privacy-preserving,
and never includes document contents.
**Why:** Privacy by architecture.
