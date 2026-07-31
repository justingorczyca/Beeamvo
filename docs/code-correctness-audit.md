# Code Correctness Audit — Task 4 of 7

> **Scope.** A comprehensive **code-quality and correctness** review of the Beeamvo
> Flutter/Dart application and its native platform integrations, with **targeted,
> evidence-backed remediation** and **focused regression tests**. It preserves the
> Task-1 baseline (`docs/release-baseline-audit.md`), the Task-2 security remediations
> (`docs/security-privacy-audit.md`), and the Task-3 supply-chain changes
> (`docs/open-source-supply-chain-audit.md`). It deliberately does **not** modify CI
> workflows, packaging/signing, perform broad stylistic refactors, dependency upgrades,
> or broad documentation synchronization.
>
> **Method.** Every Dart file under `frontend/lib` and `frontend/test` was read
> end-to-end, every called-out audit area was traced to its implementation, and the
> declared commands were executed on the host. Claims are evidence-backed with file
> paths and (where useful) line numbers. Native (Swift/C++) code was reviewed at the
> source level; where it could not be compiled/executed on this Windows host that
> limitation is stated explicitly.

---

## 1. Executive Summary

The Beeamvo Dart application is **well-engineered and defensively written**: the
recording/transcription state machine is guarded against re-entrancy and superseding
transitions (session tokens, lock flags, serialized backend-transition queues), cloud
clients apply timeouts + result guarding + body-suppression, persistence is
crash-safe (atomic write + `.bak`/`.tmp` recovery), and the native Whisper plugins
honour cancellation via atomic flags + `abort_callback`. Analysis is clean and the full
test suite passes.

**One confirmed correctness defect was found and fixed**, with a regression test:

- **C1 — `SettingsService.durationLimit` was read unclamped.** The recording start path
  builds `Timer(Duration(seconds: limitSeconds))` directly from the getter
  (`main.dart:1333-1334`). The duration-limit dialog enforces `[5, 3600]`
  (`general_settings_page.dart:999-1002`) but `SettingsService` did **not** clamp the
  persisted value — unlike its sibling `clipboardHistoryMaxItems`, which already clamps
  to `[10, 200]` (`settings_service.dart:591-592`). A corrupt, hand-edited, or
  pre-clamp `duration_limit` of `≤ 0` would arm a zero-duration timer that **stops a
  recording the instant it starts** once auto-stop is enabled. **Fix:** clamp the getter
  and setter to `[5, 3600]` via a pure, tested `clampDurationLimit` helper
  (`settings_service.dart`). Regression test: `test/settings_duration_limit_test.dart`.

No other code changes were made. 36 pre-existing-format Dart files were deliberately
**left unformatted** (see §6) to preserve the working tree and avoid broad stylistic
churn; this is a documented finding/recommendation for the CI/build phase.

**Verdict:** the application is correct and release-eligible at the source level after
this one targeted fix. Residual risks are limited and enumerated in §7.

---

## 2. Environment & Validation Commands (with outcomes)

Host: **Windows**, Flutter **3.44.2** (stable), Dart **3.12.2** (stable, x64).
All commands run from `frontend/`.

| # | Command | Outcome |
|---|---|---|
| 1 | `flutter pub get --enforce-lockfile` | **OK** — `--enforce-lockfile` accepted; `pubspec.lock` consistent, no resolution drift (27 outdated bumps noted but untouched). |
| 2 | `dart format --set-exit-if-changed lib test` | **36 of 91 files not canonical-format** (pre-existing; CI does not enforce formatting). See §6. Files actually changed in this task are formatter-clean. |
| 3 | `flutter analyze` | **No issues found!** (ran in ~3.5s) |
| 4 | `flutter test` (**before** changes) | **147 tests passed** — baseline confirmed (matches Task-2 state). |
| 5 | `flutter test` (**after** fix + new test) | **151 tests passed** (147 + 4 new), exit 0. |

> The same `analyze` + `test` steps are exactly what `.github/workflows/ci.yml`
> (`analyze-and-test` job, ubuntu-latest) executes; the Windows host reproduces them
> and they are platform-independent (pure Dart unit/widget tests, no native device runs).

