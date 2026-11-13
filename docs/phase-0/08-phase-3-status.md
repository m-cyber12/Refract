# Phase 3 — Consumer X-Ray & Proof Vault (started 2026-11-06)

Scope per spec §13 Phase 3: manual subscriptions, receipt/policy text import,
renewal timeline, explainable claim extraction, Proof Vault with hashing and
verification. TLSNotary/zkTLS explicitly deferred (research only).

## Implemented

- Schema v3 (`0003_xray_vault.sql`): subscriptions (status
  confirmed/imported/suspected/unverified), append-only evidence_records,
  evidence_claims linked to records with quote + byte offset
- New crate `evidence_engine`: SHA-256 verify, deterministic clause extraction
  (trial/renew/cancel/refund/price rules — no AI, every claim quotable)
- `personal_memory::xray`: subscription CRUD, upcoming events (30-day horizon),
  evidence insert (transactional, claims extracted in-tx), verify by re-hash
- FFI: `refract_add_subscription`, `refract_list_subscriptions`,
  `refract_upcoming_events`, `refract_add_evidence`, `refract_list_evidence`,
  `refract_list_claims`, `refract_verify_evidence`
- Flutter: X-Ray screen (upcoming events + all subscriptions with status color),
  Vault screen (evidence list, verify button, "hash proves integrity, not
  authenticity" copy, claims per record), nav gains X-Ray + Vault
- Tests: `evidence_engine` claim extraction, `xray` roundtrip incl. verify

## Acceptance criteria check (spec §13 Phase 3)

- Create/manage subscription records — done
- Evidence linked to extracted claims — done (record_id + offset)
- Hashes recalculable and checkable — done (`verify_evidence`)
- Unverified data labeled — done (status + confidence + color)
- No automatic cancellation / financial actions — by design
- No TLSNotary in this phase — honored

## Deferred

- Local notifications for renewals (needs WorkManager/UNUserNotificationCenter wiring)
- OCR of receipt screenshots (needs on-device vision model — Phase 4)
- Signed timestamps / Merkle structures — Phase 6 research
