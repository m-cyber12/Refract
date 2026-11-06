# REFRACT — Phase 0: Threat Model, Risk Register, Testing & Quality Strategy

## 1. Threat model (summary; full doc expands in `docs/security/` during Phase 0)

| Threat | Mitigation |
|---|---|
| Device loss | Platform Keystore/Keychain for keys; encrypted sensitive stores; user-controlled export |
| Malicious imported documents | Rust parsing, allowlist HTML sanitizer, no script execution, memory-bounded PDF, WebView JS-off for untrusted content |
| Malicious websites (fetch mode) | TLS + cert validation, strict network boundary, no traffic interception |
| Unauthorized sharing | Explicit per-item visibility; annotations never auto-share source docs; revocation |
| Compromised sync relays (later) | E2E encryption; relays see only ciphertext; P2P preferred |
| Incorrect AI claims | AI layer always labeled; source references; app fully usable with AI off |
| Corrupted local records | SHA-256 integrity checks, migrations, append-only evidence log |
| Malicious collaborative peers (later) | CRDT solves convergence only — explicit authz/identity handled separately |

Hard rules: never execute imported scripts; a hash proves integrity-since-hashing, never
authenticity; never store keys in plain preferences; no hidden analytics.

## 2. Risk register

| ID | Risk | L | I | Mitigation / owner |
|---|---|---|---|---|
| R1 | FFI boundary becomes a bottleneck/bug source | M | H | Small versioned C ABI, `RefractResult` errors, contract tests, background isolates |
| R2 | iOS share extension + CI build fragility | M | M | Prototype first; macOS runner pinned Xcode; fallback: manual import still works |
| R3 | PDF extraction poor on real-world files | H | M | Evaluate parsers with fixture corpus; honest confidence + raw-text fallback |
| R4 | Scope creep toward full vision in MVP | H | H | Phase gates with acceptance criteria; "avoid building" list enforced in review |
| R5 | Design system drift into generic Material look | M | M | Tokens + review checklist; prism identity in every screen review |
| R6 | Performance regressions on low-end Android | M | M | Perf targets measured on real devices; criterion benches for compiler |
| R7 | Overclaiming evidence/proof in UI copy | M | H | Copy review checklist; "what it proves / does not prove" block mandatory in Vault |
| R8 | Dependency bloat / unvetted crates | L | M | Pinned deps, justification per dep, license + audit step in CI |

L = likelihood, I = impact (L/M/H).

## 3. Testing strategy (per spec §15)

- **Unit:** extraction, sanitization, metadata, hashing, anchor logic, DB ops, subscription math, evidence verification, CRDT transforms.
- **Integration:** Flutter↔Rust calls, share flows, file imports, migrations, offline workflows, notifications (later phases).
- **UI:** navigation, import, reader, search, evidence screens, a11y, dark/light.
- **Reliability:** interrupted imports, invalid docs, missing permissions, storage exhaustion, network loss, suspension, model failure, conflicting updates.
- **Performance targets (measure, don't claim):** fast startup; 60 FPS navigation; responsive local search; no large downloads by default; non-blocking extraction; memory-aware PDF; efficient queries.

## 4. Definition of done (per phase)

Tests green in CI (Rust + Flutter + native builds), architecture boundaries reviewed,
tech-debt log updated, docs updated, previous-phase acceptance criteria re-verified.

## 5. GitHub Actions plan (config lands with Phase 1.1)

- `rust.yml`: fmt, clippy, test on Linux + cross-compile check for Android/iOS targets.
- `flutter.yml`: analyze, test, Android build on PRs.
- `release.yml`: signed AAB/IPA on `v*` tags (macOS runner for iOS).
- `docs.yml`: markdown lint; ADR index check.
