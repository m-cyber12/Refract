# Phase II Master — Phase 5 (DAILY SIGNAL AND CONTEXT) Status

Local baseline for a quiet Daily Signal, optional contextual information,
source-backed date candidates, knowledge-gap observations, saved reading
places and relevant project references.

## Daily Signal

- Migration `0007_daily_signal.sql` stores settings, the latest edition,
  observation dismissals, explicit reading places and extracted date candidates.
  Schema upgrades preserve source items, original blobs and existing indexes.
- Home replaces the old Daily Edition list with a compact Daily Signal preview.
  `/signal` shows a small, source-linked edition rather than an endless feed.
- Configurable sections: recently captured, emerging topics, connected
  discoveries, upcoming dates, unfinished knowledge, marked changes, continue
  reading, knowledge gaps and suggested reading. Sections may all be disabled.
- Edition cadence is daily (24 hours), weekly (7 days), or manual. Editions
  refresh on opening after the interval, not through a background scheduler.
  Explicit refresh generates an edition immediately. No push notifications,
  external calendar access or periodic network activity has been added.
- Settings control the capture lookback (1–90 days), upcoming date horizon
  (1–365 days), unconfirmed candidates and a maximum of 1–5 items per section.
  Ordinary imports do not bypass the configured edition cadence.
- Edits to settings, event review, reading places and dismissals invalidate
  the edition so the next read reflects that explicit action. Manual mode
  waits for explicit generation after invalidation. Cached editions recheck
  source eligibility, so newly ignored sources do not keep resurfacing.
- Empty enabled sections do not receive filler. A genuinely quiet edition is
  explicitly quiet. Disabling Daily Signal returns an off state without
  generating observations. Observations can be dismissed and later restored.

## Evidence, dates and gaps

- ISO calendar dates in imported source blocks become event candidates with
  source item ID, block index, title, category, UTC date, extraction timestamp,
  exact original text window, heuristic score and review status.
- Keyword categories include renewal, trial end, warranty expiry, appointment,
  delivery, project deadline, document expiry and a generic date mention.
  Dates and category assignments are **unconfirmed candidates**, not promises.
  There is no legal verification or automatic calendar integration.
- Users can confirm, undo confirmation or dismiss a candidate. Re-extraction
  preserves those decisions. User confirmation is labeled separately from
  independent verification. Invalid calendar dates are rejected and Unicode
  boundaries are respected when extracting evidence windows.
- Topic activity means at least two captures in the configured lookback; it
  does not imply a trend outside REFRACT or a personal belief. Marked changes
  are explicitly stored earlier-version/follow-up/contradiction links, not an
  inferred factual change in understanding.
- Gaps are optional **not-found-in-REFRACT observations**, never confirmed
  absence: a project with multiple references but no `decision:` / `decided:`
  marker in scanned source text; a receipt with no warranty keyword in its
  source/linked sources; or a subscription renewal with no cancellation marker
  in that scope. Alternative wording and information outside the scanned scope
  may exist. No unnecessary collection of documents is encouraged.
- Suggested reading uses explicit Project Space membership, not psychological
  or behavioral profiling. Unfinished knowledge is based on missing topic
  classification or pending capture review and excludes explicitly read items.

## Context and Continue Reading

- Reader has a collapsed REFRACT CONTEXT panel. It retrieves context only when
  expanded; disabling context removes the panel. Projects have a Context tab.
  No reading-interrupting popups are used.
- Context shows non-dismissed stored relationships, source annotations, explicit
  project memberships/references, related stored subscription records and date
  evidence. The current source and ignored sources are not offered as new
  related discoveries. Connection bases retain suggestion/user-assertion labels.
- Reading places are saved only through an explicit per-block bookmark button.
  Merely opening a document does not track reading or infer completion.
- Continue Reading opens the saved original block. Mark read removes the item
  from the saved-place queue and relevant unfinished observations. Saved places
  can be cleared independently of documents and annotations.
- Saving a reading place, generating an edition or opening context never
  rewrites original source content or notes.

## Interfaces and scope limits

- `personal_memory::signal` owns the local rules and persistence. Additive C ABI
  `refract_signal` dispatches typed JSON requests for edition/configuration,
  context, candidate review, reading places and dismissals. Dart uses the
  existing native response ownership/error convention and frees input buffers.
- At most 2000 eligible source items, 100 project spaces, 100 upcoming events
  and 1000 relationships are considered for an edition. Gap link scans are
  capped at 100 links per source. Context limits direct links/project references
  to ten, related annotations to three per source, entries to twenty and dates
  to ten. UI source buttons show up to five linked sources per observation.
- Extraction understands English keyword cues and valid ISO dates, not
  arbitrary natural-language dates or multilingual event semantics. Several
  dates in a short passage may receive the same contextual category; the
  original evidence and unconfirmed label remain essential.
- Project gap checks inspect source text, not every possible decision format
  or note. Other gap checks use simple keywords and explicit linked scope.
  The UI does not claim a missing policy, warranty or decision is proven absent.
- Operations currently use synchronous mobile FFI. Large-library latency and
  worker-isolate/background indexing remain future work; there is no simulated
  progress or claim that performance has been established on physical devices.
- No telemetry, external account, model inference about the user, new cloud
  dependency or external calendar permission is required.

## Verification

- Local Rust/Dart syntax and SQLite migration/query preparation checks passed.
- Rust regressions cover quiet/manual states, cadence, per-section limits,
  event evidence/review/re-extraction, invalid/Unicode dates, unconfirmed
  filtering, saved-place validation/completion, original preservation,
  dismissible gap scopes, explicit project decision markers, opt-out context,
  ignored-source removal from cached editions and schema-v6 upgrade.
- Native ABI coverage exercises settings, edition/refresh, context, event review,
  reading places, dismissals and invalid request/error envelopes.
- Flutter regressions cover JSON models, quiet editions, uncertain date labels,
  explicit confirmation, source-block navigation, lazy context and persisted
  frequency controls.
- Implementation commit `d42c96c` passed:
  - [Rust checks, workspace tests and host release build](https://github.com/m-cyber12/Refract/actions/runs/42492228450).
  - [Flutter analysis/tests, Android ABI build and APK packaging](https://github.com/m-cyber12/Refract/actions/runs/42492228474).
  - [Android emulator install and launch smoke](https://github.com/m-cyber12/Refract/actions/runs/42492228512).
  - [Documentation lint](https://github.com/m-cyber12/Refract/actions/runs/42492228550).
- Android launch smoke is not a substitute for manual feature interaction and
  large-library testing on physical devices.
