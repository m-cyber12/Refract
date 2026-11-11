# Capture confirmation hardening

Rapid repeated taps are guarded while a capture-job cancellation or web-preview
removal confirmation is open. Declining still performs no removal; confirmation
runs only the requested action. These checks supplement native idempotency and do
not imply cancellation of an active DNS request or parser. Tests exercise the
controls with fake repositories; device accessibility and lifecycle remain open.

Approval and handoff times are device-recorded event times, not publication times.
The capture-job UI and web-preview UI now handle malformed or out-of-range
seconds as unavailable instead of inventing a date or throwing while rendering.

A batch integration test exercises the actual import page through independent
preview and durable-save consent, and checks that editing one item leaves the
other queued originals unchanged. Batch drafts remain temporary process memory,
not durable staged copies; provider caches may outlive them.

The previous `6a3e7a0` change passed Flutter `43005118556`, Rust `43005118524`,
Android emulator `43005118479`, and unsigned iOS `43005118499`. Docs
`43005098078` passed on the immediately preceding documentation change. These
CI results do not replace signed-device, real-provider or security validation.
