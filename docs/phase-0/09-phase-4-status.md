# Phase 4 — Local Intelligence (started 2026-11-06)

Scope per spec §13 Phase 4, adapted to "deterministic first": the AI runtime
abstraction exists, but the shipped engine is extractive (no model download),
so every acceptance criterion about *working without models* holds by
construction. Local model slot (llama.cpp/ONNX) is behind the `AiEngine` trait.

## Implemented

- New crate `ai_runtime`: `AiEngine` trait, `ExtractiveEngine` (always
  available), `AiRuntime` with graceful fallback, `AiOutput` carrying
  `kind` (extractive|interpretation), `source_blocks`, `model_used`
- `personal_memory`: `related_items` — FTS5 shared-term related content
- FFI: `refract_summarize`, `refract_suggest_tags`, `refract_related`
- Flutter Reader: "Briefing" panel with labeled output (kind, model, source
  blocks), suggested-tag chips that apply real tags, Related section
- Tests: extractive summary labels/sources, deterministic tags

## Acceptance criteria check (spec §13 Phase 4)

- AI optional; core works without downloaded models — yes (default engine
  needs nothing)
- Interpretations labeled — yes (`kind` + `model_used` shown in UI)
- Claims reference source material — yes (`source_blocks`)
- Model failures don't break the app — yes (fallback engine, error envelope)

## Deferred (Phase 6 / research)

- Actual local LLM inference (llama.cpp / ONNX Runtime via `AiEngine` impl)
- Vector/semantic search (sqlite-vec) — needs embeddings from a local model
- Resource-aware background inference (battery/thermal gates)
