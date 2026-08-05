# Settings UI & State-Management Audit

**Scope:** All settings UI pages, the settings infrastructure/components, and the
settings state-management layer (settings provider + service).
**Out of scope (already reviewed elsewhere):** services layer
(`SERVICES_LAYER_REVIEW.md`) and macOS/Windows native code
(`frontend/macos_native_review.md`).
**SDK:** Dart 3.12 · Flutter desktop (macOS/Windows/Linux).
**Persistence:** JSON file (atomic write + `.bak`/`.tmp` recovery) + secure
credential store (Keychain).

Files reviewed: 19 — see the appendix for the full list.

---

## Executive Summary

**Severity counts:** Critical 0 · High 1 · Medium 5 · Low 9 · Info 5

| ID  | Sev     | File:Line                                                                 | Category                | Summary |
|-----|---------|---------------------------------------------------------------------------|-------------------------|---------|
| F01 | High    | `troubleshooting_page.dart:67-86`                                         | Stuck UI state          | `_runDiagnostics()` has no try/catch; an exception leaves `_diagnosticsLoading = true` forever and removes the Refresh affordance. |
| F02 | Medium  | `clipboard_page.dart:85-88`                                               | Logic / data-sync       | Pinned entries are rendered in **both** the Pinned section and the History list (duplication / contradicting "stay above history" copy). |
| F03 | Medium  | `settings_window.dart:150-153`                                            | Performance / platform  | `windowManager.startDragging()` is invoked on **every** `onPanUpdate`; should fire once on `onPanStart`. |
| F04 | Medium  | `settings_provider.dart:76`, `settings_window.dart:150-152`               | Redundant rebuilds      | Provider relays *every* `SettingsService` notify and `setDragging` notifies the whole tree, rebuilding the sidebar/page on unrelated settings mutations. |
| F05 | Medium  | `settings_service.dart:952-981, 425-436`                                  | Listener contract       | `setDurationLimitEnabled`, `setDurationLimit`, `setLaunchAtStartup` mutate + persist but do **not** call `notifyListeners()` (inconsistent with every other setter). |
| F06 | Medium  | `home_activity_heatmap.dart:334-341`                                      | Performance             | `shouldRepaint` compares freshly-built `List`/month-label identities → always repaints on every ancestor rebuild. |
| F07 | Low     | `ai_models_page.dart:215`, `prompts_page.dart:747-750`, `general_settings_page.dart:951` | Resource lifecycle | `TextEditingController`s created inside modal dialogs are never `.dispose()`d. |
| F08 | Low     | `settings_shared.dart:403-404`                                            | Dead code / a11y        | `BeeSettingsRow` disabled-branch icon color is identical to enabled (`textMuted : textMuted`) — disabled rows never dim their icon. |
| F09 | Low     | `clipboard_page.dart:256-264`                                             | Input validation        | Pinned-prompt text has **no length cap** (arbitrarily large snippets persisted to JSON). |
| F10 | Low     | `clipboard_page.dart:159-172`                                             | Accessibility           | Max-items `Slider` has no semantic label; screen readers announce a generic "slider". |
| F11 | Low     | `general_settings_page.dart:1004`                                         | Async handling          | `settings.setDurationLimit(v)` is fire-and-forget inside a sync `onPressed` (unawaited Future). |
| F12 | Low     | `general_settings_page.dart:791, 833-840`                                 | Performance / typing    | "Reset General" performs ~8 sequential atomic disk writes (one per setter); could batch. `settings` param typed `dynamic`. |
| F13 | Low     | `settings_service.dart:291, 359-360`                                      | Unawaited futures       | Fire-and-forget `_save()`/`_saveCustomPrompts()` during initialisation/migration — no `unawaited()` annotation. |
| F14 | Low     | `prompts_page.dart:658, 895`                                              | ID generation           | Custom-prompt / duplicate IDs use `millisecondsSinceEpoch` — collision risk on rapid successive creation. |
| F15 | Low     | `prompts_page.dart:891, 903`                                              | Async gap               | `setState` after awaited persistence in dialog submit has no `mounted` check (low risk — dialog is modal). |
| F16 | Info    | `ai_models_page.dart:1141`                                                | Misleading callback     | `widget.onModelDownloaded` fires on plain *selection* of an installed model, not just on a completed download. |
| F17 | Info    | `ai_models_page.dart:591, 103-108`                                        | Dead code               | `_buildLoadingState()` is unreachable: `didChangeDependencies` sets `_settingsLoaded = true` before `build` runs. |
| F18 | Info    | `home_dashboard_page.dart` `_WeeklyBarPainter`, `home_activity_heatmap.dart` | Accessibility     | Charts render via `CustomPainter` with no `Semantics`; heatmap `Tooltip`s are mouse-only. |
| F19 | Info    | `settings_shared.dart:69-70`                                              | Fragile accessor        | `beeColors()` uses `extension<BeeColors>()!`; throws if used outside a themed `MaterialApp`. |
| F20 | Info    | `settings_provider.dart:113-116`                                          | Dead method             | `checkPermissions()` only calls `notifyListeners()` and is documented "populated by the UI". |

