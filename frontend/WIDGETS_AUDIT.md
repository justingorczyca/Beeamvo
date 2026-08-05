# Onboarding & Top-Level Widgets — Deep-Dive Audit

**Scope audited:**
- `frontend/lib/widgets/onboarding/onboarding_wizard.dart`
- `frontend/lib/widgets/onboarding/onboarding_steps.dart`
- `frontend/lib/widgets/onboarding/onboarding_shared.dart`
- `frontend/lib/widgets/onboarding/permission_onboarding_dialog.dart`
- `frontend/lib/widgets/frosted_orb.dart`
- `frontend/lib/widgets/mode_selection_popup.dart`
- `frontend/lib/widgets/mode_cloud_confirm_popup.dart`
- `frontend/lib/widgets/prompt_cloud_switch_dialog.dart`
- `frontend/lib/widgets/hotkey_recorder_widget.dart`

**Context files read for integration understanding (not audited):**
`models/hotkey_config.dart`, `models/enums.dart`, `models/clipboard_history_entry.dart`,
`theme/app_theme.dart`.

**Every file listed above was read and analyzed in full.**

---

## Executive Summary

22 findings total. Severity distribution: **2 High · 9 Medium · 7 Low · 4 Info**.

The codebase is in solid shape overall — **all `AnimationController`s and `FocusNode`s are disposed correctly, and most async paths honour `mounted`**. The issues are concentrated in three areas: (1) the **onboarding `HotkeyStep`** has drifted from the standalone `HotkeyRecorderWidget` and regressed the Escape-to-cancel control; (2) **navigation state loss** because step widgets are not kept alive across the `PageView`; and (3) **keyboard accessibility** — the onboarding CTA buttons are gesture-only and the mode-switch popups have zero internal keyboard handling.

| #  | Sev | File | Lines | Summary |
|----|-----|------|-------|---------|
| 1  | High | onboarding_steps.dart | 1791‑1802 | Esc-to-cancel broken in `HotkeyStep`: Escape check sits *after* the `modifiers.isEmpty` guard, so bare Esc shows the "include a modifier" error instead of canceling (contradicts the "Press Esc to cancel" hint). The standalone recorder gets this right. |
| 2  | High | onboarding_steps.dart | 461‑483 | `_verifyConnection()` calls `setState()` after `await` with **no `mounted`** guard in both try/catch branches → assertion / crash if the step is disposed mid-verify. |
| 3  | Med | onboarding_steps.dart | 389‑650 | Step widgets are not kept alive; navigating away disposes & recreates their State, **clearing `TextEditingController`s**. `ApiKeyStep` never reloads a saved Gemini key — going back shows an empty field. |
| 4  | Med | onboarding_steps.dart | 137 | "Skip Setup" button on Welcome calls `widget.onNext` (advances one step) instead of skipping — misleading label. |
| 5  | Med | onboarding_shared.dart | 151‑256 | All onboarding CTA buttons are `GestureDetector`-only → **not keyboard focusable/activatable**, no semantic actions for screen readers (desktop a11y gap). |
| 6  | Med | onboarding_wizard.dart | 62‑74 | `_goToStep` has no in-flight guard; each call stacks a new `.then()` on the fade future. Rapid nav can flicker/fade-flash and double-`setState`. |
| 7  | Med | onboarding_wizard.dart | 241‑250 | Step-2 (offline) auto-advance fires `_nextStep()` while the page/fade animation to page 2 is still running → overlapping transitions & brief empty/flash. |
| 8  | Med | frosted_orb.dart | 132‑133, 246, 298‑309 | Frosted-glass effect only special-cases `Platform.isMacOS`. **Linux inherits the Windows `BackdropFilter` branch** — untested transparent-window rendering on Linux. |
| 9  | Med | hotkey_recorder_widget.dart / onboarding_steps.dart | 114‑118 / 1804‑1811 | Divergent persistence contracts: standalone recorder fires only `onHotkeyChanged`; `HotkeyStep` fires **both** `setHotkey` + `onHotkeyChanged` → risk of double persist/register; also explains the Esc drift. |
| 10 | Med | permission_onboarding_dialog.dart | 80‑114 | `_onAutoRepair` starts the periodic poll *and* runs an inline `isGranted()` check — both can independently call `_onGranted()`, restarting the success animation. |
| 11 | Med | prompt_cloud_switch_dialog.dart | 298‑307, 431‑451 | `showPromptCloudSwitchDialog` is `barrierDismissible` while an awaited settings mutation is in flight; dismissing mid-switch leaves the operation running with no UI feedback. |
| 12 | Med | mode_selection_popup.dart / mode_cloud_confirm_popup.dart | whole files | **No internal keyboard handling at all** — highlight/options move only if an external caller feeds `selectedIndex` and wires arrow/Enter/Esc via global hotkeys. Footer keycaps can silently lie. |
| 13 | Low | onboarding_shared.dart | 151‑256 | `OnboardingPrimaryButton`/`OnboardingSecondaryButton` are `StatefulWidget` with empty `State` — should be `StatelessWidget`. |
| 14 | Low | onboarding_shared.dart | 378‑413 | `OnboardingTextField` wraps the field in a no-op `Focus` with no `onFocusChange`; the container border never reflects focus (no focus ring). |
| 15 | Low | onboarding_wizard.dart | 37‑53 | `_OnboardingWizardState` uses `TickerProviderStateMixin` but owns a single ticker → `SingleTickerProviderStateMixin` suffices. |
| 16 | Low | frosted_orb.dart | 52‑61 | Success "pop"/shockwave only triggers on a *transition* into success; an orb created already in the success state shows no animation. |
| 17 | Low | mode_selection_popup.dart | 193‑201 | `_PromptTile` uses `AutomaticKeepAliveClientMixin` with `wantKeepAlive=true` but holds no mutable state — pointless over-retention. |
| 18 | Low | hotkey_recorder_widget.dart / onboarding_steps.dart | 60‑73 / 1755‑1768 | No escape hatch if focus is stolen mid-recording; the recorder keeps pulsing "Listening" but captures nothing. `HotkeyStep` also never unfocuses its node after capture. |
| 19 | Low | permission_onboarding_dialog.dart | 29‑34, 120‑145 | No explicit `FocusScope`/autofocus on the primary action — keyboard users must Tab to reach buttons. |
| 20 | Info | frosted_orb.dart | 246 | "Frosted" name only true on non-macOS; macOS skips blur (alpha 0.92) vs Windows blur (0.82). Document/align branding. |
| 21 | Info | onboarding_steps.dart | 2241‑2243 | `_kRadiusMd`/`_kRadiusLg` re-declared because shared tokens are file-private; consider a shared tokens file. |
| 22 | Info | onboarding_wizard.dart | 90‑97, 220‑221 | `_finish` always marks onboarding complete regardless of readiness; there is no OS-permission step in the wizard. By design, but worth documenting. |

