# A2 increment — iOS consented share handoff

## User decisions

- Explicit approval before an app-owned handoff copy is stored. Full source
  extraction/review and library-save approval remain in REFRACT, not the extension.
- Android-format parity: text, unfetched HTTP(S) addresses, UTF-8 TXT/Markdown/HTML,
  PDF and multiple items. Unsupported input is not silently converted.
- Keep staged copies until successful save/open-existing or explicit discard;
  no automatic expiry. Delivery to Dart is not deletion.
- Open REFRACT manually. No forced app launch, responder-chain hacks, private API
  or `UIApplication.shared` from the extension.

## Implementation contract

The extension shows consent before provider loading or any source-content write.
A successful approved batch is published atomically in the shared App Group, with
16 items / 24 MiB source bytes total, text 2 MiB and PDF 10 MiB per item. A failing
selection is not silently partially published. Provider callbacks can materialize
objects before app checks; these are not hard provider RAM/CPU/deadline limits.
PDFs are not parsed and HTML is not executed in the extension. File representations
are read inside their authorized callback lifetime; only file URLs are read as
files. HTTP(S) URLs are retained as text, not fetched.

The shared store uses cross-process advisory locks, reserved UUID batch paths,
0600 files, atomic rename, synced file/directory writes and per-record consistency
hashes. Hashes are not signatures, authenticity or user authentication. Only
interrupted private `.pending-UUID` files are reconciled under the store lock;
published batches never expire. Damaged batches block new staging and are exposed
for explicit discard/re-share, not silently deleted. No library directory sweep.

App Group copies have **no REFRACT app-level encryption**. iOS Complete file
protection is a separate device/lock-state layer. The directory is excluded from
new backups; this is not erasure of prior backups, caches or memory. File protection
and actual entitlements/provisioning need device validation. Logical deletion
never deletes an original in the library or an approved capture job.

Native peek/ack marks session delivery only. Launch/resume reads staged copies;
a new Dart session can rediscover them. Only an explicit delete operation removes
native data. Dart retains the entry if removal cannot be confirmed. A successful
library save remains successful even if redundant-copy cleanup fails. Jobs
completed through separate crash recovery can leave a redundant handoff copy;
review/open the existing library copy or discard the handoff copy explicitly.
Returning from review does not persist editor changes back into the handoff file.

Consent time is recorded at the extension approval action and labeled separately
from library import and source publication times. Legacy `pendingShare` content
from older builds is exposed without creating a new legacy copy, labeled as
having no recorded prior consent, and cleared only on save/discard. New shares
never use the old single-text UserDefaults slot.

## Packaging and reproduction

After Flutter scaffolding, `apps/mobile/ios/configure_handoff.rb` reproducibly adds
the shared store source to Runner and ShareExtension, creates/embeds an actual
extension target, enables extension-safe APIs and configures App Group entitlements.
The main app uses the implicit-engine registrar, not a force-unwrapped window.
Rust is statically linked with C ABI roots retained for `DynamicLibrary.process()`;
putting an unused archive in a directory is not sufficient.

Defaults are `dev.refract`, `dev.refract.ShareExtension`, `group.dev.refract`.
Set `REFRACT_BUNDLE_IDENTIFIER`, `REFRACT_APP_GROUP_IDENTIFIER` and, for signed
builds, `DEVELOPMENT_TEAM` to identifiers provisioned by the developer's Apple
account. No credentials or signing keys are stored or requested by this script.
Both targets need matching App Group entitlements/profiles. Defaults alone do not
register an App Group or grant an Apple capability.

The `ios-handoff` workflow builds real Foundation store tests on macOS, checks
cross-process publication and limits, scaffolds/wires the project twice to check
idempotence, builds Rust device/simulator archives, compiles unsigned device and
simulator apps, and checks embedded extension metadata and retained Rust ABI roots.
This is build/store evidence, not a signed physical-device share-sheet test.

## Validation status

Implementation written; macOS SDK/compiler and runtime checks pending. The local
sandbox has no Swift/Xcode, Ruby or Flutter SDK. Syntax checks are supplemental,
not compilation or runtime evidence. Do not call all of A2 complete yet.

Remaining: signed provisioning and physical iPhone/iPad tests of extension
consent/cancellation, provider files/multiple items, lock state, suspension,
main-app restart, actual App Group access and user-directed removal. Apple review,
store signing, all vendor providers, power-loss guarantees, secure erasure and
hostile-provider/parser isolation are not established by unsigned CI builds.
