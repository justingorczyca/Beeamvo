# Changelog

All notable changes to Beeamvo are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

### Security & Privacy

- Stopped treating `.env.example` as runtime configuration.
- Documented the current OS-trust TLS posture; certificate pin enforcement remains disabled pending a dedicated rollout.
- Expanded the best-effort clipboard-history sensitive-text filter and clarified plaintext-history behavior.

## [0.1.0] - 2026-06-12

Initial public release.

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
- Windows and macOS support; experimental Linux runner

[Unreleased]: https://github.com/justingorczyca/Beeamvo/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/justingorczyca/Beeamvo/releases/tag/v0.1.0
