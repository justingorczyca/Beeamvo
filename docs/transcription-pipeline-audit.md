# Transcription Pipeline Correctness Audit

**Scope:** `frontend/lib/main.dart` `_stopRecordingAndProcess` (~lines 1482–1796),
the model-resolution / override / backend-pinning logic feeding it, and the
cloud client dispatch in `cloud_transcription_service.dart`,
`gemini_api_service.dart`, `vertex_ai_service.dart`.

**Method:** static trace of every variable feeding the pipeline decision and the
runtime value it resolves to in each of the 4 [Backend × TwoPass] combinations.

---

## 1. Variables that feed the pipeline decision (resolved at 1482–1526)

| Variable | Line | Resolution |
|---|---|---|
| `effectivePromptId` | 1484–1486 | retry-current? `selectedPromptId` : (`_temporaryPromptId` ?? `selectedPromptId`) |
| `selectedPrompt` | 1487–1490 | `SystemPrompt.getById(effectivePromptId)` |
| `overrides` | 1491–1493 | `getPromptOverrides(effectivePromptId)` ?? `PromptSettings()` |
| `backend` | 1501–1504 | retry → `_resolveBackendForPrompt(fresh)`; else `_activeRecordingBackend` ?? resolve |
| `isOffline` | 1505 | `backend == whisper` |
| `effectiveRephraseLevel` | 1507–1509 | `overrides.rephraseLevel` ?? global |
| `effectiveWhisperModelId` | 1511–1512 | `overrides.whisperModelId` ?? global |
| `effectiveWhisperLanguage` | 1513–1514 | `overrides.whisperLanguage` ?? global |
| `effectiveTwoPassEnabled` | 1515–1517 | `overrides.twoPassTranscriptionEnabled` ?? global |
| `effectiveTranscriptionModelId` | 1518–1521 | `overrides.twoPassTranscriptionModelId` ?? `overrides.modelId` ?? global |
| `effectiveRefinementModelId` | 1522–1525 | `overrides.twoPassRefinementModelId` ?? `overrides.modelId` ?? global |
| `cloudInPipeline` | 1526 | `!isOffline` ‖ `effectiveTwoPassEnabled` |
| `effectiveInstruction` | 1614–1618 | `selectedPrompt.instruction` + rephraser fragment (if any) |

**Override application gates (1528–1545):**
- Model override → applied iff `overrides.modelId != null && !isOffline`.
- Provider override → applied iff `overrides.cloudProvider != null && cloudInPipeline`.

**Important:** the global getters `twoPassTranscriptionModelId` / `twoPassRefinementModelId`
fall back to `selectedModelId` (`settings_service.dart:543–544` and `551–552`), and
`selectedModelId` falls back to `AppConfig.defaultModelId` (499–500). Therefore
`effectiveTranscriptionModelId` and `effectiveRefinementModelId` are **always non-null**.

---

## 2. Pipeline-combination mapping table

| # | Backend × TwoPass | Pass-1 model + instruction | Pass-2 model + instruction | Provider override | Model-only override (`setModelById`) | thinking levels |
|---|---|---|---|---|---|---|
| **A** | **Offline + OFF** | Whisper local (`effectiveWhisperModelId`), **no instruction** (verbatim) `-` | none | not applied (`cloudInPipeline=false`) | not applied (`!isOffline` false) | n/a (local) |
| **B** | **Offline + ON** | Whisper local (`effectiveWhisperModelId`), **no instruction** | cloud `improveTranscription`: model=`effectiveRefinementModelId`, instruction=`effectiveInstruction` ✓ | applied (`cloudInPipeline=true`) | not applied; redundant — pass 2 uses explicit `modelOverrideId` | refine: `overrides.twoPassRefinementThinkingLevel ?? overrides.thinkingLevel` |
| **C** | **Cloud + ON** | cloud `transcribeAudio`: model=`effectiveTranscriptionModelId`, **no user instruction** (verbatim, thinking forced minimal) | cloud `improveTranscription`: model=`effectiveRefinementModelId`, instruction=`effectiveInstruction` ✓ | applied | applied but **redundant** — both passes pass explicit `modelOverrideId` | pass1: forced minimal (no override plumbed); pass2: `overrides.twoPassRefinementThinkingLevel ?? overrides.thinkingLevel` |
| **D** | **Cloud + OFF** (single-pass) | cloud `transcribeAndImprove`: model=`overrides.modelId` (direct), instruction=`effectiveInstruction` ✓ | none | applied | applied (and actually meaningful here) | `overrides.thinkingLevel` |

> "✓" = the user-selected prompt mission (`effectiveInstruction`, incl. rephraser
> fragment) is applied on that pass.