### Native build / platform execution — limitation
The Whisper native plugins and platform runners were reviewed at the **source level**
(`frontend/{windows,macos,linux}/runner/whisper_plugin.{cpp,m,cc}`, method-channel
contract, cancellation, locking) but **not compiled or executed** on this host (no Xcode
toolchain; a native `flutter build` requires the platform C++ SDK + Build Tools and, on
Windows/Linux, network access to fetch whisper.cpp via CMake `FetchContent`). The CI
build matrix (macos-latest, windows-latest) is the authoritative native-compile gate;
this audit's source-level review of the native layers is consistent with that CI.

---

## 3. Audit Areas — Findings

Format: **Area → result.** "Reviewed, clean" means the path was traced and found
correct/defensive; no change required. File:line references are to the current tree.

### 3.1 Recording lifecycle & state transitions — clean
`main.dart` `_BeeamvoHomeState` guards every public transition with `_isLockActive`,
`_sessionToken`, `_activeRecordingBackend` (pinned at start), and a serialized
`_backendTransitionQueue`/revision. `_showSettings`/`_cancelRecording`/`_abortStartedRecorder`
tear down the recorder, session-scoped Enter/Escape hotkeys, and the duration-limit timer.
`RecordingService` retries once with the system-default mic on a failed device start and
best-effort-stops the recorder on every failure path so a failed start never leaves the
microphone hot (`recording_service.dart:136-170`, `382-418`, `483-489`). Stream vs file
capture is resolved from the **actual** capture mode at stop time (`main.dart:1550-1558`).

### 3.2 Hotkeys — clean
`HotkeyService` serializes register/unregister per-id through a non-throwing future chain
and detects cross-hotkey conflicts **before** any mutation; the internal map is updated
only after a successful `HotKeyManager.register` so a failure leaves no stale entry
(`hotkey_service.dart:106-165`). Session-scoped Escape/Enter are `system` scope
(delivered through the OS keyboard hook) so they fire while the orb is shown without
focus (`main.dart:1345-1372`); they are unregistered in every stop/cancel/abort path.

### 3.3 Tray / window behaviour — clean
`TrayService` gates prompt/rephraser menu items by `isPromptInactiveOnLocalBackend` and
offers cloud-switch actions; all click handlers are fire-and-forget `.then(...)` so a UI
handler is never blocked (`tray_service.dart`). `WindowHelper`/platform variants use
`SW_SHOWNOACTIVATE` to show the orb without stealing focus; macOS hides via native alpha
with an off-screen fallback; Linux computes the cursor's display for positioning
(`window_helper*.dart`). Stubs throw `UnsupportedError` cleanly (`window_helper_stub.dart`).

### 3.4 Transcription backend resolution & fallback — clean
`resolveSessionBackend` honours a per-prompt override over the global default, centralizing
the decision so start/stop agree (`transcription_backend_resolver.dart`). The session
**pins** the resolved backend in `_activeRecordingBackend`; retry intentionally resolves
fresh (`main.dart:1501-1504`). Legacy `transcriptionBackend: 'gemini'` values (per-prompt)
gracefully resolve to `cloud` via `TranscriptionBackendExtension.fromValue` (anything not
`whisper` → `cloud`), so no migration hazard.

### 3.5 Local Whisper invocation & native channels/FFI — clean (source-level)
`WhisperService` wraps `MethodChannel('com.beeamvo/whisper')` with `init`/`transcribeRaw`/
`cancel`/`cleanup`. Disposal is terminal and race-aware: an `init` that completes after
`dispose()` releases the just-created native model instead of reviving the notifier
(`whisper_service.dart:346-377`, `466-472`). Native plugins (Windows `whisper_plugin.cpp`,
macOS `WhisperPlugin.m`) both: guard concurrent transcriptions with a `busy` flag, protect
the context with a mutex/lock, honour `cancel` via an atomic `cancel_requested_` +
`whisper_full` `abort_callback` (returning `""` on cancel/error, which the Dart
result-guard maps to "Nothing was transcribed"), cap thread counts, and convert PCM-16LE
to float32 first-channel-only. **(Linux `whisper_plugin.cc` mirrored for the same contract;
not compiled here.)**

