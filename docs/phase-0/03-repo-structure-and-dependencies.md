# REFRACT — Phase 0: Repository Structure & Dependency Strategy

## 1. Repository layout (monorepo, created incrementally — no empty scaffolding)

```
refract/
├── apps/
│   └── mobile/                  # Flutter app
│       ├── lib/
│       │   ├── app/             # bootstrap, router, DI
│       │   ├── core/            # FFI bridge, DB access, result types
│       │   ├── design_system/   # tokens, typography, prism components
│       │   └── features/        # home, library, reader, xray, vault, annotations, settings…
│       ├── android/             # Kotlin: share intent, SAF, WorkManager, notifications
│       └── ios/                 # Swift: share extension, BackgroundTasks, notifications
├── crates/                      # Rust workspace
│   ├── refract_core/            # C ABI, error types, versioned contracts
│   ├── content_compiler/        # extraction, sanitization, structure detection
│   ├── document_parser/         # HTML/PDF/text/markdown
│   ├── metadata_engine/
│   ├── personal_memory/         # tags, collections, library queries
│   ├── semantic_search/         # FTS5 + optional vectors
│   ├── evidence_engine/         # proof vault, append-only log
│   ├── crypto_provenance/       # hashing, signatures (research: TLSNotary/zkTLS)
│   ├── annotation_engine/       # anchors, CRDT-ready annotation model
│   ├── sync_engine/             # Loro/Automerge + WebRTC/iroh (later phases)
│   ├── ai_runtime/              # model abstraction (llama.cpp/ONNX) (later phases)
│   └── platform_bridge/         # FFI surface + UniFFI where needed
├── shared/
│   ├── schemas/                 # SQL migrations, JSON schemas
│   ├── api_contracts/           # FFI contract tests & fixtures
│   └── test_fixtures/           # sample articles/PDFs/receipts
├── docs/
│   ├── phase-0/                 # this documentation set
│   ├── architecture/
│   ├── decisions/               # ADRs
│   ├── security/                # threat model
│   └── product/
├── tests/                       # integration + E2E (flutter integration_test, Rust FFI tests)
└── .github/workflows/           # CI: rust.yml, flutter.yml, release.yml, docs.yml
```

Rule from the spec: create modules when needed, each with responsibility, public
interface, unit tests, error handling, logging rules, documented deps.

## 2. Dependency strategy

**Principles:** minimal, audited, pinned; prefer the standard library; every dependency
gets a one-line justification in the crate/app manifest and a license check in CI.

### Flutter (apps/mobile)
- `flutter_riverpod` / `riverpod` — state management
- `go_router` — navigation
- `sqflite_common_ffi` (dev/test) — DB in tests; production DB lives in Rust
- `flutter_secure_storage` — thin wrapper over Keychain/Keystore for non-secret handles
- No analytics SDKs. No HTTP client beyond Dart `http` for explicitly user-approved fetches.

### Rust (crates)
- `rusqlite` (bundled, FTS5 enabled) + `sqlx` only if async needed — decide in Phase 1
- `scraper`/`html5ever` + custom allowlist sanitizer — parsing/sanitization
- `lopdf`/`pdfium-render` (evaluate) — PDF text extraction, memory-bounded
- `sha2`, `blake3` — hashing
- `uniffi` — native bindings
- `loro` **or** `automerge-rs` — Phase 5 (behind trait)
- `candle` or `onnxruntime` — Phase 4 (behind `ai_runtime` trait)
- Dev: `criterion` (perf), `proptest` (property tests)

### Native
- Android: Kotlin stdlib, AndroidX core/work, WebView — no third-party SDKs
- iOS: Swift stdlib + BackgroundTasks — no third-party SDKs

## 3. Build & toolchain matrix

| Target | Toolchain | Built by |
|---|---|---|
| Android APK/AAB | Flutter + NDK + cargo-ndk (arm64-v8a, armeabi-v7a, x86_64) | GH Actions `flutter.yml` / `release.yml` |
| iOS IPA | Flutter + Xcode + Rust static libs (aarch64) | GH Actions `release.yml` (macOS runner) |
| Rust core tests | cargo test/clippy/fmt, all targets | GH Actions `rust.yml` |
| Docs | markdown lint | GH Actions `docs.yml` |

Rust cross-compilation for mobile targets is done via `cargo-ndk` (Android) and
`cargo-lipo`/Xcode scripts (iOS), orchestrated in CI so local dev stays simple.

## 4. Versioning & contracts

- `refract_core` C ABI carries a `REFRACT_ABI_VERSION`; Dart checks it at startup and
  shows a clear error on mismatch.
- DB schema versioned with numbered migrations in `shared/schemas/migrations/`.
- SemVer for public release tags; `main` always releasable.
