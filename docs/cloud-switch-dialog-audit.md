# Cloud-Switch Confirmation Dialogs & Prompt-Effect Detection Audit

**Scope:**
- `frontend/lib/widgets/mode_cloud_confirm_popup.dart` (211 lines) — Ctrl+M inline confirm
- `frontend/lib/widgets/prompt_cloud_switch_dialog.dart` (637 lines) — settings modal
- `frontend/lib/widgets/settings/settings_shared.dart` — shared copy / `PromptCloudModeTile`
- `frontend/lib/services/settings_service.dart` — detection predicates + switch actions
- Callers in `frontend/lib/main.dart`, `prompts_page.dart`, `tray_service.dart`,
  `mode_selection_popup.dart`, `ai_models_page.dart`

**Method:** static trace of the four detection predicates, every call site that triggers the
dialog/popup, and the resulting persisted state vs. the four pipeline paths (A–D) from
`docs/transcription-pipeline-audit.md`.

---

## 0. Detection predicates — full truth table

### `hasCloudCredentials` — `settings_service.dart:918–925`
```dart
bool get hasCloudCredentials {
  switch (cloudProvider) {
    case CloudProvider.geminiApiKey: return hasGeminiApiKey;     // env key OR secure store
    case CloudProvider.vertexAi:     return vertexProjectId != null; // project id only
  }
}
```
Returns **true/false** based on the **currently-selected** provider. Note the Vertex branch
only tests for a project id — **not** that Application Default Credentials are actually
present (see §4 GA6).

### `isCloudRefinementInPipeline` — `settings_service.dart:808–810`
```dart
bool get isCloudRefinementInPipeline =>
    transcriptionBackend == TranscriptionBackend.cloud ||
    twoPassTranscriptionEnabled;
```
**GLOBAL only.** Never consults per-prompt overrides. (`transcriptionBackend` getter 785–791,
`twoPassTranscriptionEnabled` 534.)

### `isPromptInactiveOnLocalBackend(promptId)` — `settings_service.dart:818–828`
```dart
bool isPromptInactiveOnLocalBackend(String promptId) {
  if (promptId == 'standard') return false;                 // (819) Default always active
  final overrides = getPromptOverrides(promptId);           // (820)
  if (overrides != null) {
    if (overrides.transcriptionBackend == TranscriptionBackend.cloud.value) return false; // (822) per-prompt cloud ⇒ active
    if (overrides.twoPassTranscriptionEnabled == true) return false;                       // (825) per-prompt two-pass ⇒ active
  }
  return !isCloudRefinementInPipeline;                      // (827) else use global pipeline
}
```
Returns **true** (inert) ⟺ non-`standard` prompt ∧ no cloud-bringing per-prompt override ∧
global pipeline has **no** cloud.

### `isPromptInertForCurrentPipeline` — **does not exist.**
Search (`Inert`, project-wide) returns no matches. The task brief lists four predicates but
only **three** are implemented (`isPromptInertForCurrentPipeline` was never written; its role
is filled by `isPromptInactiveOnLocalBackend`). **No dead reference** to the missing name
exists, so this is a doc/naming discrepancy only — not a code defect.

### Handling of the four task cases
| Case | Expected | Actual | OK? |
|---|---|---|---|
| Global = cloud | pipeline has refinement → no dialog | `isCloudRefinementInPipeline=true` → `isPromptInactive…=false` | ✅ |
| Glob = offline, 2-pass OFF | prompt inert → dialog fires | global pipeline empty + (no per-prompt override) → `true` | ✅ |
| Glob = offline, 2-pass ON | prompt works → no dialog | `isCloudRefinementInPipeline=true` (2-pass) → `false` | ✅ |
| Per-prompt override → cloud | prompt works → no dialog | `822` short-circuits → `false` | ✅ |
| Per-prompt override → 2-pass ON | prompt works → no dialog | `825` short-circuits → `false` | ✅ |
| Per-prompt override → **whisper + 2-pass OFF** (global has cloud) | prompt dropped (Path A) → dialog | global `cloud` ⇒ predicate `false` → **no dialog** | ⚠ **GA5** |

