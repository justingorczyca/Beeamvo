# Changelog

All notable changes to Beeamvo are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

> **Release status.** Beeamvo's source is still in pre-release preparation. The
> `version:` in `frontend/pubspec.yaml` is `0.1.0`, but no version has been tagged
> or publicly distributed yet (no installer/artifact pipeline exists — see
> `docs/open-source-release-checklist.md`). Everything below is therefore under
> **[Unreleased]**; a dated, versioned entry will be added here only when an actual
> tag is cut and published.

## [Unreleased]

The initial-release feature set plus the hardening from the pre-release audit
sequence (security/privacy, supply-chain, correctness, build/CI/packaging).

### Added

- Global hotkey voice recording with auto-paste at the cursor (`Ctrl+Shift+V` by default)
- Toggle and Hold recording modes with a floating orb status indicator
- Fully offline transcription via whisper.cpp (Tiny, Tiny English, Tiny Q5, Base, Small models)
- Cloud transcription via Gemini API key or Vertex AI (Gemini 2.5 Flash, 2.5 Flash Lite, 3 Flash, 3.5 Flash, 3.1 Flash Lite)
- Thinking levels (Minimal / Low / Medium / High) for Gemini 3+ models
- Two-pass refinement: local Whisper transcription followed by an AI polish pass
- Built-in and unlimited custom system prompts, plus a Rephraser (Off / Medium / High)
- Clipboard history with full-text search, pinning, and a popup hotkey (`Ctrl+Shift+H`)
- System tray menu for switching prompts, rephraser levels, and models
- Onboarding wizard, settings UI, and usage statistics dashboard
- API keys stored in OS secure storage (macOS Keychain, platform secure storage on Windows)
- Windows and macOS support; experimental Linux runner (built in CI, see `docs/build-ci-packaging-audit.md`)

### Fixed

- Made switching between Cloud and Offline Whisper backends safe without requiring an app restart.
- Replaced fixed WAV-header stripping with RIFF/WAV parsing for offline transcription fallback audio.
- Applied selected microphone changes immediately and released temporary audio-device enumeration resources.
- Prevented a too-short recording from being offered as a retryable transcription.
- Replaced modifier-less system-wide popup navigation keys with focused-window navigation, preserving Enter/Escape for other apps during recordings.
- Cleared stale mode-popup bindings when opening Settings or clipboard history and improved shortcut-conflict recovery.
- Made Whisper model download cancellation safe when leaving the AI Models page.
- Retried failed background update checks instead of rate-limiting them as successful checks.
- Added explicit cloud client cleanup during app shutdown and safer Gemini error messages.
- Clamped the recording auto-stop duration limit to its valid `[5, 3600]` second range so an out-of-range stored value cannot arm a zero-length or unbounded timer.

### Security & Privacy

- Removed the non-functional "certificate-pinning" wiring and renamed the client factory `createPinnedHttpClient` → `createSecureHttpClient`. All cloud traffic (Gemini API, Vertex AI, model downloads, update checks) now uses standard platform TLS validated by the OS trust store. Certificate pinning is **not** used; see `docs/security-privacy-audit.md`.
- Stopped treating `.env.example` as runtime configuration; release builds ignore dotenv files entirely.
- Expanded the best-effort clipboard-history sensitive-text filter and clarified plaintext-history behaviour.
- Scoped the macOS troubleshooting TCC reset to Beeamvo's own bundle id (absolute `/usr/bin/tccutil`, fails safe on an empty id) so it can no longer clear other apps' privacy permissions.

### Build & CI

- Rewrote `.github/workflows/ci.yml`: lockfile enforcement (`flutter pub get --enforce-lockfile`), pinned Flutter 3.44.2, a `dart format` gate, pub-dependency caching, per-job timeouts, a concurrency guard, least-privilege `permissions: contents: read`, and an experimental Linux build job alongside macOS and Windows. No secrets are required.
- Aligned the `pubspec.yaml` Dart SDK floor (`^3.12.0`) with the resolved `pubspec.lock` (`>=3.12.0 <4.0.0`).
- Canonicalized the Dart tree with `dart format` so the format gate is green.

### Removed

- Deleted the orphaned `native/parakeet_runtime/...` submodule gitlink (no `.gitmodules`, unreferenced) and the accidentally-tracked scratch files `_maindiff.txt` and `frontend/old_main.txt`, with `.gitignore` guards against recurrence.
