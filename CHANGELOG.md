# Changelog

All notable changes to Beeamvo are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