---

## Detailed Findings

### 1 — [High] Escape-to-cancel is broken in the onboarding `HotkeyStep`

**File:** `frontend/lib/widgets/onboarding/onboarding_steps.dart`**Lines:** 1770‑1802 (`_handleKeyEvent`)

**What's wrong.** The hint text says "Press Esc to cancel", but the Escape branch (line 1799) is placed **after** the `modifiers.isEmpty` guard (line 1791). When the user presses Escape alone, `modifiers` is empty, so the guard fires first, sets the message *"Include at least one modifier…"*, and `return`s — the Escape branch is never reached. Cancel is therefore impossible without a modifier, directly contradicting the UI.

The standalone `HotkeyRecorderWidget` (lines 82‑85) handles this **correctly** by checking Escape first. The onboarding copy drifted during copy/paste.

```dart
// BUGGY ORDER (onboarding_steps.dart)
if (_isModifierKey(key)) return;
final modifiers = <HotKeyModifier>{ ... }
if (modifiers.isEmpty) {            // ← bare Esc dies here
  setState(() => _errorMessage = 'Include at least one modifier …');
  return;
}
if (key == LogicalKeyboardKey.escape) { _stopRecording(); return; } // never reached
```

**Recommended fix.** Move the Escape check to the top (mirror the standalone widget). Better still, extract one shared recorder so the two copies cannot diverge again.

```dart
void _handleKeyEvent(KeyEvent event) {
  if (!_isRecording) return;
  if (event is! KeyDownEvent) return;

  final key = event.logicalKey;

  // Escape is an explicit cancel and MUST work without a modifier.
  if (key == LogicalKeyboardKey.escape) {
    _stopRecording();
    return;
  }

  if (_isModifierKey(key)) return;

  final modifiers = <HotKeyModifier>{};
  if (HardwareKeyboard.instance.isControlPressed) modifiers.add(HotKeyModifier.control);
  if (HardwareKeyboard.instance.isAltPressed) modifiers.add(HotKeyModifier.alt);
  if (HardwareKeyboard.instance.isShiftPressed) modifiers.add(HotKeyModifier.shift);
  if (HardwareKeyboard.instance.isMetaPressed) modifiers.add(HotKeyModifier.meta);

  if (modifiers.isEmpty) {
    setState(() {
      _errorMessage = 'Include at least one modifier (Ctrl, Alt, Shift, or Win)';
    });
    return;
  }

  final newConfig = HotkeyConfig(key: key, modifiers: modifiers);
  _stopRecording();
  setState(() { _currentHotkey = newConfig; _errorMessage = null; });
  widget.settingsService.setHotkey(newConfig);
  widget.onHotkeyChanged?.call(newConfig);
}
```

