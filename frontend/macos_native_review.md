# macOS Native Layer — Code Review Report

**Scope:** BeamVoice / Beeamvo macOS native Swift layer (Flutter desktop, voice-to-text)
**Reviewed files:**
- `frontend/macos/Runner/MainFlutterWindow.swift` (635 lines)
- `frontend/macos/Runner/MacAudioCapturePlugin.swift` (399 lines)
- `frontend/macos/Runner/AppDelegate.swift` (15 lines)
- `frontend/macos/Runner/Info.plist` (36 lines)
- `frontend/macos/Runner/DebugProfile.entitlements` / `Release.entitlements`
- Cross-referenced: `WhisperPlugin.swift`, `AppInfo.xcconfig`, `project.pbxproj`, `keyboard_service_windows.dart`, `keyboard_service.dart`, `macos_permission_service.dart`, `secure_credential_store.dart`

**Key environment facts established during review:**

| Fact | Value | Source |
|---|---|---|
| `MACOSX_DEPLOYMENT_TARGET` | **13.0** | `project.pbxproj` (×3 configs), `Podfile` |
| `PRODUCT_BUNDLE_IDENTIFIER` | **`com.beeamvo.app`** | `Configs/AppInfo.xcconfig`, `project.pbxproj` |
| `pubspec` `name` | `beeamvo` | `pubspec.yaml` |
| Product name | `Beeamvo` | `AppInfo.xcconfig` |
| App-Sandbox | **disabled** (both entitlements) | `DebugProfile.entitlements`, `Release.entitlements` |
| LSUIElement (accessory mode) | **true** | `Info.plist` |

> The deployment target of **macOS 13.0** is the single most important fact for this review: it means `SMAppService` (the modern launch-at-login API) is **fully available with no fallback needed**. Several findings below are actionable *because* 13.0 is the floor.

---

## Severity legend

- **Critical** — crash, data loss, or a security/correctness defect affecting the core flow *now*.
- **High** — impactful correctness/robustness bug or a deprecated API that is *also* unreliable in the field.
- **Medium** — real defect with limited blast radius, or a performance/UX hazard.
- **Low** — hygiene, latent fragility, or cosmetic inconsistency.

---

## Findings index

| # | Severity | File:line | Topic |
|---|---|---|---|
| 1 | **High** | `MainFlutterWindow.swift:519–606` | Deprecated, fragile `LSSharedFileList` launch-at-login → migrate to `SMAppService.mainApp` |
| 2 | **High** | `MainFlutterWindow.swift:482–498` | CGEvent paste omits held-modifier sweep (asymmetry vs Windows) |
| 3 | **High** | `MacAudioCapturePlugin.swift:247–305` | `AVAudioConverter` tail samples dropped — no `.endOfStream` flush at stop |
| 4 | **Medium** | `MacAudioCapturePlugin.swift:234–287` | Conversion + `NSLock` on the realtime audio thread (glitch / priority-inversion risk) |
| 5 | **Medium** | `MainFlutterWindow.swift:459–479`, `:413` | Main-thread blocking: synchronous `tccutil` Process + Keychain + LSSharedFileList in channel handlers |
| 6 | **Medium** | `MainFlutterWindow.swift:19,460,503` + `AppInfo.xcconfig:8` | Bundle-ID / identifier inconsistencies |
| 7 | **Low** | `MainFlutterWindow.swift:462` | Deprecated `Process.launchPath` (use `executableURL`) |
| 8 | **Low** | `MainFlutterWindow.swift:26` | Force-unwrap of Application Support directory path |
| 9 | **Low** | `MacAudioCapturePlugin.swift:25,48,99,241,290` | Non-atomic `isRecording` accessed across threads |
| 10 | **Low** | `MacAudioCapturePlugin.swift:126–139,234–245` | `startEngine` error path leaks the tap / leaves `converter` set |
| 11 | **Low** | `MacAudioCapturePlugin.swift:253–254` | Output buffer capacity margin is thin |
| 12 | **Low/Nit** | `MainFlutterWindow.swift:302` | `awakeFromNib` calls `super` last |
| 13 | **Info** | `MainFlutterWindow.swift:124` | Keychain `…AfterFirstUnlockThisDeviceOnly` — correct for a post-login menu-bar app |
| 14 | **Info** | Entitlements / `Info.plist` | Sandbox-off intentional; usage strings correct; `NSAppleEventsUsageDescription` correctly absent |
| 15 | **Info** | `GeneratedPluginRegistrant.swift:13` | `record_macos` still registered but bypassed at runtime (dead weight) |

