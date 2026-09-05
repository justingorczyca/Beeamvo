# Project notes

- The Flutter application and tests live in `frontend/`.
- CI verification: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, and `flutter test`, run from `frontend/`. CI pins Flutter 3.44.2 and resolves dependencies with `flutter pub get --enforce-lockfile`.
- With dependencies already resolved, use `flutter analyze --no-pub` and `flutter test --no-pub` to avoid incidental lockfile updates.
- Cloud transcription has two provider implementations: `GeminiInteractionsService` uses the Gemini Interactions API; `VertexAiService` uses Vertex `generateContent`. `CloudTranscriptionService` is the shared transcript-validation boundary.
- Normal cloud dictation applies the selected writing style in one request. Explicit two-step refinement transcribes audio first, then refines text in a second sequential request. Preserve this user choice and explicit per-model thinking overrides.
- Transcript auto-paste awaits the clipboard write, then calls `KeyboardService.simulateCtrlV(waitForModifiers: false)`. Keep fixed pre-paste timers out of this path and retain the native modifier-release events. Windows paste tests inject `sendInput` so tests never synthesize real keyboard input.
- Debug latency diagnostics use `[TranscriptionTiming]` for desktop audio preparation/delivery, `[CloudTranscription]` for model/provider/stage timing, and `[TranscriptionRequest]` for HTTP attempts/backoff. Do not log audio, transcripts, prompts, API keys, or upstream response bodies when extending diagnostics.
