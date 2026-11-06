# Phase 1 — Implementation Status (updated 2026-11-06)

Started. Source tree created; verification runs in GitHub Actions (the authoring
sandbox has no Rust/Flutter toolchains, and the network allowlist blocks their
download servers — CI is the compile gate by design).

## Done in this pass

- [x] 1.1 Repo + CI bootstrap: Rust workspace, `.github/workflows/{rust,flutter,docs,release}.yml`
- [x] 1.2 Design system v1: `RefractColors` tokens (spec §8.2 palette), dark/light
      themes, `PrismMark` signature logo
- [x] 1.3 Rust core skeleton: `refract_core` (types, errors, ABI v1) +
      `platform_bridge` C ABI with JSON envelopes, panic-free boundary,
      `refract_abi_version` handshake, FFI roundtrip test
- [x] 1.4 DB layer: `shared/schemas/migrations/0001_init.sql` (items, blobs,
      blocks, FTS5 + sync triggers), `personal_memory` store with migrations,
      insert/list/get/search, unit tests
- [x] 1.5 Compiler pipeline: `document_parser` (text/markdown/HTML-sanitizing/PDF)
      + `content_compiler` (hash original, structure, confidence, title fallback)
- [x] 1.6 Flutter app shell: GoRouter, Riverpod, FFI bindings, repository providers
- [x] 1.7 Intake (native): Android `ACTION_SEND` → MethodChannel; iOS Share
      Extension → App Group → `refract://share` URL → MethodChannel
- [x] 1.8 Reader + Library UI: Clean Reader with provenance panel (hash, source,
      confidence), Library with FTS search, Home command center
- [x] 1.9 Refraction transition: import screen shows real busy state bound to the
      actual pipeline call (no fake progress)
- [~] 1.10 Polish + tests: Rust unit/FFI tests + Flutter widget test added; full
      integration_test suite and on-device perf pass remain

## Known follow-ups

- `flutter create` platform shells (android/ios gradle + Xcode project) are
  generated in CI; a maintainer should run it locally once and commit the shells.
- URL *fetching* (turning a shared URL into HTML) is a later-phase item; Phase 1
  stores shared URLs as referenced text and imports pasted HTML directly.
- PDF import via file picker (SAF) wired in native layer next pass.
