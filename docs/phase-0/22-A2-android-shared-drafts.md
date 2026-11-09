# A2 increment — Android shared-draft handoff

This increment targets Android intake, not all of A2. iOS Share Extension source
and release packaging remain unvalidated and are not made production-ready here.
A3 URL fetching, browser integration, OCR and parser isolation remain untouched.

## Contract

- Android `SEND` and `SEND_MULTIPLE` accept text and OS-authorized `content://`
  streams: UTF-8 TXT/Markdown/HTML or PDF. A stream in `ClipData` is also accepted.
  No broad storage permissions, persisted URI grants, `file://` paths or network
  fetcher are added. Providers can download/cache a user-shared file themselves.
- Native intake reads off the UI thread and retains bounded **process memory**.
  Native pull/ack IDs bridge cold start and Flutter readiness. Flutter also pulls
  on resume. No unreviewed file, text, URI or route argument is written by this
  Android intake path to disk or the library. This is not restart durability.
- Each native/Dart inbox has at most 16 entries and 24 MiB of input, separately.
  Text input is limited to 2 MiB, PDF to 10 MiB. Native intent work is reserved
  before enqueue; a single reader bounds executor concurrency. Native completed
  batches wait for the UI thread before reading another batch. Platform and codec
  copies/base64/decoded strings add overhead: these are not hard RAM/CPU budgets.
- Empty, unsupported, oversized or expired-grant files become generic per-item
  errors, without source snippets or provider paths. Overflow is visible and asks
  for a smaller re-share; it is not silently accepted. Device/provider failures
  can still terminate a process or block a provider read. No parser/provider
  sandbox or hard read deadline is claimed.
- Shared drafts are independent of A1 approved jobs. The app-wide banner links to
  an inbox; it never navigates automatically, previews automatically, overwrites an
  open editor or saves while startup is loading. Opening Review uses route extras,
  never source-bearing route URLs. Files carry only an untrusted parser suggestion.
- Preview and the existing explicit durable-save confirmation remain mandatory.
  Successful save/open-existing removes the shared inbox entry. Returning from
  review retains original shared input, not editor changes. Discard removes the
  inbox entry; open editors can still hold copies. It is not secure erasure.
- Android process death loses unreviewed drafts by design. Activity/engine
  recreation within the process uses the remaining native queue; received activity
  intents are consumed to avoid replay. Dart retries an uncertain acknowledgement
  without adding a duplicate. Repeated deliberate shares have separate IDs.

## Validation

Pending real SDK and emulator execution. No local Flutter/Kotlin/Android SDK is
installed. Syntax/lint checks alone are not runtime evidence.

Added Dart tests cover queued cold delivery before page subscription, resume,
multiple entries, exact binary/BOM bytes, uncertain acknowledgements, capacity,
invalid UTF-8/errors and explicit review without navigation on incoming delivery.

The Android smoke workflow now builds a **separate synthetic sender APK** with a
non-exported content provider. It exercises real temporary URI grants and checks
cold/warm/backgrounded delivery, multiple Markdown/PDF streams, unchanged open
input, no originals before review/preview, explicit A1 PDF save, exact saved bytes,
denied grants, unsupported/oversized files and the ephemeral process-death boundary.
Fixture code is under `.github/fixtures`, never added to the product manifest/APK.
UI XML, screenshot and synthetic logcat are collected as evidence on failure too.
APK identity checks require `dev.refract` and its custom `MainActivity`, with
supported share filters; generated scaffolding uses `--org dev`. Older scaffolding
used `--org dev.refract`, generating a different package, while the old launch
smoke did not assert successful UI delivery. That prior smoke is not evidence
that the native share receiver was packaged/launched correctly.

## Remaining A2 gates

- iOS target embedding, entitlements/App Group, extension-safe handoff, signed
  packaging and physical-device suspension/cold launch/file-provider behavior.
  Existing iOS legacy text callback is compatible with the new Dart inbox, but
  the existing extension persists a single pending text in UserDefaults and may
  lose it before Flutter is ready. This Android increment does not repair that
  iOS privacy/delivery gap or validate its use of host-launch APIs.
- Android physical devices, additional vendor/cloud providers, low-memory and
  grant-revocation/lifecycle variations. Emulator fixture results are not proof
  of every provider or device behavior.
- Durable pre-review sharing would require a separate explicit privacy decision;
  the reviewed-save queue must not silently become storage for unreviewed shares.
