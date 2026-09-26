# Gemini API Key Setup

Use this path if you want the simplest cloud setup.

> **Platforms:** Windows and macOS are supported; Linux is experimental. **Whisper Local** (offline) needs none of the steps below — choose it in Settings → Transcription instead.

## What it does

Beeamvo stores your Gemini API key in local OS secure storage and sends cloud requests directly to the Gemini API. No Google Cloud project is required for this mode. When you are on the **Whisper Local** engine, audio never leaves your machine; audio is only sent to Google after you explicitly choose **Cloud AI**; with Two-Step Refinement on the offline engine, only the transcript text (never audio) is sent for polishing.

## Steps

1. Open Google AI Studio and create a Gemini API key.
2. Start Beeamvo.
3. Go to Settings -> Transcription.
4. Keep `Processing Engine` set to `Cloud`.
5. Set `Cloud Provider` to `Gemini API Key`.
6. Click `Add API Key`, paste the key, and save it. For development-only overrides, you can alternatively set `GEMINI_API_KEY` in `.env`.
7. Click `Verify`.
8. Choose the cloud model you want to use.

In the Gemini API Key section, **API Surface** lets you choose Google's
recommended **Interactions** API or the legacy `generateContent` API.

## Notes

- Prefer saving the key via the UI, where it is stored in OS secure storage.
- `.env` is for local debug/development overrides only. Release builds ignore dotenv files; do not use `.env` for packaged releases or shared machines.
- `.env` is ignored by Git and must not be copied into source archives, app bundles, screenshots, or issue reports.
- The key is not committed to the repository.
- The app currently uses inline audio requests for Gemini. If a recording is too large, reduce the duration limit and retry.
- Interactions is the recommended surface for new setups; `generateContent`
  remains available for compatibility.

## Troubleshooting

- `Add a Gemini API key in Settings before using cloud transcription.`
  Your key has not been saved yet.
- `Gemini request failed` or `Invalid API key`
  Re-check the key in Google AI Studio and replace it in Settings.
- Empty response
  Retry with a shorter recording or a different model.
