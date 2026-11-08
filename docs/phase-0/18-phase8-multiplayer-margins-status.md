# Phase II Master — Phase 8: Multiplayer Margins

Selected shared content, durable offline editing, explicit conflict resolution,
recipient-encrypted foreground exchange and conservative annotation anchoring.
Implementation is present; final CI validation of this revision is pending.

## Dependency evaluation and CRDT choice

Evaluated the projects' Rust architecture and documented capabilities:
[Loro](https://github.com/loro-dev/loro) and
[Automerge](https://github.com/automerge/automerge). Both offer local-first CRDT
storage and merging; neither establishes human identity, application permissions,
privacy boundaries or honest collaborators. Automerge additionally documents a
compact change format and synchronization protocol. No comparative mobile
performance benchmark was conducted; no performance superiority is claimed.

Retain the repository's existing Loro 1.x dependency instead of adding a second
CRDT implementation. A last-writer-wins JSON annotation register alone would hide
concurrent edits, so authenticated workspaces use a Loro map of immutable,
uniquely identified logical revisions and an explicit parent DAG. Joining these
revision sets is commutative/idempotent. Concurrent heads, including an edit
concurrent with deletion, remain visible until the user explicitly selects a
version and reviews all current heads. Stale editor forms cannot silently join
unseen heads. Previously committed versions remain in history.

The wire protocol exchanges bounded, validated logical revision records, NOT
opaque untrusted Loro snapshots. This prevents a remote collaborator from
injecting arbitrary CRDT roots or rewriting/deleting existing immutable history.
Validated additions are applied to the durable local Loro document. Transport is
full bounded logical state, not a bandwidth-optimized incremental Loro sync
protocol or character-by-character collaborative text editing.

## Privacy and selected-device permissions

- Schema 11 introduces authenticated workspaces, separate from legacy anonymous
  workspace/outbox prototypes. Migration preserves private annotations, original
  documents and legacy data; nothing is automatically promoted or exported.
  Legacy unauthenticated raw-state import/export C entry points fail closed.
- A new workspace starts private, with one owner and exchange paused. Private
  Reader annotations stay private; sharing creates a separately reviewed copy.
  Only explicitly placed workspace entries, their retained history and selected
  device roster are in transfer payloads. No original files, entire library,
  private decisions, unrelated metadata or private annotation database is sent.
- Source quote sharing defaults to **no prefix/suffix/heading, source title or
  source URL**. Optional context is at most 40 characters on each side and a
  120-character heading. The user reviews exactly what is included. A canonical
  review digest binds publication to the selected workspace and reviewed
  content/source representation;
  source changes require another preview rather than silently sharing new text.
- Device contact cards bind an Ed25519 signing key and X25519 encryption key with
  a self-signature. Names and keys do not verify a real-world person. Users must
  independently compare full fingerprints through a trusted channel.
- Only the owner signs workspace policies. Each policy binds workspace identity,
  immutable owner key, epoch and selected owner/editor/viewer device cards.
  Editors may modify all shared content; viewers cannot publish edits, invite
  devices, change roles or export a state update. Viewers can acknowledge imports.
- Only the owner changes roles/removes devices. Old/forked policies are rejected
  once a newer policy is known. Owner policy-only packets can notify removed
  devices without sending new annotation content. Offline devices necessarily
  keep their last known policy until an update reaches them. Revocation cannot
  erase received copies, prevent screenshots, or retroactively revoke disclosure.
- Collaborators may supply revision-author fields. These are explicitly unverified
  attribution, not cryptographic proof of individual edit authorship. Signed
  exporter keys are recorded separately in the local exchange journal. An editor
  is trusted to write workspace content, not to establish factual truth.

## Encrypted optional foreground exchange

- Ed25519 signatures bind domain-separated protocol headers, nonce and ciphertext.
  Fresh ephemeral X25519 plus HKDF-SHA256 derives a per-transfer key;
  XChaCha20-Poly1305 encrypts/authenticates the payload with the header as AAD.
  Workspace ID, epoch, transfer kind, sender, recipient and ephemeral public key
  remain routing metadata. Wrong-recipient, malformed, tampered and unauthorized
  packets are rejected before shared-state mutation.
- No network, relay account, continuous background process or always-on P2P is
  required or promised. Users explicitly prepare an invitation, state update or
  policy packet, save an encrypted JSON file or copy a small package, deliver it
  using a channel of their choice, inspect it on the selected device, verify the
  owner fingerprint and explicitly merge it. A new join starts further exchange
  paused. Optional transport adapters remain future work, not a pretend connection.
- Large packages use the platform document picker/save dialog rather than risking
  Android clipboard IPC limits. File reads are streamed and size checked. Nothing
  is automatically copied or saved. Selecting an OS/cloud document provider is
  an explicit user action; the application adds no mandatory cloud connection.
- Local CRDT state is durable independently of transfer rows. Prepared encrypted
  outgoing packets are retained for exact retry; preparing/exporting is never
  called delivery or complete synchronization. Policy-stale outgoing packets must
  be rebuilt rather than silently retried under changed access permissions.
- Incoming records, policy, bindings/journal changes and receipts commit
  transactionally. Existing immutable revision rewrites, missing/cyclic parents,
  invalid references, unknown fields and limits are rejected without partial
  merges. Canonical packet hashes make whitespace/object-order replay equivalent.
- Receipts are separately prepared, signed and recipient-encrypted after import.
  They acknowledge the hash of a specific packet addressed to that signing peer.
  A receipt is that device's claim of import, not proof of reading, honest remote
  storage, delivery to every collaborator or universal convergence. Receipt-of-
  receipt loops are not generated. No fake progress percentage is shown.

## Shared content and resilient anchors

- Notes, quoted highlights, comments/replies, source references and named research
  collections/reading lists are supported. Entries can belong to a collection,
  carry read/done state and participate in nested discussion threads. Deletion is
  an explicit retained tombstone, not erasure of previously shared history.
- Anchors record a workspace-scoped random document identity, content fingerprint,
  representation-version fingerprint, quote, optional adjacent prefix/suffix and
  heading, block index, anchor schema version and relative-position hint.
- Recipient devices explicitly match shared document identities to local sources;
  bindings are private and never exported. Schema 12 preserves existing bindings
  while allowing independent collaborator aliases to match one local original;
  users never need to duplicate a private document merely to match another alias.
  No private-library scan or automatic same-URL attachment occurs. Missing bindings are shown as unbound.
- Anchor schema 3 fingerprints length-delimited block indices, kinds and UTF-8
  text, so block renumbering cannot accidentally reuse an exact-match address.
  Legacy anchors fall back to conservative quote/context resolution.
- Unchanged content with the correct block/unique occurrence is exact; otherwise a
  unique surviving exact quote can relocate. Multiple occurrences require uniquely
  matching adjacent context and heading where present. Relative position alone
  never resolves ambiguity. A changed/missing quote stays lost even when old
  prefix/suffix strings happen to survive; repeated ambiguous text is unresolved.
- Every conflicting version has its own local anchor resolution/source link.
  The UI never applies the first version's source location to another version.
  Unresolved anchors do not expose a misleading supporting-block button.

## Bounds and remaining trust limitations

- Up to 30 selected devices, 150 entries, 512 immutable revisions, 32 concurrent
  heads per entry and 900 KB serialized logical history per workspace. Oversized
  changes fail explicitly; no hidden truncation or automatic history loss occurs.
  Packet limit is 1.6 MB and decrypted plaintext 1 MB. Source selection shows the
  first 100 local items; workspace lists show the latest 100 metadata summaries,
  without eagerly loading all workspace histories. Exchange/history lists display
  the latest 100 records; durable outgoing transfers are not automatically erased.
- Device signing/decryption secrets live in the private local application database,
  not hardware-backed OS key storage. There is no account recovery service, claim
  of encrypted-at-rest SQLite, protection against database/device compromise,
  independent protocol audit or forward-secrecy guarantee. Do not share the raw
  database. Lost device keys are not recoverable through this transfer protocol.
- Manual sharing cannot stop an authorized reader/editor from copying or
  redisclosing information. Routing metadata is not hidden. This is selected-
  device collaboration, not verified human accounts, live presence, live cursors,
  automatic network discovery, a relay service or continuous background syncing.

## Integration and validation

- `refract_margins(handle, json)` exposes contact validation, private workspace
  creation, owner policies, reviewed publication, explicit conflict resolution,
  private source matching, inspection/import/export, receipts, retries and history.
  Requests use the existing owned-string envelope and strict typed decoding.
- Flutter exposes Margins from Settings, Smart Memory and each Reader annotation's
  sharing action. Dedicated pages cover workspaces, people/access, exact content
  previews, discussion threads, history and manual encrypted exchange.
- Backend tests cover convergence, explicit resolution/stale heads, private
  defaults, read-only rejection including signed malicious writes, recipient
  encryption, owner verification, policy/revocation timing, immutable-history
  rejection/rollback, receipt binding/replay, source privacy/review changes,
  anchoring, reopen durability and version-10/11 migrations without legacy promotion.
  Native ABI tests exercise two stores and negative/legacy requests. Mobile tests
  exercise consent, roles, per-version source navigation, explicit conflict
  review and safe handling of large file-only packages.
- Local Rust/Dart syntax parsing and SQLite migration checks are supplemental,
  not substitutes for compiler/device validation. Final GitHub Actions Rust,
  Flutter analysis/tests, packaged APK, emulator and documentation gates pending.
- Manual two-physical-device file/clipboard transfer, large-workspace latency,
  accessibility review, independent cryptographic review and adversarial protocol
  assessment remain outstanding. Emulator smoke checks launch/native loading,
  not every collaboration flow or cross-device delivery.
