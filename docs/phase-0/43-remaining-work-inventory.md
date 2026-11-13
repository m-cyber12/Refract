# Remaining work inventory

This inventory distinguishes current implementation from requested future work.
The numbered roadmap through Phase 9 is documented, but that is not a production
readiness claim. Decisions and release gates remain in
[open work direction](24-open-work-direction-decisions.md); this list does not
replace them or imply that exploratory work is implemented.

## Capture and documents

- **A1–A2:** signed physical Android/iOS device, lifecycle, lock-state and real
  provider validation remain. Android pre-review shares are process-memory only.
- **A3:** static explicitly approved fetch and retained preview exist. Isolated
  rendering, real network/device end-to-end and hostile DNS/VPN/TLS validation,
  cancellation and independent review remain.
- **A4:** Firefox address-only prototype exists; actual Firefox Android/device
  verification, selected-text/page handoff, other browsers and any separately
  approved site permissions remain. No automatic collection or cloud relay.
- **A5:** supported UTF-8 formats including YAML as plain text, bounded per-item batch review and original-only
  PDF candidates exist. Broader formats, folder intake and original-only handling
  beyond PDF candidates remain incremental research; universal support is not
  promised.
- **A6:** OCR is not implemented. Explicit on-request local/consented online
  OCR, language resources, provider policies and independently labeled derived
  output remain.
- **A7:** separately approved PDF original export and limited extraction exist;
  in-app original-layout viewing, separate extracted-text view and local password
  handling research remain.
- **A8:** parser process isolation, hard memory/CPU budgets and additional
  adversarial testing remain. Existing bounds are not a sandbox.
- **A9–A10:** explicitly approved foreground capture recovery exists; further
  quick-capture UX and optional, explicitly enabled local screening remain.

## Storage, intelligence and integrations

- **B1–B2:** full encrypted backup/restore, app-level library encryption, key
  management, recovery and migration remain. Existing storage is not claimed
  app-level encrypted, and deletion is not secure erasure.
- **B3–B4:** signed-device, lifecycle, accessibility, performance and independent
  security gates remain, as does design/migration of maintained native projects.
- **C1–C3 / D1–D2:** measured scale and background work; optional downloaded
  local embeddings and generated answers; further evidence-linked extraction,
  descriptive timelines, knowledge tools and user-reviewed reminders/calendar
  work remain. No model, automatic download or inference is selected.
- **E1–E3:** optional direct/relay collaboration, narrow provider authorization
  and opt-in filtered Android notifications require design, consent and security
  work. They are not enabled by this inventory.
- **F1–F2:** trusted timestamp and C2PA evaluation and separate TLSNotary/zkTLS
  research remain; desktop remains lower priority than mobile. Provenance checks
  cannot establish factual truth.

Physical signing/provisioning, real devices and independent review require
external resources. No CI pass can substitute for those gates. Work must remain
local-first and consented, preserve originals and explicit organization choices,
and avoid inferring personal identity or beliefs from reading behavior.
