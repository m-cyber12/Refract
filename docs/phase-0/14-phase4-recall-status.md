# Phase II Master — Phase 4 (REFRACT RECALL) Status

Local Recall baseline for approximate descriptions, hybrid retrieval, contextual
sources, inspectable ranking, and an evidence-first Memory Assistant.

## Architecture

- `personal_memory::recall` combines FTS5 matches, versioned local concept
  vectors, title/author/project/entity matching, explicit source URL matching,
  capture-time filters, and non-dismissed relationship traversal.
- Migration `0006_recall.sql` persists per-block vectors, encoder version and
  source-text hashes. This is a derived index; original bytes, source blocks,
  annotations and metadata are never replaced by assistant output.
- The encoder `local-concepts-hash-v1` uses a small English synonym dictionary
  and normalized 256-dimensional signed feature hashing. Cosine similarity is
  combined with actual concept overlap, so vector collisions alone cannot
  justify a result. **This is not a learned neural embedding model.**
- Natural-language scaffolding is stripped for retrieval. Examples supported
  by the local dictionary include AI / machine learning, privacy / GDPR / data
  protection, encryption / cryptography, subscription renewal, and local-first.
  PDF intent is recognized; project names match project metadata. Other source
  types and exact author/entity/URL constraints have explicit filters.
- Relevance combines concept/keyword passage scores, metadata, full-text
  evidence, exact URL matches, contextual relationship strength, extraction
  quality and pinned-topic importance. Recency is not the default ordering;
  it gets a small boost only when requested. "Last week/month" means a rolling
  7/30-day capture-time window and is disclosed as such in the response.
- New captures are indexed after persistence. Legacy items are indexed lazily
  during retrieval. A transactional rebuild replaces the derived vector index
  without modifying originals; corrupt derived vectors surface an error.

## Evidence and assistant

- Each hit includes a real item ID, original source URL if available, original
  block index, verbatim passage, ranking reasons, and a non-probabilistic score.
  Passage windows respect original Unicode boundaries and synonym matches.
- Direct quotations, context-only excerpts and metadata-only hits are labeled
  separately. A metadata hit is not evidence for an answer about document text.
- Modes: find, evidence for a question, summarize selected sources, compare
  selected sources, explain stored connections, and source-backed timeline.
- Summaries are extractive: short original passages from up to three blocks
  per selected source, each with its own citation. They are not complete
  abstractive summaries. Comparison shows sources separately, without asserting
  agreement or contradiction that has not been established.
- Answer mode presents retrieved quotations and explicitly refuses to infer
  beyond them. No results means insufficient evidence, not invented facts or
  citations. There is no LLM-generated interpretation in this implementation.
- Timeline entries retain their distinct capture/publication/modification/
  event/deadline kinds and candidate/user notes. Connection explanations retain
  the existing basis/score and suggestion labels rather than asserting truth.
- Unknown selected source IDs, reversed date ranges, unsupported modes and
  invalid input return errors rather than silent empty results.

## Mobile and ABI

- `/recall` is linked from Library and Settings. Reader opens contextual Recall
  to discover related stored documents; the current item is excluded.
- Query, assistant mode, source type, Project Space, author, entity, exact URL
  and UTC capture-date filters are available. Select up to 20 result documents
  for extractive summary or comparison.
- Source buttons open the Reader with `?block=N`; Reader displays the cited
  source block above the full document, or explicitly reports a missing block.
- New C ABI entry points: `refract_recall_query`, `refract_recall_rebuild`.
  Dart models, input-buffer ownership, repository methods and providers match
  the existing JSON-envelope/error convention.

## Limits and privacy

- No cloud calls, model downloads, telemetry or reading-behavior profiling.
  Quotes show what a source says; they do not establish that it is true.
- Dictionary semantics are deliberately limited, mainly English, and cannot
  provide general multilingual paraphrase understanding. Learned embeddings,
  an ANN index and generative synthesis are not implemented.
- Search scans at most 5000 items in deterministic ID order and discloses
  truncation. Explicit source selection bypasses that corpus window. Responses
  return at most 50 hits; contextual/connection traversal is capped at 1000
  links. Large-library performance requires additional testing.
- Indexing/retrieval currently execute synchronously through the mobile FFI;
  first use or rebuilding a large library may block the UI. No fake background
  progress is displayed. A worker-isolate/background-indexing layer is future
  work, not claimed as implemented here.
- Relationship traversal is one-hop and stored suggestions are not semantic
  proof. Assistant answers identify evidence gaps but do not infer missing
  facts, perform external verification or reconcile conflicting claims.

## Verification

- Local Rust/Dart tree-sitter checks and SQLite schema/query preparation checks
  passed. SDK compilation runs in GitHub Actions, not in this workspace.
- Rust regressions cover approximate language, ranking against unrelated recent
  content, source quotations, explicit metadata/entity/capture filters, exact
  URLs, projects, missing evidence, hostile query syntax, selection modes,
  unchanged originals, timestamp kinds, dismissed contextual links, index
  repair, Unicode passages, and upgrade from schema v5 with lazy indexing.
- Native ABI regression verifies real source/block references, JSON envelopes,
  invalid requests and rebuild behavior.
- Flutter regressions cover JSON models, natural-language requests, cited-block
  navigation, reading context, no-evidence responses and visible errors.
- Implementation commit `91e02a6` passed:
  - [Rust checks, workspace tests and host release build](https://github.com/m-cyber12/Refract/actions/runs/42486639188).
  - [Flutter analysis/tests, Android ABI build and APK packaging](https://github.com/m-cyber12/Refract/actions/runs/42486639215).
  - [Android emulator install and launch smoke](https://github.com/m-cyber12/Refract/actions/runs/42486639212).
- [Documentation lint](https://github.com/m-cyber12/Refract/actions/runs/42486423580)
  passed for the status-document introduction commit.
- Emulator launch smoke does not substitute for physical-device interaction
  or large-library performance testing.
