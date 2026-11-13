# Android-first v1 scope and release gates

The user selected Android first; iOS and desktop are deferred, not declared
complete. V1 requires the existing capture baseline, on-request OCR and original
PDF page layout, encrypted full backup/restore, app-level library encryption,
optional downloaded AI models, collaboration, provider connections, opt-in
notification capture and advanced provenance. These are scope decisions, not
permission to enable integrations or download models automatically. Earlier
per-use consent, local-first, original-preservation and evidence-labeling
constraints remain in force.

## Work required before v1

1. Define and implement bounded, separately reviewed capture, on-request OCR
   with resource/language choices, and original-layout PDF viewing. Preserve and
   distinguish originals and derived text; address hostile parser isolation.
2. Design, implement and test encrypted complete backup/restore and app-level
   encryption, keys, recovery, migration, interruption and data-loss handling.
   Do not present the existing partial plaintext JSON as a backup.
3. Implement optional downloaded models and evidence-linked outputs; establish
   licensing, download integrity, device/resource budgets and deterministic
   fallback. No model is selected by the scope decision.
4. Implement separately approved collaboration and provider connections,
   filtered opt-in notifications and provenance capabilities. Specify threat
   models, supported providers, trust limits and data sharing before enabling.
5. Maintain Android project/build configuration and measure performance,
   accessibility, lifecycle and recovery on representative physical devices.
6. Obtain independent security review, resolve release blockers, validate signed
   Android builds and real providers, and complete store/privacy/support release
   requirements. CI and unsigned builds do not substitute for these checks.

Feature-specific acceptance criteria, models, providers, security designs and
release sign-off remain to be resolved. These selections substantially enlarge
v1; none of these items is marked complete by this document.

## Existing JSON copy safety

The legacy settings action now asks before writing its partial unencrypted JSON
copy, and describes its 10,000-item limit, omitted originals, overwrite and OS
backup risks. This is a safeguard, not encrypted backup or restore, and does not
remove existing copies or guarantee secure deletion. It is separate from the
user-selected encrypted-backup requirement above.
