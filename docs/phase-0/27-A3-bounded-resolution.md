# A3 — bounded DNS resolution increment

This remains an isolated Rust crate, **not integrated into the app**. URL shares
are still never fetched by the app. No user consent, storage or library behavior
changes in this increment.

Before DNS, the resolver checks explicit single-hop request approval and any HTTP
or changed-destination approvals. Public IP literals are checked without DNS.
For domain names it uses the operating system resolver, with two fixed workers,
a four-request bounded queue, a five-second caller timeout, and an answer cap.
A timed-out queued job is skipped; an active system lookup cannot be interrupted
and can occupy its worker until the OS returns. Saturation fails explicitly rather
than creating unlimited threads. DNS reveals the hostname to configured resolvers;
there is no claim of anonymous or encrypted DNS.

The entire returned address list is checked against the conservative A3 policy.
A private, special-purpose, mixed or oversized answer fails; no partial list is
used. The result is a non-publicly constructible, single-use request capability
binding the URL to the validated addresses. It expires after ten seconds. The
single-hop transport consumes it and pins the connection, without DNS fallback,
proxy, auto-follow or retry. Each new redirect hop needs a fresh resolution and
approval checks; callers must still enforce the redirect chain limit and bind UI
choices to the exact destination. DNS results are those exposed by the system
resolver, not a guarantee of complete authoritative records or DNS authenticity.

Tests use a fake resolver to check approval before lookup, mixed answers, fresh
resolution after redirects, timed-out queued jobs and fixed worker concurrency;
a separate fixture tests pinned HTTP transport. No real network is required for
those tests. They do not prove behavior of device DNS/VPN stacks, certificate
validation under attack, actual cancellation of a stuck system resolver, or
correct integration of a future consent UI. Backend work remains blocking and must
not run on the UI thread. No full feature or production-readiness claim is made.
CI validation is pending.
