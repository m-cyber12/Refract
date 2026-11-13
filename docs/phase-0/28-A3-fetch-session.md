# A3 — approval-bound fetch session

The isolated web acquisition crate now has an in-memory state machine for one
explicitly requested URL. It remains **unconnected to the app and C ABI**: the
app still never fetches shared URLs. This does not implement preview persistence,
review/save, mobile networking permissions or a production-ready fetch feature.

The session presents a unique approval ticket bound to its exact URL and redirect
state. Stale tickets, including tickets from another session or before retry, are
rejected. HTTP requires explicit confirmation for each HTTP request. A redirect
that changes host or effective port is presented for confirmation before DNS or
network activity. Related subdomains are treated conservatively as different
hosts. Same-destination HTTPS redirects may continue under the original fetch
request, subject to the five-hop cap; every hop performs fresh, bounded DNS
resolution and address checks. The underlying single-hop request cannot
implicitly follow redirects. Invalid/private destinations fail closed.

Failures do not automatically retry. The caller may request a fresh approval for
an explicit retry. A successful result consists of exact accepted HTML response
bytes and the requested/final addresses, held only in memory until taken or
cancelled. Redirects and results may contain sensitive URLs or content and must
not be logged. These addresses are network request targets (fragments removed),
not claims of publisher identity or publication time.

Tests simulate redirects and errors without network access. They cover exact
bytes, same-host continuation, changed-destination and HTTP prompts, stale and
cross-session approvals, explicit retry, blocked private redirects, loop caps and
cancellation before or after a response. DNS/transport fixtures remain separate.
The blocking session cannot interrupt an active request; worker-isolate/UI
lifecycle and active cancellation still need design. Hostile DNS/transport/TLS,
mobile platform behavior, consent presentation, durable-preview permission and
cleanup, review binding, resource limits and independent security review remain
open.

## Validation

For implementation `d6740fe`, GitHub Actions passed
[Rust tests and host build](https://github.com/m-cyber12/Refract/actions/runs/42859353635),
[Flutter tests and Android packaging](https://github.com/m-cyber12/Refract/actions/runs/42859353735),
[Android emulator share smoke](https://github.com/m-cyber12/Refract/actions/runs/42859353700),
[unsigned iOS builds and handoff tests](https://github.com/m-cyber12/Refract/actions/runs/42859353554),
and [documentation lint](https://github.com/m-cyber12/Refract/actions/runs/42859353489).
Only Rust host tests exercise the isolated session. Mobile checks do not exercise
web acquisition. The earlier Android draft-count failure documented in the prior
increment remains unexplained despite later passing runs.
