# Beeamvo Simplification & Production-Readiness Plan

> Living document. Re-read this before every sprint step. Update the backlog
> status (`[ ]` → `[x]`) as work lands. Sections 1–3 are the *why*, 4–6 are the
> *what*, 7–8 are the *how*.

---

## 1. Original request (verbatim from Justin)

> Analyze the current state of this application, and we need to simplify and
> make the user experience significantly better. Currently, we have too many
> options and the app is working itself, but it feels more like an expert's
> developer tool, and I want to make it very simple. So, for example, when we
> are selecting two pass transcription, it should just be a nice addition. So,
> um currently, we need to scroll very down to see the second model, which is
> a bad UI and UX. Um, on the other hand, we have like somehow our prompt
> selection, which obviously we have the smart mode, but also we have in the
> general tab somehow a setting where we can select only transcription or
> something different. All in all, this is very complex and it's not very
> nice. So, I think we have duplicated logic for some things, which are
> getting overwritten and are bad. We have legacy things inside, we have a
> clean um to clean up, and we have to work on this. So, first of all, do a
> structured MD file, which you can reread to the whole process. Um, you can
> write it very detailed, all your findings, and all what I told you right
> now, the prompt. Write it down into his MD file, write a structured to-do
> list, and run a complete Scrum session, um act as a Scrum master, you can
> spawn sub-agents and work to this complete application to make it now
> production ready and perfect. So, it is clean, it has no dead code, it has
> no complication. It's looking nice, it has a perfect look and feel. It's
> very user-friendly and so on.

### Distilled goals

1. **Simple, not expert.** Fewer visible options; sane defaults; progressive
   disclosure only where truly needed.
2. **Two-pass is "a nice addition".** One toggle next to the model, second
   model visible right there — no scrolling.
3. **One concept for "how the text is processed".** No overlapping
   Prompt / Smart Mode / Output Mode / Rephraser / transcription-only knobs.
4. **No duplicated or overwritten logic.** One source of truth for each
   setting; predictable effective behaviour.
5. **No legacy / dead code.** Delete rather than hide.
6. **Polished look & feel.** Consistent, calm, production-grade UI.
7. **Production ready.** `flutter analyze` clean, `dart format` clean,
   `flutter test` green, Linux release build succeeds.

---

## 2. Current state — audit findings

Repo: `/home/ubuntu/repos/Beeamvo`, Flutter app in `frontend/`.
Baseline (Flutter 3.47.1 locally, CI pins 3.44.2): `flutter analyze` → 5
warnings (`unawaited_return_in_try_block` in
`whisper_model_download_service.dart`), `flutter test` → 237 passing.

### 2.1 The processing pipeline has FIVE overlapping "how is my text shaped" controls

| # | Control | Where | Persisted key(s) |
|---|---------|-------|------------------|
| 1 | **Prompt** (Default / Concise / Smart Mode / custom) | Prompts page, tray, mode popup, onboarding "Transcription Style" | `selectedPromptId` |
| 2 | **Professional Rephrasing** Off/Medium/High (global) | Prompts page "Rephraser", tray submenu | `rephraseLevel` |
| 3 | **Per-prompt Rephraser override** | Prompt override panel | `promptOverrides[id].rephraseLevel` |
| 4 | **Output Mode** Verbatim/Smart | AI Models page "Transcription Settings" (only when a transcription-only model is primary) | `transcriptionMode` |
| 5 | **Transcription-only model as primary** (`gemini-3.5-transcribe`) → silently ignores prompt + rephraser | AI Models page model dropdown | `selectedModelId` |

