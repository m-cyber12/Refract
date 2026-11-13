# Phase 5 — Multiplayer Margins (started 2026-11-06)

Scope per spec §13 Phase 5, with transport kept honest: CRDT + outbox are
real; WebRTC/iroh/relay transport remains pluggable research (Phase 6).

## Implemented

- New crate `annotation_engine`:
  - `Anchor` (content hash + quote + prefix/suffix + block idx + version) and
    `resolve_anchor` with Exact/Relocated/Ambiguous/Lost — never silently
    re-attaches (spec §C2)
  - `AnnotationDoc` on **Loro** CRDT: concurrent offline edits converge;
    tests prove two docs converge after exchanging state
- New crate `sync_engine`: workspaces + append-only sync outbox
  (`pending`/`sent`), fully offline-capable; opportunistic by design (spec §C4)
- `personal_memory::collab`: workspace CRUD, `upsert_shared_annotation`
  (CRDT upsert + enqueue), `pending_sync`
- FFI: `refract_create_workspace`, `refract_list_workspaces`,
  `refract_share_annotation`, `refract_sync_pending`
- Flutter: share-to-workspace action on each annotation (annotation payload
  only — never the source document, spec §C5), workspace picker/creator
- Tests: anchor resolution paths, CRDT convergence, outbox flow

## Acceptance criteria check (spec §13 Phase 5)

- Concurrent changes converge — yes (CRDT, tested)
- Offline changes preserved — yes (outbox + local CRDT)
- Private stays private unless explicitly shared — yes (visibility default)
- Annotation relocation on content change — yes (anchor resolution)
- Two-user live collaboration over a network — deferred to Phase 6
  (transport: WebRTC/iroh/relay + E2E encryption)

## Deliberately not built (per spec §14 avoid-list)

- Always-on background P2P networking; identity/authz for malicious peers is
  documented as out of CRDT scope (spec §C3 caveat)