---

## 1. Call-site map

Three distinct UI shells offer the switch; a fourth (tray) offers switch *actions* without the
modal.

| # | Entry point | File:line | Gate (when does it fire?) | Result consumption |
|---|---|---|---|---|
| G1 | Ctrl+M mode popup, prompt tile selected | `main.dart:1008` → `_enterModeCloudConfirm` (1032) | `isPromptInactiveOnLocalBackend(prompt.id)` is **true** | `_confirmModeCloudConfirm(idx)` applies switch (1097), then records with `_temporaryPromptId` (1118) |
| G2 | Settings → Prompts, prompt **row** tap | `prompts_page.dart:590` | `_promptBlockedFor` = `isPromptInactiveOnLocalBackend` (101→102) | resolves `PromptCloudResult`; on localTwoPass/cloud → `setSelectedPromptId` (611) **persisted** |
| G3 | Settings → Prompts, **rephraser** seg pick | `prompts_page.dart:239` | `_rephraserBlockedFor` = `!isCloudRefinementInPipeline` (87–88) ∧ level≠off (230) | resolves result; casts to AI-Models page only on `openSettings` |
| G4 | Tray context menu, blocked prompt switch actions | `tray_service.dart:100` (`prompt_switch_cloud` / `prompt_switch_twopass` / `prompt_setup_cloud`) | offered when `promptsNeedCloud` (94) — direct actions, **no dialog shell** | calls `switchToCloudTranscription` (199) / `enableLocalTwoPassRefinement` (206) / open settings (212) |
| G5 | Tray: blocked **prompt** items | `tray_service.dart:124–135` | `isPromptInactiveOnLocalBackend` true → item `disabled:true`, label "(needs cloud)" | cannot be selected |
| G6 | Tray: **rephraser** items | `tray_service.dart:148–156`, handler `219–227` | **NEVER gated** — always enabled, just `setRephraseLevel` | silent set → **GA2** |
| G7 | `_PromptTile` badge (Ctrl+M list) | `mode_selection_popup.dart:204` | `isPromptInactiveOnLocalBackend` → dim (opacity 0.5, 224) + tappable to drill-in (G1) | visual only |

**Self-heal (adjacent):** `_onBackendSelected` in `ai_models_page.dart:189–192` resets
`rephraseLevel` to Off when the backend drops *back* to Whisper. Partial — it only fires on a
backend dropdown change, **not** when two-pass is toggled off, nor on the dialog/tray paths.

---

## 2. Decision matrix — non-default prompt selection

Axes: **GB** global backend (Cloud/Whisper) · **TP** global two-pass (On/Off) · **CC**
`hasCloudCredentials` (✓/✗) · **OV** per-prompt override (`none` / `cloud` /
`tp-on` (=2-pass true) / **`force-local`** (=whisper + 2-pass false)).

Pipeline legend: A=Whisper·off (prompt dropped) · B=Whisper·on · C=Cloud·on · D=Cloud·off.
`inert?` = what `isPromptInactiveOnLocalBackend` returns. `Runtime` = the path the recording
actually takes for that prompt (override-aware). ✓ = dialog gate correct; ⚠ = mismatch.

**GB=Cloud** (`isCloudRefinementInPipeline` always true → predicate never inert):
| OV | TP | inert? | Dialog? | Runtime path | Note |
|---|---|---|---|---|---|
| none | Off | false | no | **D** | ✓ |
| none | On  | false | no | C | ✓ |
| cloud | * | false | no | **D** | ✓ |
| tp-on | * | false | no | C (if GB Cloud) | ✓ |
| **force-local** | * | **false** | **no** | **A** (drop) | ⚠ **GA5** — predicate says active, runtime inert |