### 3.6 Gemini / Vertex clients — clean
Both clients decode defensively (`is`/`is!` guards, never raw `as` casts), suppress raw
upstream bodies from user-facing messages (logging only in `kDebugMode`), and throw typed
`CloudTranscriptionException`s with actionable copy (`gemini_api_service.dart:285-349`,
`vertex_ai_service.dart:424-507`). `CloudTranscriptionService` always initializes lazily
and guards `attachSettings`/`dispose`/`_ensureNotDisposed`.

### 3.7 Cancellation / timeouts / retries — clean
- Cloud: every outbound request is wrapped in `.timeout(60s)`; Vertex recycles the cached
  ADC client and **retries exactly once** on 401/403 with a generation guard that closes an
  in-flight client superseded by a recycle/dispose (`vertex_ai_service.dart:130-175`,
  `439-466`). Gemini has no equivalent auto-retry — by design (single key, no token refresh).
- Inline-payload size pre-checks (`maxInlineRequestBytes = 20 MiB`) fail fast before the
  network for both providers.
- Whisper: best-effort cancellation channel + 2s `stopStreamAndGetPcm` done-completer
  timeout; empty/error buffers are discarded (`recording_service.dart:429-465`).
- Model download: 30s request timeout, 2m idle-stream timeout, size cap per model, SHA
  verification, idempotent `_cleanup` shared by cancel/dispose
  (`whisper_model_download_service.dart`).

### 3.8 Result guarding — clean
`TranscriptionResultGuard` (350 ms minimum duration; `[NO_TRANSCRIPT]`/empty → exception)
is applied on the audio transcription path and the Whisper raw-transcript path
(`cloud_transcription_service.dart:129,145`; `main.dart:1567,1642,1673`). Text-only
`improveTranscription` is intentionally unguarded because the underlying
`_postGenerateContent` already throws on an empty candidate response, so an empty
improvement cannot leak to the clipboard.

### 3.9 Settings serialization / migrations — clean (C1 is the only fix)
`SettingsService` loads with live → `.bak` → `.tmp` → empty recovery; writes are serialized
on a `_saveQueue` whose chain survives single-write errors and each write is atomic
(temp + `.bak` + rename) (`settings_service.dart:121-183`). Typed accessors use `is` guards
so mistyped JSON cannot throw. `_migrateModels` always materializes a valid
`selected_model_id` and clears stale two-pass overrides; `_migrateCloudSettings` maps legacy
`gemini` → `cloud`.

### 3.10 Credential references — clean
API keys flow only through `SecureCredentialStore` (Keychain channel on macOS,
`flutter_secure_storage` elsewhere) and travel only in the `x-goog-api-key` header; Vertex
uses ADC with no stored secret. `.env` is a dev-only convenience, **disabled in release
builds** (`config.dart:198-211`). Env reads are trimmed and treated as documentation-only.

### 3.11 Clipboard / history — clean
Clipboard history + watcher default **off** for new users (privacy-safe); the watcher polls
every 1.2 s and applies `shouldSkipClipboardHistoryText` (best-effort bearer/token/PEM
filter) before persisting. History trims non-pinned to `[10,200]` and `clipboardHistoryMaxItems`
is clamped. (Best-effort filtering is a documented security residual, not a correctness bug.)

### 3.12 Onboarding / permissions — clean
First-run onboarding is gated on `!isOnboardingComplete && !hasGeminiApiKey`; existing
users with credentials are silently marked complete. macOS returning users get a single
native Accessibility nudge; first-run users get the guided dialog (no double nudge)
(`main.dart:415-424`). `MacOsPermissionService` and `scopedTccutilArgs` (Task-2
additions) reset only this app's bundle id and fail safe on empty ids.

### 3.13 Model download state — clean
`WhisperModelDownloadService` is a `ChangeNotifier` with a cancellation-aware lifecycle:
`cancelAndDispose` is awaited by page teardown, downloads reject unknown/unsafe model ids
and out-of-dir target paths before any network access, and `dispose()` is idempotent and
closes the scoped HTTP client. Covered by existing `whisper_*` tests.