> **Overall:** The settings layer is well-structured — atomic/queued JSON
> persistence with crash recovery, consistent deferred-load pattern,
> `mounted` checks on most async paths, and good semantic-label coverage.
> The findings are predominantly Medium/Low robustness, performance, and
> accessibility polish; no data-corruption or crash-on-launch defects were
> found. The highest-impact item (F01) is a recoverable stuck-UI state.

---

## Detailed Findings

### F01 — Diagnostics loading spinner can get permanently stuck  [High]

**File:** `widgets/settings/pages/troubleshooting_page.dart:67-86`
(and the unguarded entry points at `:47` and `:685`).

**Problem.** `_runDiagnostics()` sets `_diagnosticsLoading = true` and only
clears it inside the final `setState`:

```dart
Future<void> _runDiagnostics() async {
  final settings = SettingsProviderScope.of(context).settingsService;
  setState(() => _diagnosticsLoading = true);

  final items = <_DiagnosticItem>[ /* ... */ ];

  await _appendMacOSPermissionDiagnostics(items); // ← can throw (PlatformException)
  await _appendMicrophoneDiagnostics(items);

  if (!mounted) return;
  setState(() {
    _diagnostics = items;
    _diagnosticsUpdatedAt = DateTime.now();
    _diagnosticsLoading = false;   // ← skipped if either await throws
  });
}
```

`_appendMacOSPermissionDiagnostics()` calls
`keyboardService.checkAccessibilityPermissions()` (a platform-channel call)
with no surrounding `try/catch`. If that throws, the exception propagates out
of `_runDiagnostics`, **`_diagnosticsLoading` stays `true` forever**, and
because the diagnostics panel renders a `CircularProgressIndicator` instead of
the Refresh `IconButton` while loading (`:667-693`), the user has **no way to
retry without leaving and re-entering the page**.

**Impact.** On macOS, a transient platform error during the initial
diagnostics run permanently disables the panel until the page is re-mounted.

**Fix.** Wrap the body in `try/catch/finally` so loading is always cleared
(and surface the failure as a diagnostic row):

```dart
Future<void> _runDiagnostics() async {
  final settings = SettingsProviderScope.of(context).settingsService;
  setState(() => _diagnosticsLoading = true);
  try {
    final items = <_DiagnosticItem>[
      _platformDiagnostic(),
      _backendDiagnostic(settings),
      _clipboardDiagnostic(settings),
    ];
    await _appendMacOSPermissionDiagnostics(items);
    await _appendMicrophoneDiagnostics(items);
    if (!mounted) return;
    setState(() {
      _diagnostics = items;
      _diagnosticsUpdatedAt = DateTime.now();
    });
  } catch (e) {
    if (!mounted) return;
    setState(() {
      _diagnostics = [
        _DiagnosticItem(
          label: 'Diagnostics',
          detail: 'Could not run diagnostics: $e',
          icon: Icons.error_outline_rounded,
          status: _DiagnosticStatus.error,
        ),
      ];
      _diagnosticsUpdatedAt = DateTime.now();
    });
  } finally {
    if (mounted) setState(() => _diagnosticsLoading = false);
  }
}
```

