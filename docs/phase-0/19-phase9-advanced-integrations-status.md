# Phase II Master — Phase 9: Advanced Integrations

Optional integrations are not prerequisites for the core. This increment provides
consent-gated local adapter boundaries, selected email copies, reviewed calendar
files, and advanced integration research. **Final validation is pending.** Live
mailbox connectors and notification listeners are not implemented or connected.

## Implemented: consent and offline adapters

- Schema 13 adds only local adapter/category consent and a monotonic revision.
  Reading the catalog does not enable anything. Default is disabled, with no
  selected categories. Unknown/unimplemented providers cannot be enabled through
  the ABI. Disabling clears categories and invalidates existing review digests;
  it does not erase previously captured library copies or external files.
- `refract_integrations` is a strict, bounded JSON dispatcher using the existing
  owned-string ABI. New adapters remain in the modular monolith, not services.
  There are no account tokens, passwords, OAuth placeholders, network clients,
  background workers, analytics or new OS permissions in this increment.
- Settings links to Optional integrations. Every capability shows actual
  availability, scope and limitations. Local consent is explicitly **not** a
  provider authorization, OS permission or account connection. Core manual
  import/share remains independent of these optional local adapter controls.

### Selected email copy (manual, not a mailbox connector)

User selects an allowed category and explicitly chooses/pastes one UTF-8 `.eml`.
A stateless preview retains nothing in the database. Supported format is one
inline `text/plain` MIME part, including base64/quoted-printable transfer decoding.
Raw email limit: 256 KiB; decoded body: 48 KB; up to 100 headers. MIME type is
checked before recursive parsing; HTML, multipart and attachments are rejected.
Copy the wanted text manually for unsupported formats. This is deliberately not
an `.mbox` importer or a broad inbox ingestion engine.

Subject, From and email-declared Date are excluded by default. If explicitly
selected, each is labeled an unverified header; email-declared time is not capture
time. Categories are user-selected, not AI facts. The exact retained text is
reviewed, and its digest binds the category, selected content and consent revision.
Publication recomputes the preview and rejects stale/changed consent or text.

Only the approved copy is compiled into the private library with source kind
`email_copy`. Its immutable input blob/hash represents **that selected copy, not
original email bytes**. The full `.eml`, unselected headers and attachments are
not retained. Normal local indexing/uncertain candidate extraction then applies.
Retained-copy management remains available with the adapter disabled. Users can
open/delete a selected copy without deleting other originals; filesystem cleanup
is reported separately, with no secure-erasure or backup/external-copy deletion
promise. Attached annotations/claim reviews/source links are removed; existing
decisions, subscription records and summary contents remain, and no subscription
is canceled. The list is bounded to the latest 100 copies.

No DKIM/SPF/DMARC, sender identity, purchase, obligation or publication date is
verified. The OS picker/provider may download/cache the selected file before
returning it; application size bounds do not bound provider cache/download work.
The raw preview is transient in page memory, not an encrypted staging vault.

### Calendar integration (reviewed ICS file only)

The user explicitly allows confirmed dates, selects at most 20 user-confirmed
Signal candidates, supplies export titles, reviews the complete unencrypted ICS
and chooses an OS save destination. Candidate listing is bounded to the latest
100 confirmed dates and reports truncation. No private-library-wide scan occurs.

- Current exact evidence and the mentioned ISO date must still exist. Missing,
  ignored, dismissed, unconfirmed or changed source evidence blocks export.
- All entries use `VALUE=DATE` and an exclusive next-day end. A date mention does
  not establish an appointment time/timezone. Export does not book appointments,
  cancel subscriptions, make financial actions or schedule reminders.
- Private source titles/URLs are not automatically copied. The default export
  title is generic until explicitly edited. Source excerpts/local reference IDs
  require a separate opt-in and appear in the exact file preview.
- Text is escaped, UTF-8 lines folded at 75 octets, CRLF used, UID stable per local
  candidate. No `VALARM`, attendees, organizer, invitation method or recurrence is
  generated. Device-clock preparation time is not a trusted signed timestamp.
- Export revalidates consent, selection, source evidence, titles and preparation
  time against the reviewed digest. Saving a file is **not** calendar delivery or
  external import confirmation. A calendar provider may upload an imported file
  to a cloud account. REFRACT requests no calendar account permission and cannot
  retract/delete an external copy after export.

## Investigated: live email and authorized source architecture

Primary references reviewed:

