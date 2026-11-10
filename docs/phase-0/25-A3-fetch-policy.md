# A3 — URL fetch policy foundation

This increment adds **planning checks only**, not a network client or a user-facing
fetch feature. URL references remain unfetched. Nothing here changes capture,
consent, persistence or library-save behavior.

The pure Rust policy rejects malformed/credential-bearing addresses, local or
special-purpose host/address categories, empty/mixed unsafe/oversized DNS results,
and redirects beyond five hops. It strips fragments from request targets. The
address checks are intentionally conservative and may reject destinations that
could technically be routed publicly. Redirects changing host or effective port
require confirmation; this is more conservative than treating related subdomains as
one site. Every HTTP request requires confirmation, including redirect hops.

This policy by itself **does not prevent SSRF**. A future transport must apply it
before every request, resolve and validate all answers, pin the actual connection
to validated addresses without re-resolution or proxy delegation, authenticate TLS
against the requested hostname, and disable automatic redirects and credentials.
It also needs bounded reads/timeouts/decompression, consent and cancellation,
local staging with explicit approval, reviewed original-byte binding, lifecycle
and adversarial DNS/redirect tests. No network access or durable fetched content
is introduced by these checks. An isolated renderer is a separate investigation.

Tests cover special IPv4/IPv6 ranges, numeric-address encodings, mixed DNS answers,
literal/address mismatch, redirect limits, HTTP approvals and changed hosts/ports.
Compilation and runtime validation require CI; do not treat policy tests as an
end-to-end security audit or a production-readiness sign-off.