---

### F02 — Pinned clipboard entries duplicated across two sections  [Medium]

**File:** `widgets/settings/pages/clipboard_page.dart:85-88`

**Problem.** The History list is computed from the full `_history`, which
includes pinned entries, while a separate "Pinned Prompts" section renders
those same entries:

```dart
final items = q.isEmpty
    ? _history                                   // ← includes pinned
    : _history.where((e) => e.text.toLowerCase().contains(q)).toList();
final pinnedItems = _history.where((e) => e.isPinned).toList();
```

A pinned snippet is therefore visible in **both** the "Pinned Prompts" block
and the "History" block. This contradicts the inline guidance which states
pinned items "stay *above* history", and produces a confusing `n/n` count in
`_buildHistoryMeta` (total counts pinned entries the user expects to be
excluded).

**Impact.** Visual duplication and an unexpected item count; users may
believe they have duplicate entries.

**Fix.** Exclude pinned entries from the history list (the Clear action
already operates on non-pinned only, so this is consistent):

```dart
final items = (q.isEmpty ? _history : _history.where(
        (e) => e.text.toLowerCase().contains(q)))
    .where((e) => !e.isPinned)
    .toList();
final pinnedItems = _history.where((e) => e.isPinned).toList();
```
(If showing pinned in history is actually intentional, update the helper copy
and the count so the behaviour matches the documentation.)

---

### F03 — `windowManager.startDragging()` invoked on every pan-update  [Medium]

**File:** `widgets/settings/settings_window.dart:148-153`

**Problem.** The title-bar drag gesture calls the native drag entry point on
every `onPanUpdate` event, generating a burst of redundant platform-channel
invocations during a single drag:

```dart
onPanStart:  (_) => widget.provider.setDragging(true),
onPanEnd:    (_) => widget.provider.setDragging(false),
onPanCancel: ()  => widget.provider.setDragging(false),
onPanUpdate: (_) async => await windowManager.startDragging(), // ← every move
```

`windowManager.startDragging()` should be requested **once** when the drag
begins; the OS then owns the drag loop.

**Impact.** Many superfluous platform calls per drag (potential stutter /
extra jank on slower systems), contrary to the documented plugin usage.

**Fix.** Move the native call into `onPanStart`:

```dart
onPanStart: (_) {
  widget.provider.setDragging(true);
  windowManager.startDragging(); // fire-and-forget; called once
},
```

---

### F04 — `SettingsProvider` relays every service notify + dragging reflows the tree  [Medium]

**Files:** `providers/settings_provider.dart:76`, `widgets/settings/settings_window.dart:150-152`

**Problem.** Two compounding rebuild amplifiers:

1. The provider forwards **every** `SettingsService.notifyListeners()` to its
   own listeners. The sidebar (`AnimatedBuilder(animation: provider, …)`) only
   consumes `selectedCategory`, so it rebuilds on every unrelated change
   (slider drag, keystroke, etc.).
2. `setDragging(true/false)` calls `notifyListeners()` on every drag
   begin/end, even though nothing in the sidebar/page container reads
   `isDragging` — so a drag reflows the entire settings subtree for nothing.

**Impact.** Redundant rebuilds of the sidebar and page container on frequent
settings edits and on every window drag.

**Fix.** (a) Make `isDragging` non-notifying (e.g. a plain `ValueNotifier` the
title bar alone listens to), or stop notifying when only dragging changes:

```dart
bool _isDragging = false;
bool get isDragging => _isDragging;

void setDragging(bool value) {
  if (_isDragging == value) return;
  _isDragging = value;
  // Do NOT notify — no consumer outside the title bar depends on this.
}
```

