# Phase II Master — Phase 3 (SMART MEMORY) Status

Implements the Phase 3 local, deterministic baseline: automatic categorization,
topic identification, entity candidates, relationship suggestions, Memory
Timeline, Knowledge Evolution, and Project Spaces.

## What was built

- Migration `0005_smart_memory.sql` adds topics, durable category decisions,
  entities, item associations, inspectable relationships, distinct timestamp
  kinds, projects, and project references. Existing items and original blobs
  remain unchanged. Migration is repeatable through the schema-version gate.
- New captures run organization after persistence. Earlier captures can be
  organized from the Smart Memory menu. Existing categories are reused; each
  item gets at most three keyword-derived topics and twelve entity candidates.
- Topics can be renamed, merged, pinned, and rejected. Redirect/rejection rules
  preserve user decisions during later organization. A rejected category does
  not silently reappear; renamed/merged categories retain their canonical ID.
- Relationships contain an explicit basis and a heuristic score. Automatic
  links use shared topics, organization candidates, or multiple shared name
  candidates. They are suggestions, not verified factual connections. Canonical
  pairs prevent duplicate reverse suggestions. Dismissal is retained in storage
  and does not silently reset when either item is organized again.
- Users can explicitly add related-topic, supporting-reference,
  contradicting-source, earlier-version, follow-up, and general links. These
  are user assertions, not conclusions reached by the extraction engine.
- Memory Timeline distinguishes capture, publication, modification, event,
  and deadline timestamps. Capture time is system-managed. Valid ISO dates
  extracted from content are labeled **event candidates**, not established
  events or deadlines. Other date kinds can be specified explicitly by users.
- Knowledge Evolution groups a topic's captured sources chronologically and
  describes the collected information. It does not infer beliefs, politics,
  psychological traits, or identity from reading behavior.
- Project Spaces group references and show their capture/content timestamps
  alongside the date each reference joined the project. Deleting a project or
  removing a reference never deletes its original library item. Automatically
  generated same-project links are hidden when no shared project remains.
- Twenty-two C ABI functions have matching Dart bindings and repository APIs.
  New Dart input UTF-8 buffers are freed after each call; native response
  ownership follows the existing `refract_free_string` convention.
- `/memory` is linked from Library and Settings. Five tabs show Timeline,
  Topics, Entities, Connections, and Projects. Topic detail shows Knowledge
  Evolution and source links; project detail supports adding/removing
  references and reviewing its timeline. Errors are surfaced explicitly.

## Limits and honesty notes

- Organization uses a small English keyword taxonomy, not embeddings or an
  LLM. Content classification from SENSE remains separate and unchanged.
  Names are heuristic candidates, not verified person/organization identities.
- Extraction currently recognizes emails, valid ISO dates, and capitalized
  name candidates. It does not reliably classify arbitrary events, places,
  publication dates, or deadlines automatically.
- Evolution currently summarizes chronological source accumulation rather
  than detecting changes in claims or resolving contradictions.
- Scores are heuristics, not calibrated probabilities. A score of 1 on an
  explicit relationship indicates a user-specified link or project membership,
  not independently verified truth.
- Current views are bounded: 100 timeline rows, 50 entities/connections/topic
  items, and 100 project references/timeline rows. Item pickers offer the most
  recent 500 library items. Full pagination and background indexing are not
  implemented here; large-library performance needs further device testing.
- Organization is best-effort after import so derived-data failure cannot
  discard an original capture. The manual organization action surfaces errors.
- No telemetry, cloud dependency, user profiling, or replacement of originals
  has been added. Semantic/hybrid recall belongs to the next phase.

## Verification

- Local Rust/Dart tree-sitter syntax checks and SQLite schema/query preparation
  checks passed. Rust and Flutter SDKs are not installed in the workspace;
  compilation and runtime tests are performed by GitHub Actions.
- Rust regression tests cover organization/reuse, topic customization,
  relationship basis/scores/dismissal, timestamp-kind separation, valid UTC
  dates and malformed Unicode-safe extraction, descriptive evolution,
  project membership, and upgrade from schema v4.
- Native FFI integration exercises the new APIs and JSON envelope ownership.
- Flutter tests cover native-model JSON decoding, topic controls, explicit
  timeline kinds, candidate labeling, and visible error states.
- Implementation commit `a954b59` passed:
  - [Rust: clippy, workspace tests, host release build](https://github.com/m-cyber12/Refract/actions/runs/42483679631).
  - [Flutter: analysis, tests, Android ABIs, APK and packaging check](https://github.com/m-cyber12/Refract/actions/runs/42483679633).
  - [Android emulator: install, launch, native-load/crash smoke](https://github.com/m-cyber12/Refract/actions/runs/42483679634).
- Documentation lint passed on the status-document introduction commit:
  [docs run](https://github.com/m-cyber12/Refract/actions/runs/42482973656).
- Android launch smoke is not a substitute for manual Smart Memory interaction
  or large-library performance testing on a physical device.
