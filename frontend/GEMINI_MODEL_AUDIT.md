# Gemini Model Audit for Beeamvo

This file tracks the scrum-style audit of every Gemini model exposed in Beeamvo, the reasoning-effort levels supported by each, and the fixes applied to keep the registry correct.

## Sprint 1: Gather sources

Official documentation consulted:

- [Gemini API deprecations](https://ai.google.dev/gemini-api/docs/deprecations)
- [Gemini Enterprise Agent Platform — model versions/lifecycle](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/model-versions)
- [Gemini Enterprise Agent Platform — thinking](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/thinking)
- [Gemini API — thinking](https://ai.google.dev/gemini-api/docs/thinking)
- [Gemini API — models](https://ai.google.dev/gemini-api/docs/models/gemini)
- Model pages for [3.7 Flash](https://ai.google.dev/gemini-api/docs/models/gemini-3.7-flash), [3.6 Flash](https://ai.google.dev/gemini-api/docs/models/gemini-3.6-flash), [3.5 Flash](https://ai.google.dev/gemini-api/docs/models/gemini-3.5-flash), [3.5 Flash-Lite](https://ai.google.dev/gemini-api/docs/models/gemini-3.5-flash-lite), [3.1 Flash-Lite](https://ai.google.dev/gemini-api/docs/models/gemini-3.1-flash-lite), [3 Flash preview](https://ai.google.dev/gemini-api/docs/models/gemini-3-flash-preview), [2.5 Flash](https://ai.google.dev/gemini-api/docs/models/gemini-2.5-flash), [2.5 Flash-Lite](https://ai.google.dev/gemini-api/docs/models/gemini-2.5-flash-lite), [3.5 Transcribe announcement](https://blog.google/innovation-and-ai/models-and-research/gemini-models/gemini-3-5-transcribe/)

## Sprint 2: Current Beeamvo registry

`frontend/lib/config.dart` exposes these model IDs today:

| id | modelName | isPreview | thinkingLevel default | supportedThinkingLevels | status |
|---|---|---|---|---|---|
| gemini-2.5-flash | gemini-2.5-flash | false | n/a (thinkingBudget 0) | n/a | deprecated, shutdown 2026-10-16 |
| gemini-2.5-flash-lite | gemini-2.5-flash-lite | false | n/a (thinkingBudget 0) | n/a | deprecated, shutdown 2026-10-16 |
| gemini-3.7-flash | gemini-3.7-flash | false | minimal | [minimal, low, medium, high] | wrong: does not support minimal |
| gemini-3-flash | gemini-3-flash-preview | true | minimal | [minimal, low, medium, high] | wrong: default should be high |
| gemini-3.5-flash | gemini-3.5-flash | false | minimal | [minimal, low, medium, high] | wrong: default should be medium |
| gemini-3.1-flash-lite | gemini-3.1-flash-lite | false | minimal | [minimal, low, medium, high] | deprecated, shutdown 2027-05-07 |
| gemini-3.5-flash-lite | gemini-3.5-flash-lite | false | minimal | [minimal, low, medium, high] | correct |
| gemini-3.5-transcribe | gemini-3.5-transcribe | true | n/a | n/a | correct, transcription-only |

## Sprint 3: Official truth

### Deprecations / retirement

From the official deprecations and lifecycle pages (checked 2026-08-28):

- `gemini-2.5-flash` — shutdown 2026-10-16, replacement `gemini-3.6-flash`
- `gemini-2.5-flash-lite` — shutdown 2026-10-16, replacement `gemini-3.1-flash-lite`
- `gemini-3.1-flash-lite` — shutdown 2027-05-07, replacement `gemini-3.5-flash-lite`

### Thinking levels (Gemini 3.x)

From the [Google Cloud thinking doc](https://docs.cloud.google.com/gemini-enterprise-agent-platform/models/thinking):

| Model | Supported thinking_level values | Default |
|---|---|---|
| Gemini 3.7 Flash | LOW, MEDIUM, HIGH | MEDIUM |
| Gemini 3.6 Flash | MINIMAL, LOW, MEDIUM, HIGH | MEDIUM |
| Gemini 3.5 Flash | MINIMAL, LOW, MEDIUM, HIGH | MEDIUM |
| Gemini 3.5 Flash-Lite | MINIMAL, LOW, MEDIUM, HIGH | MINIMAL |
| Gemini 3.1 Flash-Lite | MINIMAL, LOW, MEDIUM, HIGH | MINIMAL |
| Gemini 3 Flash preview | MINIMAL, LOW, MEDIUM, HIGH | HIGH |

### Missing model

`gemini-3.6-flash` is a stable model in the Gemini 3 family and is the recommended replacement for `gemini-2.5-flash`. It supports all four thinking levels and defaults to MEDIUM.

### 2.5 series thinking budgets

`gemini-2.5-flash` uses `thinkingBudget` (integer), not `thinkingLevel`. Setting `thinkingBudget` to `0` disables thinking; `-1` enables dynamic thinking. `gemini-2.5-flash-lite` does not think by default. Because the 2.5 Flash/Lite models are deprecated, we will remove them rather than adjust budgets.

## Sprint 4: Mismatches and fixes

1. **Gemini 3.7 Flash** must not advertise `minimal` and must default to `MEDIUM`; supported levels = `[low, medium, high]`.
2. **Gemini 3 Flash preview** must default to `HIGH`.
3. **Gemini 3.5 Flash** must default to `MEDIUM`.
4. **Gemini 2.5 Flash / Flash-Lite** are deprecated — remove from `availableModels`.
5. **Gemini 3.1 Flash-Lite** is deprecated — remove from `availableModels`.
6. **Add Gemini 3.6 Flash** as the replacement for the retired 2.5 Flash line.
7. **Validation:** any stored user thinking-level override or `forceMinimal` fallback must be clamped to the model's `supportedThinkingLevels`. This prevents sending `minimal` to 3.7 Flash (which returns HTTP 400).
8. **UI:** `ai_models_page` and `prompt_override_panel` must clamp displayed thinking level to supported values.

## Sprint 5: Implementation

### 5.1 Registry update (`lib/config.dart`)

- Removed deprecated models from `availableModels`: `gemini-2.5-flash`, `gemini-2.5-flash-lite`, `gemini-3.1-flash-lite`.
- Added `gemini-3.6-flash` (stable replacement for 2.5 Flash).
- Corrected defaults and `supportedThinkingLevels`:
  - `gemini-3.7-flash` → default `medium`, supports `[low, medium, high]`.
  - `gemini-3.6-flash` → default `medium`, supports `[minimal, low, medium, high]`.
  - `gemini-3.5-flash` → default `medium`, supports `[minimal, low, medium, high]`.
  - `gemini-3.5-flash-lite` → default `minimal`, supports `[minimal, low, medium, high]`.
  - `gemini-3-flash` (preview) → default `high`, supports `[minimal, low, medium, high]`.
  - `gemini-3.5-transcribe` → no thinking config, transcription-only.

### 5.2 Centralised level clamping (`lib/config.dart`)

Added `GeminiModelConfig.resolveThinkingLevel({levelOverride, forceMinimal = false})`:

- Returns `null` when the model has no thinking level support.
- Validates `levelOverride` (and stored UI overrides) against `supportedThinkingLevels`.
- Falls back to the model default when the override is unsupported.
- When `forceMinimal` is true (raw transcription / Pass 1), it picks `minimal` if supported, otherwise the lowest supported level. This fixes the 3.7 Flash case where `minimal` is not supported.

`thinkingConfigWithLevel` and `thinkingConfig` now use `resolveThinkingLevel`.

### 5.3 Service wiring

Updated three service files to use `model.resolveThinkingLevel` instead of directly constructing `GeminiThinkingLevel.minimal`:

- `lib/services/gemini_api_service.dart` — `_buildThinkingConfig` now resolves the effective level via `resolveThinkingLevel`.
- `lib/services/vertex_ai_service.dart` — same as above.
- `lib/services/gemini_interactions_service.dart` — `_resolveThinkingLevel` now calls `model.resolveThinkingLevel` with the stored override.

### 5.4 UI clamping

- `lib/widgets/settings/pages/ai_models_page.dart` — the reasoning-effort dropdown uses `modelConfig.resolveThinkingLevel(levelOverride: selectedLevel)` before building the `BeeDropdown` value.
- `lib/widgets/settings/pages/prompt_override_panel.dart` — both the cloud and refinement reasoning rows use `model.resolveThinkingLevel(levelOverride: storedLevel)` so the displayed global level cannot be an unsupported value.

### 5.5 Test updates

- `test/gemini_config_test.dart` — updated defaults and supported levels for 3.7, 3.5, 3 Flash, and 3.6. Added unit tests for `resolveThinkingLevel` clamping and `forceMinimal` fallback. Removed tests that referenced `gemini-3.1-flash-lite`.
- `test/vertex_ai_service_test.dart` — replaced `gemini-2.5-flash` with `gemini-3.6-flash` in URI tests.
- `test/gemini_interactions_service_test.dart` — replaced removed `gemini-2.5-flash` in the thinking-budget test with an inline `GeminiModelConfig(thinkingBudget: 0)`.
- `test/cloud_transcription_service_test.dart` — replaced `gemini-3.1-flash-lite` override with `gemini-3.5-flash-lite`.
- `test/prompt_override_panel_test.dart` — replaced `gemini-2.5-flash` two-pass pass-1 override with `gemini-3.5-flash-lite`.

## Sprint 6: Verification

### Commands run

```bash
cd /home/ubuntu/repos/Beeamvo/frontend
dart format lib test
flutter analyze
flutter test
```

### Results

- `dart format lib test` — clean, formatted 6 files.
- `flutter analyze` — only pre-existing warnings in `lib/services/whisper_model_download_service.dart` (5 `unawaited_return_in_try_block` warnings). No new issues introduced.
- `flutter test` — all 235 tests passed.

## Sprint 7: Final registry

`AppConfig.availableModels` now contains only current Gemini models:

| id | modelName | default thinkingLevel | supportedThinkingLevels | notes |
|---|---|---|---|---|
| gemini-3.7-flash | gemini-3.7-flash | `medium` | `[low, medium, high]` | no `minimal` |
| gemini-3.6-flash | gemini-3.6-flash | `medium` | `[minimal, low, medium, high]` | replacement for 2.5 Flash |
| gemini-3.5-flash | gemini-3.5-flash | `medium` | `[minimal, low, medium, high]` | |
| gemini-3.5-flash-lite | gemini-3.5-flash-lite | `minimal` | `[minimal, low, medium, high]` | default app model |
| gemini-3-flash | gemini-3-flash-preview | `high` | `[minimal, low, medium, high]` | preview |
| gemini-3.5-transcribe | gemini-3.5-transcribe | n/a | n/a | preview, transcription-only |

Removed from the registry:

- `gemini-2.5-flash`
- `gemini-2.5-flash-lite`
- `gemini-3.1-flash-lite`

## Conclusion

The Gemini model registry and reasoning-effort logic are now aligned with the official Google documentation. Deprecated models are removed, `gemini-3.6-flash` is present, and all thinking-level overrides and UI selections are clamped to each model's supported levels so the app can no longer send `minimal` to `gemini-3.7-flash`.