(b) Consider having the sidebar depend on a narrower notifier (e.g. a
`ValueListenable<SettingsCategory>`) instead of the whole provider, so it no
longer rebuilds on every service mutation.

---

### F05 — Three setters persist but skip `notifyListeners()`  [Medium]

**File:** `services/settings_service.dart`

| Setter | Line | Notifies? |
|--------|------|-----------|
| `setDurationLimitEnabled` | 952-954 | ❌ |
| `setDurationLimit` | 979-981 | ❌ |
| `setLaunchAtStartup` | 425-436 | ❌ |

Every other mutating setter in the service follows `_set…()` with
`notifyListeners()`. These three break the convention. Today it is masked
because the editing page does a local `setState`, but any *other* listener
(a future recorder that subscribes to auto-stop changes, a tray/menu, an
observer) will silently miss the update.

**Impact.** Violates the reactive contract; latent missed-update bugs as new
listeners are added.

**Fix.** Add `notifyListeners()` after each persistence step (mirroring
`setClipboardWatcherEnabled`, `setTwoPassTranscriptionEnabled`, …):

```dart
Future<void> setDurationLimitEnabled(bool value) async {
  await _setBool(_kDurationLimitEnabled, value);
  notifyListeners();
}

Future<void> setDurationLimit(int seconds) async {
  await _setInt(_kDurationLimit, clampDurationLimit(seconds));
  notifyListeners();
}
```

---

### F06 — Heatmap repains on every ancestor rebuild  [Medium]

**File:** `widgets/settings/pages/home_activity_heatmap.dart:334-341`

**Problem.** `_HeatmapPainter.shouldRepaint` compares the `grid` and
`monthLabels` lists by identity. Both are rebuilt fresh on every
`HomeActivityHeatmap.build()`, so the comparison is virtually always `!=`,
forcing a full repaint on every unrelated ancestor rebuild (theme toggle,
hover state in a sibling, etc.):

```dart
@override
bool shouldRepaint(covariant _HeatmapPainter old) =>
    grid != old.grid ||
    maxVal != old.maxVal ||
    monthLabels != old.monthLabels || // new List every build → always !=
    ...
```

**Impact.** Unnecessary repaints of the largest `CustomPainter` on the
dashboard.

**Fix.** Compare by *value* (e.g. a computed signature/hash) or hoist the data
into a small cached model passed down so identity is stable when the data is
unchanged:

```dart
@override
bool shouldRepaint(covariant _HeatmapPainter old) {
  if (maxVal != old.maxVal ||
      inkColor != old.inkColor ||
      hoveredCol != old.hoveredCol ||
      hoveredRow != old.hoveredRow ||
      grid.length != old.grid.length ||
      monthLabels.length != old.monthLabels.length) {
    return true;
  }
  for (var c = 0; c < grid.length; c++) {
    for (var r = 0; r < 7; r++) {
      if (grid[c][r] != old.grid[c][r]) return true;
    }
  }
  return false;
}
```

---

### F07 — Modal-dialog `TextEditingController`s never disposed  [Low]

**Files:**
- `widgets/settings/pages/ai_models_page.dart:215` (`_showTextInputDialog`)
- `widgets/settings/pages/prompts_page.dart:747-750` (`_showPromptDialog`: `nameCtrl`, `instrCtrl`)
- `widgets/settings/pages/general_settings_page.dart:951` (`_showDurationDialog`: `ctrl`)

**Problem.** Each dialog allocates one or more controllers locally but never
calls `.dispose()`. They become eligible for GC once the dialog's
`StatefulBuilder` closure is released, but the standard, lint-clean pattern is
to dispose them deterministically so any attached listeners and the internal
clipboard buffer are released immediately.

**Fix.** Dispose in a `whenComplete`, or move the fields into a dedicated
`StatefulWidget` for the dialog body:

```dart
Future<void> _showTextInputDialog({...}) async {
  final controller = TextEditingController(text: initialValue);
  try {
    return await showDialog<String>(
      context: context,
      builder: (context) { /* uses controller */ },
    );
  } finally {
    controller.dispose();
  }
}
```

