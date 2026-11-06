# Phase 2 — Personal Memory MVP (started 2026-11-06)

Scope per spec §13 Phase 2: tags, collections, highlights/notes, full-text
search (done in Phase 1), related-content (deferred), Daily Edition foundation,
export. No cloud dependency anywhere.

## Implemented

- Schema v2 (`0002_personal_memory.sql`): tags, item_tags, collections,
  item_collections, annotations (quote-anchored, visibility default `private`)
- Rust: `personal_memory::memory` (tag/collection/annotation CRUD, `export_all`
  JSON, `daily_edition`), new FFI functions in `platform_bridge`
  (`refract_tag_item`, `refract_list_tags`, `refract_list_item_tags`,
  `refract_create_collection`, `refract_list_collections`,
  `refract_add_to_collection`, `refract_add_annotation`,
  `refract_list_annotations`, `refract_export`, `refract_daily_edition`)
- Flutter: models + FFI bindings + providers; Reader gains Note FAB + tag
  action + annotations section; Home gains Daily Edition rail; Settings gains
  JSON export to app documents
- Tests: `personal_memory` Phase 2 roundtrip test (tags/collections/
  annotations/export/daily edition)

## Acceptance criteria check (spec §13 Phase 2)

- Organize imported content (tags/collections) — done
- Annotate documents — done (quote-anchored notes)
- Local search — done in Phase 1 (FTS5)
- Export — done (JSON, user-controlled)
- No cloud dependency — holds

## Deferred (with reason)

- Semantic/vector search — needs local embeddings (Phase 4, ai_runtime)
- Related-content suggestions — same dependency
- CRDT-backed shared annotations — Phase 5
