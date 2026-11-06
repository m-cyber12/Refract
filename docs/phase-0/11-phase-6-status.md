# Phase 6 — Advanced Provenance & Research (started 2026-11-06)

## Shipped

- New crate `crypto_provenance`: append-only **Merkle log** over evidence
  record hashes, inclusion proofs, and verification. Every proof carries an
  explicit statement: it proves inclusion in the local log — NOT who created
  the file or source authenticity (spec §B5).
- `personal_memory::provenance`: `evidence_merkle_root`,
  `evidence_merkle_proof(record_id)` over the ordered evidence log
- Cross-device sync state transfer: `export_workspace_state` /
  `import_workspace_state` (transport-agnostic hex payload over the CRDT
  outbox) — works over QR/file/relay later
- FFI: `refract_evidence_merkle_root`, `refract_evidence_merkle_proof`,
  `refract_verify_evidence_proof`, `refract_export_workspace_state`,
  `refract_import_workspace_state`
- Flutter Vault: Merkle root header with the honest scope statement
- Tests: Merkle proof roundtrip + tamper rejection; provenance over evidence

## Research modules — documented, not shipped (spec §B5/§13 Phase 6)

- **TLSNotary / zkTLS**: could prove facts about a *network interaction*
  (e.g., that a server presented certain bytes over TLS at a time). Trust
  assumptions: the notary set, the TLS stack, the verifier. It does NOT prove
  legal identity, contractual validity, or seller performance. Integration
  would be a separate research module and must never block the MVP.
- **Signed timestamps** (RFC 3161): could anchor "existed by time T" — trust
  in the TSA. Not implemented.
- **WebRTC / iroh / relay transport** for the sync outbox: pluggable behind
  `sync_engine`; requires E2E encryption before any relay sees payloads.
- **Optional desktop client**: possible later via the same Rust core.

## Roadmap status

Phases 0–6 are all implemented and CI-green on `arena/04fef284-refract`.