---

### F08 — Disabled `BeeSettingsRow` never dims its icon  [Low]

**File:** `widgets/settings/settings_shared.dart:403-404`

**Problem.** Both branches of the ternary resolve to the same colour, so
disabling a row only dims its label/description, not its leading icon (the
doc-comment at `:396-398` claims all three are dimmed):

```dart
final iconColor = widget.enabled ? textMuted : textMuted; // identical
```

**Fix.**

```dart
final iconColor = widget.enabled ? textMuted
    : textMuted.withValues(alpha: kBeeTintDisabled); // visibly dimmed
```

---

### F09 — No length cap on pinned-prompt text  [Low]

**File:** `widgets/settings/pages/clipboard_page.dart:256-264`

**Problem.** `_pinPrompt()` only checks `text.isEmpty`. The trimmed text is
passed straight into the persisted clipboard history JSON with no upper bound,
so a paste of a multi-megabyte blob is stored verbatim and serialised on every
write.

**Fix.** Enforce a sane ceiling consistent with the prompt instruction limit
(6000) and surface a message when it is exceeded:

```dart
Future<void> _pinPrompt(SettingsService settings) async {
  final text = _pinnedCtrl.text.trim();
  if (text.isEmpty) return;
  const maxLen = 2000;
  if (text.length > maxLen) {
    _showSnack('Snippets must be $maxLen characters or fewer');
    return;
  }
  await settings.addPinnedClipboardPrompt(text);
  ...
}
```
(Also add `maxLength` to the `TextField` for inline feedback.)

---

### F10 — Max-items slider has no semantic label  [Low]

**File:** `widgets/settings/pages/clipboard_page.dart:159-172`

**Problem.** The "Max History Items" `Slider` has no `Semantics` label; an
assistive-tech user hears only "slider, adjustable" with no context.

**Fix.**

```dart
Semantics(
  label: 'Maximum history items',
  value: '$_maxItems items',
  child: Slider(
    value: _maxItems.toDouble(),
    min: 10, max: 200, divisions: 190,
    onChanged: (v) => setState(() => _maxItems = v.round()),
    onChangeEnd: (v) async { /* ... */ },
  ),
)
```

---

### F11 — `setDurationLimit` is fire-and-forget  [Low]

**File:** `widgets/settings/pages/general_settings_page.dart:995-1007`

**Problem.** The Save button's `onPressed` is synchronous, so
`settings.setDurationLimit(v)` returns an unawaited `Future` (and the
`unawaited_futures` lint will flag it). Persistence still happens, but the
intent is unclear and the lint will fire.

**Fix.** Make the handler `async` and `await` (or explicitly `unawaited`):

```dart
onPressed: () async {
  final v = int.tryParse(ctrl.text);
  if (v == null) { ... }
  else if (v < 5) { ... }
  else if (v > 3600) { ... }
  else {
    await settings.setDurationLimit(v);   // no fire-and-forget
    if (!mounted) return;
    setState(() => _durationLimit = v);
    Navigator.of(context).pop();
  }
},
```

---

### F12 — "Reset General" performs ~8 sequential disk writes  [Low]

**File:** `widgets/settings/pages/general_settings_page.dart:791, 833-840`

**Problem.** Reset calls each setter individually; each `set*` enqueues a
separate atomic write through the `_saveQueue` (8 writes in sequence). The
`settings` argument is also typed `dynamic`, losing compile-time safety.

**Impact.** 8× the I/O latency of a single batched write; no functional error.

**Fix.** (a) Type the parameter as `SettingsService`. (b) Add a
batched/transactional reset in `SettingsService` that mutates `_data` once and
saves once:

```dart
Future<void> resetGeneralDefaults() async {
  _data.remove(_kHotkey);
  _data.remove(_kClipboardPopupHotkey);
  _data.remove(_kModeSelectionHotkey);
  _data[_kRecordingMode] = RecordingMode.toggle.name;
  _data.remove(_kSelectedAudioDeviceId);
  _data[_kLaunchAtStartup] = false;
  _data[_kDurationLimitEnabled] = false;
  _data[_kDurationLimit] = 300;
  await _save();
  notifyListeners();
}
```

