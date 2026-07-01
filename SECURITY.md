# Security Policy

Beeamvo is an offline-first desktop voice-to-text app with **optional** cloud
transcription (Google Gemini API or Vertex AI). This document explains the
supported versions, the current security/privacy posture, and how to report a
vulnerability.

## Reporting a vulnerability

If you believe you have found a security vulnerability, **please do not open a
public GitHub issue.** Instead, report it privately using one of:

- **GitHub private vulnerability reporting** ("Report a vulnerability" on the
  repository's **Security → Advisories** tab) — preferred; or
- a private message to the maintainer via a GitHub-attached contact.

Please include:

1. A description of the issue and its potential impact.
2. Steps to reproduce (minimal if possible).
3. The platform(s) and Beeamvo version affected.

Reports are acknowledged as soon as practical. There is no formal SLA; this is a
best-effort, community-maintained project. Please **do not include** real API
keys, transcripts, recordings, or other sensitive data in your report.

## Scope

In scope: the Beeamvo source in this repository, including the bundled
`whisper.cpp` integration, the cloud transcription clients, credential storage,
and the platform runners under `frontend/{windows,macos,linux}/`.

Standard caveats apply to **how** you use Beeamvo:

- **Cloud transcription is opt-in.** With **Whisper Local** selected, audio never
  leaves your machine. Audio is only transmitted when you choose Cloud or enable
  two-pass refinement — and the app confirms the first switch.
- **Credentials.** Gemini API keys are stored in OS secure storage (macOS
  Keychain, platform secure storage on Windows/Linux); Vertex AI uses
  Application Default Credentials and stores no secret. Keep your OS and its
  trusted root certificates up to date.
- **Transport.** All cloud traffic uses standard platform TLS validated by the
  OS trust store. **Certificate pinning is not used.**
- **Clipboard history.** If enabled, history entries are stored as plaintext in
  the app-data directory; a best-effort sensitive-text filter is available in
  Settings.

## Supported versions

Only the latest released version is supported. New builds are the only place to
get security-relevant fixes. (See [CHANGELOG.md](CHANGELOG.md) for the current
state; no signed, distributed binary release exists yet — builds from source are
the supported form today.)