---

### 2 — [High] `setState()` after `await` without a `mounted` check (verification crash risk)

**File:** `frontend/lib/widgets/onboarding/onboarding_steps.dart`**Lines:** 461‑483 (`ApiKeyStep._verifyConnection`)

**What's wrong.** After `await widget.onVerifyCloudProvider!(_provider)` the code calls `setState(...)` in **both** the `try` and `catch` branches with no `if (!mounted) return;` guard. If the user navigates away from the API-key step (forward to Model, or via "Skip All") while verification is in flight, the step's `State` is disposed and the `setState` throws the *"setState() called after dispose()"* assertion.

Every other async path in the audited set guards this correctly (e.g. `ModelStep._startDownload` line 669, `PermissionOnboardingDialog`, `_PromptCloudSwitchDialog._confirm`), so this is an oversight, not a pattern.

**Recommended fix.**

```dart
Future<void> _verifyConnection() async {
  if (widget.onVerifyCloudProvider == null) return;
  setState(() {
    _isVerifying = true;
    _statusMessage = null;
  });
  try {
    await widget.onVerifyCloudProvider!(_provider);
    if (!mounted) return;                 // ← guard
    setState(() {
      _isVerifying = false;
      _statusMessage = _provider == CloudProvider.geminiApiKey
          ? 'API key verified!'
          : 'Vertex AI configuration verified!';
      _statusIsError = false;
    });
  } catch (e) {
    if (!mounted) return;                 // ← guard
    setState(() {
      _isVerifying = false;
      _statusMessage = e.toString();
      _statusIsError = true;
    });
  }
}
```

---

### 3 — [Medium] Navigation state loss — step `State`/`TextEditingController`s are discarded

**File:** `frontend/lib/widgets/onboarding/onboarding_steps.dart`**Lines:** `ApiKeyStep` 389‑444 (esp. 432‑437), `ModelStep` 593‑650, `TranscriptionModeStep` 1080‑1101, `RecordingModeStep` 1523‑1544

**What's wrong.** None of the step widgets implement `AutomaticKeepAliveClientMixin`, so the surrounding `PageView` (`onboarding_wizard.dart` 136‑145) may dispose a step's `State` once it scrolls out of the cache window. Each step keeps its selection **and** its `TextEditingController`s as instance state. Two concrete symptoms:

1. **`ApiKeyStep`** — `initState` restores the **Vertex project id** from settings (434‑436) but never restores the **Gemini API key**:
   ```dart
   if (_provider == CloudProvider.vertexAi) {
     _projectIdController.text = widget.settingsService.vertexProjectId ?? '';
   }
   // no restore for the Gemini key
   ```
   So: user types a key → Continue (persisted) → Model step → Back → the key field is **empty**, even though it is stored. The user is led to re-enter/replace it, and if they press Verify/Continue again with the empty field the empty-input guard blocks them unexpectedly.
2. Any selection held **only** in local state and not yet persisted (e.g. chosen before pressing Continue) is lost when you navigate away and come back.

**Recommended fix.**

a) Keep the steps alive so their `State` survives the whole wizard:

```dart
class _ApiKeyStepState extends State<ApiKeyStep>
    with AutomaticKeepAliveClientMixin {        // ← add mixin
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);                          // ← required
    // …
  }
}
```
(Apply to every step — they all hold transient state.)

b) Rehydrate the Gemini key in `initState` so a return-to-step shows persisted data:

```dart
@override
void initState() {
  super.initState();
  if (_provider == CloudProvider.vertexAi) {
    _projectIdController.text = widget.settingsService.vertexProjectId ?? '';
  } else {
    final existing = widget.settingsService.geminiApiKey; // expose a getter
    if (existing != null && existing.isNotEmpty) {
      _apiKeyController.text = existing;
    }
  }
}
```

---

### 4 — [Medium] "Skip Setup" on Welcome only advances one step

**File:** `frontend/lib/widgets/onboarding/onboarding_steps.dart`**Line:** 137