---

### F13 — Initialisation fire-and-forget saves are not annotated  [Low]

**File:** `services/settings_service.dart:291` (`_migrateModels`) and
`:359-360` (`_migrateCustomPromptOverrides`).

**Problem.** `_save()` / `_saveCustomPrompts()` are called without `await` or
`unawaited()` during initialisation/migration. Functionally OK (the writes are
queued), but the dangling futures trip the `unawaited_futures` lint and cloud
the intent.

**Fix.** Annotate explicitly: `unawaited(_save());` (importing `dart:async`).

---

### F14 — Custom-prompt IDs use millisecond timestamps  [Low]

**File:** `widgets/settings/pages/prompts_page.dart:658, 895`

**Problem.** `id: 'custom_${DateTime.now().millisecondsSinceEpoch}'` is used on
both create and duplicate. Two rapid additions within the same millisecond
(e.g. double-click "New") would collide, and `addCustomPrompt` does not detect
duplicate IDs (`_customPrompts.add(prompt)` in `settings_service.dart:475`).

**Fix.** Use a monotonic/higher-resolution identifier:

```dart
id: 'custom_${DateTime.now().microsecondsSinceEpoch}_${_idCounter++}',
```
or a proper UUID/banner-based unique id, and have `addCustomPrompt` replace an
existing entry with the same id (or reject it).

---

### F15 — `setState` after awaited persistence lacks `mounted` guard  [Low]

**File:** `widgets/settings/pages/prompts_page.dart:891, 903`

**Problem.** Inside the dialog submit handler:

```dart
await settings.addCustomPrompt(p);
await settings.setSelectedPromptId(p.id);
setState(() {                       // ← no mounted check after the awaits
  _customPrompts = settings.customPrompts;
  _selectedPromptId = p.id;
});
```

The risk is low because the dialog is modal and blocks sidebar navigation, but
it is still a latent bad-after-async pattern. The sibling `_showTextInputDialog`
path in `ai_models_page` and the `_showResetDefaultsDialog` already guard with
`mounted`.

**Fix.**

```dart
await settings.addCustomPrompt(p);
await settings.setSelectedPromptId(p.id);
if (!mounted) return;
setState(() { ... });
```

---

### F16 — `onModelDownloaded` fires on plain model selection  [Info]

**File:** `widgets/settings/pages/ai_models_page.dart:1137-1143`

```dart
onTap: () async {
  final settings = SettingsProviderScope.of(context).settingsService;
  await settings.setWhisperModelId(modelId);
  setState(() {});
  widget.onModelDownloaded?.call(); // fired on SELECTION, not download
},
```

Tapping an already-installed model to activate it fires the
`onModelDownloaded` callback. This may be deliberate wiring (the parent
re-initialising Whisper), but the name is misleading and the side effect is
non-obvious. Consider a dedicated `onActiveModelChanged` callback or document
the intent.

---

### F17 — `_buildLoadingState()` is unreachable  [Info]

**File:** `widgets/settings/pages/ai_models_page.dart:591, 103-108`

`_settingsLoaded` is flipped to `true` inside `didChangeDependencies` (which
runs before the first `build`), so by `build` time the guard
`if (!_settingsLoaded) return _buildLoadingState();` is never entered — the
loading placeholder never renders. Loading is synchronous anyway (the service
is already initialised), so this is harmless, but the branch is dead code.

---

### F18 — Dashboard / heatmap charts lack semantics  [Info]

**Files:** `home_dashboard_page.dart` (`_WeeklyBarPainter`), `home_activity_heatmap.dart`
(`_HeatmapPainter` / per-cell `Tooltip`).

