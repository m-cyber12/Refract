# A1 — Durable approved capture saves

Focused first increment of section A. A2–A10 (native share completion, URL fetching,
browser, broader formats/OCR, PDF fidelity/isolation, quick-entry and pre-storage
SENSE policy changes) are not implemented by this increment.

## Contract

- Unreviewed drafts and previews remain temporary. Only an explicitly approved
  save enters SQLite staging after matching the existing byte/parser/URL review
  binding. The UI separately discloses durable, unencrypted staging. The ABI
  requires `persist_approved: true`; a local review binding is not authentication.
- Migration 15 stores jobs as queued, processing, failed, completed or cancelled,
  with device approval/update times, attempt count and a reserved original item
  UUID. Approval time is distinct from the eventual library import time.
  An idempotency token is bound to the approved draft and duplicate choice.
- Original item/block/blob publication and completed-job acknowledgement, including
  clearing the active staged payload, commit in the **same SQLite transaction**.
  A retry after commit returns the same result even for explicit keep-copy saves.
- Per-job OS advisory file locks prevent concurrent retries/cancel from stealing
  an active worker. There are no expiring clock leases. A dead process releases
  its lock; explicit Resume can recover a processing job. Lock inodes are kept
  rather than unlinked/recreated while another worker could hold the old inode.
- Recovery only removes an unreferenced file for that job's reserved UUID, under
  its lock and an immediate DB transaction. Any item/blob reference blocks removal.
  Unrelated/legacy orphans are never swept or guessed at.
- Failed jobs retain approved input for explicit retry/cancel. History errors are
  generic and contain no source snippets/parser diagnostics. Completed/cancelled
  jobs clear active input; hashes/metadata/history remain. This is not secure
  erasure of SQLite free pages, WAL, backups, memory or provider caches.
- Staging is limited to 64 unresolved jobs and 256 MiB of active serialized payload.
  This is not a cap on SQLite/WAL physical disk size. Cancellation refuses live
  workers and completed captures; it never deletes a completed library original.
- Home shows unresolved jobs; Import and Settings link to Capture jobs. Opening
  history never automatically retries parsing. UI shows up to 100 jobs, unresolved
  first; backend list supports bounded limit/offset. Errors and the saved original
  remain separate from best-effort derived analyses.

## Validation

Pending SDK compilation and runtime tests in GitHub Actions. Local syntax and
migration checks are supplemental; no Rust/Flutter SDK is installed locally.

Added tests cover review/approval, token binding, staged privacy, capacity, failed
SQL retry, terminal cancellation, live worker locks, scoped orphan cleanup,
idempotent keep-copy publication, native ABI, actual Dart FFI across restart,
confirmation/cancel UI and history without automatic processing.

The Rust process-kill regression launches a separate test executable, waits at a
boundary and kills it without running Rust destructors: after synced original
creation, before SQL commit, and after commit before returning. On reopen, the
first two resume to one source; the last returns the already completed source.
Test fault hooks exist only in `cfg(test)` and do not ship in the native library.

## Still outstanding within A1 / reliability

- No persisted unreviewed drafts, native WorkManager/BGTask service, automatic
  startup retry or promise of background completion. Recovery is foreground and
  explicit. Editing a draft does not cancel a previously approved staged job.
- No interruption of a running native parser; cancel applies only when the OS
  lock is free. Parser process isolation, native CPU/RAM budgets and safe active
  cancellation remain A8 work.
- Process-kill tests are not a hardware power-loss/filesystem-failure guarantee.
  Physical Android/iOS lifecycle, storage exhaustion and filesystem behavior need
  device validation. iOS/native share wiring remains A2, not proved by host tests.
- No automatic recovery/deletion of unrelated legacy orphans, full history UI
  pagination/pruning, at-rest encryption, or secure-erasure claim.
- Legacy direct commit APIs stay compatible; only the new UI save flow uses the
  queue. Opening an existing copy is immediate and does not stage a new source.