**What's wrong.** The label promises to skip setup, but it is wired to `onNext` (→ Provider step):
```dart
OnboardingSecondaryButton(label: 'Skip Setup', onTap: widget.onNext),
```
The genuine "skip all" control (`_finish`) is the title-bar button. Users clicking "Skip Setup" expecting to exit onboarding are funnelled into the next step instead.

**Recommended fix.** Either rename the button to "Next" / "Get Started", or route it to the real skip callback. If the parent should own the skip action, add it to `WelcomeStep`:

```dart
class WelcomeStep extends StatefulWidget {
  final VoidCallback onNext;
  final VoidCallback? onSkip;          // ← new
  // …
}

// in build:
OnboardingSecondaryButton(
  label: 'Skip Setup',
  onTap: widget.onSkip ?? widget.onNext,
),
```
…and in the wizard pass `onSkip: _finish`.

---

### 5 — [Medium] Onboarding CTA buttons are not keyboard-accessible

**File:** `frontend/lib/widgets/onboarding/onboarding_shared.dart`**Lines:** 151‑219 (`OnboardingPrimaryButton`), 223‑256 (`OnboardingSecondaryButton`), 301‑354 (`OnboardingGlowCard`)

**What's wrong.** Primary/secondary CTAs and selection cards are `GestureDetector` + `Container`. `GestureDetector` produces no focusable node and no semantic action, so:
- **Tab/Enter/Space cannot activate any on-screen button** in the wizard (the keyboard is effectively unusable beyond the text field),
- Screen readers announce the buttons as plain text with no "button" role/tap action.

This is a notable gap for a desktop app, and it also reflects the only "keyboard navigation" that exists in the wizard — there is none beyond tabbing, and tabbing lands on nothing actionable.

**Recommended fix.** Use `InkWell`/`OutlinedButton`/`FilledButton` (which receive focus and expose semantics), or at minimum wrap with `Semantics(button: true, …)` + `Focus`. Example for the primary button:

```dart
OnboardingPrimaryButton →
Focus(
  canRequestFocus: true,
  descendantsAreFocusable: false,
  child: Semantics(
    button: true,
    enabled: widget.onTap != null && !widget.isLoading,
    child: Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: widget.isLoading ? null : widget.onTap,    // Enter/Space now work
        borderRadius: BorderRadius.circular(_kRadiusMd),
        child: /* existing container */,
      ),
    ),
  ),
)
```
(Using `FilledButton`/`ElevatedButton` from the theme would be the lowest-effort fix and would inherit focus styling.)

---

### 6 — [Medium] `_goToStep` stacks transition callbacks (no in-flight guard)

**File:** `frontend/lib/widgets/onboarding/onboarding_wizard.dart`**Lines:** 62‑74

**What's wrong.** Every navigation registers a **new** `.then((_) { setState(…); animateToPage(…); forward(); })` on the fade controller's `reverse()` future. There is no flag preventing a new transition from starting mid-transition. Tapping Next/Back/Skip quickly (or the auto-advance in finding 7) can register several callbacks; when the single reverse completes they all fire, each calling `setState(_currentStep = …)` with possibly different targets and re-animating the page — yielding flicker, fade-through-black flashes, or a final step that does not match what the user tapped.

**Recommended fix.** Track an in-flight flag (and optionally coalesce/cancel the pending forward).

```dart
bool _isTransitioning = false;

void _goToStep(int step) {
  if (step < 0 || step >= _kTotalSteps) return;
  if (_isTransitioning) return;                 // ← ignore while animating
  _isTransitioning = true;

  _fadeController.reverse().then((_) {
    if (!mounted) { _isTransitioning = false; return; }
    setState(() => _currentStep = step);
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeOutCubic,
    );
    _fadeController.forward().then((_) {
      if (mounted) _isTransitioning = false;
    });
  });
}
```

---

### 7 — [Medium] Offline step-2 auto-advance races the page/fade animation

**File:** `frontend/lib/widgets/onboarding/onboarding_wizard.dart`**Lines:** 241‑250 (plus 62‑74)