Charts are pure `CustomPainter`s with no `Semantics`, and the heatmap `Tooltip`
children are mouse-only (`SizedBox.expand()` hit targets, no focus path).
Keyboard / screen-reader users receive no summary of the activity data.

**Fix (lightweight).** Wrap each chart `CustomPaint` in a `Semantics` with a
generated textual summary (e.g. "This week: N words across X of 7 days") so the
information is available non-visually; the painted visuals remain for sighted
users.

---

### F19 — `beeColors()` dereferences the extension with `!`  [Info]

**File:** `widgets/settings/settings_shared.dart:69-70`

```dart
BeeColors beeColors(BuildContext context) =>
    Theme.of(context).extension<BeeColors>()!;
```

This will throw a `TypeError` if called from a context without the
`BeeColors` theme extension registered (e.g. a dialog shown above a bare
`MaterialApp`, or a unit test without the theme). It is a safe assumption for
the shipping app, but a fallback `?? BeeColors.light()` would make it robust.

---

### F20 — `SettingsProvider.checkPermissions()` is a no-op stub  [Info]

**File:** `providers/settings_provider.dart:113-116`

```dart
Future<void> checkPermissions() async {
  // Will be populated by the UI using KeyboardService
  notifyListeners();
}
```

It only notifies and delegates real work to the pages. No caller appears to use
it meaningfully (pages call `KeyboardService` directly). Either implement it or
remove it to avoid confusion.

---

## Positive observations

- **Persistence is solid.** `_save()` serialises writes on a single
  `_saveQueue`, and `_writeAtomic()` does temp-write → rename with a `.bak` of
  the previous-good file; `_load()` falls back through live → `.bak` → `.tmp` →
  empty. This is crash-safe and the strongest area of the layer.
- **Defensive typed accessors.** `_getString`/`_getBool`/`_getInt` use `is`
  guards (not `as`), so a corrupt/hand-edited `settings.json` degrades to
  defaults instead of throwing on launch.
- **Consistent deferred-load pattern.** Every page uses the
  `didChangeDependencies` + `_settingsLoaded` one-shot load, and the AI Models /
  Prompts pages layer a `_syncFromSettings` / `_syncMutableSettings` that
  **compares before calling `setState`** — a thoughtful no-op-rebuild guard.
- **`mounted` checks are present on virtually every async page path**
  (`_verifyCloudProvider`, `_loadAudioDevices`, `_checkPermissions`,
  `_checkForUpdates`, `_resetPermissions`, `_runDiagnostics`, the download
  listener, clipboard `_reload`/`_showSnack`). F01 is the one gap.
- **Good semantic coverage** via `BeeInteractive` (`semanticLabel`, keyboard
  `Enter`/`Space` activation, hover/focus parity). The close button and most
  action chips are correctly announced.
- **Sensible secure-credential handling.** API keys live in the secure store,
  never in the JSON; `.env` values are treated as read-only and override UI
  stored values; the AI-Models UI distinguishes env-managed vs local keys.

---

## Appendix — Files reviewed

**Settings pages** (`widgets/settings/pages/`)
- `ai_models_page.dart` (1278 lines)
- `clipboard_page.dart` (772 lines)
- `general_settings_page.dart` (1016 lines)
- `home_achievements_section.dart` (279 lines)
- `home_activity_heatmap.dart` (481 lines)
- `home_dashboard_page.dart` (444 lines)
- `prompts_page.dart` (1270 lines)
- `prompt_override_panel.dart` (856 lines)
- `troubleshooting_page.dart` (876 lines)

**Settings infrastructure** (`widgets/settings/`)
- `settings_window.dart` (291 lines)
- `settings_sidebar.dart` (294 lines)
- `settings_page_container.dart` (113 lines)
- `settings_shared.dart` (1246 lines)
- `bee_data_card.dart` (38 lines)
- `bee_dropdown.dart` (263 lines)
- `bee_input.dart` (49 lines)
- `bee_page_header.dart` (63 lines)

**State management**
- `providers/settings_provider.dart` (162 lines)
- `services/settings_service.dart` (1087 lines)
