# API Request/Response Performance Audit

## Scrum goal
Confirm or refute the perception that the Gemini API request/response flow is unnecessarily slow, then fix concrete hotspots and keep the code best-practice.

## Sprint 1 – Map the hot path
Path audited:
1. `mobile_transcription_controller.dart` / `main.dart` capture audio.
2. `cloud_transcription_service.dart` picks `GeminiApiService`, `GeminiInteractionsService`, or `VertexAiService`.
3. Service builds JSON payload with inline base64 audio.
4. `http.Client` POST + retry.
5. Response JSON parsed and `transcription_result_guard.dart` sanitises output.
6. Result copied to clipboard.

## Sprint 2 – Measure and identify bottlenecks
Findings:

| # | Location | Issue | Impact |
|---|----------|-------|--------|
| 1 | `gemini_api_service.dart`, `gemini_interactions_service.dart`, `vertex_ai_service.dart` `_buildAudioContent` | `base64Encode(audioData)` runs synchronously on the UI isolate. | Jank / frame drops for multi-MB recordings; blocks `await` chain before the network request even starts. |
| 2 | Same services, `_postGenerateContent` / `_postInteractions` / `_postWithAdcRetry` | `jsonEncode(payload)` also runs on the UI isolate and the resulting `String` is later UTF-8-encoded again by `http`. | Double work and main-thread CPU time. |
| 3 | `settings_service.dart` `readGeminiApiKey()` | Reads the secure credential store (`flutter_secure_storage`) on every API call. | Adds a platform/Keychain round-trip to every single cloud request. |
| 4 | `buildImprovePayload` / `buildTranscribeAndImprovePayload` in all three services | `maxOutputTokens` capped at `32768`. | Larger than necessary for transcription outputs, can increase model latency and cost with no benefit. |
| 5 | `gemini_interactions_service.dart` `_postWithRetry` | Body type was `String`; HTTP package re-encodes to bytes on main thread. | Avoidable conversion. |

Confirmed: there **was** unnecessary synchronous work on the UI isolate and a redundant secure-storage read per request.

## Sprint 3 – Fixes

1. **Worker-isolate serialization** (`lib/services/serialization_utils.dart`)
   - `encodeBase64Async` – runs `base64Encode` in an isolate.
   - `encodeJsonAsync` – runs `jsonEncode` + `utf8.encode` in an isolate and returns `Uint8List`.

2. **Offload base64 encoding in all three cloud services**
   - Added `String? audioBase64` to `buildTranscribePayload`, `buildTranscribeAndImprovePayload` and `_buildAudioContent`.
   - Service methods `transcribeAudio` / `transcribeAndImprove` now call `await encodeBase64Async(audioData)` before building the payload.
   - Payload builders keep a synchronous fallback (when `audioBase64` is null) so unit tests that only build payloads do not need to spawn isolates.

3. **Offload JSON encoding and send bytes directly**
   - `_postWithRetry`, `_postInteractions`, `_postWithTransientRetry` now accept `Uint8List body`.
   - JSON is encoded in an isolate and passed to `http.post(..., body: bytes)`, skipping the main-thread `String`→`bytes` conversion.

4. **Cache Gemini API key in memory**
   - `SettingsService` now keeps `_geminiApiKey` and `_hasGeminiApiKey`.
   - `readGeminiApiKey()` returns the cached value after the first secure-storage read.
   - `setGeminiApiKey` / `clearGeminiApiKey` update the cache immediately.

5. **Lower excessive `maxOutputTokens` caps**
   - `buildImprovePayload` and `buildTranscribeAndImprovePayload` changed from `32768` to `8192` across `GeminiApiService`, `GeminiInteractionsService`, and `VertexAiService`.
   - `buildTranscribePayload` initially set `8192` as well, but was later left uncapped (see Sprint 5).
   - `verifySetup` still uses `64` (tiny text probe).

## Sprint 5 – Review feedback fix
Devin Review flagged that `buildTranscribePayload` should not cap the raw verbatim transcript at `8192` tokens, because long recordings could be silently truncated. Raw transcription payloads (`buildTranscribePayload`) now leave `maxOutputTokens` unset so the model uses its default maximum. The `8192` cap is kept only for `buildImprovePayload` and `buildTranscribeAndImprovePayload`.

## Sprint 6 – Final verification

```bash
dart format lib test          # clean
flutter analyze               # only pre-existing whisper_model_download_service warnings
flutter test                  # 237/237 passed
```

## Result
- Perceived latency before the HTTP request is reduced by moving CPU-heavy base64/JSON work off the UI isolate.
- Secure-store round-trip eliminated after the first read.
- Request bodies are now sent as pre-encoded bytes.
- Output token caps are right-sized for speech-to-text outputs.

## Files changed
- `lib/services/serialization_utils.dart` (new)
- `lib/services/gemini_api_service.dart`
- `lib/services/gemini_interactions_service.dart`
- `lib/services/vertex_ai_service.dart`
- `lib/services/settings_service.dart`
- `test/gemini_interactions_service_test.dart`
