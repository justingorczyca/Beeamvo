# Security Policy

Beeamvo is an offline-first desktop voice-to-text app with **optional** cloud
transcription (Google Gemini API or Vertex AI) and optional two-step polish
providers (Gemini, Vertex AI, OpenAI, ChatGPT/Codex, xAI Grok) that receive
transcript text only, never audio. This document explains the
supported versions, the current security/privacy posture, and how to report a
vulnerability.

## Reporting a vulnerability

If you believe you have found a security vulnerability, **please do not open a
public GitHub issue.** Instead, report it privately using one of:

- **GitHub private vulnerability reporting** ("Report a vulnerability" on the
  repository's **Security → Advisories** tab) — preferred; or
- email to **justin.gorczyca1999@gmail.com**.

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
  leaves your machine; enabling two-step refinement there sends only the local
  transcript text to the chosen polish provider. Audio is only transmitted when
  you choose Cloud — and the app confirms the first switch. Cloud audio goes
  only to the first-pass provider, which is restricted to Gemini or Vertex AI;
  the two-step polish provider (any supported provider) receives validated
  transcript text only, never audio.
- **Credentials.** macOS stores Gemini API keys in the native Keychain with
  `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Windows and Linux use
  `flutter_secure_storage`: Windows stores an AES key in Credential Manager
  alongside an encrypted app-support file, while Linux uses libsecret. These
  mechanisms are not equivalent, and Windows has no per-application ACL prompt
  equivalent to Keychain.
- **Vertex AI credentials.** Beeamvo stores no Vertex secret itself. The
  authorizing Application Default Credentials are a plaintext JSON file found
  via `GOOGLE_APPLICATION_CREDENTIALS` or the per-OS gcloud ADC path. Beeamvo
  requests the broad `cloud-platform` scope, so protect that file and account.
- **Transport.** All cloud traffic uses standard platform TLS validated by the
  OS trust store. **Certificate pinning is not used.**
- **Clipboard history.** If enabled, history entries are stored as plaintext in
  the app-data directory; a best-effort sensitive-text filter is available in
  Settings.

## Supported versions

| Version | Supported |
|---------|-----------|
| 0.1.x   | Yes       |
| < 0.1   | No        |

Security fixes land in the latest 0.1.x release. No signed, distributed binary
release exists yet; builds from source are the supported form today.