**What's wrong.** For offline users, step 2 renders an empty `SizedBox.shrink` and schedules `_nextStep()` in a post-frame callback:
```dart
case 2:
  if (!isCloud) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_currentStep == 2) _nextStep();
    });
    return const SizedBox.shrink();
  }
```
But `_goToStep(2)` (from step 1's Continue) animates **to** page 2 and runs the fade-forward. The post-frame callback that builds page 2 during that animation immediately calls `_nextStep()` → `_goToStep(3)`, which starts **another** fade-reverse while page 2 is still sliding in and fading forward. The user sees page 2 (empty) flash up and then a second fade-out/in. It also compounds finding 6 (extra `.then()` callbacks).

**Recommended fix.** Skip the dead step entirely instead of animating to it. Compute the *target* step from the backend and animate directly there:

```dart
case 2:
  if (!isCloud) {
    // Never land on an empty page — jump straight to the next real step.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _currentStep == 2) _goToStep(3);
    });
    return const SizedBox.shrink();
  }
  return Center(child: ApiKeyStep(…));
```
combined with finding 6's guard, and ideally **don't animate into an empty page at all** — make `_nextStep` aware that the step is a pass-through:

```dart
int _nextStepFrom(int current) {
  int next = current + 1;
  // Skip the API-key step for offline users no matter how we land here.
  if (next == 2 &&
      widget.settingsService.transcriptionBackend != TranscriptionBackend.cloud) {
    next = 3;
  }
  return next;
}
void _nextStep() => _goToStep(_nextStepFrom(_currentStep));
```

---

### 8 — [Medium] Frosted glass effect not special-cased for Linux

**File:** `frontend/lib/widgets/frosted_orb.dart`**Lines:** 132‑133, 246, 298‑309

**What's wrong.** The macOS branch explicitly disables `BackdropFilter` ("causes black background on transparent windows"), and the Windows branch applies a 16-px blur:
```dart
color: orbSurface.withValues(alpha: Platform.isMacOS ? 0.92 : 0.82),
…
if (Platform.isMacOS) {
  return ClipOval(child: orbContent);          // no blur
}
return ClipOval(child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16), child: orbContent));
```
The guard is `Platform.isMacOS` only, so **Linux** (there is a `frontend/linux/` target in the workspace) falls into the blur branch. The exact "black on transparent" defect the macOS branch was written to avoid is very likely reproducible on Linux compositors (Wayland/X11 transparent windows behave differently per compositor) and is entirely untested.

**Recommended fix.** Restrict blur to a known-good platform set, or invert the logic to skip blur anywhere it is not explicitly supported:

```dart
static bool get _supportsBackdropBlur =>
    Platform.isWindows; // add others only after verification

// …
color: orbSurface.withValues(alpha: _supportsBackdropBlur ? 0.82 : 0.92),

// …
return _supportsBackdropBlur
  ? ClipOval(child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
      child: orbContent,
    ))
  : ClipOval(child: orbContent);
```

---

### 9 — [Medium] Two hotkey recorders, two persistence contracts (double-write + drift)

**Files:**
- `frontend/lib/widgets/hotkey_recorder_widget.dart` lines 114‑118
- `frontend/lib/widgets/onboarding/onboarding_steps.dart` lines 1804‑1811

**What's wrong.** The settings-page recorder and the onboarding `HotkeyStep` are near-duplicates but diverge in two ways:

a) **Persistence contract.** `HotkeyRecorderWidget` calls only:
```dart
final newConfig = HotkeyConfig(key: key, modifiers: modifiers);
_stopRecording();
widget.onHotkeyChanged(newConfig);
```
whereas `HotkeyStep` calls **both** persistence and the parent callback:
```dart
widget.settingsService.setHotkey(newConfig);   // persist
widget.onHotkeyChanged?.call(newConfig);        // and parent
```
If `onHotkeyChanged` (wired from `main.dart`) also persists and re-registers the global `HotKey`, the hotkey is written twice and — worse — registered with `hotkey_manager` twice. That is the classic "duplicate registration" race the task asks about; the recorder cannot enforce idempotency because it doesn't know what the parent will do.

b) **Behavioural drift.** The two copies already diverged on Escape handling (finding 1) and on the "Keep Default" affordance. Keeping two copies guarantees future drift.

**Recommended fix.** Make the recorder the single source of truth for *capturing* a combo, and let the parent own persistence/registration (stop calling `setHotkey` from the step):

```dart
// OnboardingStep — remove the redundant persist:
final newConfig = HotkeyConfig(key: key, modifiers: modifiers);
_stopRecording();
setState(() { _currentHotkey = newConfig; _errorMessage = null; });
widget.onHotkeyChanged?.call(newConfig);   // parent persists + (re)registers
```
Then document `onHotkeyChanged` as the sole persist/register boundary. Ideally delete one of the two recorder implementations and reuse the other.

---

### 10 — [Medium] Permission dialog: two concurrent detection paths can double-fire `_onGranted`

**File:** `frontend/lib/widgets/onboarding/permission_onboarding_dialog.dart`**Lines:** 80‑94, 107‑114