### 3.14 Update checks — clean
`UpdateCheckService` is fully best-effort (swallows network/parse errors), closes its
scoped client in `finally`, and distinguishes `UpdateCheckResult.succeeded` from a (valid)
"up to date" so a transient failure is **not** consumed against the 24 h rate-limit
(`update_check_service.dart:89-133`, `main.dart:448-469`). Version comparison is a strict
3-component numeric increase after normalizing leading `v` and stripping `-pre`/`+build`.
*(Note: the version helpers have no unit tests — see §7 test-coverage notes.)*

### 3.15 Error propagation — clean
Recording/transcription failures surface recoverable, user-facing messages; a cloud failure
with a retained audio file is retriable; every `setState` is `mounted`-guarded; onboarding
completion cannot deadlock (`_onboardingCompletion` is also completed in `_shutdownServices`).

### 3.16 Concurrency / races — clean
Re-entrancy (`_isLockActive`), superseding transitions (`_sessionToken`, backend
`_backendTransitionRevision`), serialized writes (`_saveQueue`), per-id hotkey locks,
coalesced Vertex ADC client creation with generation validation, and the `busy`-guarded
native transcribe all prevent the observed interleavings from corrupting state.

### 3.17 Disposal / resource leaks — clean
`_BeeamvoHomeState.dispose` → `_shutdownServices` stops/hotkey-unregisters/disposes the
recorder, whisper, hotkey, cloud, and tray services and cancels all timers. HTTP clients
are scoped and closed. `cancelAndDispose` for downloads awaits cleanup. `VertexAiService`
closes superseded ADC clients. No unawaited-Future/non-closed-client leak observed.

### 3.18 Platform stubs — clean
`keyboard_service_stub.dart` / `window_helper_stub.dart` throw `UnsupportedError` (never
return a misleading success), compiled in on non-FFI/non-Windows targets. Platform
`dart:io` `Platform.is*` branches are exhaustive (Windows/macOS/Linux else-fallback).

### 3.19 Null / error handling — clean
`late` fields are assigned before any await that reads them (`_file` in
`SettingsService.initialize`, `_stats` `late File`). Typed accessors default instead of
throwing. Native return values are null-coalesced (`ok ?? false`, `text ?? ''`).

---

## 4. Confirmed Defects & Fixes

### C1 (Fixed) — Recording auto-stop `durationLimit` read unclamped
- **Evidence (read path):** `main.dart:1332-1342` arms
  `_durationLimitTimer = Timer(Duration(seconds: _settingsService.durationLimit), …)`
  but `SettingsService.durationLimit` previously was
  `_getInt(_kDurationLimit, defaultValue: 300)` with **no clamp**.
- **Evidence (UI contract):** the duration-limit dialog validates `5 ≤ v ≤ 3600`
  (`general_settings_page.dart:996-1007`).
- **Evidence (parallel guard):** the sibling numeric setting is already guarded —
  `clipboardHistoryMaxItems` clamps to `[10, 200]` (`settings_service.dart:591-592`).
  The duration-limit clamp is the missing parallel.
- **Impact:** if `duration_limit` in `settings.json` is `≤ 0` (corrupt write / manual
  edit / pre-clamp value) **and** auto-stop is enabled, `Timer(Duration(seconds: 0))`
  fires on the next event-loop tick and immediately calls `_stopRecordingAndProcess`,
  making recording unusable. An absurdly large value would allow an effectively unbounded
  recording.
- **Fix (minimal, mirrors existing pattern):** added `minDurationLimitSeconds` (5),
  `maxDurationLimitSeconds` (3600) constants and a pure `clampDurationLimit(int)` helper;
  the getter now returns `clampDurationLimit(_getInt(...))` and the setter normalizes via
  the same helper (`frontend/lib/services/settings_service.dart`). Single source of truth,
  int-typed, behaviour-preserving for all in-range values.
- **Regression test:** `frontend/test/settings_duration_limit_test.dart` (4 tests):
  getter default + static clamp of 0/negative/over-max → bounds, in-range preservation,
  and a bounds-drift lock test.

No other defects found.

---

## 5. Test Coverage Added

| File | Tests | Covers |
|---|---|---|
| `frontend/test/settings_duration_limit_test.dart` | 4 | C1 clamp on the recording auto-stop value (helper clamp semantics, in-range passthrough, default, UI-contract bounds drift). |

Suite: **147 → 151 passing**, plus `flutter analyze` clean. The new tests follow the
established, no-I/O pattern (`SettingsService()` in-memory defaults + pure static helper,
identical to `settings_service_privacy_test.dart`).