Effective instruction at runtime (`main.dart:1559-1685`) =
`prompt.instruction + rephraseFragment`, where each piece is resolved
`override ?? global`. #4 is *not even used* by the cloud pipeline for
two-pass; it only changes the system prompt of the raw pass. #5 makes the
Prompts page a no-op without telling the user (until the "Transcription
Settings" section appears far below). This is exactly the confusion Justin
described ("smart mode … but also a setting where we can select only
transcription").

### 2.2 Two-pass: buried and over-parameterised

`ai_models_page.dart` order: Engine → Provider → API surface → Credentials →
Verify → Model → Thinking level → Whisper models → Language → **Transcription
Pipeline** (toggle) → Pass 1 model → Pass 2 model → Pass 2 thinking level →
Transcription Settings → Cloud fallback. Pass 2 lives ~10 rows below the
primary model, and it's *a second copy of the primary model choice* with its
own thinking level. Per-prompt overrides duplicate all of this again
(`prompt_override_panel.dart`, 859 lines).

Persisted keys involved: `twoPassTranscriptionEnabled`,
`twoPassTranscriptionModelId`, `twoPassRefinementModelId`,
`thinkingLevel_<model>` (per model, used for both passes), plus
`PromptSettings.twoPassTranscriptionEnabled / twoPassTranscriptionModelId /
twoPassRefinementModelId / twoPassRefinementThinkingLevel / thinkingLevel`.

### 2.3 Backend/cloud coupling & implicit "fallback" logic (the "overwritten" logic)

- `TranscriptionBackend.whisper` + non-default prompt + cloud credentials ⇒
  **implicit cloud refinement pass** (`whisperPromptFallback`, `main.dart:1606`)
  even though two-pass is off. Surfaced as a read-only "Cloud Fallback" row.
- Three different ways the same fact ("cloud is in the pipeline") is computed:
  `SettingsService.isCloudRefinementInPipeline`, `isPromptInactiveOnLocalBackend`,
  `main.dart cloudInPipeline`.
- Cross-page dialogs triggered by this coupling: `prompt_cloud_switch_dialog`,
  `mode_cloud_confirm_popup`, tray items `rephrase_switch_cloud`,
  `rephrase_switch_twopass`, `rephrase_setup_cloud`, prompt-page banners,
  mode-popup "blocked" state. ~1 000 lines exist only to explain the coupling.
- Helper transitions `enableLocalTwoPassRefinement()` /
  `switchToCloudTranscription()` mutate two keys each.

### 2.4 Exposed implementation details

- **API Surface** (Interactions vs Legacy `generateContent`) is a user-facing
  dropdown (desktop + mobile). Users cannot make an informed choice here.
  Transcription-only model *requires* Interactions
  (`cloud_transcription_service.dart:172`) so the wrong combination errors out.
- **Cloud provider** Gemini vs Vertex AI — legitimate, keep, but in one
  compact "Account" group.
- **Thinking level** per model — keep, but as one segmented control for the
  selected model only.
- Whisper **Language** vs cloud **Transcription language** are two different
  keys (`whisperLanguage`, `transcriptionLanguage`) for the same user intent.

### 2.5 Dead / legacy code (verified by grep — no runtime callers)

| Item | Location | Notes |
|------|----------|-------|
| OpenAI-compatible provider | `models/openai_compatible_config.dart`, `services/openai_compatible_service.dart`, `SettingsService.openAiCompatible*`, `credential_store` keys, `test/openai_compatible_service_test.dart` | Never reachable from UI (`CloudProvider` has no OpenAI value). |
| `enableDiarization`, `enableWordTimestamps` | `settings_service.dart` | Persisted, never read by any pipeline. |
| `TranscriptionMode` enum + `transcriptionMode` setting | `enums.dart`, `settings_service.dart`, AI page, mobile | Superseded by prompts. |
| `GeminiApiSurface` enum + `GeminiApiService` (generateContent) | `enums.dart`, `services/gemini_api_service.dart`, `test/gemini_api_service_test.dart` | Keep **one** Gemini client (Interactions). |
| `SystemPrompt.modelId` "backward-compatible getter" | `system_prompt.dart` | Legacy. |
| Legacy hotkey migration `_legacyHotkeyKeys` | `settings_service.dart` | Verify; drop if pre-1.0. |
| Stale review docs | `SERVICES_LAYER_REVIEW.md`, `frontend/SETTINGS_AUDIT.md`, `frontend/WIDGETS_AUDIT.md`, `frontend/macos_native_review.md` | Point-in-time audits, partially outdated. Fold still-valid items into this plan, delete files. |
| `RephraseLevel` + fragments | `system_prompt.dart`, tray, prompts page, override panel, onboarding step | Replaced by a built-in "Professional" prompt. |
| `PromptSettings` (11 nullable override fields) + `prompt_override_panel.dart` + `getPromptOverrides/setPromptOverrides` | models/, widgets/, services/ | Removed entirely (see decision D3). |

### 2.6 Still-valid items from the old audits (carry over)

- Onboarding: Escape handling broken; state lost between steps; "Skip Setup"
  misleading; gesture-only CTAs (a11y).
- Diagnostics page can get stuck in loading.
- Clipboard history duplicate entries; whole-page rebuilds on any setting
  change; heatmap repaints.
- Missing `mounted` checks after awaits in several dialogs.
- Duplicate permission-polling callbacks.

### 2.7 Onboarding is 9 steps

Welcome → Provider → API key → Model → Transcription Style → Two-pass &
Rephrase → Recording mode → Hotkey → Ready. Steps 4, 6, 7 are expert
choices with good defaults.

### 2.8 Surfaces that mirror settings (must stay in sync)

Desktop settings pages, mobile `mobile_settings_screen.dart`, tray menu
(`tray_service.dart`), mode popup (`mode_selection_popup.dart`), onboarding,
`README.md`, `CHANGELOG.md`.

---

## 3. Target experience

### 3.1 Mental model (what a user needs to understand)

1. **Engine** — *Cloud* (best quality) or *Offline* (private, Whisper).
2. **Style** — which prompt shapes the text (Default / Concise / Smart /
   Professional / your own).
3. **Refine** *(optional)* — "Two-step: transcribe first, then polish with the
   AI model". One toggle. Second dropdown appears directly beneath it.

That's it. Everything else is account setup, hotkeys, or diagnostics.

### 3.2 Effective pipeline (single, explicit resolution — no overrides, no implicit fallback)

```
engine = cloud:
  twoStep off → model.transcribeAndImprove(audio, prompt)
  twoStep on  → raw = step1Model.transcribe(audio)
                out = model.improve(raw, prompt)
engine = offline:
  twoStep off → out = whisper.transcribe(audio)      # prompt not applied; UI says so
  twoStep on  → raw = whisper.transcribe(audio)
                out = model.improve(raw, prompt)
```

- `model` = the single "AI model" (main models only). Its thinking level is
  the single thinking level. No separate "refinement model".
- `step1Model` = defaults to the dedicated transcription model
  (`gemini-3.5-transcribe`) on Gemini; falls back to `model` where not
  supported (Vertex).
- Whisper-with-prompt no longer silently calls the cloud. If Offline and
  two-step is off, prompts/style are shown as "Applied when Refine is on" in
  the Prompts page — one inline hint, no dialogs.

### 3.3 Settings information architecture

| Page | Groups (rows) |
|------|---------------|
| **Home** | unchanged (stats) |
| **General** | Appearance · Recording (device, mode, auto-stop) · Shortcuts (3) · System (login, permission, wizard, reset) · About (version, update) |
| **Transcription** *(renamed from AI Models)* | **Engine** (Cloud/Offline segmented) · **Account** [cloud] (provider, key/project, verify — compact) · **Model** [cloud] (model, quality/thinking) · **Refine** (two-step toggle → step-1 model row directly below) · **Offline model** [offline] (Whisper model list, language) · **Language & vocabulary** (one spoken-language setting, custom vocabulary) |
| **Prompts** | Current style (cards) · Custom prompts. No rephraser, no override panel. |
| **Clipboard** | unchanged |
| **Help** *(renamed from Troubleshooting)* | diagnostics, logs, platform info |

### 3.4 Onboarding (7 steps, down from 9)

Welcome → Engine (Cloud/Offline) → Account (API key, only if cloud) → Model
& Style → Recording mode → Hotkey → Ready. No Output Mode / Rephraser steps.

### 3.5 Visual polish principles

- One visual language (`BeeSettingsRow`, `BeeGroupLabel`, `BeeSegmented`,
  `BeeToggle`), no BETA badges, no warning banners for normal states.
- Max ~6 rows per group, ≤ 3 groups visible without scrolling at 720 px.
- Conditional rows animate in place (`AnimatedSize`), never at the page end.
- Copy: short label + one-line description in plain language.

---

## 4. Decisions (made by the Scrum master; flag to Justin if he disagrees)

| ID | Decision | Rationale |
|----|----------|-----------|
| D1 | Remove the **Rephraser** feature; add a built-in **Professional** prompt instead. | Rephraser is a second "style" axis fighting with prompts. One axis is simpler. |
| D2 | Remove **Output Mode (Verbatim/Smart)** and the ability to pick a transcription-only model as the *primary* model. Transcription-only models are only offered as step 1 of two-step. | Removes the "transcription only" setting that silently disables prompts. |
| D3 | Remove **per-prompt overrides** entirely (`PromptSettings`, override panel). A prompt = name + instruction. | 11 override fields × 5 surfaces was the main "duplicated logic getting overwritten". |
| D4 | Remove the **API Surface** switch; Gemini API-key always uses Interactions. Delete `GeminiApiService`. | Implementation detail; the transcription model needs Interactions anyway. |
| D5 | Remove **implicit whisper→cloud fallback**. Offline + Refine off = raw Whisper. | Predictable. Replaces ~1 000 lines of "why did it use the cloud" dialogs. |
| D6 | Single **refinement model** = the primary model. Drop `twoPassRefinementModelId` and its thinking level. | "Two-pass is an addition", not a second configuration. |
| D7 | Unify `whisperLanguage` + `transcriptionLanguage` → one `spokenLanguage`. | Same user intent. |
| D8 | Delete dead OpenAI-compatible provider, diarization/timestamps flags, stale audit MDs. | No dead code. |
| D9 | Old persisted keys are removed on load (`SettingsService._migrate`); overrides are dropped. Prompt id `standard` stays; rephraser ≠ off migrates to `professional` prompt only if prompt was `standard`. | Clean upgrade for existing users. |

---

## 5. Backlog (Scrum)

Legend: `[ ]` todo · `[~]` in progress · `[x]` done. Owner: **SM** = this
session, **A/B/C** = child sessions.

### Sprint 1 — Core model & pipeline — DONE

- [x] S1.1 `enums.dart`: `TranscriptionMode`, `GeminiApiSurface` deleted.
- [x] S1.2 `settings_service.dart`: rephrase, transcriptionMode, diarization,
      wordTimestamps, openAiCompatible*, geminiApiSurface, custom vocabulary,
      twoPassRefinementModelId, promptOverrides API, cloud-switch helpers
      removed. Language unified as `spoken_language`. `_migrate()` maps
      `rephrase_level != off` (on the Default prompt) → Professional, merges
      the two language keys, resolves stale model ids and drops retired keys.
      `selectedModelId` always resolves to a prompt-capable model.
- [x] S1.3 `models/`: `prompt_settings.dart`, `openai_compatible_provider.dart`,
      `transcription_backend_resolver.dart` deleted; `SystemPrompt` is
      id/name/instruction only; built-in **Professional** style added.
- [x] S1.4 `config.dart`: `mainModels` (primary) / `transcriptionModels`
      (step 1) / `defaultTranscriptionModelId`; `resolveRefinementModelId`
      kept as the single "is this prompt-capable" resolver.
- [x] S1.5 `services/`: `gemini_api_service.dart`, `openai_compatible_service.dart`
      deleted; `CloudTranscriptionService` = Gemini Interactions or Vertex, no
      provider/model override plumbing.
- [x] S1.6 `main.dart` / mobile controller: pipeline per §3.2, no per-prompt
      overrides, no implicit Whisper→cloud fallback, no cloud-confirm popup.
- [x] S1.7 Tests migrated; `settings_service_migration_test.dart` added.

### Sprint 2 — UI — DONE

- [x] S2.A **Transcription page** (`ai_models_page.dart`): Engine → Spoken
      Language → Cloud Account → AI Model → Two-Step Refinement (Step 1 and
      Step 2 rows inline under the toggle, no scrolling) → Whisper models.
- [x] S2.B **Writing Style page + tray**: single global style selection,
      preview, custom-style CRUD, "styles are paused while offline" hint with
      a jump to Transcription. Tray = Settings · Writing Style · Exit.
- [x] S2.C **Onboarding**: 7 steps, no mode/rephraser questions.
- [x] S2.D **Help / Mobile**: Troubleshooting renamed Help; mobile settings
      lose API-surface/mode/rephraser rows and follow the global pipeline.

### Sprint 3 — Polish & hardening — DONE (except UI verification)

- [x] S3.1 Dead-code sweep: OpenAI-compatible credential helpers, stale
      audit MDs, dead `onBackendChanged` plumbing, provider override API.
- [ ] S3.2 Carry-over bugs (§2.6) — deferred to a follow-up PR.
- [ ] S3.3 Visual review at 1280×720 / 1024×640 — via testing agent.
- [x] S3.4 Docs: README, CHANGELOG, setup guides updated.
- [x] S3.5 `flutter analyze` 0 issues · `dart format` clean · 166 tests
      green · `flutter build linux --release` OK (added the missing
      `linux/flutter/CMakeLists.txt`, which the Linux build requires).
- [ ] S3.6 PR opened; UI verification pending Justin's go-ahead.

---

## 6. Definition of Done

- No references to removed concepts remain (`rg -i "rephras|apiSurface|TranscriptionMode|PromptSettings|openAiCompat|diarization|wordTimestamp"` → 0 in `lib/`).
- Every setting has exactly one persisted key and one UI control.
- Two-step toggle and its step-1 model are adjacent to the primary model.
- Fresh install → onboarding ≤ 7 steps → first transcription without touching Settings.
- Existing install upgrades without crash; stale keys removed.
- All quality gates in S3.5 pass.

---

## 7. Working agreements

- Branch: `devin/<ts>-simplify-ux`. Children commit to the same branch, pull
  `--rebase` before push, never force-push, no PRs from children.
- Every child gets: this file, its file list, the §3 target, and "do not
  touch files outside your list".
- SM integrates after each sprint: analyze → format → test → update §5.

---

## 8. Sprint log

- **2026-09-04** Sprint 0: audit complete, plan written. Baseline: 237 tests
  green, 5 analyzer warnings.
- **2026-09-04** Sprint 1–3 implemented on `devin/1788535360-simplify-ux`.
  Result: 166 tests green, 0 analyzer issues, Linux release build OK.
  Removed concepts: Output Mode, Rephraser, per-prompt overrides, Gemini API
  Surface, OpenAI-compatible providers, separate Pass-2 model, custom
  vocabulary, diarization/word timestamps, implicit cloud fallback.
  Open: carry-over bugs (§2.6) and UI verification.