---

## 1. [High] Deprecated, fragile `LSSharedFileList` launch-at-login → migrate to `SMAppService.mainApp`

**File:** `frontend/macos/Runner/MainFlutterWindow.swift:510–606`
**Used APIs:** `LSSharedFileListCreate`, `LSSharedFileListCopySnapshot`, `LSSharedFileListItemCopyResolvedURL`, `LSSharedFileListItemRemove`, `LSSharedFileListInsertItemURL`, `kLSSharedFileListSessionLoginItems`, `kLSSharedFileListItemLast`.

### Why this matters

1. **Deprecated since macOS 10.11 (El Capitan, 2015).** The entire `LSSharedFileList` family emits deprecation warnings on every build against a modern SDK. Given `MACOSX_DEPLOYMENT_TARGET = 13.0`, there is **no reason** to keep it — the replacement is available.

2. **Unreliable in the field, not just deprecated.** `LSSharedFileListInsertItemURL` for login items has a well-known track record on macOS 13/14 of either silently failing to persist the item, or the item not launching for signed / notarized / `LSUIElement` apps after the bundle is moved/re-signed (CDHash change). `SMAppService.mainApp` is the Apple-blessed modern path and is markedly more reliable.

3. **Fragile manual Core Foundation memory management.** Several retain semantics are unsafe:
   - `kLSSharedFileListSessionLoginItems.takeRetainedValue()` (`:521`, `:560`) and `kLSSharedFileListItemLast.takeRetainedValue()` (`:587`) call `takeRetainedValue()` on **immortal global constants**. These constants are not heap-allocated in a retain-count-ownable sense, so `takeRetainedValue()` is semantically wrong (it only "works" because immortal singletons ignore `release`). This is a latent bug that disappears entirely once the API is removed.
   - `let item = LSSharedFileListInsertItemURL(...)` (`:585–593`) returns an owned `Unmanaged` value that is checked for `nil` but **never consumed/released** → item leak on every `enable`.
   - `Bundle.main.bundleIdentifier ?? "com.beamvo.Beeamvo"` (`:503`) is the *wrong* fallback id (see Finding 6) — it's only used as the cosmetic *display name* of the login item, so it doesn't break matching (which is URL-path based at `:539`/`:574`), but it's another symptom of glue that `SMAppService` removes.

4. The file **already imports `ServiceManagement`** (`:4`) but never uses it.

### Fix (replace `isLaunchAtLoginEnabled` + `setLaunchAtLoginEnabled`, lines 510–606)

Because the deployment floor is `13.0`, no version branching is required:

```swift
import ServiceManagement   // already imported at top of file

// MARK: - Launch at Login (SMAppService, macOS 13+)

func isLaunchAtLoginEnabled() -> Bool {
  // SMAppService.mainApp is the single source of truth for the main-app
  // login item. .enabled == registered and active at next login.
  SMAppService.mainApp.status == .enabled
}

@discardableResult
func setLaunchAtLoginEnabled(_ enabled: Bool) -> Bool {
  do {
    if enabled {
      try SMAppService.mainApp.register()
    } else {
      try SMAppService.mainApp.unregister()
    }
    return true
  } catch {
    debugLog("[LaunchAtLogin] SMAppService \(enabled ? "register" : "unregister") failed: \(error)")
    return false
  }
}
```

You can then **delete** `getBundleID()` (`:502–504`) and `getAppURL()` (`:506–508`) — `SMAppService.mainApp` derives both from the bundle automatically. `LSUIElement = true` (Info.plist `:33–34`) is fully compatible with `SMAppService.mainApp`; the app still launches hidden/accessory on login.

