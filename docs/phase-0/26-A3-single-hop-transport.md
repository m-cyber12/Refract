# A3 — isolated single-hop transport increment

This crate is **not connected to the mobile app or C ABI**. URL references remain
unfetched in the product. No automatic downloads, persistence, cookies, account
credentials, telemetry or new UI are introduced. The standalone crate is not a
dependency of the app; adding it to the workspace runs its tests independently.

The experimental blocking transport accepts an explicitly approved request and a
complete freshly resolved address list supplied by a future caller. It requires
separate approval for HTTP and changed redirect destinations, checks the entire
address list with the A3 policy, pins that list to the hostname, disables proxies
and redirects, and performs a single GET with TLS certificate checks enabled.
Redirect locations are returned without following them. It requests identity
encoding, accepts only UTF-8 HTML, enforces a 2 MiB body limit and connection/total
request timeouts, and neither renders scripts nor fetches embedded resources.
Response bytes are returned in memory; no reviewed-save or staging path is added.
Errors do not include addresses or content. These are design and test targets,
not evidence that an adversarial network has been fully contained.

The future app integration must provide a bounded, fresh DNS resolver (including
answer completeness and rebinding tests), explicit per-hop UI approval, lifecycle
and cancellation handling, durable preview-copy consent and cleanup, review
binding, and user-facing error/privacy descriptions. Blocking work must not run on
the UI thread. Redirects must be revalidated and resolved again on every hop;
approval cannot be inferred from redirect data. Device DNS/proxy/VPN behavior,
TLS trust, hostile response framing, interruption, resource budgets and security
review remain release gates. A redirect's sensitive address must not be logged.
The full reviewed capture feature and production readiness are **not complete**.

Local fixtures exercise request headers, response bytes, redirect non-following,
size limits, type/encoding restrictions and rejection of unapproved/private
requests. Fixture-only loopback bypasses the production destination guard; it is
not a production override. These tests do not establish TLS authenticity or DNS
rebinding resistance end to end. CI validation is pending.
