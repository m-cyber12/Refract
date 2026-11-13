# Capture consent and handoff metadata hardening

- The web capture page reserves its start operation before opening the consent
  dialog. Rapid taps must not stack dialogs or start multiple sessions. Decline
  still starts no session, and each actual request requires its existing explicit
  approval. This does not add cancellation of active DNS/HTTP or change network
  security limitations.
- Invalid native handoff consent timestamps are treated as unavailable rather
  than passed to date formatting or reinterpreted as another timestamp kind. The
  user can still inspect the content; its time is not invented. Valid handoff
  time remains device consent time, not publication or import time.
- Widget tests exercise both cases with fake repositories/native channels. They
  are not evidence of physical-device behavior, app-level encryption, secure
  deletion or production readiness. CI remains necessary for these changes.
