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
  remain separate. Fetch only when explicitly requested per link, without browser
  cookies, saved logins or credentials. Block localhost/private-network and similar
  addresses, including after redirects and DNS resolution. Follow limited same-site
  redirects and ask before contacting a different site. Require confirmation before
  each unencrypted HTTP request; do not silently downgrade. Start with static
  retrieval and separately investigate an explicitly consented isolated renderer.
  Ask before writing a bounded preview handoff copy, retaining it until save or
  explicit discard. Retry failures only on user request. Detailed network, retention
  and original-byte semantics remain open.
- **A4:** investigate mobile browser capabilities first and local-only handoff,
  without cloud relay or analytics. Offer explicit choices of address, selected
  text or page content, with separate review and save. Investigate additional
  site-specific permissions only with separate consent and visible controls. No
  permission grant or background collection is authorized; scope remains open.
- **A5:** aim broadly at file support, ordered by implementation judgment; do not
  claim universal support. Add formats and folder/batch selection incrementally,
  preserving originals; each item requires its own review/save decision. Explore
  explicit original-only saving for unsupported types, without claiming their
  contents can be read or searched.
- **A6:** pursue OCR, retaining originals and labeling derived text. Suggest OCR
  for likely scanned sources but run only on request initially; park automatic OCR
  for later. Local OCR remains available where supported; the user additionally
  permits a separately selected online provider only with clear per-use consent.
  Language resources are selected and explicitly downloaded in settings. Aim for
  broad online language coverage and platform/downloaded languages offline, but
  actual support depends on providers, models and devices and cannot be promised
  universally. Provider data handling and consent details remain open.
- **A7:** improve PDF reader fidelity and extraction incrementally while keeping
  originals and labeling incomplete results. Show original page layout first,
  with extracted text as a separate view. Explore a local password prompt for
  protected PDFs; do not store passwords by default.
- **A8:** investigate stronger platform-appropriate parser isolation, resource
  budgets and adversarial tests for untrusted documents.
- **A9:** explore consented quick capture/queue; preserve clear review and save
  semantics. Keep bounded, explicitly approved staged copies until save or explicit
  discard, with no automatic expiry.
- **A10:** explore optional explicitly enabled local pre-storage SENSE screening;
  consent details remain open. If screening fails, show the failure and ask the
  user to explicitly continue or cancel.

## Storage, security and release

- **B1:** pursue user-controlled full encrypted backup/restore including original
  files and relevant library data. Explore both passphrase and recovery-key
  methods, explaining that lost secrets can make backups unrecoverable. Export to
  an explicitly chosen destination without automatic upload. Preview and choose
  a supported restore strategy; do not silently replace an existing library.
  Format and exact restore coverage remain open. Current JSON export is not a full
  source backup.
- **B2:** pursue app-level library encryption and key management/migration design.
  Explore a choice of platform-protected device unlocking or app passphrase, with
  recovery and device trade-offs explained. Treatment of staged copies, recovery
  and platform constraints remains open; current storage is not claimed to have
  app-level encryption. Deletion must be described honestly as logical removal,
  not a secure-erasure guarantee; external caches, backups and storage behavior
  may retain copies.
- **B3:** production-grade gates, including signed physical-device tests,
  lifecycle, accessibility, performance and independent security review. Avoid
  wider testing releases until the required gates pass.
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
  interoperability. Reminders require individual user confirmation. Explore
  separately consented direct calendar integration; if access is not granted,
  offer reviewed calendar-file export instead. Extraction remains evidence-linked
  and user-reviewed.

## Collaboration, integrations and provenance

- **E1:** explore optional encrypted direct collaboration plus an explicitly
  chosen relay when direct connection is unavailable, with key storage, recovery
  and independent security review. Share only user-selected, approved material;
  current manual exchange remains.
- **E2:** explore separately authorized, narrowly scoped provider connections,
  starting with selected individual emails for review rather than mailbox-wide
  collection. No account is connected by this decision.
- **E3:** explore opt-in, filtered Android notification access; offer matching
  notifications for explicit review before durable capture. No listener or OS
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