**GB=Whisper, TP=Off** (global pipeline empty):
| OV | inert? | CC | Dialog? | Result→Runtime | Note |
|---|---|---|---|---|---|
| none | **true** | ✓ | **yes** | localTwoPass→**B** · cloud→**D** · cancel→**A** | ✓ correct |
| none | true | ✗ | yes | **openSettings** (no options) | ✓ correct (both options need creds) |
| force-local | **true** | ✓ | yes | localTwoPass→B · cloud→D · cancel→A | ✓ (override already forces A; switching global→cloud makes OV-resolve to cloud = D; switching global→whisper+tp-on but OV still says whisper+off ⇒ still A! see ⚠) |
| cloud | false | * | no | D (OV overrides backend→cloud) | ✓ |
| tp-on | false | * | no | B (eff two-pass=true) | ✓ |

**GB=Whisper, TP=On** (global pipeline has cloud via 2-pass):
| OV | inert? | Dialog? | Runtime | Note |
|---|---|---|---|---|
| none | false | no | **B** | ✓ |
| cloud | false | no | D | ✓ |
| tp-on | false | no | B | ✓ |
| **force-local** | **false** | **no** | **A** (drop) | ⚠ **GA5**; OV forces whisper+off even w/ global tp-on |

> ⚠ **localTwoPass + force-local subtlety:** after picking localTwoPass, global becomes
> Whisper+On, but the prompt's **per-prompt `twoPassTranscriptionEnabled=false` override still
> wins** (`effectiveTwoPassEnabled = overrides.twoPass… ?? global`), so the prompt **stays on
> Path A** and the switch did not help that prompt. The user got no warning. (Only reachable
> when a force-local override already pins 2-pass off; edge.)

`standard` prompt: **never** blocked (`819`) regardless of any axis — correct (Whisper's own
pass is the implicit baseline).

---

## 3. Decision matrix — rephraser Medium/High pick

Blocked = `!isCloudRefinementInPipeline` = **(GB=Whisper ∧ TP=Off)**, independent of prompt
overrides (global feature) and of CC for the *gate*.

| GB | TP | Blocked? | CC | Behavior |
|---|---|---|---|---|
| Cloud | * | no | * | set directly; works at runtime (C/D) ✓ |
| Whisper | On | no | * | set directly; works at runtime (B) ✓ |
| Whisper | **Off** | **yes** | ✓ | **dialog** (`feature=rephraser`) → localTwoPass→**B** · cloud→**D** · openSettings/cancel→(stays inert, level set on confirm only) ✓ |
| Whisper | **Off** | yes | ✗ | dialog → **openSettings** (no options) ✓ |
| Whisper·Off via **tray menu** (G6) | — | **no gate** | — | level set silently → **Path A drop** ⚠ **GA2** |
| Cloud-GB but prompt pinned **force-local** | — | no (global check) | — | set directly; for *that* prompt the refine pass is skipped ⇒ rephraser dropped (A) ⚠ GA5 |

> On cancel of the rephraser dialog the level is **not** changed
> (`prompts_page.dart:252–253` `return`), which is correct — no silent stale setting.

---

## 4. Findings

### Confirmed correct