- [Gmail discovery API](https://github.com/googleapis/google-api-go-client/blob/main/gmail/v1/gmail-api.json).
- [Microsoft Graph message retrieval](https://github.com/microsoftgraph/microsoft-graph-docs-contrib/blob/main/api-reference/v1.0/api/message-get.md).
- [Microsoft permissions reference](https://learn.microsoft.com/graph/permissions-reference).

Future provider adapters need independently reviewable capability manifests,
provider-specific delegated authorization, OS/browser-supported OAuth with PKCE
where supported, narrow scopes, secure OS token storage and explicit account
selection. Gmail body-reading permissions and Graph `Mail.Read` are broader than
a receipt category; provider/app-side search filters are **not** scope-limited
mailbox access. Graph basic metadata permissions do not provide unrestricted body
access. Do not describe a receipt query as authorization to read only receipts.
App registration, provider verification/policy, redirect handling, refresh-token
rotation/revocation and mobile secure storage require real provider testing.

Proposed processing boundary: validate current consent/account/category before
fetch, target user-selected IDs or narrowly queried candidates, show exact
proposed capture, retain only approved content, stop further processing on
disconnect, clear pending state/credentials and attempt provider revocation.
Distinguish local disconnect from successful remote token revocation. Retain
existing captures only with explicit deletion controls; no automatic broad inbox
backfill. Never parse/retain unrelated account messages as a convenience.

Additional source adapters must use authorized API/export/share/document access.
Existing manual text/HTML/PDF/share capture remains usable without any connector.
No browser credential scraping, accessibility harvesting, unrestricted folder
watching, hidden URL refresh or implied third-party account connection is added.

## Investigated: optional Android notification intelligence

[Android NotificationListenerService source](https://github.com/aosp-mirror/platform_frameworks_base/blob/master/core/java/android/service/notification/NotificationListenerService.java)
documents explicit listener binding/user settings, platform restrictions and work
profile/low-RAM limitations. A future native Android module would need:

1. Separate explanatory consent and a real OS notification-access grant.
2. User-selected package allowlists and explicit supported OS categories;
   unsupported/missing categories default to discard, not collect-everything.
3. Package/category filtering **before** reading text extras, followed by targeted
   local interpretation/review. No blanket notification cache, logs of dropped
   content, historical scraping or cross-app reading-history inference.
4. Recheck grant/allowlists on every callback and reconnect; stop on revocation.
   Account/work-profile boundaries, sensitive/hidden content, listener reconnect,
   duplicate/update/removal events and OS background behavior need device tests.

**No listener service or permission request ships here.** An unavailable tile
cannot be enabled. iOS does not gain unrestricted access to other apps'
notifications; no Android/iOS parity claim is made. Semantic purchase/travel
categories are not equivalent to Android's notification category metadata.

## Advanced provenance: decision record and actual hardening

Primary references reviewed:
[TLSNotary](https://github.com/tlsnotary/tlsn) (upstream warns against production use)
and [C2PA Rust SDK](https://github.com/contentauth/c2pa-rs).
No TLSNotary, generic zkTLS, C2PA or timestamp authority dependency is added.

| Technology | Possible claim | Trust/verification needs | Not established / decision |
| --- | --- | --- | --- |
| Content hash | Bytes match an independently known digest | Correct byte representation and trusted expected digest | Not authorship, truth or time; already available |
| Device signatures | A holder of a key signed these bytes | Domain binding, key provenance, revocation and secure key storage | Not human/legal identity; existing Margins signs exports, not every revision |
| Local Merkle inclusion | Evidence digest is consistent with supplied root/tree size/position | Independently trusted root, size and expected evidence digest | Not append-only history, trusted time or publisher identity |
| Signed timestamps | Authority attests a digest existed by its declared time | TSA chain/policy, algorithm validation, revocation and durable timestamp token | Not source truth or original creation date; deferred |
| TLSNotary | Selectively disclosed bytes relate to an attested TLS interaction under a protocol's assumptions | Supported protocol/version, notary/session trust, domain/time binding, redaction/leakage and audited verifier | Not legal identity, fulfillment or arbitrary page authenticity; research only |
| zkTLS family | Protocol-specific private statement about an interaction | Evaluate each concrete protocol/circuit, prover/verifier/notary assumptions, freshness and selective disclosure | Not one interchangeable standard or generic verified badge; research only |
| C2PA | Signed media assertions/manifests bind to an asset under a trust policy | Manifest/asset binding, signature/certificate/trust-list/revocation and assertion validation | Not factual truth or universal identity; missing manifest is not proof of fraud; deferred |

Actual verifier fixes: fixed-length lowercase ASCII hash decoding cannot panic on
odd/non-ASCII input; corrupt evidence hashes fail instead of being replaced with
zero bytes or silently omitted. Proofs now carry tree size; the bound verifier
checks an independently supplied root, size and evidence digest, sibling direction,
path length, index and odd-tail duplication. Duplicate evidence hashes resolve to
the requested record's position, not the first equal hash. Legacy proofs lacking
size fail closed and can be regenerated from the local evidence log.

The compatibility `verify_proof` helper checks consistency with a supplied root;
it does not independently bind to file bytes or authenticate tree size. A local
root computed from the same database as its proof is not independent evidence.
`verify_local_proof` exposes the stronger explicit expected-value boundary.
Single inclusion proofs do not prove append-only log evolution, and historical
record ordering is not retroactively certified. These limitations now appear in
proof statements, rather than implying a witnessed append-only history.

## Validation and remaining gates

Planned coverage: default-denied/category authorization, unsupported provider
rejection, disabled/re-enabled consent invalidating previews, no preview retention,
email exclusion/decoding/unsupported MIME, immutable selected-copy bytes, calendar
confirmation/staleness/escaping/folding/privacy, schema-12 upgrades, malformed
proofs and independent value mismatches. Native ABI and mobile consent/navigation
checks complement backend tests. Syntax/migration checks alone are not compiler
or device validation. CI results will be recorded after the final source run.

Remaining release work: real provider OAuth/security review, hardware-backed
credential/device-key storage, Android native listener design/device tests,
calendar-client interoperability/physical-device save tests, accessibility and
large-library latency measurement, independent cryptographic/adversarial review.
No continuous background connectivity or equivalent cross-platform permissions
are promised. Core library operation remains local and independent.
