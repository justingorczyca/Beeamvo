# Changelog

All notable changes to Beeamvo are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project aims to follow [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2026-09-26

Initial public release.

### Added

- Global hotkey voice recording with auto-paste at the cursor (`Ctrl+Shift+V` by default); `Esc` cancels and `Enter` commits early
- Toggle and Hold recording modes with a floating orb status indicator
- Fully offline transcription via whisper.cpp v1.8.4 (Tiny, Tiny English, Tiny Q5, Base, Small models)
- Cloud transcription via Gemini API key (Interactions or `generateContent` surface) or Vertex AI: Gemini 3.7 Flash, 3.6 Flash, 3.5 Flash, 3.5 Flash Lite, 3 Flash, 3.1 Flash Lite, 2.5 Flash, 2.5 Flash Lite, and the dedicated Gemini 3.5 Transcribe speech model (Gemini API only)
- Per-model thinking levels, stored separately for the transcript pass and the polish pass
- Two-step refinement: local Whisper or Gemini/Vertex transcribes the audio, then a freely chosen polish provider (Gemini, Vertex AI, OpenAI, ChatGPT/Codex, or xAI Grok) refines the transcript with its own model, thinking level, and credentials; polish providers receive text only, never audio
- Clear per-account setup messages when a credential needed by any pipeline stage is missing, plus polish-account checks in Troubleshooting
- Built-in writing styles (Standard, Concise, Smart, Professional, and more) and unlimited custom styles
- Clipboard history with full-text search, pinning, a popup hotkey (`Ctrl+Shift+H`), and a best-effort sensitive-text filter
- System tray menu for switching writing styles
- Onboarding wizard, settings UI, and usage statistics dashboard
- Credentials stored in OS secure storage (macOS Keychain, platform secure storage on Windows); standard platform TLS for all cloud traffic
- Windows and macOS desktop support, Android and iOS cloud dictation, and an experimental Linux runner built in CI
- CI with lockfile enforcement, pinned Flutter 3.44.2, `dart format`, `flutter analyze`, `flutter test`, and per-OS builds

[0.1.0]: https://github.com/justingorczyca/Beeamvo/releases/tag/v0.1.0