- **CC1 — `localTwoPass` ⇒ Path B.** `_confirm()` (dialog `435–436'; popup `main.dart:1106`)
  calls `enableLocalTwoPassRefinement()` (`settings_service.dart:834–837`):
  `setTranscriptionBackend(whisper)` + `setTwoPassTranscriptionEnabled(true)` ⇒
  Offline·2-pass-ON = **Path B**. The refine pass applies `effectiveInstruction`
  (prompt mission + rephraser fragment). ✓
- **CC2 — `cloud` ⇒ Path D.** calls `switchToCloudTranscription()` (`841–844`):
  `setTranscriptionBackend(cloud)` + `setTwoPassTranscriptionEnabled(false)` ⇒
  Cloud·2-pass-OFF single-pass = **Path D**. ✓
- **CC3 — credential gating is consistent across all three shells.** Both options need cloud
  creds (localTwoPass's refine pass + cloud's single pass both hit a cloud API). Gated at:
  dialog `prompt_cloud_switch_dialog.dart:287` (returns openSettings/cancelled, no options);
  popup `mode_cloud_confirm_popup.dart:53` (`needsSetup` swap to `_buildNeedsSetup`, footer
  hints flip at `179–188`); main `_enterModeCloudConfirm:1037` (registers only Esc + Enter→
  `_openSettingsFromCloudConfirm`, **no** arrow/confirm hotkeys). The tray likewise swaps the
  two switch actions for a single "Set up cloud for prompts…" (`tray_service.dart:113–120`).
- **CC4 — popup ↔ modal persist identical state.** Both call the same `SettingsService`
  methods (`enableLocalTwoPassRefinement`/`switchToCloudTranscription`); option-index mapping
  is identical (`kPromptCloudModeOptions[0]`=Local, `[1]`=Cloud; modal `_order=[localTwoPass,
  cloud]` `385`; popup clamp `0..1` `1075`). They share `kPromptCloudModeOptions`,
  `PromptCloudModeTile`, and `promptCloudSwitchCopy`, so choices and wording cannot diverge.
  No out-of-sync risk on the backend/2-pass choice.

### Gating bugs / silent failures / UX inconsistencies

- **GA1 (doc/naming, benign) — `isPromptInertForCurrentPipeline` does not exist.** Brief lists
  it; the real predicate is `isPromptInactiveOnLocalBackend` (`settings_service.dart:818`).
  No code references the missing name. → update brief/docs only.

- **GA2 (silent failure, REAL) — rephraser is un-gated in the tray menu.**
  `tray_service.dart:148–156` builds the Rephraser submenu with every level always enabled;
  handler `219–227` calls `setRephraseLevel(level)` with no blocked-check, no badge, no
  dialog. On GB=Whisper·TP=Off this selects Medium/High silently; at record time it lands on
  **Path A** and the rephraser fragment is dropped (Task-1 audit `C1`). Contrast: the Prompts
  page gates the rephraser with the LOCAL-ONLY badge + `showPromptCloudSwitchDialog`
  (`prompts_page.dart:209, 239–260`), and the tray **does** gate *prompts*
  (`tray_service.dart:124–135` disabled + "(needs cloud)"). The tray is the only inert-rephraser
  entry point with zero feedback. **Fix:** mirror the prompt handling — disable Medium/High
  when `!isCloudRefinementInPipeline` and route through the same switch actions / setup item.

- **GA3 (UX inconsistency, copy) — `_LocalOnlyBadge` keys off `hasGeminiApiKey`, not
  `hasCloudCredentials`.** Constructed at `prompts_page.dart:209` and `552` and the popover
  branches on it at `1221–1225` ("Add a Gemini API key in Settings → AI Models"). When the
  active provider is **Vertex AI**, a configured project (`hasCloudCredentials==true`) still
  renders `hasGeminiKey=false`, so the badge/popover tells the user to add a Gemini key even
  though cloud is ready. The dialog/popup/tray all use the correct `hasCloudCredentials`.
  **Fix:** pass `hasCloudCredentials` (and adjust popover copy to mention Vertex).

- **GA4 (copy bug) — `_LocalOnlyBadge` tooltip/popover always say "Rephraser…", even on prompt
  rows.** The widget (`prompts_page.dart:970–1072`) hardcodes the tooltip 1027–1028 and the
  body 1210–1218 to the rephraser, but it is reused verbatim for blocked **prompt** rows at
  `551–553`. Hovering the badge on a prompt row therefore reads *"Rephraser has no effect on
  offline-only Whisper."* — wrong feature. **Fix:** parameterise the badge with a feature label.

- **GA5 (predicate blind spot, edge) — force-local per-prompt override is invisible to both
  predicates.** `isCloudRefinementInPipeline` (808–810) is global-only; `isPromptInactiveOnLocalBackend`
  (818–828) only short-circuits overrides that **bring cloud in** (`822`, `825`). A per-prompt
  override pinning `transcriptionBackend='whisper'` + `twoPassTranscriptionEnabled=false` is
  ignored when the **global** pipeline has cloud, so the predicate returns `false` (active) but
  `resolveSessionBackend` honors the whisper override at record time → **Path A** (prompt +
  rephraser dropped) with **no dialog**. Same blind spot affects the rephraser table row above.
  *Severity: low/edge* (requires a deliberate "pin this prompt to offline" override) and is
  arguably defensible (nagging a user who explicitly pinned offline would be annoying — the
  asymmetry is the lesser evil), but it is a genuine logic gap: the predicate's own contract
  ("prompt would have NO effect with the current pipeline") is violated. Recommend documenting
  the asymmetry, or computing inert-ness against the *resolved* per-prompt backend + effective
  2-pass.

- **GA6 (readiness false-positive, pre-existing, Vertex) — `hasCloudCredentials` trusts a V\
  project id alone** (`settings_service.dart:918–925`). On the `vertexAi` provider it returns
  `vertexProjectId != null`; it does **not** verify Application Default Credentials exist.
  Consequently the dialog/tray offer and apply the switch to cloud, and transcription then
  fails at first request (no ADC). Mirrors the onboarding/troubleshooting readiness checks per
  the doc comment (915–917), so it is a known simplification — but it makes "openSettings" a
  *false-negative* gating case for Vertex-without-ADC, and lets the user choose cloud when it
  will not actually run.

### Design notes (not bugs)

- **DN1 — switch actions are global, not per-prompt.** `enableLocalTwoPassRefinement` /
  `switchToCloudTranscription` persist the **global** backend + 2-pass (`834–844`), so they
  move *every* prompt — e.g. `standard` also shifts A→B or A→D (an extra cloud call it didn't
  make before). This matches the "Transcription Mode" framing of the dialog (a
  whole-pipeline choice), and the shared tiles are labeled as modes, so it is intentional —
  noted for awareness.
- **DN2 — pulse prompt-id persistence differs by entry point (by design).** The Ctrl+M mode
  popup stores a **one-shot** `_temporaryPromptId` (`main.dart:1118`) and does **not** persist
  `selectedPromptId`; the settings modal *does* persist (`prompts_page.dart:611`). Only the
  **backend/two-pass** choice is shared, and that is identical across both (CC4). So the two
  flows cannot desync on the thing this audit tracks; the prompt-id divergence is the intended
  overlay-vs-settings UX.
- **DN3 — `setModelById(overrides.modelId)` is effectively dead for two-pass**
  (Task-1 `C2`). Unrelated to gating; flagged for completeness.

---

## 5. Verdict against the assignment

| Question | Answer |
|---|---|
| Do `localTwoPass`/`cloud` produce the intended pipeline? | **Yes** — localTwoPass→**Path B**, cloud→**Path D** (CC1/CC2). |
| Are both options correctly cred-gated when `hasCloudCredentials==false`? | **Yes** — all three shells gate identically (CC3). |
| Can popup & modal get out of sync? | **No** — identical `SettingsService` methods + shared tiles/copy (CC4). |
| Any prompt-inert state with **no** dialog (silent failure)? | **Yes — two:** tray rephraser (GA2, common), force-local override on a cloud pipeline (GA5, edge). The task-1-design Path A silent-drop (offline·2-pass-off) is correctly surfaced everywhere the predicates are consulted. |
| Any dialog firing **unnecessarily** (annoying)? | No false positives found; every fire corresponds to an actually-inert prompt/rephraser. |
| `isPromptInertForCurrentPipeline`? | **Does not exist** (GA1); the real predicate is `isPromptInactiveOnLocalBackend`. |

**Recommended fixes (priority order):**
1. **GA2** — gate the tray Rephraser items like prompts (disable + switch/setup actions).
2. **GA3** — `_LocalOnlyBadge`/popover: use `hasCloudCredentials` / mention Vertex.
3. **GA4** — parameterise `_LocalOnlyBadge` feature label so prompt-row badges don't say "Rephraser".
4. **GA5** — (optional) make `isPromptInactiveOnLocalBackend` resolve the per-prompt backend + effective 2-pass for an exact inert verdict, or document the asymmetry.
5. **GA6** — (pre-existing) refine `hasCloudCredentials`/Vertex to also verify ADC.
