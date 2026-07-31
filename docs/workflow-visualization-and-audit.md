# Beeamvo — Workflow Visualization & Consolidated Audit

> **Status & history.** This document is an **internal engineering audit** (pre-release). It
> consolidates the transcription-pipeline correctness audit and the cloud-switch dialog gating
> audit by re-verifying every cited file:line against the then-current source. It is preserved as
> design/architecture history; it is **not** end-user documentation. Code line numbers may drift
> over time — treat the flowcharts and the logic described as the durable part. The product name in
> the diagrams below uses an older spelling ("BeamVo"); the app is named **Beeamvo**.

This is the **single consolidated deliverable** combining the two prior audits:

- **Task 1** — Transcription pipeline correctness (`docs/transcription-pipeline-audit.md`): the
  4 [Backend × TwoPass] paths (A/B/C/D), model-resolution / override / backend-pinning logic.
- **Task 2** — Cloud-switch dialogs & prompt-effect detection (`docs/cloud-switch-dialog-audit.md`):
  the 3 detection predicates, every dialog/popup call site, and the gating bugs (GA1–GA6).

Every file:line cited below was re-verified against the current source for this report.

**Contents**

1. [Master flowchart — hotkey → paste](#1-master-flowchart--hotkey--paste)
2. [Path selection + per-path diagrams (A/B/C/D)](#2-path-selection--per-path-detail)
3. [Cloud-switch dialog gating logic](#3-cloud-switch-dialog--gating-logic)
4. [Consolidated prioritized issues table (C1–C6, GA1–GA6)](#4-consolidated-prioritized-issues-table)
5. [Appendix — confirmed-correct behavior](#5-appendix--confirmed-correct-behavior)

> **Legend**

```
✓ = applies    ❌ = dropped / not applied    → = flows to    ▼ = next step
```

---

## 1. Master flowchart — hotkey → paste

Shows the complete end-to-end decision flow, including the 2×2 path selection that fans out into
paths A/B/C/D. Per-path detail is in [Section 2](#2-path-selection--per-path-detail).

```
 ╔═══════════════════════════════════════════════════════════════════════╗
 ║            BEAMVO — HOTKEY → "RECORDING" → PASTE : MASTER FLOW        ║
 ╚═══════════════════════════════════════════════════════════════════════╝

 ┌─────────────────────────┐
 │  USER PRESSES HOTKEY    │   idle → armed; a new session token is minted
 └────────────┬────────────┘              (guards against race transitions)
              ▼
       ┌──────────────┐    no    ┌──────────────────────────────┐
       │ mic perm OK? │─────────▶│ surface permission onboarding│
       └──────┬───────┘          └──────────────────────────────┘
              ▼ yes
 ┌─────────────────────────────────────────────────────────────────────┐
 │ START RECORDING                          (main.dart ~1280–1326)     │
 │  • resolve session backend first:                                   │
 │      backend = _effectiveBackendForSession()                        │
 │            → _resolveBackendForPrompt(promptId)                     │
 │              honors a per-prompt backend override                   │
 │  • PIN the backend on the session  _activeRecordingBackend = ...    │
 │                                       (main.dart:1323)              │
 │  • start recorder + stopwatch                                        │
 └─────────────────────────┬───────────────────────────────────────────┘
                           ▼
                 ┌───────────────────┐
                 │ RECORDING ACTIVE  │   ESC = cancel · re-press hotkey = stop
                 └─────────┬─────────┘   · duration-limit hit = stop
                           ▼
 ┌─────────────────────────────────────────────────────────────────────┐
 │ STOP & PROCESS   _stopRecordingAndProcess   (main.dart ~1482–1796)   │
 └─────────────────────────┬───────────────────────────────────────────┘
                           ▼
 ╔═════════════════════════════════════════════════════════════════════╗
 ║ RESOLVE EVERYTHING (main.dart 1484–1526)  each value = override ?? global ║
 ║                                                                       ║
 ║   effectivePromptId   retry? selectedPromptId : (_temp ?? selected)   ║
 ║   overrides           getPromptOverrides(id) ?? PromptSettings()      ║
 ║   effectiveWhisperModelId / Language   (offline pass)                 ║
 ║   effectiveTwoPassEnabled               overrides.twoPass ?? global    ║
 ║   effectiveTranscriptionModelId  twoPassTransModel ?? modelId ?? glbl ║
 ║   effectiveRefinementModelId     twoPassRefnModel ?? modelId ?? glbl  ║
 ║   effectiveInstruction            prompt.mission + rephraser fragment ║
 ║                                                                       ║
 ║   ⚠ both per-pass model ids are ALWAYS non-null                       ║
 ║     (globals fall back to selectedModelId → AppConfig.defaultModelId) ║
 ╚═════════════════════════════════════════════════════════╤═════════════╝
                                                           ▼
                              ┌──────────────────────────┐
                              │ retryExisting ?          │──yes──▶ resolve backend
                              └────────────┬─────────────┘        FRESH (ignores the
                                       no  │                      pin) · main 1501–1504
                                           ▼  (F4: intentional)
                        use pinned _activeRecordingBackend
                                           ▼
 ╔═════════════════════════════════════════════════════════════════════╗
 ║                      2 × 2  PATH SELECTION                          ║
 ║                                                                     ║
 ║                          backend + effectiveTwoPass                  ║
 ║                                  │                                   ║
 ║              ┌───────────────────┴───────────────────┐              ║
 ║            OFFLINE                                 CLOUD            ║
 ║         (effectiveWhisper)                      (cloud client)      ║
 ║              │                                       │              ║
 ║        ┌─────┴─────┐                          ┌───────┴───────┐      ║
 ║      OFF          ON                         OFF            ON      ║
 ║        │           │                           │             │       ║
 ║        ▼           ▼                           ▼             ▼       ║
 ║     PATH A     PATH B                      PATH D        PATH C     ║
 ║    verbatim   whisper→cloud              single cloud  cloud→cloud  ║
 ║     (drop)      refine                     pass          2 passes   ║
 ╚═════════════════════════════════════════════════════════════════════╝
                           │  (see Section 2 for pass detail)
                           ▼
 ┌─────────────────────────────────────────────────────────────────────┐
 │ APPLY OVERRIDES                            (main.dart 1528–1545)     │
 │  • model-only   iff overrides.modelId  != null &&  !isOffline        │
 │  • provider     iff overrides.cloudProvider != null && cloudInPipeline│
 │  (restored in the finally block, see below)                         │
 └─────────────────────────┬───────────────────────────────────────────┘
                           ▼
           ╔═══════════════════════════════════════╗
           ║  PATH A / B / C / D EXECUTES          ║
           ║   pass 1   (+ pass 2 for B & C)        ║
           ╚══════════════════════╤════════════════╝
                                  ▼
 ┌─────────────────────────────────────────────────────────────────────┐
 │ RESTORE in finally                        (main.dart 1783–1794)      │
 │  • reset cloud model back to selectedModelId                        │
 │  • clear provider override + the two "active" flags                 │
 │  • _activeRecordingBackend = null           (main.dart 1775)         │
 └─────────────────────────┬───────────────────────────────────────────┘
                           ▼
                 ┌──────────────────────┐
                 │ _state == processing?│── no (user cancelled)──▶ return · no paste
                 └──────────┬───────────┘
                            ▼ yes
 ┌─────────────────────────────────────────────────────────────────────┐
 │ COPY TO CLIPBOARD + PASTE (auto-paste on)   main.dart 1725           │
 │  • _copyToClipboardAndPaste(improvedText)                           │
 │  • addClipboardEntry(improvedText)                                  │
 └─────────────────────────────────────────────────────────────────────┘
```

---

## 2. Path selection + per-path detail

The 2×2 above selects exactly one of four paths. Each diagram below shows pass 1 → pass 2 with the
**specific model id, instruction, provider, and thinking level** used, plus which overrides are
applied. "✓ instruction" = the user's prompt mission + rephraser fragment (`effectiveInstruction`)
is actually consumed.

### Path A — Offline · TwoPass OFF  (silent drop → see C1)

```
 AUDIO ──▶ ┌─────────────────────────────────────────────────────┐
           │ PASS 1  (the ONLY pass)                             │
           │  Engine  : Whisper, local in-process                │
           │  Model   : effectiveWhisperModelId                  │
           │            = overrides.whisperModelId ?? global     │
           │  Language: effectiveWhisperLanguage                 │
           │  Instruct: ❌ NONE — verbatim transcription         │
           │  Thinking: n/a (local)                              │
           └────────────────────┬────────────────────────────────┘
                                ▼
                          rawTranscript
                       (assigned = improvedText)
                        main.dart 1693–1695
                                ▼
                           PASTE VERBATIM

 PASS 2 : —— none ——
 ⚠ DROPPED : effectiveInstruction (prompt mission + rephraser fragment)
   — no runtime log, surfaced only in the UI.  (Issue C1)
 Provider override : —— not applied (cloudInPipeline = false)
 Model override    : —— not applied (!isOffline is false)
```

### Path B — Offline · TwoPass ON  → instruction applied on pass 2

```
 AUDIO ──▶ ┌─────────────────────────────────────────────────────┐
           │ PASS 1                                              │
           │  Engine  : Whisper, local                           │
           │  Model   : effectiveWhisperModelId                  │
           │  Instruct: ❌ none (verbatim baseline pass)         │
           │  Thinking: n/a (local)                              │
           └────────────────────┬────────────────────────────────┘
                                ▼ rawTranscript
           ┌─────────────────────────────────────────────────────┐
           │ PASS 2  —— cloud  improveTranscription ——           │
           │  Engine  : Cloud (Gemini API-key or Vertex AI)      │
           │  Model   : effectiveRefinementModelId  (main ~1707) │
           │           = twoPassRefinementModelId                │
           │               ?? overrides.modelId ?? global        │
           │  Instruct: ✓ effectiveInstruction                   │
           │           (prompt mission + rephraser fragment)     │
           │  Thinking: twoPassRefinementThinkingLevel           │
           │               ?? overrides.thinkingLevel            │
           └────────────────────┬────────────────────────────────┘
                                ▼ improvedText
                           PASTE
 Provider override : ✓ applied iff overrides.cloudProvider != null
```

### Path C — Cloud · TwoPass ON  → instruction on pass 2 only; pass 1 verbatim

```
 AUDIO ──▶ ┌─────────────────────────────────────────────────────┐
           │ PASS 1  —— cloud  transcribeAudio ——   main 1698–1702│
           │  Engine  : Cloud                                   │
           │  Model   : effectiveTranscriptionModelId            │
           │           = twoPassTranscriptionModelId             │
           │               ?? overrides.modelId ?? global        │
           │  Instruct: ❌ none  ("cheap verbatim" pass)         │
           │  Thinking: FORCED minimal  —— no knob ——            │
           │           cloud_transcription_service.dart 132–136  │
           │           (Issue C4 — by design)                    │
           └────────────────────┬────────────────────────────────┘
                                ▼ rawTranscript
           ┌─────────────────────────────────────────────────────┐
           │ PASS 2  —— cloud  improveTranscription ——           │
           │  Model   : effectiveRefinementModelId  (main 1707)  │
           │  Instruct: ✓ effectiveInstruction                   │
           │  Thinking: twoPassRefinementThinkingLevel           │
           │               ?? overrides.thinkingLevel            │
           └────────────────────┬────────────────────────────────┘
                                ▼ improvedText
                           PASTE
 ⚠ pass 1 & pass 2 can use DIFFERENT models when only modelId +
   twoPassTranscriptionModelId are set (Issue C3)
```

### Path D — Cloud · TwoPass OFF  (single pass)  → instruction applied directly

```
 AUDIO ──▶ ┌─────────────────────────────────────────────────────┐
           │ SINGLE PASS —— cloud  transcribeAndImprove ———      │
           │              main.dart 1714–1720                    │
           │  Engine  : Cloud                                   │
           │  Model   : overrides.modelId  (DIRECT — not        │
           │           effectiveTranscriptionModelId)  (F1)      │
           │           (null ⇒ client falls back to global)      │
           │  Instruct: ✓ effectiveInstruction                   │
           │  Thinking: overrides.thinkingLevel                  │
           └────────────────────┬────────────────────────────────┘
                                ▼ improvedText
                           PASTE

 PASS 2 : —— none ——
 Provider override : ✓ applied
 Model override    : ✓ applied (and actually meaningful here)
```

### Cross-path comparison

```
 ┌──────┬───────────┬──────────────┬──────────────┬──────────────────────────────┐
 │ Path │ Backend   │ TwoPass      │ Instruction  │ Model used (per pass)        │
 ├──────┼───────────┼──────────────┼──────────────┼──────────────────────────────┤
 │  A   │ Offline   │ OFF          │ ❌ dropped   │ p1: whisperModelId           │
 │  B   │ Offline   │ ON           │ ✓ pass 2     │ p1: whisperModelId           │
 │      │           │              │              │ p2: refinementModelId        │
 │  C   │ Cloud     │ ON           │ ✓ pass 2     │ p1: transcriptionModelId     │
 │      │           │              │              │ p2: refinementModelId        │
 │  D   │ Cloud     │ OFF (single) │ ✓ pass 1     │ p1: overrides.modelId        │
 └──────┴───────────┴──────────────┴──────────────┴──────────────────────────────┘
 thinking : A/B p1 = n/a · C p1 = forced minimal · B/C p2 & D = thinkingLevel override
```

---

## 3. Cloud-switch dialog — gating logic

When a **blocked** selection (a non-default prompt that would be inert, or a rephraser level ↑ on a
local-only pipeline) is attempted, the app offers a switch to bring a cloud model into the pipeline.
The diagram shows the predicate gate, the credential check, the two options, what each persists, and
the resulting path. The call-site table beneath maps every entry point.

```
 ╔═══════════════════════════════════════════════════════════════════════╗
 ║          CLOUD-SWITCH DIALOG / POPUP — GATING LOGIC                   ║
 ╚═══════════════════════════════════════════════════════════════════════╝

   a blocked selection is attempted
   (non-default prompt on local-only pipeline, OR rephraser Off→Medium/High)
                 │
                 ▼
   predicate gate:
     prompt   → isPromptInactiveOnLocalBackend(id)   settings_service.dart:818
     rephraser→ !isCloudRefinementInPipeline         settings_service.dart:808
                 │
                 ▼
       ┌─────────────────────────┐
       │   hasCloudCredentials?  │   settings_service.dart:918–925
       │   Gemini-key → apiKey   │
       │   Vertex     → projectId│   ⚠ GA6 : ADC NOT checked
       └────────────┬────────────┘
        false    ┌──┴──┐    true
                 │     │
        ┌────────┘     └─────────┐
        ▼                        ▼
 ┌──────────────────┐   ┌─────────────────────────────────┐
 │ "needs setup"    │   │  FIRE DIALOG / POPUP            │
 │ shell            │   │  two option tiles appear:       │
 │ both choices     │   │  ┌───────────────────────────┐  │
 │ hidden → single  │   │  │ ◯ Local 2-pass refine     │  │
 │ action:          │   │  │ ◯ Cloud                   │  │
 │ "Open Settings"  │   │  └─────────────┬─────────────┘  │
 │ Result =         │   └────────────────┬────────────────┘
 │ openSettings     │            ┌───────┴────────┐
 │  (Esc = cancelled│            ▼                ▼
 │  → no change)    │   ┌──────────────┐ ┌──────────────┐
 └──────────────────┘   │ localTwoPass │ │   cloud      │
                        └──────┬───────┘ └──────┬───────┘
                               ▼                ▼
          enableLocalTwoPass-    switchToCloud-
            Refinement()           Transcription()
            (settings_service       (settings_service
             :834–837)               :841–844)
            backend = whisper       backend = cloud
            two-pass = TRUE         two-pass = FALSE
                               │                │
                               ▼                ▼
                           PATH B ✅        PATH D ✅
                     (W.→cloud refine)  (single cloud pass)

   ⚠ GA2  Tray Rephraser entry point bypasses the whole gate — see table below
   ⚠ GA5  force-local per-prompt override is invisible to the predicates — edge
```

### Call-site map (which entry points actually run the gate)

```
 ┌────┬──────────────────────────────────┬───────────────────────────────┬──────────┐
 │ #  │ Entry point                      │ Gate applied                  │ Persists │
 ├────┼──────────────────────────────────┼───────────────────────────────┼──────────┤
 │ G1 │ Ctrl+M mode popup                │ isPromptInactiveOnLocalBackend│ 1-shot*  │
 │    │ main.dart:1008 / _enter… :1032   │ (mode_cloud_confirm_popup:53) │          │
 │ G2 │ Settings → Prompts, prompt ROW   │ isPromptInactiveOnLocalBackend│ yes      │
 │    │ prompts_page.dart:590–591        │                               │          │
 │ G3 │ Settings → Prompts, REPHRASER    │ !isCloudRefinementInPipeline  │ casts to │
 │    │ prompts_page.dart:239–244        │                               │ AI-Models│
 │ G4 │ Tray: prompt switch ACTIONS      │ promptsNeedCloud (any)        │ direct   │
 │    │ tray_service.dart:99–122         │                               │ action   │
 │ G5 │ Tray: blocked PROMPT items       │ isPromptInactive… → disabled  │ (none)   │
 │    │ tray_service.dart:123–135        │                               │          │
 │ G6 │ Tray: REPHRASER items            │ ❌ NEVER gated  ←── GA2 ──     │ silent   │
 │    │ tray_service.dart:148–156,219–227│                               │ set      │
 │ G7 │ _PromptTile badge (Ctrl+M list)  │ isPromptInactive… → dim       │ visual   │
 │    │ mode_selection_popup.dart:204    │                               │ only     │
 └────┴──────────────────────────────────┴───────────────────────────────┴──────────┘
   * G1 stores a one-shot _temporaryPromptId (main 1118); it does NOT persist
     selectedPromptId. Only the backend/two-pass choice is shared — and it is
     identical across every entry point (same SettingsService methods).
```

---

## 4. Consolidated prioritized issues table

Merges **all** findings from Task 1 (`C1`–`C6`) and Task 2 (`GA1`–`GA6`). Sorted by **severity
descending** (High → Medium → Low → Info). Severity rubric:

- **High** — a real bug causing silent wrong behaviour in a *common* reachable flow.
- **Medium** — silent/incorrect behaviour or wrong guidance in a notable flow; or the foundational
  design decision the silent drops derive from.
- **Low** — edge cases, redundant/dead code, cosmetic & copy inconsistencies, design nits.
- **Info** — documentation / naming; by design, no code change required.

| ID | Sev | Title | File:Line | Description | Recommendation |
|----|-----|-------|-----------|-------------|----------------|
| **GA2** | **High** | Tray Rephraser menu is never gated | `tray_service.dart:148–156, 219–227` | The Rephraser submenu is built with every level always enabled; the click handler calls `setRephraseLevel(level)` with **no** blocked-check, badge, or dialog. On Offline·2-pass-OFF this silently picks Medium/High, resolves to **Path A**, and the rephraser fragment is dropped with zero feedback. Every *other* inert entry point is gated (prompts tray G5, prompts page, Ctrl+M popup); the tray rephraser is the lone un-gated path. | Mirror the prompt handling: disable Medium/High when `!isCloudRefinementInPipeline` and route through the same `switchToCloudTranscription` / `enableLocalTwoPassRefinement` / setup item (`tray_service.dart:99–122`). |
| **C1** | **Medium** | Offline·2-pass-OFF silently drops prompt + rephraser (Path A) | `main.dart:1693–1695` | Path A sets `improvedText = rawTranscript`; `effectiveInstruction` (prompt mission **and** rephraser fragment) is never used. For the `standard` prompt this is invisible; for `concise`/`smart`/custom + any rephrase level the user gets verbatim Whisper with no mission, no summarisation, no rephrasing — and **no runtime log**. Only the UI hints at it (`mode_selection_popup.dart:201–204`, `isPromptInactiveOnLocalBackend`). Deliberate design rule, but a silent data path. | Either auto-enable two-pass when a non-default prompt / non-OFF rephraser is active on the offline backend, or emit a `debugPrint`/"(ignored on Offline)" hint at production time so the drop is auditable. *(This silent drop is the root cause GA2 and GA5 surface.)* |
| **GA3** | **Medium** | `_LocalOnlyBadge` keys off `hasGeminiApiKey`, not `hasCloudCredentials` | `prompts_page.dart:209, 552, 970–973, 1221–1225` | Constructed with `hasGeminiKey: settings.hasGeminiApiKey` and the popover body says "Add a Gemini API key…". When the active provider is **Vertex AI**, a configured project makes `hasCloudCredentials==true`, yet `hasGeminiApiKey` is false — so a ready-to-go Vertex user is told to add a Gemini key. The dialog/popup/tray all use the correct `hasCloudCredentials`; only this badge is wrong. | Pass `hasCloudCredentials` to `_LocalOnlyBadge` instead, and make the popover copy provider-aware (mention Vertex / generic "cloud"). |
| **GA6** | **Medium** | Vertex `hasCloudCredentials` trusts project-id, not ADC | `settings_service.dart:918–925` | On `vertexAi`, `hasCloudCredentials` returns `vertexProjectId != null`; it does **not** verify Application Default Credentials exist. So the switch is offered and applied, then cloud transcription **fails at first request** (no ADC). Makes `openSettings` a false-negative gate and lets users pick a cloud that won't run. Pre-existing / mirrors readiness checks per the doc comment (915–917). | Verify ADC presence in the Vertex branch (or at least a lightweight token probe), or gate on a combined `projectId != null && adcPresent` check. |
| **C3** | **Low** | `overrides.modelId` sits in both two-pass fallback chains → mismatched pass models | `main.dart:1518–1525` | `effectiveTranscriptionModelId = twoPassTranscriptionModelId ?? modelId ?? global` and `effectiveRefinementModelId = twoPassRefinementModelId ?? modelId ?? global`. If a user sets `modelId` **and** `twoPassTranscriptionModelId` (but not the refinement one), Path C pass-1 uses `twoPassTranscriptionModelId` while pass-2 uses `modelId` — different models, no warning. The override UI (`prompt_override_panel.dart:645–647`) describes a null pass-1 slot as "Inherits the app default", understating the real `modelId → global` precedence. | Tighten the override-panel description to state that `modelId` feeds the per-pass slots, and/or document the precedence chain. |
| **GA4** | **Low** | `_LocalOnlyBadge` hardcodes "Rephraser…" copy, reused on prompt rows | `prompts_page.dart:970–1072` (tooltip 1027–1028, body 1210–1218); reused at 551–553 | The badge widget hardcodes its tooltip/body to the rephraser feature, but is also used verbatim for blocked **prompt** rows. Hovering the badge on a prompt row reads *"Rephraser has no effect on offline-only Whisper."* — the wrong feature. | Parameterise the badge with a feature label (rephraser vs prompt) and branch the text accordingly. |
| **GA5** | **Low** | force-local per-prompt override invisible to the predicates | `settings_service.dart:808–810, 818–828` | `isCloudRefinementInPipeline` is global-only; `isPromptInactiveOnLocalBackend` only short-circuits overrides that *bring cloud in* (822 cloud, 825 two-pass-on). A per-prompt override pinning `whisper` + `twoPass=false` is ignored when the *global* pipeline has cloud, so the predicate returns `false` (active) but `resolveSessionBackend` honors the whisper override at record time → **Path A** drop with **no dialog**. Edge; arguably defensible (the user explicitly pinned offline), but the predicate's own contract is violated. | Compute inert-ness against the *resolved* per-prompt backend + effective two-pass for an exact verdict — or explicitly document the asymmetry. |
| **C5** | **Low** | Empty-string instruction passed through verbatim | `main.dart:1614–1618`; clients `gemini_api_service.dart:383–384` (Vertex likewise) | `SystemPrompt.fromMap` allows `instruction == ''`. If a custom prompt ends up empty, `effectiveInstruction` becomes the rephraser fragment alone (or just the fragment). The cloud clients only fall back to the default prompt when `missionInstruction` is **null**, not empty — so the empty string is sent as-is. Not reachable with built-in prompts. | Treat empty-string instruction as null at resolve time (or in `fromMap`), so the default-prompt fallback applies. |
| **C6** | **Low** | No in-flight cancellation of cloud requests | `main.dart:1870–1873` | `_cancelRecording` cancels only Whisper (`cancelTranscription`). An in-flight cloud HTTP request runs to completion after a user cancel — wasted cloud spend. No model/override leak (state is reset in the same method). Outside the 4-path matrix. | Pass a cancellable token / `AbortController`-equivalent into the cloud client calls and abort on cancel. |
| **C2** | **Low** | `setModelById(overrides.modelId)` is effectively dead for two-pass | `main.dart:1531–1537` | The model-only override mutates the client's `_currentModel`, but on Path C both passes pass an explicit non-null `modelOverrideId`, and on Path D the override is also passed directly as `modelOverrideId: overrides.modelId` (1718). Redundant and harmless; flagging dead machinery for two-pass. | Consider dropping the per-run `setModelById` mutation, or document that it only matters for Path D where it is already redundant. |
| **C4** | **Info** | Pass-1 transcription is always forced-minimal thinking (by design) | `cloud_transcription_service.dart:132–136`; `gemini_api_service.dart:235–236`, `vertex_ai_service.dart:344–345` | `transcribeAudio` calls `_buildThinkingConfig(…, forceMinimal: true)` and accepts **no** `thinkingLevelOverride`; `PromptSettings` has no `twoPassTranscriptionThinkingLevel` field. Raising per-prompt/global thinking affects only the refine pass, never the transcription pass. Intended "cheap verbatim pass" — but the override surfaces imply it might apply to both passes. | If exposing it is ever desired, add a `twoPassTranscriptionThinkingLevel` field; otherwise document the design in the override UI. No defect. |
| **GA1** | **Info** | `isPromptInertForCurrentPipeline` does not exist (naming/doc) | (brief vs `settings_service.dart:818`) | The Task-2 brief names four predicates, but only three are implemented. The role of the missing name is filled by `isPromptInactiveOnLocalBackend`. **No code references** the missing name — pure doc/naming discrepancy. | Update the brief/docs to reference the real predicate name. No code change. |

### Recommended fix order (impact-weighted)

```
 1. GA2  gate the tray Rephraser items            (High — common silent fail, real bug)
 2. C1  add a runtime signal for the Path-A drop   (Medium — root of GA2 / GA5)
 3. GA3 fix _LocalOnlyBadge credential source      (Medium — wrong copy for all Vertex users)
 4. GA6 verify Vertex ADC in hasCloudCredentials   (Medium — offered-then-fail)
 5. GA4 parameterise _LocalOnlyBadge feature label (Low  — wrong-feature tooltip)
 6. C3  document the modelId precedence chain      (Low  — potential model mismatch)
 7. GA5 resolve per-prompt inert-ness, or document (Low  — edge)
 8. C5  treat empty instruction as null            (Low  — custom prompts)
 9. C6  cancel in-flight cloud requests            (Low  — wasted spend)
10. C2  drop redundant per-run setModelById        (Low  — dead code)
11. C4  document forced-minimal pass-1 thinking    (Info)
12. GA1 update docs for predicate name             (Info)
```

---

## 5. Appendix — confirmed-correct behavior

Findings prefixed **F** below were confirmed correct during the audits (Task-1 `F1`–`F5`). They are
*not* issues — included so the full picture of "what was verified" is in one place.

- **F1 — Single-pass cloud uses `overrides.modelId` directly.** `main.dart:1718` passes
  `modelOverrideId: overrides.modelId` (not `effectiveTranscriptionModelId`). When `overrides.modelId`
  is null, the client falls back to its `_currentModel` (the global default, since the global
  `setModelById` override isn't applied). No leak. ✓
- **F2 — `effectiveTranscriptionModelId` is cloud-two-pass-only.** Referenced exactly once
  (`main.dart:1701`, Path C pass 1). Whisper uses `effectiveWhisperModelId`; single-pass uses
  `overrides.modelId`. No leak. ✓
- **F3 — Backend pinning (`_activeRecordingBackend`).** Set at `main.dart:1323` after a committed
  start; reset on start / abort / cancel / stop-`finally`; consumed on stop (1503) and on
  cancel-during-processing (1871). Reuses the pinned value with a fresh `_resolveBackendForPrompt`
  safety-net when null. Correct and consistent. ✓
- **F4 — Retry resolves backend (and prompt) fresh.** `main.dart:1501–1504`:
  `retryExisting ? resolve(prompt) : (pinned ?? resolve)`. Combined with `_useCurrentSettingsForRetry`
  (1484–1486), a user who flips backend/prompt in Settings then retries gets the new decision.
  Intentional and correct. ✓
- **F5 — Override restore in `finally`.** `main.dart:1783–1794` restores the cloud model to
  `selectedModelId`, clears the provider override, and clears both "active" flags; the flags are
  reset (1529–1530) and re-applied (1531–1545) each run. Restore runs unconditionally in `finally`,
  which is safe across the keep-session-for-retry → retry cycle. ✓
- **CC1 — `localTwoPass` ⇒ Path B.** `enableLocalTwoPassRefinement()` (`settings_service.dart:834–837`)
  sets Whisper + two-pass ON. ✓
- **CC2 — `cloud` ⇒ Path D.** `switchToCloudTranscription()` (`settings_service.dart:841–844`) sets
  Cloud + two-pass OFF (single pass). ✓
- **CC3 — Credential gating is consistent across all three shells** (popup `mode_cloud_confirm_popup.dart:53`,
  modal `prompt_cloud_switch_dialog.dart:287`, tray `tray_service.dart:113–120`). ✓
- **CC4 — Popup ↔ modal persist identical state.** Both call the same `SettingsService` methods and
  share `kPromptCloudModeOptions` / `PromptCloudModeTile` / copy (`prompt_cloud_switch_dialog.dart:113–114, 279–296`).
  Cannot desync on the backend/two-pass choice. ✓

---

*Sources: verified against `frontend/lib/main.dart`, `services/settings_service.dart`,
`services/tray_service.dart`, `services/cloud_transcription_service.dart`,
`widgets/mode_cloud_confirm_popup.dart`, `widgets/prompt_cloud_switch_dialog.dart`,
`widgets/settings/pages/prompts_page.dart`, `widgets/mode_selection_popup.dart`. Consolidates
`docs/transcription-pipeline-audit.md` (C/F series) and `docs/cloud-switch-dialog-audit.md` (GA/CC series).*