**What's wrong.** `_onAutoRepair` does:
```dart
setState(() => _step = _Step.waiting);
_startPolling();                       // ← periodic Timer firing isGranted() every 1s
await MacOsPermissionService.autoRepair();
if (!mounted) return;
final granted = await MacOsPermissionService.isGranted();
if (mounted && granted) _onGranted();   // ← inline check
```
Both the periodic timer callback (line 82‑86) and the inline check (line 113) can independently observe `granted == true` and call `_onGranted()`. `_onGranted` cancels the timer and does `_checkController.forward(from: 0)`, so the second call restarts the success animation mid-play and re-`setState`s to an already-granted state. The same race exists for `_onEnablePressed` (it also calls `_startPolling`, but without the inline recheck, so that path is safer).

**Recommended fix.** Make `_onGranted` idempotent with a state guard:

```dart
void _onGranted() {
  if (_step == _Step.granted) return;        // already done — ignore re-fire
  _poll?.cancel();
  _poll = null;
  setState(() => _step = _Step.granted);
  _checkController.forward(from: 0);
}
```

---

### 11 — [Medium] Cloud-switch dialog is barrier-dismissible mid-mutation

**File:** `frontend/lib/widgets/prompt_cloud_switch_dialog.dart`**Lines:** 298‑307 (`showDialog`), 431‑451 (`_confirm`)

**What's wrong.** Both `showDialog` calls use `barrierDismissible: true`. While `_confirm()` awaits `enableLocalTwoPassRefinement()` / `switchToCloudTranscription()` (which flip the backend and may download/switch a model), the user can dismiss by clicking outside or pressing Esc. The awaited mutation keeps running headless; the user gets no success/failure feedback and may think nothing happened and try again. The code is *technically* safe (second `Navigator.pop` is skipped via the `if (mounted)` check), but the user experience is a silent loss of feedback.

**Recommended fix.** Disable barrier dismiss during the in-flight switch; keep Esc/Cancel only when idle:

```dart
@override
Widget build(BuildContext context) {
  return Focus(
    autofocus: true,
    onKeyEvent: _onKeyEvent,
    child: AbsorbPointer(                       // ← block taps while working
      absorbing: _isWorking,
      child: Dialog(
        // …
      ),
    ),
  );
}

// and in showDialog pass barrierDismissible: true, BUT re-open is fine since
// _confirm ignores re-entry via `if (_isWorking) return;` — the real fix is to
// also ignore Esc while working:
void _cancel() {
  if (_isWorking || !mounted) return;           // already present — good
  Navigator.pop(context, PromptCloudResult.cancelled);
}
```
The `_cancel` guard already blocks Esc mid-work; the gap is only the barrier tap, addressed by `AbsorbPointer`.

---

### 12 — [Medium] Mode-selection / cloud-confirm popups have **zero** internal keyboard handling

**Files:**
- `frontend/lib/widgets/mode_selection_popup.dart` (whole file — note footer keycaps lines 140‑170)
- `frontend/lib/widgets/mode_cloud_confirm_popup.dart` (whole file — footer lines 166‑191)

**What's wrong.** Both popups render footer hints ("Up/Down navigate · Enter select · Esc cancel") but contain **no `Focus`/`KeyboardListener`/`RawKeyboardListener` anywhere**. The DartDoc explains this is intentional — the popup window is shown without OS focus and is driven entirely by **external** global-hotkey wiring in `main.dart` that mutates `selectedIndex` and invokes `onSelect`/`onCancel`. The risk: this is an implicit, undocumented contract. If *any* entry point neglects to feed `selectedIndex` on Arrow, or to call `onSelect`/`onCancel` on Enter/Esc, the footer actively lies to users — the highlight never moves or Enter does nothing — with no in-widget fallback. There is also no focus trap, so mouse-only operation is the only guaranteed path.

**Recommended fix.** Make navigation self-contained where Flutter *can* receive keys (the settings modal already does this in `_PromptCloudSwitchDialog._onKeyEvent`). For the unfocused-overlay popups, either (a) request window focus and handle keys locally, or (b) at minimum document and **assert** the contract. A defensive, self-contained handler is best:

```dart
class _ModeSelectionPopupState extends State<ModeSelectionPopup> {
  late FocusNode _focusNode;
  int _highlight = 0;

  @override
  void initState() {
    super.initState();
    _highlight = widget.selectedIndex;
    _focusNode = FocusNode();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
  }

  @override
  void dispose() { _focusNode.dispose(); super.dispose(); }

  KeyEventResult _onKey(FocusNode n, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    final prompts = [...SystemPrompt.availablePrompts, ...widget.settingsService.customPrompts];
    final k = e.logicalKey;
    if (k == LogicalKeyboardKey.arrowUp && _highlight > 0) { setState(() => _highlight--); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.arrowDown && _highlight < prompts.length - 1) { setState(() => _highlight++); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.enter) { widget.onSelect(prompts[_highlight].id); return KeyEventResult.handled; }
    if (k == LogicalKeyboardKey.escape) { widget.onCancel(); return KeyEventResult.handled; }
    return KeyEventResult.ignored;
  }
  // wrap the popup body in Focus(focusNode: _focusNode, onKeyEvent: _onKey, …)
}
```

---

### 13 — [Low] `OnboardingPrimaryButton` / `OnboardingSecondaryButton` are needlessly `StatefulWidget`

**File:** `frontend/lib/widgets/onboarding/onboarding_shared.dart`**Lines:** 151‑219, 223‑256

**What's wrong.** Both are declared `StatefulWidget`, but their `State` classes contain **no mutable fields and no lifecycle logic** — the entire body is `build`. This adds a `State` allocation per instance for no benefit and obscures intent (reviewers assume mutable state exists).

**Recommended fix.** Convert to `StatelessWidget` (and, while here, address finding 5 for keyboard access).

---

### 14 — [Low] `OnboardingTextField` has a no-op `Focus` wrapper and no focus styling

**File:** `frontend/lib/widgets/onboarding/onboarding_shared.dart`**Lines:** 378‑413

**What's wrong.** The field is wrapped in `Focus(child: AnimatedContainer(…))` with **no `onFocusChange`**, so the decoration never reacts to focus — there is no focus ring, and the `Focus` widget does nothing useful. For a data-entry form with validation, the lack of a focus indicator is an a11y/UX gap (the underlying `TextField` draws `InputBorder.none`, so nothing signals focus).

**Recommended fix.** Drive the border from focus state (and optionally expose a `FocusNode`):

```dart
bool _focused = false;
// …
Focus(
  onFocusChange: (f) => setState(() => _focused = f),
  child: AnimatedContainer(
    duration: const Duration(milliseconds: 200),
    decoration: BoxDecoration(
      color: beeSurfaceHighest(context),
      borderRadius: BorderRadius.circular(_kRadiusMd),
      border: Border.all(
        color: _focused ? beeYellow(context) : beeBorder(context),  // ← focus ring
        width: _focused ? 1.5 : 1,
      ),
    ),
    child: TextField(…),
  ),
)
```

---

### 15 — [Low] `_OnboardingWizardState` uses `TickerProviderStateMixin` for a single ticker

**File:** `frontend/lib/widgets/onboarding/onboarding_wizard.dart`**Lines:** 37‑53

**What's wrong.** The state mixes in `TickerProviderStateMixin` but owns exactly one animation (`_fadeController`). `SingleTickerProviderStateMixin` is the correct, lighter choice and also gives you a (debug) assertion if a second ticker is ever introduced accidentally.

**Recommended fix.** Use `with SingleTickerProviderStateMixin`.

---

### 16 — [Low] Frosted orb success "pop"/shockwave doesn't play if created already in success

**File:** `frontend/lib/widgets/frosted_orb.dart`**Lines:** 52‑61

**What's wrong.** The success transition is wired through `didUpdateWidget` — it only plays on a *change* **into** `RecordingState.success`. If the orb is constructed while already in `success` (e.g. the overlay re-mounts), no shockwave/pop is shown; the user sees a static settled orb with no celebratory cue.

**Recommended fix.** Seed the transition in `initState` when the initial state is already success:

```dart
@override
void initState() {
  super.initState();
  _transitionController = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
  _entranceController = AnimationController(vsync: this, duration: const Duration(milliseconds: 250));
  _entranceController.forward();
  if (widget.state == RecordingState.success) {
    _transitionController.value = 1.0; // or forward() for the full pop
  }
}
```

---

### 17 — [Low] `_PromptTile` keeps itself alive for no reason

**File:** `frontend/lib/widgets/mode_selection_popup.dart`**Lines:** 193‑201

**What's wrong.** `_PromptTile` mixes in `AutomaticKeepAliveClientMixin` with `wantKeepAlive => true`, but its `State` has **no mutable fields** (it reads everything from `widget.settingsService`/props each build). The keep-alive therefore changes nothing functionally while forcing the `ListView` to retain every tile's subtree forever — wasteful if a user has many custom prompts.

**Recommended fix.** Remove the mixin and the `super.build(context)` call.

---

### 18 — [Low] Hotkey recording has no escape hatch on focus loss; `HotkeyStep` never unfocuses