> Note on `status`: for `SMAppService.mainApp` (not a login-item *helper*), `register()` does **not** require the user to toggle anything in System Settings — `.enabled` is reached directly. If you wanted to surface "registered but pending approval" separately you could also treat `.requiresApproval` as enabled for toggle purposes; for a main app it is not expected.

---

## 2. [High] CGEvent paste omits held-modifier sweep — asymmetry vs Windows

**File:** `frontend/macos/Runner/MainFlutterWindow.swift:482–498`
**Cross-reference:** `frontend/lib/services/keyboard_service_windows.dart:14–80` (sweeps both left/right of Ctrl/Alt/Shift/Win), `frontend/lib/services/keyboard_service.dart:57–59` (macOS side only waits 300 ms).

### The asymmetry

The **Windows** path (rightfully) does two things before the paste:
1. waits ~300 ms for physical release, **then**
2. sends an explicit `KEYEVENTF_KEYUP` sweep for Ctrl / Alt / Shift / Win (both hands) so a still-held modifier (sticky key, slow release, Ctrl+Shift+V hotkey) cannot turn Ctrl+V into Ctrl+Shift+V.

The **macOS** path does **only (1)** — a 300 ms `Future.delayed` in Dart (`keyboard_service.dart:59`) — and then relies solely on:

```swift
let source = CGEventSource(stateID: .combinedSessionState)
...
keyDown.flags = .maskCommand
keyUp.flags = .maskCommand
```

Setting `.flags = .maskCommand` makes the *posted event* declare only Command, but the **physical keyboard state is never normalized**. Because the source is `.combinedSessionState`, the live hardware modifier state is still part of the system's combined state at dispatch time, and apps that read `[NSEvent modifierFlags]` / the current Carbon modifiers while handling the event will still see, e.g., Shift held. The net effects:

- Hotkey **Cmd+Shift+V** (or any custom hotkey containing Shift/Option/Ctrl/§) that hasn't fully released within 300 ms → paste arrives as **Cmd+Shift+V** in apps where that maps to *“Paste and Match Style”* (Safari/Notes/TextEdit/Word), silently changing formatting, or being a no-op elsewhere.
- **Sticky / held Fn or Caps-Lock-Shift** → a phantom modifier rides along.
- After the paste the user's modifier is *still physically down* (we never released it), so the very next input can be misinterpreted.

### Fix — mirror the Windows sweep on macOS

Read the current combined flags, post key-up for each modifier that is actually held (both hands), then post Cmd+V:

```swift
/// Post a Cmd+V keystroke via CGEvent. kVK_ANSI_V == 9.
private func pasteWithCmdV() -> Bool {
  guard let source = CGEventSource(stateID: .combinedSessionState) else {
    debugLog("[Permission] pasteWithCmdV: failed to create CGEventSource")
    return false
  }

  let tap = CGEventTapLocation.cghidEventTap

  // (1) Modifier release sweep — release every modifier that is currently
  //     physically held so it can't combine with Cmd+V (mirrors the Windows
  //     SendInput KEYUP sweep in keyboard_service_windows.dart).
  //     Using both left & right virtual keycodes guarantees the generic flag
  //     is cleared regardless of which side the user holds.
  let held = source.flagsState
  let modifiers: [(flag: CGEventFlags, keys: [CGKeyCode])] = [
    (.maskShift,       [56, 60]), // L/R shift
    (.maskControl,     [59, 62]), // L/R control
    (.maskAlternate,   [58, 61]), // L/R option
    (.maskCommand,     [55, 54]), // L/R command (harmless to release first)
    (.maskSecondaryFn, [63]),     // fn
  ]
  for mod in modifiers where held.contains(mod.flag) {
    for vKey in mod.keys {
      guard let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false) else { continue }
      up.post(tap: tap)
    }
  }

  // (2) The actual Cmd+V.
  guard let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
        let keyUp   = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
    debugLog("[Permission] pasteWithCmdV: failed to create V events")
    return false
  }
  keyDown.flags = .maskCommand
  keyUp.flags   = .maskCommand
  keyDown.post(tap: tap)
  keyUp.post(tap: tap)
  return true
}
```

