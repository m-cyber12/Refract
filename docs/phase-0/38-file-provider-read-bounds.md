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