**Files:**
- `frontend/lib/widgets/hotkey_recorder_widget.dart` lines 60‑73
- `frontend/lib/widgets/onboarding/onboarding_steps.dart` lines 1755‑1768

**What's wrong.** Recording relies on a `KeyboardListener`/`FocusNode` (lines 66, 1761). If focus is stolen mid-record (another window, an OS dialog, a programmatic focus change elsewhere), key events stop arriving but `_isRecording` stays `true` and the pulse animation keeps running — the UI says "Listening…" while silently capturing nothing. The only recovery is a manual tap. Separately, `_stopRecording()` in `HotkeyStep` (1764‑1768) never calls `_focusNode.unfocus()`, so focus lingers on the (now hidden) key listener after a successful capture until the step is disposed.

**Recommended fix.** Listen for focus loss during recording and auto-stop, and unfocus on stop:

```dart
@override
void initState() {
  super.initState();
  _focusNode.addListener(() {
    if (!_focusNode.hasFocus && _isRecording) _stopRecording();
  });
  // …
}

void _stopRecording() {
  _focusNode.unfocus();          // ← release on capture
  setState(() => _isRecording = false);
  _pulseController.stop();
  _pulseController.reset();
}
```

---

### 19 — [Low] Permission dialog: no autofocus/focus-scope on primary actions

**File:** `frontend/lib/widgets/onboarding/permission_onboarding_dialog.dart`**Lines:** 29‑34, 120‑145

**What's wrong.** The `AlertDialog` does not autofocus its primary button, and there is no explicit `FocusScope`. Keyboard users must Tab to reach "Enable Paste" / "Done" and there is no visible focus ring customization. With `barrierDismissible: true`, pressing Esc closes the dialog (acceptable), but the in-dialog button tab order is uncontrolled.

**Recommended fix.** Wrap the body in a `FocusScope(autofocus: true, …)` and/or set the `ElevatedButton`'s autofocus. Minor, but rounds out keyboard support.

---

### 20 — [Info] "Frosted" naming is platform-conditional

**File:** `frontend/lib/widgets/frosted_orb.dart`**Line:** 246 (and 298‑309)

The class/docstring calls this a frosted orb, but on macOS the `BackdropFilter` blur is intentionally disabled (`alpha: 0.92` flat disk) to avoid the transparent-window black bug; only non-macOS gets the actual 16-px frosted blur (`alpha: 0.82`). Behaviour is correct; consider renaming or documenting so "frosted" isn't read as a hard guarantee.

---

### 21 — [Info] Duplicated radius consts

**File:** `frontend/lib/widgets/onboarding/onboarding_steps.dart`**Lines:** 2241‑2243

`_kRadiusMd` / `_kRadiusLg` are re-declared at the bottom of this file because the matching tokens in `onboarding_shared.dart` (lines 13‑15) are **file-private** (underscore). Works, but is a maintenance hazard (two sources of truth). Consider promoting these to a small shared `tokens.dart` or a public part-of file.

---

### 22 — [Info] Onboarding never gates on OS permissions; completion ignores readiness

**File:** `frontend/lib/widgets/onboarding/onboarding_wizard.dart`**Lines:** 90‑97 (`_finish`), 220‑221 ("Skip All"), 302‑309 (Ready step)

`_finish` unconditionally calls `setOnboardingComplete()` + `onComplete()`; the `ReadyStep.isReady` flag only changes copy ("You're All Set" vs "Almost There"), it does **not** block finishing. There is also no macOS Accessibility / mic permission step *inside* the wizard — `PermissionOnboardingDialog` is a separate, separately-triggered surface. This is consistent with a deliberately-skippable setup, but worth documenting so it isn't mistaken for a hard gate: a user can "finish" onboarding with no backend configured and no permissions granted.

---

## Cross-cutting observations (non-blocking)

- **Positive:** Every `AnimationController` and `FocusNode` in the audited set is disposed in `dispose()` (wizard, background, welcome, ready, hotkey step/recorder, permission dialog, frosted orb's own controllers). No ticker/focus leaks were found.
- **Positive:** The frosted orb correctly receives its `glow`/`rotation` controllers from the parent and **only disposes the ones it owns**, avoiding a double-dispose.
- **Theme handling** (`beeYellow`, `beeSurfaceRaised`, … from `settings_shared.dart`) is applied consistently and the painters receive resolved colors via parameters — no `BuildContext` used inside `CustomPainter`. Good.
- The biggest single maintainability win would be **consolidating the two hotkey recorders** (findings 1 + 9) — that also removes the Escape regression automatically.
