# Service Layer Code Review — Cross-Platform Services

**Scope:** macOS/Windows/Linus service layer (`frontend/lib/services/`).
**Focus:** Implementation asymmetries, dead code, bugs, and improvement opportunities — especially on the macOS native path.

---

## Executive Summary

The service layer is generally well-structured (per-id locking in `HotkeyService`, defensive stop-on-failure in `RecordingService`, clean conditional imports). However, there is a **confirmed reliability asymmetry** in macOS paste-synthesis (no modifier sweep, unlike Windows), **~97 lines of dead code**, **two hardcoded screen-size fallbacks** that can misplace the overlay window, a small set of **state-machine/robustness edges** in the recording and keyboard services, and a **keychain accessibility flag** worth revisiting.

| # | Finding | Severity | Primary location |
|---|---------|----------|------------------|
| 1 | macOS `Cmd+V` has **no modifier-release sweep** (asymmetric vs Windows) | **High** | `keyboard_service.dart:57-93`, `MainFlutterWindow.swift:482-498` |
| 2 | `_isPasting` can **lock out pasting forever** if the native call hangs | **Medium** | `keyboard_service.dart:43-48`, `macos_permission_service.dart:63-72` |
| 3 | `WindowHelperMacOS` class (97 lines) is **dead code — never imported** | **Medium** | `window_helper_macos.dart` (entire file) |
| 4 | Sync `getScreenSize()` is **dead** AND returns hardcoded `1920×1080` for non-Windows | **Medium** | `window_helper.dart:94-102` |
| 5 | macOS positioning **fallback hardcodes `1440×900`** → window misplacement | **Medium** | `window_helper.dart:140-150` |
| 6 | Keychain uses `AfterFirstUnlockThisDeviceOnly`; update never re-sets the accessibility class | **Medium** | `MainFlutterWindow.swift:124, 137-140` |
| 7 | `getAudioBytes()` rebuilds WAV from lingering `_macNativePcm`; consumed PCM is **not reset** | **Low** | `recording_service.dart:259-283` |
| 8 | Audio file is **double-waited** (up to ~4s) and polled on a fixed 40 ms cadence | **Low** | `recording_service.dart:252-254, 277, 297-336` |
| 9 | Fire-and-forget `Future.delayed` in `finally` (minor leak on dispose) | **Low** | `keyboard_service.dart:43-48` |
| 10 | Hotkey label shows **"Win" on macOS** for `HotKeyModifier.meta` | **Low** | `hotkey_service.dart:89` |
| 11 | `AXIsProcessTrusted` FFI uses signed `Int8` for C `Boolean` (correct, but imprecise) | **Informational** | `keyboard_service_macos.dart:27-32` |
| 12 | `stopRecording()` mixes into the native stream state (file stop on a stream start) | **Low** | `recording_service.dart:241-243` |

---

## Finding 1 — macOS `Cmd+V` lacks the modifier-release sweep (HIGH)

**Severity:** High
**Location:** `frontend/lib/services/keyboard_service.dart:57-93` (Dart side), `frontend/macos/Runner/MainFlutterWindow.swift:482-498` (Swift `pasteWithCmdV()`).
**Cross-ref:** `frontend/lib/services/keyboard_service_windows.dart:36-54` (the Windows path that gets this *right*).

### What's wrong

The Windows path documents and implements a deliberate fix: it waits ~300 ms for the user to release hotkey modifiers, **then explicitly sends `KEYEVENTF_KEYUP` for all 8 modifier VKs** (left/right Ctrl, Alt, Shift, Win) so a physically- or sticky-held modifier cannot turn `Ctrl+V` into `Ctrl+Shift+V`:

```dart
// keyboard_service_windows.dart:14-23, 47-54
const List<int> _modifierVks = <int>[
  VK_LCONTROL, VK_RCONTROL, VK_LMENU, VK_RMENU,
  VK_LSHIFT, VK_RSHIFT, VK_LWIN, VK_RWIN,
];
...
for (var i = 0; i < modifierCount; i++) {
  pInputs[i].type = INPUT_KEYBOARD;
  pInputs[i].Anonymous.ki.wVk = _modifierVks[i];
  pInputs[i].Anonymous.ki.dwFlags = KEYEVENTF_KEYUP;   // force-release sweep
}
```

