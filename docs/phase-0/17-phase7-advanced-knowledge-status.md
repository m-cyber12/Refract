# Phase II Master — Phase 7 (Advanced Knowledge System) Status

Decision Memory, a progressively loaded Knowledge Map, optional extractive Memory
Compression and local Source Intelligence. No network fetching, telemetry,
behavioral profiling or mandatory model service is added.

## Decision Memory

- Decisions are explicitly saved user records, never inferred from imported
  `Decision:` markers, uncertain extraction or model output. Fields include title,
  context, options considered, exact selected option, reasoning, source references,
  decision date, expected outcome, optional review date and Project Space.
- Save/edit/archive/restore operations are transactional; revision snapshots keep
  all decision fields and historical references. The UI exposes the latest 100
  revisions. Archiving preserves original documents and the record's history.
- Validation rejects invalid selections, dates/review order, missing references,
  missing projects and excessive inputs. Decisions may have up to 30 sources.
- Knowledge Hub provides text search, project and archived-state filters, editing,
  history and source navigation. Recall surfaces matching user-recorded reasons
  separately from source excerpts; these records do not establish objective truth.
  With source filters, a record must reference at least one source surviving the
  bounded scan/filter. Capture-date filters never become decision-date filters.
- Search uses bounded literal meaningful-term matching across the latest 1,000
  decision-date-ordered records, returning up to 100. It is not semantic reasoning.
  Active explicit project decisions suppress that project's Daily Signal missing
  decision-marker suggestion; imported markers are still only source-text markers.

## Knowledge Map and relationship exploration

- Migration `0009_knowledge.sql` projects existing documents, topics, projects,
  entity candidates, annotations, event candidates and active decisions into
  SQLite node/edge views. It does not duplicate the existing knowledge stores.
- One-hop neighbor loading defaults to 20 nodes, hard-capped at 40, with explicit
  paging (offset capped at 100,000), category and UTC date filters. Filters apply
  to neighbors, not the focus. Document dates are capture times; events use event
  dates and decisions the user-recorded decision date. Other node dates are
  record-creation times, labeled by node kind/detail.
- Mobile map draws at most eight neighbors and lists every node in the current
  page, with expansion, previous-focus navigation, source/project/decision access,
  and an edge inspector. Root spokes mean navigation-index membership, not semantic
  similarity or a factual relationship. Existing relationship basis, heuristic
  confidence and dismissible IDs survive the projection.
- Suggested/user-asserted document links can be dismissed without editing sources.
  Membership edges are associations, not verified factual assertions. At most
  2,000 focus edges are inspected for display; a paged neighbor can therefore lack
  displayed edge detail beyond that bound.
- Path exploration requires two distinct sources and traverses non-dismissed
  document links as undirected associations, with 1–4 hops, at most 2,000 links and
  200 visited sources. Limit hits are disclosed. A path is not factual entailment;
  failure to find one is not evidence that no relationship exists.

## Optional Memory Compression

- Only explicit user creation produces an overview. No original is replaced,
  removed or modified. The generator is deterministic and extractive, not a
  neural model; it does not invent a narrative or inferred beliefs.
- Select 1–30 sources or a project/topic/collection's first 30 eligible IDs.
  Scope truncation is disclosed. Source selection UI displays the first 200
  captures with a local title filter; it is not an unbounded library picker.
- Each source contributes at most one exact 600-character block excerpt, two
  literal question excerpts and 20 stored typed timestamps. Capture metadata is
  included separately when not already recorded. All excerpts, topic/entity
  counts, timelines and disagreement links retain original-source navigation.
- Concepts are stored topic associations; recurring entities are extracted
  candidates. Literal questions are not proven unresolved questions. Possible
  disagreements are existing contradicting-source suggestions/user assertions,
  not automatically verified contradictions (first 2,000 links only).
- Persisted snapshots carry block fingerprints, represented-source metadata and
  association fingerprints, and scope-membership fingerprints. Changes flag stale
  content/metadata/scope without overwriting the historical snapshot. Membership
  freshness for scopes over 30 checks the represented window and total count,
  not every unrepresented source.
- Regeneration is explicit and replaces only the derived snapshot. Discard removes
  only the overview and its source-reference index; originals remain saved.
  Source Intelligence lists the associated derived snapshot independently.

## Source Intelligence and separately archived versions

- Reader exposes recorded URL, capture method/time, author/language when known,
  parsing heuristic, explicit date kinds and three distinguished fingerprints:
  recorded original-byte SHA-256 reference, stored import-content fingerprint and
  current normalized compiler-block fingerprint. None authenticates a publisher.
- New imports receive best-effort retained-state snapshots. An explicit action can
  snapshot current state for legacy sources. History timestamps are when state
  was recorded, not invented extraction/transformation times; unchanged stage/
  version/fingerprint entries are deduplicated. Intermediate raw extraction was
  not separately archived and legacy processing history may be absent.
- Existing rule-derived consumer candidates, local retrieval vectors, optional
  extractive overviews and user annotations/decision references remain distinct
  from original content. Unknown artifact-generation times remain unknown.
- Opening Source Intelligence does not verify original bytes. Existing explicit
  Consumer X-Ray integrity comparison is linked separately and still makes no
  publisher-authenticity, authorship, factual or legal-verification claim.
- Version candidates share an exact recorded URL or an existing earlier-version/
  follow-up link. Those are association bases, not proof of common authorship,
  publication chronology or applicability. No live page is fetched or monitored.
- Optional local comparison labels before/after source IDs explicitly and compares
  exact line presence, ignoring ordering and duplicate counts. Each side returns
  at most 200 excerpts of at most 600 characters, with truncation disclosed. Both
  independently saved originals remain unchanged.

## Integration and validation

- Native ABI: `refract_knowledge(handle, json)` uses the existing owned-string JSON
  envelope, rejects unknown actions/DTO fields and guards invalid handles.
- Mobile: typed decision/graph models, native binding, repository/providers,
  Knowledge Hub and detail/editor/map/path/compression/source/diff routes. Entry
  points are Settings, Smart Memory, Project Spaces and Reader; Recall separates
  user-recorded decisions from retrieved source evidence.
- Ten backend knowledge regressions cover migration 8→9/idempotence, ignored
  sources, explicit-only decisions, rollback, validation, revisions/archive,
  Recall, projected graph kinds/paging/dates/dismissal, compression citations,
  freshness/regeneration/discard, metadata/provenance, project-signal gaps and
  separately archived source history/diff without overwrites.
- A native ABI end-to-end test covers decision lifecycle, graph/path/dismissal,
  compression lifecycle, source history/diff and malformed/unknown requests.
  Mobile tests cover JSON contracts, UTC calendar validation, explicit decision
  save, bounded graph requests, source-block navigation, stale-derived labels,
  discard confirmation and honest unavailable legacy history.
- Local Rust/Dart syntax parsing, SQLite migrations and `git diff --check` pass.
  Full Rust/Flutter toolchains are unavailable in the authoring sandbox; compiler,
  test, APK and emulator validation run in GitHub Actions.
- Final CI validation for the latest revision is pending. Earlier backend Rust
  clippy/tests passed; this is not a claim that the final mobile/APK gates passed.
- Emulator smoke checks app launch/native loading only, not every knowledge flow.
  Physical-device, large-library latency/memory and broad accessibility testing
  remain manual validation work. FFI operations remain bounded but synchronous.