### Notes on model selection per path
- **A, B pass 1:** Whisper uses `effectiveWhisperModelId` + `effectiveWhisperLanguage`.
- **B pass 2 & C pass 2:** `effectiveRefinementModelId` is passed explicitly, so the
  cloud client's `_currentModel` is never consulted. `_resolveModel` always gets a
  non-null override.
- **C pass 1:** `effectiveTranscriptionModelId` is passed explicitly.
- **D:** `transcribeAndImprove` is called with `modelOverrideId: overrides.modelId`
  (line **1718**), **not** `effectiveTranscriptionModelId`. Confirmed correct (Finding F1).

---

## 3. Findings

### F1. CONFIRMED CORRECT — single-pass cloud uses `overrides.modelId` directly
`main.dart:1714–1718`:
```dart
improvedText = await _cloudService.transcribeAndImprove(
  audioBytes!, 'audio/wav',
  missionInstruction: effectiveInstruction,
  modelOverrideId: overrides.modelId,   // <-- direct, not effectiveTranscriptionModelId
  thinkingLevelOverride: overrides.thinkingLevel,
);
```
`effectiveTranscriptionModelId` does **not** leak into the single-pass path. When
`overrides.modelId` is null, the client (`_resolveModel`) falls back to
`_currentModel`, which is the global default because the global `setModelById`
override wasn't applied. Correct.

### F2. CONFIRMED CORRECT — `effectiveTranscriptionModelId` is cloud-two-pass-only
It is referenced exactly once, at line 1701 (Path C pass 1). The Whisper branch
(1621–1695) uses `effectiveWhisperModelId`; single-pass (1712–1721) uses
`overrides.modelId`. No leak. ✓

### F3. CONFIRMED CORRECT — backend pinning (`_activeRecordingBackend`)
- Set at `main.dart:1323` after a committed start (`if (started)`), from
  `_effectiveBackendForSession()` (789–792) which resolves via
  `_resolveBackendForPrompt(_temporaryPromptId ?? selectedPromptId)`.