The macOS path has **no equivalent**. `_simulateCtrlVMacOS()` only does a 300 ms `Future.delayed(...)`, then invokes the native paste, which posts a bare `Cmd+V`:

```swift
// MainFlutterWindow.swift:482-498
private func pasteWithCmdV() -> Bool {
  let source = CGEventSource(stateID: .combinedSessionState)
  guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
        let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { ... }
  keyDown.flags = .maskCommand
  keyUp.flags   = .maskCommand
  keyDown.post(tap: .cghidEventTap)
  keyUp.post(tap: .cghidEventTap)
  return true
}
```

Although `.maskCommand` is the mask stamped on the *synthesized* event, target apps that query **live** modifier state (e.g. `NSEvent.modifierFlags`, `[NSApp currentEvent]`) will still observe any modifier the user is physically holding. So a `Cmd+Shift+V`-style global hotkey followed too quickly by the auto-paste (300 ms is a guess; sticky keys, motor differences, or a fast re-trigger can all exceed it) will be interpreted as **`Cmd+Shift+V`** ("Paste and Match Style") by many text fields — or the plain paste simply fails to insert anything. Because the team already understood and fixed this *exact* failure mode on Windows, the macOS omission is a genuine **asymmetry/regression**, not a deliberate platform exclusion.

### Recommended fix

Mirror the Windows sweep on the native side: post `keyUp` CGEvents for every modifier immediately before the `V` keystroke.

```swift
// MainFlutterWindow.swift — pasteWithCmdV()
private func pasteWithCmdV() -> Bool {
  let source = CGEventSource(stateID: .combinedSessionState)
  let tap = CGEventTapLocation.cghidEventTap

  // Sweep: force-release every modifier (mirrors the Windows SendInput KEYUP
  // sweep) so a physically-held Shift/Ctrl/Option from the triggering hotkey
  // can't turn the synthesized Cmd+V into Cmd+Shift+V.
  let modifierKeyCodes: [CGKeyCode] = [
    0x37, // left  command
    0x36, // right command
    0x38, // left  shift
    0x3C, // right shift
    0x3B, // left  control
    0x3E, // right control
    0x3A, // left  option
    0x3D, // right option
  ]
  for code in modifierKeyCodes {
    if let up = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: false) {
      up.post(tap: tap)
    }
  }

  guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
        let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
    debugLog("[Permission] pasteWithCmdV: failed to create CGEvents")
    return false
  }
  keyDown.flags = .maskCommand
  keyUp.flags   = .maskCommand
  keyDown.post(tap: tap)
  keyUp.post(tap: tap)
  return true
}
```

(Then the 300 ms Dart-­side delay in `_simulateCtrlVMacOS()` can stay as the first line of defence, matching Windows.) Optional hardening: optionally read live flags via `CGEventSource.flagsState(.combinedSessionState)` and only post the `V` events once confirmed clear — but the explicit sweep is the deterministic fix.

---

## Finding 2 — `_isPasting` can permanently lock out pasting (MEDIUM)

**Severity:** Medium
**Location:** `frontend/lib/services/keyboard_service.dart:43-48` + `macos_permission_service.dart:63-72`.

The re-entrancy guard sets `_isPasting = true` at the top of `simulateCtrlV()` and resets it inside a **fire-and-forget `Future.delayed`** in the `finally` block:

```dart
// keyboard_service.dart:43-48
} finally {
  Future.delayed(const Duration(milliseconds: 500), () {
    _isPasting = false;     // only runs AFTER the try body completes
  });
}
```

`finally` only executes **after** the awaited native call returns. `MethodChannel.invokeMethod` has **no built-in timeout**. So if the native `pasteWithCmdV` / `simulateCtrlVWindows` call ever hangs (engine stall, plugin not attached, deadlock in the platform thread), `finally` never runs, `_isPasting` stays `true` forever, and **every subsequent paste is silently dropped** ("Already pasting, ignoring duplicate call").

The 500 ms delay also does not begin until *after* completion — so the guard's window of protection already expired when reset is scheduled.

### Recommended fix

