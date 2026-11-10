# Open work — user direction decisions

These are planning directions, not implementation, permission grants, or a release
sign-off. Feature-specific limits, threat models, consent flows and acceptance
criteria still need decisions. Existing privacy and evidence-labeling constraints
remain in force.

## Capture and documents

- **A1–A2:** implemented baselines; interruption, physical-provider and signed
  iOS device testing remain. Android pre-review handoff is not promised durable.
  The earlier iOS decisions (explicit handoff-copy consent, Android format parity,
  retention until save/discard, manual app opening) remain in force.
- **A3:** pursue explicitly initiated, bounded URL fetching; review and save
  remain separate. Redirect, network, privacy and failure policies remain open.
- **A4:** explore a separately consented browser extension. No permission grant or
  background collection is implied; scope and architecture remain open.
- **A5:** add DOCX, folders and/or batch formats incrementally with review and
  preserved originals; exact order and semantics remain open.
- **A6:** pursue optional on-device OCR, retaining originals and labeling derived
  text; model, platform and resource decisions remain open.
- **A7:** improve PDF reader fidelity and extraction incrementally while keeping
  originals and labeling incomplete results.
- **A8:** investigate stronger platform-appropriate parser isolation, resource
  budgets and adversarial tests for untrusted documents.
- **A9:** explore consented quick capture/queue; preserve clear review and save
  semantics. Staging and retention details remain open.
- **A10:** explore optional explicitly enabled local pre-storage SENSE screening;
  consent and failure behavior remain open.

## Storage, security and release

- **B1:** pursue user-controlled full encrypted backup/restore including original
  files and relevant library data. Key recovery, format and restore scope remain
  open. Current JSON export is not a full source backup.
- **B2:** pursue app-level library encryption and key management/migration design.
  Treatment of staged copies, recovery and platform constraints remains open;
  current storage is not claimed to have app-level encryption.
- **B3:** production-grade gates, including signed physical-device tests,
  lifecycle, accessibility, performance and independent security review.
- **B4:** commit and maintain Android and iOS platform projects, with reproducible
  CI verification. Migration from generated shells remains to be designed.

## Memory and intelligence

- **C1:** incrementally scale with pagination, real background work and measured
  large-library performance.
- **C2:** local models, embeddings and generative synthesis **undecided**. The user
  needs clearer understanding of capabilities and size before deciding. No model
  download or inference is authorized by the other choices.
- **C3 / D2:** improve reviewable extraction, descriptive timelines, source
  navigation and knowledge tools; preserve explicit edits and originals. Do not
  infer personal beliefs or turn similarity into factual relationships.
- **D1:** expand reviewable Consumer X-Ray analysis, including investigation of
  multilingual extraction, pagination, optional reminders and calendar
  interoperability. Extraction remains evidence-linked and user-reviewed.

## Collaboration, integrations and provenance

- **E1:** explore optional encrypted network collaboration with key storage,
  recovery and independent security review; current manual exchange remains.
- **E2:** explore separately authorized, narrowly scoped provider connections,
  with explicit review and revocation; no account is connected by this decision.
- **E3:** explore opt-in, filtered Android notification access; no listener or OS
  permission is enabled by this decision, and iOS parity is not assumed.
- **F1:** explore optional trusted timestamps and C2PA verification; research
  TLSNotary/zkTLS separately without promising a production integration. Each has
  distinct trust assumptions and none establishes factual truth.
- **F2:** mobile first; desktop is not prioritized now.

## Next priority

Continue **capture first**, including A1/A2 physical-device and signed validation
and subsequent capture choices. Other selected work and production gates are not
waived. Device signing/provisioning and physical-device access are still external
prerequisites; unsigned CI is not a substitute.
