# REFRACT

**Your personal runtime for understanding and controlling the digital world.**

REFRACT is a privacy-first, local-first, cross-platform *Sovereign Client Runtime*.
It takes fragmented digital input — shared URLs, PDFs, receipts, notes — and
refracts it into structured, searchable, verifiable, user-controlled information,
with provenance preserved.

## Architecture in one line

Flutter UI → Rust domain core (stable C ABI / FFI) → Kotlin & Swift native glue →
local SQLite (FTS5) as the source of truth. No mandatory cloud, no telemetry,
AI optional and on-device.

## Layout

- `apps/mobile/` — Flutter app (design system + features)
- `crates/` — Rust workspace (`refract_core`, `content_compiler`, `document_parser`,
  `personal_memory`, `platform_bridge`)
- `shared/schemas/migrations/` — SQLite schema, versioned
- `docs/phase-0/` — architecture, ADRs, repo/dependency strategy, Phase 1 plan, risks
- `.github/workflows/` — CI (rust, flutter, docs) and release builds

## Status

Core import, Clean Reader, local search and Phase II memory features are
implemented. The latest scope, limitations and validation status are tracked in
[Phase 9 — Advanced Integrations](docs/phase-0/19-phase9-advanced-integrations-status.md)
and the preceding phase status documents.

CI: rust, flutter, docs workflows run on every push to the branch.