- Reset to `null` at 1233 (start), 1374 (start didn't commit), 1845 (abort),
  1889 (cancel), and 1775 (stop `finally`).
- Consumed at 1503 (stop: pinned) and 1871 (cancel during processing: decides
  whether to call `_whisperService.cancelTranscription()`).
- The comment block at 1495–1500 is faithfully implemented: a non-retry stop
  reuses the captured value with a `_resolveBackendForPrompt(...)` safety-net
  fallback for the edge case where the pinned value is null.
Pinning is **correct and consistent**.

### F4. CONFIRMED CORRECT — retry resolves backend (and prompt) fresh
`main.dart:1501–1504`: `retryExisting ? _resolveBackendForPrompt(effectivePromptId) : (pinned ?? resolve)`.
On retry, `effectivePromptId` additionally honors `_useCurrentSettingsForRetry`
(1484–1486), so a user who opens Settings, flips Cloud↔Whisper and/or switches the
active prompt, then retries, gets the **new** decision. Matches the comments at
1499–1500 ("Retry intentionally resolves fresh so the user can re-run with the
newly chosen settings"). ✓ Intentional and correct.

### F5. CONFIRMED CORRECT — override restore in `finally`
`main.dart:1783–1794` restores `_cloudService` model to `selectedModelId` and
clears the provider override, gated by the `_promptModelOverrideActive` /
`_promptProviderOverrideActive` flags, then clears the flags. The flags are reset
to false at the top of each run (1529–1530) and re-applied (1531–1545) for that
run. Restore-and-reapply stays consistent even across the
keep-session-for-retry → retry cycle (the retry re-enters `_stopRecordingAndProcess`
and re-applies). The restore itself runs **unconditionally** in `finally`
(regardless of `keepSessionForRetry`), which is safe because nothing else runs
between the failed attempt and the retry. ✓

---

## 4. Inconsistencies / concerns (none are logic bugs that corrupt output)

### C1 (by design, but silent) — Offline + TwoPass OFF drops the selected prompt
**Path A, lines 1693–1695** set `improvedText = rawTranscript`. `effectiveInstruction`
(the selected prompt mission **and** the rephraser fragment) is never used on this path.
- For the default `standard` prompt this is invisible (Whisper's own pass is the
  de-facto "standard" baseline).
- For `concise`, `smart`, or any custom prompt + any rephrase level, the user
  gets **verbatim Whisper output** with no mission, no summarisation, no rephrasing,
  and **no runtime warning/log** in `_stopRecordingAndProcess`.
- The only signals that this will happen live in the UI:
  `mode_selection_popup.dart:201–202` ("On the local-only backend a non-default
  prompt has no effect until a cloud model is in the pipeline") and
  `settings_service.isPromptInactiveOnLocalBackend` (818–826).
- This exactly matches the task-5 suspicion: **offline + two-pass OFF silently
  ignores the selected prompt.** It is a deliberate design rule, not a coding bug,
  but it is a silent data path. Recommendation: either auto-enable two-pass when a
  non-default prompt / non-`off` rephrase is selected on the offline backend, or
  emit a `debugPrint`/"(ignored on Offline)" hint at the point the transcript is
  produced, so the behaviour is auditable in production logs.

### C2 (redundant, harmless) — `setModelById(overrides.modelId)` has no effect on any two-pass path
The model-only override (`_cloudService.setModelById`, 1531–1537) mutates the client's
`_currentModel`. But:
- Path C (cloud two-pass): both passes pass explicit, always-non-null
  `modelOverrideId`, so `_currentModel` is never read.
- Path D (cloud single-pass): the override is also passed as `modelOverrideId`
  directly (1718), so the global mutation is redundant there too.
- Path B (offline two-pass): `!isOffline` is false, so it isn't applied — but the
  refine pass still passes `effectiveRefinementModelId` explicitly, so no problem.

Net effect: the only place the `setModelById` mutation is *observable* is Path D,
and even there it is redundant with the per-call argument. Not a bug; flagging that
the model-override machinery is effectively dead for two-pass.

### C3 (precedence nit) — `overrides.modelId` lives in both two-pass fallback chains, enabling a non-obvious split
`effectiveTranscriptionModelId` (1518–1521) = `twoPassTranscriptionModelId ?? modelId ?? global`
`effectiveRefinementModelId` (1522–1525)   = `twoPassRefinementModelId ?? modelId ?? global`

If a user sets only `modelId` (generic) **and** `twoPassTranscriptionModelId`
(pass-1-specific), then on Path C pass 1 uses `twoPassTranscriptionModelId` while
the refine pass uses `modelId` (because `twoPassRefinementModelId` is null and
`modelId` sits ahead of global). The two passes then use **different** models with
no warning. The UI at `prompt_override_panel.dart:645–647` describes a null pass-1
override as "Inherits the app default", which understates the real precedence
(`modelId` override first, *then* app default). Suggest tightening the description
and/or documenting that `modelId` is a catch-all that also feeds the per-pass slots.

### C4 (by design, no UI control) — pass-1 transcription is always forced-minimal thinking
`cloud_transcription_service.transcribeAudio` (132–136) and both clients
(`gemini_api_service.dart:235–236`, `vertex_ai_service.dart:344–345`) call
`_buildThinkingConfig(..., forceMinimal: true)` and accept **no** `thinkingLevelOverride`.
`PromptSettings` (prompt_settings.dart) has no `twoPassTranscriptionThinkingLevel`
field either. So a user who raises the per-prompt / global thinking level gets it
only on the refine/merge pass, never on the transcription pass. This is the intended
"cheap verbatim pass" design; flagged only because the override surfaces suggest it
might apply to both passes. Not a bug.

### C5 (edge, custom prompts) — empty-string instruction is passed through verbatim
`SystemPrompt.fromMap` allows an empty `instruction` (line 263). If a custom prompt
ends up with `instruction == ''`, `effectiveInstruction` becomes the rephraser
fragment alone (or empty + fragment). The cloud clients
(`gemini_api_service.dart:383–384`, `vertex_ai_service.dart` likewise) only fall back
to the default prompt when `missionInstruction` is **null**, not when empty. An empty
custom-prompt instruction is therefore sent as-is. Not reachable with the built-in
prompts; minor data-hygiene risk for hand-crafted custom prompts.

### C6 (out of scope but noted) — no in-flight cancellation for cloud requests
`_cancelRecording` (1870–1873) cancels only Whisper transcription (`cancelTranscription`).
An in-flight cloud HTTP request is not cancelled and runs to completion in the
background after a user-cancel. No model/override leak results (state is reset in the
same method), but it is wasted cloud spend. Not part of the 4-path matrix.

---

## 5. Summary verdict on the assignment's questions

1. **Override fallback chains** — correct; `effectiveTranscriptionModelId` /
   `effectiveRefinementModelId` are always non-null (C3 documents the precedence nuance).
2. **`overrides.modelId` only-when-not-offline, provider only when `cloudInPipeline`** —
   correct; restored correctly in `finally` (F5).
3. **`effectiveTranscriptionModelId` confined to cloud-two-pass pass 1; single-pass
   uses `overrides.modelId` directly** — CONFIRMED (F1, F2). No leak.
4. **Retry resolves backend (and prompt) fresh** — CONFIRMED (F4).
5. **Path where the prompt instruction is silently dropped** — YES, Path A
   (Offline + TwoPass OFF); by design and surfaced only in the UI, not at runtime (C1).
6. **Backend pinning** — correctness CONFIRMED (F3).