*Inspection also identified two low-risk, currently-uncovered critical-path helpers
(`UpdateCheckService` version comparison; `RecordingService.extractMono16kPcmFromWav`
beyond the existing success-case test). The version helper is correct and would require
new `@visibleForTesting` seams to unit-test (no HTTP seam exists); per the "minimal
changes / no speculative test scaffolding" guidance these are recorded as coverage
recommendations (§7) rather than changed here.*

---

## 6. Formatting / Lockfile Consistency (checked, not bulk-changed)

- **Lockfile:** `flutter pub get --enforce-lockfile` succeeds → `pubspec.lock` is
  consistent with `pubspec.yaml`; no dependency versions changed.
- **Formatting:** `dart format --set-exit-if-changed lib test` reports **36 / 91** Dart
  files are not currently canonical-format (a **pre-existing**, project-wide condition;
  the project's `CI` only runs `analyze` + `test`, not a format gate). To **preserve the
  working tree and avoid a broad stylistic churn** (against the task directive), I did
  **not** bulk-reformat; the two files I authored/edited (`settings_service.dart`,
  `settings_duration_limit_test.dart`) are verified formatter-clean. **Recommendation
  (CI/build phase):** add `dart format --set-exit-if-changed` to the `analyze-and-test`
  job so formatting drift is caught at PR time rather than bundled into a future change.

---

## 7. Residual Risks & Recommendations (no action taken this phase)

1. **(Coverage)** Add unit coverage for `UpdateCheckService` version normalization/comparison
   (introduce `@visibleForTesting` static entry or an injectable HTTP client) and for
   `RecordingService.extractMono16kPcmFromWav` truncation/odd-edge cases. Low risk; the
   underlying logic reviewed here is correct.
2. **(Quality, CI/build)** Adopt `dart format --set-exit-if-changed` in CI (§6).
3. **(Native)** The macOS/Linux native runners were source-reviewed but not compiled here;
   the CI build matrix remains the authoritative native-compile gate.
4. **(Hardening, optional)** `macos_tcc_reset`/`gcloud`/`xdotool` external-tool invocations
   rely on absolute paths or PATH lookups scoped by feature flags — already documented in
   the security audit; no change warranted here.
5. **(Settings)** Other numeric settings (`two_pass` model ids) are migration-validated, not
   range-clamped, because they are enums/ids rather than magnitudes — no defect.

None of the above block source-level release after C1.

---

## 8. Release Recommendation

**Source-level release: APPROVED after the C1 fix.** Analysis is clean, all 151 tests pass,
the lockfile is consistent, and the one confirmed correctness defect is minimally fixed and
covered by a regression test. Native binaries (#3) must still be validated by the CI build
matrix / packaging phase (no native toolchain on this host). No CI, packaging/signing,
dependency, or broad-doc changes were made.

---

## 9. Files Changed (exact)

| Path | Status | Reason |
|---|---|---|
| `frontend/lib/services/settings_service.dart` | **modified** | C1 fix: clamp `durationLimit` to `[5,3600]` (getter + setter) via pure `clampDurationLimit` helper + bounds constants. |
| `frontend/test/settings_duration_limit_test.dart` | **added** | C1 regression test (4 tests). |
| `docs/code-correctness-audit.md` | **added** | This document. |
| `docs/release-baseline-audit.md` | **modified** | Task-4 status note (new C1 row + residual/coverage notes). |

*(All Task-1/2/3 changes — junk/gitlink removal, `pinned_http_client.dart` TLS simplification,
THIRD_PARTY_NOTICES license corrections, `macos_tcc_reset.dart` + tests, etc. — are preserved
unchanged in the working tree.)*

### Validation outcomes (final)
```
flutter pub get --enforce-lockfile              -> exit 0 (lockfile consistent)
flutter analyze                                 -> "No issues found!" (exit 0)
flutter test                                    -> 151 passed (exit 0)  (was 147)
dart format --set-exit-if-changed (2 changed files) -> formatter-clean (0 changed)
dart format --set-exit-if-changed lib test      -> 36/91 pre-existing non-canonical (exit 1) — documented, not bulk-changed
```