This brings macOS to parity with Windows. (You can additionally keep the Dart-side 300 ms pre-delay; it's belt-and-braces, but it must not be the *only* defense.)

---

## 3. [High] `AVAudioConverter` tail samples are dropped — no `.endOfStream` flush at stop

**File:** `frontend/macos/Runner/MacAudioCapturePlugin.swift:247–287` (convert) and `:289–305` (stop, which never flushes).

### Analysis of the `consumed`-bool pattern (it is *not* the bug)

The single-buffer pattern in `appendConverted` (`:263–271`):

```swift
var consumed = false
let status = conv.convert(to: outBuffer, error: &error) { _, outStatus in
  if consumed { outStatus.pointee = .noDataNow; return nil }
  consumed = true
  outStatus.pointee = .haveData
  return buffer
}
```

is the **documented** one-shot streaming pattern. Returning `.noDataNow` after the first buffer tells the converter “that’s all for now”, and crucially the converter is a **persistent instance** (`self.converter`, set once at `:228`, reused on every tap callback), so its internal resampler delay-line / phase state is carried across calls. **Samples are therefore NOT dropped mid-stream** — your suspicion of chunked-conversion sample loss does *not* hold here. The capacity math (`ratio * frameLength + 32`) is also adequate for ratio ≤ ~2 and 48 kHz→16 kHz.

### The real loss: the tail

When `stopEngineAndTakePcm()` runs (`:289–305`) it removes the tap, stops the engine, sets `converter = nil` (`:302`) and returns the buffer — **without ever signalling end-of-stream**. A polyphase resampler holds roughly *one filter-tail* worth of samples internally (≈ a few hundred frames, i.e. a few-tens-of-ms of audio at 16 kHz). Those samples are silently discarded on every recording. Whisper pads short clips, so transcription quality is rarely affected, but the *last word of a quick utterance* can be clipped, and the returned byte count is slightly short of the true capture.

### Fix — drain the converter before discarding it

Add a flush step to `stopEngineAndTakePcm`:

```swift
private func stopEngineAndTakePcm() -> Data {
  isRecording = false

  // Capture the destination format used for this session so the flush uses
  // the right one even after the tap is gone.
  let dstFormat = converter?.outputFormat   // AVAudioConverter retains its output format

  if let eng = engine {
    eng.inputNode.removeTap(onBus: 0)
    if eng.isRunning { eng.stop() }
  }
  teardownEngine()

  // Flush resampler tail: tell the converter the stream ended and let it emit
  // whatever it still holds in its delay line.
  if let dstFormat, let conv = (lock; run), let tailBuffer = AVAudioPCMBuffer(pcmFormat: dstFormat, frameCapacity: 4096) {
     flushConverter(converter: conv, into: tailBuffer, dstFormat: dstFormat)
  }

  lock.lock()
  let data = pcmBuffer
  pcmBuffer = Data()
  converter = nil
  lock.unlock()
  return data
}

private func flushConverter(converter: AVAudioConverter,
                            into outBuffer: AVAudioPCMBuffer,
                            dstFormat: AVAudioFormat) {
  // Hand the converter endOfStream with no buffer; it drains internally.
  var flushError: NSError?
  let status = converter.convert(to: outBuffer, error: &flushError) { _, outStatus in
    outStatus.pointee = .endOfStream
    return nil
  }
  guard status != .error, flushError == nil,
        outBuffer.frameLength > 0,
        let ch = outBuffer.int16ChannelData else { return }
  let bytes = Data(bytes: ch[0],
                   count: Int(outBuffer.frameLength) * MemoryLayout<Int16>.size)
  lock.lock()
  pcmBuffer.append(bytes)
  lock.unlock()
}
```

(If `converter.outputFormat` is awkward to retrieve, stash `dstFormat` as a private property in `startEngine` and read it back here — `dstFormat` is already local to `startEngine` today.)

---

## 4. [Medium] Conversion work + `NSLock` on the realtime audio thread

**File:** `frontend/macos/Runner/MacAudioCapturePlugin.swift:234–237` (tap install), `:247–287` (`appendConverted`).

The input tap block executes on AVAudioEngine's **realtime audio render thread**, with hard real-time constraints. Inside it the code:

- acquires `lock` to read `converter` (`:248–251`),
- runs a full `AVAudioConverter.convert(...)` (resampling DSP) **synchronously** on that thread,
- acquires `lock` again to append bytes (`:284–286`).

Locking on the realtime thread is a well-known anti-pattern: `NSLock` is not real-time-safe — a contending holder (e.g. `stopEngineAndTakePcm` on the platform/main thread, or Keychain-adjacent work) triggers priority inversion and audio dropouts/glitches. Doing the resampler math on the audio thread compounds it. Both competing sections are short, so this is *medium*, not severe — but the right architecture is to **copy the buffer and lower-kick the work to a background queue**:

```swift
let workQueue = DispatchQueue(label: "com.beeamvo.audioconv", qos: .userInitiated)

input.installTap(onBus: bus, bufferSize: bufferSize, format: srcFormat) {
  [weak self] buffer, _ in
  guard let self else { return }
  // Shallow but stable copy: PCM buffers handed from the tap are recycled by
  // the engine, so we must copy before crossing threads.
  let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength)
  copy?.frameLength = buffer.frameLength
  if let src = buffer.floatChannelData, let dst = copy?.floatChannelData {
    for c in 0..<Int(buffer.format.channelCount) {
      dst[c].update(from: src[c], count: Int(buffer.frameLength))
    }
  }
  guard let copy else { return }
  self.workQueue.async { self.appendConverted(buffer: copy, dstFormat: dstFormat) }
}
```

The tap callback then does no DSP and takes no lock; all locking/append happens on `workQueue`. (If you prefer to keep it simple and single-threaded, the current design is “acceptable until a glitch is observed”, but it should not ship as-is for a pro-audio-quality product.)

---

## 5. [Medium] Main-thread blocking in method-channel handlers

**File:** `frontend/macos/Runner/MainFlutterWindow.swift:413–452` (permission handler), `:459–479` (`resetAccessibilityEntry`), `:373–398` (launch-at-login handler), `:313–360` (credentials handler).

On macOS, Flutter method-channel calls are dispatched on the **main thread**. The handlers perform real work synchronously:

| Call | Blocking work | Where |
|---|---|---|
| `resetAccessibilityEntry` | `Process().run()` + `task.waitUntilExit()` (spawns `/usr/bin/tccutil`) | `:469–471` |
| `isEnabled` / `enable` / `disable` | `LSSharedFileListCreate` + snapshot + (de)insert (launchd/file I/O) | `:510–606` |
| `read` / `write` / `delete` | `SecItemCopyMatching` / `SecItemAdd` / `SecItemUpdate` (Keychain, may be slow / prompt) | `KeychainCredentials` |

A `tccutil` spawn is easily 50–300 ms; Keychain calls occasionally block waiting for the security daemon. Each stalls the UI thread and can cause spinning/coloured cursor or transient unresponsiveness of the orb.

### Fix — offload to a background queue, hop back to main to invoke `result`

```swift
case "resetAccessibilityEntry":
  DispatchQueue.global(qos: .userInitiated).async { [weak self] in
    let ok = self?.resetAccessibilityEntry() ?? false
    DispatchQueue.main.async { result(ok) }
  }

// For credentials/launchAtLogin, dispatch the synchronous Keychain /
// SMAppService calls to .global(qos:.userInitiated) and call result() on main.
```

`result(...)` can be invoked from a background thread too (Flutter results are thread-safe), but hopping back to main is clearer. This pairs naturally with the other fixes (the `tccutil` call in `resetAccessibilityEntry` becomes *invisible* to the UI).

---

## 6. [Medium] Bundle-ID / identifier inconsistencies

**Files:**
- `MainFlutterWindow.swift:460` — `resetAccessibilityEntry` fallback: `"com.beeamvo.app"`
- `MainFlutterWindow.swift:503` — `getBundleID()` fallback: `"com.beamvo.Beeamvo"`  ← **wrong** (missing "e")
- `MainFlutterWindow.swift:19` — Keychain `service = "com.beamvo.Beeamvo.credentials"`
- `MainFlutterWindow.swift:20` — legacy App Support subdir `directory = "com.beamvo"`
- `AppInfo.xcconfig:8` — real `PRODUCT_BUNDLE_IDENTIFIER = com.beeamvo.app`
- `secure_credential_store.dart:20` ↔ `MainFlutterWindow.swift:309` — channel `com.beamvo/keychain_credentials` (these two *match each other*, so the channel works)

### What is and isn't a bug

- **`getBundleID()` fallback (`:503`) is simply wrong.** The product id is `com.beeamvo.app`, not `com.beamvo.Beeamvo`. In practice `Bundle.main.bundleIdentifier` is always populated for a real `.app`, so this fallback rarely fires. Its only consumer today is the cosmetic *display name* passed to `LSSharedFileListInsertItemURL` (`:588`) — and login-item matching is URL-path based, not id based. So today it's cosmetic. **But it is a latent footgun:** any future code that trusts `getBundleID()` for a real TCC/identifier comparison will silently mis-scope to the wrong app. Also: `getBundleID()` disappears if you adopt Finding 1's `SMAppService` migration.
- **`tccutil` fallback (`:460`) is correct** (`com.beeamvo.app`) ✓.
- **Keychain `service` (`:19`)** is a stable namespace string. It does **not** need to equal the bundle id, and it is internally self-consistent. **However**, the string is inconsistent with the channel + bundle convention and reads like copy-paste drift; it's safe but confusing for your future self.
- **Legacy `directory = "com.beamvo"` (`:20`)** is the old plaintext store path — kept only for one-time migration. Understandable, but double-check there's no live WRITES to it after migration (there shouldn't be — `saveLegacyStore` is only called from `removeLegacyValue`, and that path is exercised only during migration). If migrations have shipped, do **not** change this string, or you'll strand unmigrated plaintext credentials.

