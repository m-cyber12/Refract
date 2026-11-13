# A3 — consented static web capture integration

## Scope and flow

The mobile capture screen now offers a separate **Fetch a webpage with consent**
flow. Opening it, saving a URL reference, or receiving a share never starts a
network request. Shared text that looks like a complete HTTP(S) address may be
prefilled, but it is not fetched until explicitly approved. The user first
approves the disclosure and a durable preview copy, then confirms the exact
request. HTTP requests and host/port-changing redirects require confirmation
before the corresponding network request; limited same-destination HTTPS
redirects can continue under the original approval. Untrusted redirect targets
are revalidated and resolved per hop. Retries are manual.

The Rust transport checks all system DNS answers, pins a validated address, blocks
local/private and other special ranges, disables proxies, cookies, referrers,
automatic retries and automatic redirects, and verifies HTTPS certificates. It
requests identity encoding and accepts UTF-8 HTML up to 2 MiB. It does not run
scripts or load page resources, and dynamic pages may be incomplete. The actual
network address and query may be visible to the target, network and configured
DNS resolver; blocking private destinations is defense in depth, not a security
audit. Blocking work runs on a Dart isolate. Active DNS/HTTP cannot currently be
cancelled by the UI; configured DNS and request timeouts and bounded DNS workers
limit waiting but cannot interrupt a stuck OS resolver.

On success, the approved response bytes and requested/final addresses are
staged in local SQLite, not the library. Migration 16 limits retained copies to
16 entries / 24 MiB total, with a 2 MiB per-entry limit, SHA-256 consistency
check and explicit deletion. No automatic expiration occurs. Approval time is a
device timestamp, not source publication time. Previews survive restart and can
be opened or discarded from **Web previews**. They are stored without app-level
encryption; logical deletion is not secure erasure of SQLite/WAL, backups,
provider caches or memory. A fetch or staging failure is reported separately;
if staging outcome is uncertain, check Web previews before retrying.

Opening a retained copy presents it in the existing local HTML preview/review
flow. The final request address is the library source address; the initially
requested address is displayed separately in the preview, but is not separately
persisted in the library item. A successful reviewed save or exact duplicate
reuse removes the handoff copy only if the content and final-address binding were
unchanged; edited captures leave the original fetched copy for explicit review or
discard. A crash or cleanup failure after save can leave a redundant copy. No
library content is silently replaced. This is not a guarantee against power loss
or storage corruption.

## Validation and outstanding gates

Unit and widget tests cover consent, approval tickets, redirects, byte limits,
private-address rejection, bounded DNS workers, durable staging/reopen/deletion,
content-preserving save cleanup and the native ABI. Network transport fixtures
use test-only loopback bypass in the isolated Rust transport; production has no
such bypass. Automated tests do not yet establish a complete live-fetch-to-save
flow on real Android or iOS, hostile DNS/proxy/VPN and TLS behavior, active
cancellation, power-loss handling, accessibility or independent security review.
Signed iOS physical-device validation and the other production gates remain open.
The earlier Android share draft-count failure is still unexplained even though
later smoke runs passed. A later Android emulator run for `a565a02` also failed
in the emulator step without a more specific annotation; its cause is unknown.
Do not describe this as production-ready.

For implementation `5e48dee`, the following checks passed:

- [Rust tests and host build](https://github.com/m-cyber12/Refract/actions/runs/42877139008).
- [Flutter analysis, widget tests, real Dart-to-native approval test and Android packaging](https://github.com/m-cyber12/Refract/actions/runs/42877139015).
- [Android emulator share smoke](https://github.com/m-cyber12/Refract/actions/runs/42877139016).
- [Unsigned iOS device/simulator build and handoff tests](https://github.com/m-cyber12/Refract/actions/runs/42877139049).

These runs do not prove live web fetching on mobile or explain the earlier smoke
failures. A prior documentation-only follow-up passed its documentation check.

### Save cleanup binding

After an unchanged fetched preview is saved, cleanup compares its ID, requested
and final addresses, recorded SHA-256 and device consent time within a SQLite
write transaction. It also recomputes the hash of the retained bounded HTML
before deletion. A changed or replaced row is not silently discarded. If no
row matches, the UI asks the user to check Web previews; the approved library
save remains separate. Explicit discard still removes the selected preview ID,
including damaged copies. These comparisons are consistency checks, not proof
of source authenticity or secure deletion.

The explicit discard dialog binds its deletion to the selected summary: ID,
addresses, byte length, recorded hash and approval time are compared atomically.
A mismatch is reported rather than deleting the changed row. A damaged row can
still be discarded after reviewing its current summary. Because this compares
metadata rather than authenticating or inspecting damaged content, it cannot
detect every possible change. Preview reopening and idempotent restaging avoid
loading oversized damaged HTML blobs into application memory; such rows remain
listed for explicit discard. SQLite and OS-level resource use is not sandboxed.