Reset the flag synchronously in `finally` (the guard's purpose — preventing re-entry during the async native round-trip — is satisfied the instant the method returns), and bound the native call so a hang cannot wedge the app:

```dart
} finally {
  _isPasting = false;   // synchronous reset; native op has already settled
}
```

```dart
// macos_permission_service.dart — add a guard so a hung channel can't wedge pasting
static Future<bool> pasteCmdV() async {
  if (!Platform.isMacOS) return false;
  try {
    final result = await _channel
        .invokeMethod<bool>('pasteWithCmdV')
        .timeout(const Duration(seconds: 3), onTimeout: () {
      debugPrint('MacOsPermissionService.pasteCmdV timed out');
      return false;
    });
    return result ?? false;
  } catch (e) {
    debugPrint('MacOsPermissionService.pasteCmdV error: $e');
    return false;
  }
}
```

---

## Finding 3 — `WindowHelperMacOS` is dead code (MEDIUM)

**Severity:** Medium (maintenance burden / confusion)
**Location:** `frontend/lib/services/window_helper_macos.dart` (entire file, 97 lines).

### Verification

- A workspace search for `WindowHelperMacOS` returns **only its own class declaration** — no other reference.
- A search for `import ...window_helper_macos` returns **zero matches** — the file is never imported anywhere.
- `window_helper.dart` talks to macOS via its **own inline** `const _macOSChannel = MethodChannel('beeamvo/window')` (line 12) and inlines the `invokeMethod('show'/'hide'/…)` calls directly. `WindowHelperMacOS` duplicates that exact same channel and the exact same method names, so it is a redundant Shadow that callers never reach.

    ```dart
    // window_helper.dart:11-12, 20-31   ← the real macOS path (inline channel)
    const _macOSChannel = MethodChannel('beeamvo/window');
    ...
    await _macOSChannel.invokeMethod('showWithoutFocus');   // NOT WindowHelperMacOS
    ```

### Recommended fix

**Delete `frontend/lib/services/window_helper_macos.dart`.** It is unreferenced and any line changed here would have no runtime effect while misleading future editors. If you want a typed macOS helper later, refactor `window_helper.dart`'s inline channel calls into it **and** actually call it.

---

## Finding 4 — Sync `getScreenSize()` is dead AND hardcodes `1920×1080` (MEDIUM)

**Severity:** Medium
**Location:** `frontend/lib/services/window_helper.dart:94-102`.

### What's wrong

```dart
// window_helper.dart:95-102
static (int, int) getScreenSize() {
  if (Platform.isWindows) {
    return win32_impl.getScreenSizeWindows();
  } else {
    // Fallback for synchronous call; async callers should use getScreenSizeAsync
    return (1920, 1080);   // ← hardcoded, wrong for any non-Windows, non-1080p screen
  }
}
```

- It returns a hardcoded `1920×1080` for **every** macOS/Linux display, regardless of actual resolution.
- It has **no callers**: a search for `getScreenSize()` returns only this definition and the unrelated async one. (`main.dart:61` uses the async `getScreenSizeAsync()`, not this.)
- Keeping a "looks synchronous, returns garbage" version of an otherwise-correct async API is a footgun: the moment someone calls it (e.g. during a refactor), macOS/Linux windows are positioned as if on a 1080p panel.

### Recommended fix

**Delete the sync `getScreenSize()`.** There is no synchronous source of truth for display dimensions on macOS/Linux; the correct API is the async `getScreenSizeAsync()` (which uses `screen_retriever`). Removing the fork prevents accidental misuse.

---

## Finding 5 — macOS positioning fallback hardcodes `1440×900` (MEDIUM)

**Severity:** Medium
**Location:** `frontend/lib/services/window_helper.dart:140-150`.

### What's wrong

The macOS branch of `positionAtActiveMonitorBottomCenter` calls the native `positionAtBottomCenter` first, but the **fallback** (executed if the channel throws) hardcodes a 13" MacBook resolution:

```dart
// window_helper.dart:140-150
const screenHeight = 900.0;
const screenWidth  = 1440.0;
final xPos = (screenWidth / 2) - (windowWidth / 2);
final yPos = screenHeight - 120.0;
await windowManager.setPosition(Offset(xPos, yPos));
```

On an external 4K/5K display, a Retina-scaled panel, or any monitor other than 1440×900 logical, this places the overlay at the **wrong** location (often clipped off-screen or far from bottom-center). Note the **Linux** branch right below it (lines 151-186) already does this correctly via `screen_retriever` (`getCursorScreenPoint` → active display → `visiblePosition`/`size`). The macOS fallback should reuse that logic rather than a magic constant.

Also note the secondary inconsistency: `getScreenSizeAsync()`'s error fallback returns `1920×1080` (line 115) while this branch uses `1440×900` — two different "defaults" for the same conceptual value.

### Recommended fix

Reuse `screen_retriever` in the macOS fallback (identical to the Linux branch), or — simplest — call the existing async screen helper:

```dart
} catch (e) {
  debugPrint('WindowHelper.positionAtActiveMonitorBottomCenter macOS fallback: $e');
  await windowManager.setSize(Size(windowWidth.toDouble(), windowHeight.toDouble()));
  try {
    final display = await screenRetriever.getPrimaryDisplay();
    final sw = display.size.width;
    final sh = display.size.height;
    final origin = display.visiblePosition ?? Offset.zero;
    await windowManager.setPosition(
      Offset(origin.dx + (sw / 2) - (windowWidth / 2), origin.dy + sh - 120.0),
    );
  } catch (_) {
    await windowManager.center();
  }
  await windowManager.setAlwaysOnTop(true);
  await windowManager.show();
}
```

(For multi-monitor correctness, mirror the Linux block and resolve the display **under the cursor**, not just the primary.)

---

## Finding 6 — Keychain accessibility flag (`AfterFirstUnlockThisDeviceOnly`) (MEDIUM)

**Severity:** Medium (security posture)
**Location:** `frontend/macos/Runner/MainFlutterWindow.swift:124` (write) and `137-140` (update).

Two observations:

### 6a. `AfterFirstUnlockThisDeviceOnly` is permissive for an API key

```swift
// MainFlutterWindow.swift:124
addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
```

`AfterFirstUnlock` keeps the item readable **while the device is locked** (after the first post-boot unlock). It's the right choice for a background daemon/agent that must run from the Lock Screen — but this app is a **foreground dictation tool**. The credential stored here is a **Gemini API key** (full account billing/transcription scope). The stricter `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` is the usual recommendation for end-user secrets: it requires an *unlocked* device at read time and shrinks the blast radius if the laptop is lost/stolen while locked. `ThisDeviceOnly` (no iCloud/backup migration) is already correct and good.

**Trade-off to confirm:** if any feature reads the key while the screen is locked, `WhenUnlocked` would break it and `AfterFirstUnlock` should stay. Otherwise prefer `WhenUnlockedThisDeviceOnly`:

```swift
addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
```

### 6b. `SecItemUpdate` never (re-)sets the accessibility class

```swift
// MainFlutterWindow.swift:137-140
let updateStatus = SecItemUpdate(
  baseQuery(account: account) as CFDictionary,
  [kSecValueData as String: data] as CFDictionary   // only the value is touched
)
```

`SecItemUpdate` updates **only** `kSecValueData`. The accessibility attribute of a *pre-existing* item is left untouched. Therefore:

- An item written by an older build under a different (e.g. less restrictive) class is **not promoted** to the class set in `addQuery`.
- If you adopt 6a's stricter class, **existing users won't get it** until the entry is deleted and re-created.

**Recommended fix:** on `errSecDuplicateItem`, update the attributes too, or delete-then-add:

```swift
let attributes: [String: Any] = [
  kSecValueData as String: data,
  kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
]
let updateStatus = SecItemUpdate(baseQuery(account: account) as CFDictionary,
                                 attributes as CFDictionary)
```

---

## Finding 7 — `_macNativePcm` is not reset after consumption in `getAudioBytes()` (LOW)

**Severity:** Low (bounded memory + privacy)
**Location:** `frontend/lib/services/recording_service.dart:259-283`.

### State-machine review

I traced the full lifecycle of `_macNativePcm`:

| Step | Sets `_macNativePcm` | Notes |
|------|----------------------|-------|
| `_startMacNative()` (line 742) | `null` (cleared up front) | ✔ start is clean |
| `_stopMacNativePcm()` (line 803) | fresh PCM (retained) | ✔ kept for consumers |
| `getAudioBytes()` (lines 263-269) | *unchanged* | ✔/⚠ retained **after** consumption |
| `_stopMacNativeToWavPath()` (lines 833-866) | *unchanged* | ✔ builds WAV from retained PCM |
| `_bestEffortStopMacNative()` (cancel, line 896) | `null` (cleared) | ✔ **cancel path is clean** |
| `deleteRecording()` (line 530) | `null` (cleared) | ✔ |

**Good news (directly answering the task's question):** the *cancelled*-recording path is clean — `_bestEffortStopMacNative()` sets both `_usingMacNative = false` and `_macNativePcm = null`. There is **no leak of PCM after a cancelled recording.**

**The remaining gap:** `getAudioBytes()` consumes the PCM into a WAV and returns it, but does **not** reset `_macNativePcm`. The data lingers until the *next* `_startMacNative()` / `deleteRecording()` / `dispose()`. The retention is *intentional* (it enables cloud retry to rebuild from memory instead of the file — see the comment at lines 853-855), and is **bounded to one recording** (each new start clears it), so memory impact is limited. For long dictations, however, megabytes of the **previous** user utterance sit in memory longer than necessary (minor privacy/retention concern).

### Recommended fix

Clear the in-memory PCM once the WAV has been *durably* written to disk, so retries fall back to the file rather than stale RAM:

```dart
Future<Uint8List?> getAudioBytes() async {
  final nativePcm = _macNativePcm;
  if (nativePcm != null && nativePcm.isNotEmpty) {
    final wav = buildMono16kWav(nativePcm);
    final persisted = await _writeWavFileBestEffort(wav);
    if (persisted) {
      _macNativePcm = null;   // disk has the WAV; no need to keep audio in RAM
    }
    return wav;
  }
  ...
}
```

(Only drop RAM when the file write succeeded, to preserve the retry path when the cache dir is unavailable — which is exactly the scenario the retention was added for.)

---

## Finding 8 — `getAudioBytes()` double-waits the file and uses a fixed 40 ms poll (LOW)

**Severity:** Low (performance)
**Location:** `recording_service.dart:252-254` and `277`, plus `_waitForRecordingFile()` at `297-336`.

Two minor inefficiencies:

1. **Double wait.** `stopRecording()` already calls `_waitForRecordingFile(path)` (line 253). Callers in `main.dart` (lines 1643, 1653) then call `getAudioBytes()`, which calls `_waitForRecordingFile(path)` **again** (line 277). Each call can block up to 2000 ms → ~4 s worst case of redundant FS polling.
2. **Fixed 40 ms cadence** = up to ~50 `exists()`/`length()` probes in the timeout window. Not a hot spin (there's a sleep), but it's chatty.

This only affects the Windows/Linux file path — the macOS native path short-circuits on `_macNativePcm` before reaching the poller.

### Recommended fix

- Skip the re-wait inside `getAudioBytes()` when the caller has already waited (e.g. gate `_waitForRecordingFile` on a `_fileReady` flag set by `stopRecording()`), or drop the wait in `stopRecording()` since `getAudioBytes()` always waits.
- Start the poll at a slightly larger interval (e.g. 50–60 ms) and keep it constant; the current 40 ms is fine, just avoid the redundant second pass.

---

## Finding 9 — Fire-and-forget `Future.delayed` in `finally` (LOW)

**Severity:** Low
**Location:** `keyboard_service.dart:43-48`.

As written (and assuming Finding 2's reset is adopted, this fully goes away), the current `Future.delayed(...)` in `finally` schedules a one-shot timer whose callback writes to a `static` field. It is effectively a leak on widget/app dispose (the timer is not tracked or cancelled). Because it touches only a primitive `static bool`, the practical harm is nil, but it is the kind of pattern analyzers flag. Adopting the Fix in Finding 2 (reset synchronously in `finally`) eliminates this entirely.

---

## Finding 10 — Hotkey recorder shows "Win" for `Cmd` on macOS (LOW)

**Severity:** Low (cosmetic, user-facing in logs/conflict errors and likely the recorder UI)
**Location:** `hotkey_service.dart:89`.

```dart
if (modifiers.contains(HotKeyModifier.meta)) parts.add('Win');
```

`HotKeyModifier.meta` is the **Command** key on macOS (where it's the primary modifier) and the Windows key on Windows. A macOS user binding `Cmd+V` therefore sees `"Win + V"` in `HotkeyConflictException` messages and `debugPrint` logs. This is the same `_comboLabel()` used to format conflict errors shown to users.

### Recommended fix

Branch on platform (add `import 'dart:io';`):

```dart
if (modifiers.contains(HotKeyModifier.meta)) {
  parts.add(Platform.isMacOS ? 'Cmd' : (Platform.isLinux ? 'Super' : 'Win'));
}
```

(`_comboSignature()` at lines 69-77 is unaffected — it uses `.name` sorted, so conflict detection is still correct; this is display-only.)

---

## Finding 11 — `AXIsProcessTrusted` FFI signature (INFORMATIONAL)

**Severity:** Informational
**Location:** `keyboard_service_macos.dart:27-32`.

```dart
final checkTrusted = _appServices!
    .lookupFunction<Int8 Function(), int Function()>('AXIsProcessTrusted');
return checkTrusted() != 0;
```

The C declaration is `Boolean AXIsProcessTrusted(void)` where `Boolean` is `unsigned char`. The Dart mapping uses `Int8` (signed). Because the only values ever returned are `0`/`1`, signed-vs-unsigned is irrelevant and the call is **functionally correct**, with `!= 0` correctly normalizing the result. The marginal improvement would be `UnsignedInt8 Function()` for fidelity. No behaviour change. (The modern one-shot *prompt* API `AXIsProcessTrustedWithOptions` is correctly routed through the native channel in `MacOsPermissionService.request()` — the FFI lookup here is only for the silent pre-check, which is the right design.)

---

## Finding 12 — `stopRecording()` can stop a native *stream* as a file (LOW)

**Severity:** Low
**Location:** `recording_service.dart:241-256` vs `741-794`, `672-725`.

`_startMacNative(asStream: true)` (from `startStreamRecording`) sets `_usingMacNative = true` **and** `_isStreamRecording = true`. But `stopRecording()` only checks `if (_usingMacNative) return _stopMacNativeToWavPath();` — so if a stream-started session is stopped via `stopRecording()` instead of `stopStreamAndGetPcm()`, it takes the **file** path (materializes a WAV, never runs the stream-cleanup branch that discards on error at lines 703-716) and leaves `_isStreamRecording` true until the next `_stopStreamRecording()`. In current usage `main.dart` always pairs `startStreamRecording` with `stopStreamAndGetPcm`, so this is latent — but it's an easy state-machine footgun.

### Recommended fix

Either gate on both flags in `stopRecording()`:

```dart
if (_usingMacNative && _isStreamRecording) {
  // Stream session stopped through the file API — forward to the PCM path
  // and run stream cleanup so error/empty handling is consistent.
  final pcm = await _stopMacNativePcm();
  await _stopStreamRecording();
  if (pcm == null || pcm.isEmpty) return null;
  // (optional) materialize WAV as before
}
```

…or assert at the API boundary that file/stream start/stop are not mixed.

---

## Cross-Platform Asymmetry Summary

| Behaviour | Windows | macOS | Linux |
|-----------|---------|-------|-------|
| Modifier release sweep before paste | ✅ explicit 8-VK KEYUP sweep | ❌ **none (Finding 1)** | ⚠️ X11 only via `--clearmodifiers`; Wayland `wtype` has none |
| Pre-paste delay | 300 ms | 300 ms | 300 ms |
| Accessibility permission check | n/a | ✅ FFI silent + native prompt | n/a |
| Screen-size source (sync) | Win32 `GetSystemMetrics` | **dead → hardcoded (Findings 3,4)** | dead → hardcoded |
| Screen-size source (async) | Win32 | `screen_retriever` (w/ 1920×1080 fallback) | `screen_retriever` (active-by-cursor) |
| Position fallback constants | real monitor bounds | **hardcoded 1440×900 (Finding 5)** | real `screen_retriever` display |
| Paste re-entrancy guard | `static _isPasting` (lock-prone, Finding 2) | same | same |
| Audio capture backend | `record` package (file/stream) | **native AVAudioEngine** (in-memory PCM) | `record` package |

The single highest-value fix is **Finding 1**: bringing macOS paste up to the reliability already achieved on Windows. Findings 3–5 are cheap cleanups that reduce confusion and a real misplacement bug. Finding 6 is a security-posture decision worth an explicit product call.

---

*Review based on the current service-layer snapshot: `keyboard_service*`, `window_helper*`, `macos_permission_service.dart`, `recording_service.dart`, `hotkey_service.dart`, `secure_credential_store.dart`, and the native `MainFlutterWindow.swift` (keychain + `pasteWithCmdV`).*