### Recommended cleanup

```swift
// Single source of truth — matches AppInfo.xcconfig.
private static let bundleID = "com.beeamvo.app"     // or Bundle.main.bundleIdentifier!
// resetAccessibilityEntry fallback:        bundleID                 (already correct)
// getBundleID():                           DELETE (gone with SMAppService)
// Keychain service: keep "com.beamvo.Beeamvo.credentials" (do NOT rename post-ship)
//                                   — but add a comment that it's a legacy namespace,
//                                     deliberately distinct from the bundle id.
```

Add a `tccutil`/identifier unit test that asserts the in-binary fallback string equals `PRODUCT_BUNDLE_IDENTIFIER`. (There's already `frontend/test/macos_tcc_reset_test.dart` referencing `com.beeamvo.app` — extend it.)

---

## 7. [Low] Deprecated `Process.launchPath`

**File:** `MainFlutterWindow.swift:462` — `task.launchPath = "/usr/bin/tccutil"`

`launchPath` is deprecated since macOS 10.13; with a 13.0 deployment target it always warns. Prefer `executableURL`:

```swift
task.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
```

---

## 8. [Low] Force-unwrap of the Application Support directory

**File:** `MainFlutterWindow.swift:26`

```swift
let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
```

Practically `applicationSupportDirectory` is always present on macOS, so this won't crash — but it is an unevaluated `!` in a credentials-management class. Replace with a defensive `guard` that logs and returns `nil` up the chain (callers already tolerate missing data via the legacy-store fallthrough):

```swift
private var fileURL: URL? {
  guard let appSupport = FileManager.default.urls(
          for: .applicationSupportDirectory, in: .userDomainMask).first
  else {
    debugLog("[KeychainCredentials] Application Support dir unavailable")
    return nil
  }
  return appSupport.appendingPathComponent(directory).appendingPathComponent(filename)
}
```

Then thread the optionality through `loadLegacyStore`/`saveLegacyStore`.

---

## 9. [Low] Non-atomic `isRecording` across threads

**File:** `MacAudioCapturePlugin.swift:25` (field), read/written at `:48`, `:99`, `:241`, `:290`, `:309`.

`isRecording` is a plain `Bool` touched from the method-channel handler (main thread) and, indirectly, reasoned about against the audio thread. Swift does not guarantee atomicity for plain `Bool` reads/writes; concurrent `start`/`stop` is currently prevented only by the assumption that main-thread method calls never overlap (true for a single channel, but fragile). Options:

- Move all read/write of `isRecording` behind a small lock, or
- Declare `private static let stateQueue = DispatchQueue(label: ...)`, wrapping access (combine with Finding 4's `workQueue`), or
- Declare it `@unchecked private var` and access via `lock`.

Practically low (single channel ⇒ serialized calls), but it's the first thing to blame if a "start while stopping" race ever appears.

---

## 10. [Low] `startEngine` error path leaks the tap / leaves `converter` set

**File:** `MacAudioCapturePlugin.swift:234–245` (install tap + start), `:126–139` (catch), `:307–310` (teardownEngine).

Sequence on failure: tap is installed (`:234`) → `converter` written under lock (`:228`) → `newEngine.start()` throws (`:239`) before `self.engine` / `isRecording` are set. The catch calls `teardownEngine()`, which sets `self.engine = nil` — but `self.engine` was **never assigned** (the local `newEngine` is the one that failed), so the tap on `newEngine` is only reclaimed when the local is dealloced (ARC + AVAudioEngine deinit), and `self.converter` is left referencing the dead converter until the next `start`.

Fix — make the failure path explicit: remove the tap from `newEngine` and nil `converter` before throwing/returning the error:

```swift
do {
  try startEngine(deviceUID: preferredDeviceUID)
  result(true)
} catch {
  teardownFailedEngine()
  result(FlutterError(code: "start_failed", /* ... */))
}

private func teardownFailedEngine() {
  lock.lock(); converter = nil; pcmBuffer = Data(); lock.unlock()
  isRecording = false
  if let eng = engine { eng.inputNode.removeTap(onBus: 0); eng.stop(); engine = nil }
}
```

(If `startEngine` is refactored to own its own cleanup on throw, even better.)

---

## 11. [Low] Output buffer capacity margin is thin

**File:** `MacAudioCapturePlugin.swift:253–254`

```swift
let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 32
```

`+32` frames covers typical converter phase rounding but is small; an unusual src/dst ratio or a large tap `frameLength` could in principle ask the converter for more output than capacity, forcing it to return an error or a truncated frame (`.inputRanOut`). Low because the ratios in play (48k/44.1k → 16k) are well-behaved, but bumping the headroom to e.g. `+ 256` and clamping to a sane floor:

```swift
let requested = Double(buffer.frameLength) * ratio
let capacity = max(4096, AVAudioFrameCount(requested) + 256)
```

is cheap insurance.

---

## 12. [Low / Nit] `awakeFromNib` calls `super` last

**File:** `MainFlutterWindow.swift:302` — `super.awakeFromNib()` is invoked at the very end of the override. Convention (and safety with future AppKit changes) is to call `super` first. Reorder so `super.awakeFromNib()` is the first statement.

---

## 13. [Info — no action required] Keychain accessibility class

**File:** `MainFlutterWindow.swift:124` — `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`.

This is a **reasonable, intentional** choice for a voice-to-text menu-bar app:

- `ThisDeviceOnly` ⇒ items are excluded from iCloud Keychain and device-to-device restore — appropriate for private API keys you don't want replicated.
- `AfterFirstUnlock` ⇒ readable by background processes after the first post-boot unlock, even while the screen is later locked. Crucially, **launch-at-login fires after the user logs in (post-unlock)**, so a `com.beeamvo.app` launched at login can always read its Gemini/Vertex keys. The "not available until first unlock" caveat is irrelevant for a user-session app.
- If you ever support a true pre-login daemon mode, switch to `…AccessibleWhenUnlocked` semantics review. No change needed today.

---

## 14. [Info — no action required, with rationale] Entitlements & Info.plist correctness

### Entitlements (`DebugProfile.entitlements`, `Release.entitlements`)
- `com.apple.security.app-sandbox = false` (both) — **intentional and required**. The app needs to (a) spawn `/usr/bin/tccutil` via `Process` and (b) post global `CGEvent`s — both impossible under the sandbox. ⚠️ If a future finding re-introduces sandboxing, the `tccutil reset` path and the CGEvent paste path will both break.
- `com.apple.security.device.audio-input = true` ✓ (needed even without sandbox for the mic permission UX).
- `com.apple.security.network.client = true` ✓ (cloud transcription / Vertex / Gemini / update check).
- `com.apple.security.cs.allow-jit = true` (Debug only) ✓ (whisper.cpp/ggml can JIT on debug builds).
- **`com.apple.security.automation.apple-events` is correctly absent** — the CGEvent paste path injects HID events directly and needs only Accessibility, **not** Automation/Apple Events. Do not add it unless you reintroduce an osascript / `tell application` fallback.

### `Info.plist`
- `NSMicrophoneUsageDescription` ✓ present (`:31–32`).
- `LSUIElement = true` ✓ (`:33–34`) — accessory/background mode; consistent with `AppDelegate.applicationShouldTerminateAfterLastWindowClosed → false`. Compatible with `SMAppService.mainApp` (Finding 1).
- `NSAppleEventsUsageDescription` correctly **absent** (see entitlements note). If `openAccessibilitySettings` were ever replaced by an Apple-Events deep link, you'd need it — the current `x-apple.systempreferences:` URL scheme does **not** require it.
- `CFBundleIconFile = ""` (`:9–10`): fine — modern macOS resolves icons from the `Assets.xcassets/AppIcon.appiconset` asset catalog.
- Consider adding `LSApplicationCategoryType` (e.g. `public.app-category.productivity`) for cleaner App Store / Spotlight classification. Nit only.

---

## 15. [Info — cleanup opportunity] `record_macos` is registered but bypassed at runtime

**File:** `frontend/macos/Flutter/GeneratedPluginRegistrant.swift:13` (`import record_macos` … `register`), with the macOS runtime path routed entirely through `MacAudioCapturePlugin` (`recording_service.dart:42` → `_useMacNativeCapture => Platform.isMacOS`).

Functionally harmless (the plugin is initialized but never invoked on macOS), but it ships native code, adds to startup, and is a standing source of the exact "empty WAV" race the native plugin was written to avoid. Consider gating `record` to non-macOS in `pubspec.yaml` so `record_macos` is not compiled into the macOS build. (Out of scope for the .swift review, but flagged for completeness.)

---

## Suggested fix order

1. **Finding 1** (SMAppService) — removes deprecated API, fragile CF memory handling, and the wrong bundle-id fallback in one move; highest leverage given the 13.0 floor.
2. **Finding 2** (modifier sweep) — tightens the core "voice → paste" happy-path on macOS; small, self-contained change.
3. **Finding 3** (AVAudioConverter flush) — stops silently dropping the last few ms of every recording; one new method.
4. **Finding 5** (background-thread handlers) — removes main-thread stalls; pair with Finding 1.
5. **Finding 4, 10, 11** (audio-thread / error-path hygiene) — harden the capture pipeline.
6. Findings 6–9, 12 — hygiene pass.

---

## Appendix — channel-name / identifier map (verified)

| Identifier | Value | Location | ✓/✗ |
|---|---|---|---|
| Product bundle id | `com.beeamvo.app` | `AppInfo.xcconfig:8`, `project.pbxproj` | — (source of truth) |
| Window channel | `beeamvo/window` | `MainFlutterWindow.swift:240` | ✓ matches Dart |
| Credentials channel | `com.beamvo/keychain_credentials` | `:309` ↔ `secure_credential_store.dart:20` | ✓ (both sides agree) |
| Launch-at-login channel | `beeamvo/launch_at_login` | `:369` | ✓ |
| Permission channel | `beeamvo/permission` | `:409` ↔ `macos_permission_service.dart:18` | ✓ |
| Audio channel | `com.beeamvo/mac_audio_capture` | `MacAudioCapturePlugin.swift:19` ↔ `recording_service.dart:20` | ✓ |
| Whisper channel | `com.beeamvo/whisper` | `WhisperPlugin.swift:27` ↔ `whisper_service.dart:10` | ✓ |
| Keychain service | `com.beamvo.Beeamvo.credentials` | `MainFlutterWindow.swift:19` | ⚠ legacy namespace (safe, but inconsistent) |
| `getBundleID()` fallback | `com.beamvo.Beeamvo` | `:503` | ✗ wrong (cosmetic only) |
| `tccutil` bundle id fallback | `com.beeamvo.app` | `:460` | ✓ correct |
