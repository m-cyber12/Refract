# Phase II Master — Phase 2 (REFRACT SENSE) Status

Implements "PHASE 2 — REFRACT SENSE" from the Phase II master expansion spec:
classification, rule-based value scoring, capture policies, Auto Save /
Smart Suggest / Ignore, review actions, undo, editable rules.

## What was built

- **Pipeline** (spec §3.1): every imported item passes through
  Detect → Classify → Evaluate → Deduplicate → Decide → Organize → Persist.
  Hooked into `Store::insert_item` (`crates/personal_memory/src/lib.rs`).
- **Classification** (`sense.rs::classify`): rule-based categories —
  receipt, subscription, article, document, note, temporary, reference —
  with a confidence value.
- **Value scoring** (`sense.rs::score_value`): transparent dimensions
  (reference_value, information_density, uniqueness, classification_confidence).
  The score is explicitly NOT an objective measure of importance; every
  decision carries a human-readable explanation.
- **Decisions**: `auto_save` / `smart_suggest` / `ignore`, stamped on the
  item (`items.sense_decision`, `items.sense_score`) and logged in
  `capture_decisions` (migration `0004_sense.sql`).
- **Capture policies** (spec §3.3): `sense_rules` table + REFRACT SENSE RULES
  settings page (`/sense`) with presets conservative / balanced / research /
  personal_archive. Presets never overwrite user ('custom') rules.
- **Review & undo**: `review_capture_decision` supports approve / dismiss /
  undo; history is never deleted. Smart Inbox strip on Home shows pending
  suggestions with Save/Ignore actions.
- **FFI**: `refract_sense_evaluate`, `refract_sense_decisions`,
  `refract_sense_review`, `refract_sense_rules`, `refract_sense_rule_upsert`,
  `refract_sense_rule_delete`, `refract_sense_preset_set`,
  `refract_sense_setting_get`, `refract_sense_setting_set`.

## Honesty notes

- Scoring is deterministic and rule-based; no model is involved. AI-assisted
  evaluation remains an optional future layer, per spec.
- "Ignore" still logs the decision (history preserved); it does not delete
  the already-persisted item, only marks it ignored — undo restores review.

## CI

rust / flutter / android-emulator-smoke all green on
`arena/04fef284-refract` (latest: smoke 42399565547).
