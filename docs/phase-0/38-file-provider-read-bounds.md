# File-provider read bounds

Single and multi-file capture now apply a 15-second inactivity timeout to each
Dart read stream and a two-minute aggregate read budget after the picker returns.
The remaining aggregate budget also caps each pending stream read, so a slow
stream cannot extend the read indefinitely by delivering occasional chunks. A stalled, expired, malformed or over-limit
selection is rejected as a whole, with no library save or batch acceptance.
The app requests cancellation of the Dart stream subscription and mobile picker
cache cleanup. Tests exercise stalled and slow streams, cancellation and cleanup.

These are best-effort Dart-side bounds, not hard end-to-end deadlines. The OS,
picker, provider, plugin cache cleanup, file allocations, stream cancellation
or an individual long-running operation may block or allocate outside these
checks. The picker may download/cache data before returning. No secure-erasure,
provider compatibility or physical-device claim follows from these tests.

## Provider size consistency

A nonzero size reported by the picker must match the bytes actually read;
otherwise the entire selection is rejected and cache cleanup is requested. This
helps detect truncated or unexpectedly extended streams, but providers may
report stale or inaccurate sizes and therefore cause a false rejection. A zero
size is treated as unknown. Matching lengths do not prove that bytes are
complete, authentic, or unchanged at the source. Provider caching and cleanup
limitations remain as above.

## Android share size consistency

Android content-URI handoff also compares a positive optional provider-reported
size with the bytes actually read and rejects mismatches before draft delivery.
A missing, null, zero or negative size is treated as unknown. If a provider
rejects the size projection, the name-only query is retried. Inaccurate size
metadata can reject a usable file; matching lengths are not proof of completeness
or authenticity. This does not add a hard deadline to Android provider calls or
reads. Synthetic emulator fixtures cover mismatched, unknown and unsupported size
projections; real providers and physical devices still require validation.

Android share processing now waits at most 15 seconds for a whole share batch
once its provider task starts. A timed-out batch yields an error draft, not
partially accepted or late results; another share can be handled while a
provider call is stuck. The provider executor has at most two workers and no
waiting task queue; if both are unavailable, subsequent shares are rejected
with an explicit error. The controller itself serializes pending batches, so
waiting time before a batch starts is not included in the 15 seconds.

Cancellation is best effort: Binder, provider queries or reads can ignore an
interrupt, retain memory or grants, and occupy a worker until they return or the
app process exits. The timeout does not stop the provider or prove deletion of
its caches, nor does it guarantee hard limits on provider/OS memory or CPU.
Timeouts may reject slow but valid files. The emulator fixture includes a slow
provider and tests whole-batch rejection and later share handling; physical
providers, device lifecycle and interruption remain unverified.

## iOS handoff file checks

For provider-vended file URLs, the extension opens the final component without
following a symlink, uses nonblocking open, and checks the opened object is a
regular file before bounded reads. A positive file size must agree with the
bytes read. This can reject legitimate provider representations, including
final-component symlinks or stale sizes. It does not protect every path
component, sandbox a provider, prevent a regular-file read from stalling, or
prove completeness and authenticity. Provider memory allocation and OS caching
may happen before the app's checks. The synthetic macOS provider tests cover
regular files, final symlinks, a FIFO, empty files and size limits; signed iOS
physical-device and real-provider compatibility remain unverified.
