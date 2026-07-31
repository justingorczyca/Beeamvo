# Security & Privacy Audit — Task 2 of 7

> **Scope.** Deep security & privacy review of the entire Beeamvo application
> (Dart app + native code + platform manifests), with remediation of confirmed
> issues that can be fixed safely **without redesigning product behaviour**, plus
> regression tests where practical. This pass builds on the Task-1 baseline
> (`docs/release-baseline-audit.md`), which is referenced for items B1–B13. It
> does **not** touch general README/CHANGELOG synchronisation, supply-chain
> licensing, CI expansion, or unrelated cleanup.
>
> **Method.** Findings are evidence-backed with repository paths/line numbers.
> All security-relevant areas named in the task brief were inspected (see §1).
> Claims that could not be confirmed from the tree are omitted. Static analysis
> (`flutter analyze`) and the full test suite (`flutter test`) were run before and
> after remediation (see §6).

---

## 1. Methodology & Coverage

The following areas were inspected directly (Dart under `frontend/lib`, native
code under `frontend/{windows,macos,linux}/runner`, platform manifests), in the
order listed in the task brief:

| # | Area | Primary evidence reviewed | Outcome |
|---|------|---------------------------|---------|
| 1 | API keys & secure storage / migration | `services/secure_credential_store.dart`; `macos/Runner/MainFlutterWindow.swift` (`KeychainCredentials`); `config.dart` (dotenv handling) | ✅ Sound; one minor residual (§5.1) |
| 2 | Logging & error messages | `gemini_api_service.dart`, `vertex_ai_service.dart`, `recording_service.dart`, `MainFlutterWindow.swift`, whisper plugins | ✅ Sound; one minor residual (§5.4) |
| 3 | Recording/audio lifecycle & temp-file deletion | `recording_service.dart`; `main.dart` stop/abort/cancel/cleanup paths | ✅ Sound |
| 4 | Clipboard/history persistence | `settings_service.dart` (`shouldSkipClipboardHistoryText`); `main.dart` (`_pollClipboardText`) | ✅ Sound; plaintext disclosure documented |
| 5 | Usage telemetry / update checks | `usage_stats_service.dart`; `update_check_service.dart`; `main.dart` (`_performBackgroundUpdateCheck`) | ✅ Sound (all local; best-effort) |
| 6 | Gemini/Vertex/cloud data flows & consent | `gemini_api_service.dart`, `vertex_ai_service.dart`, `cloud_transcription_*`, `prompt_cloud_switch_dialog.dart`, `mode_cloud_confirm_popup.dart` | ✅ Sound (consent + injection guard) |
| 7 | Endpoint construction & redirects | `gemini_api_service._buildUri`; `vertex_ai_service.buildUri` + `isValidVertexProjectId`; `update_check_service._api`; `whisper_model_download_service` URLs | ✅ Sound |
| 8 | HTTP/TLS behaviour & pinned client | `pinned_http_client.dart`; 3 call sites | 🔧 **Fixed (§3.1)** |
| 9 | Model & update downloads, integrity, path traversal | `whisper_model_download_service.dart`; `whisper_service.dart` (path validation); native plugin FFI | ✅ Sound |
| 10 | Process execution | `widgets/settings/pages/troubleshooting_page.dart` (`_resetPermissions`); `MainFlutterWindow.swift` (`resetAccessibilityEntry`) | 🔧 **Fixed (§3.2)** |
| 11 | Permissions / entitlements | `macos/Runner/Release.entitlements`, `DebugProfile.entitlements`, `Info.plist` | ⚠️ Residual (§5.2) |
| 12 | Local settings | `settings_service.dart` (atomic save/load, `.bak` recovery) | ✅ Sound |
| 13 | Prompt-injection / data-disclosure boundaries | `models/system_prompt.dart`; `transcription_result_guard.dart` | ✅ Sound |
| 14 | Native FFI / memory handling | `windows/runner/whisper_plugin.cpp`; `macos/Runner/WhisperPlugin.swift`; `keyboard_service_windows.dart` | ✅ Sound |
| 15 | Secret scanning | repo-wide grep for common secret shapes; `.env.example` | ✅ No secrets |
| 16 | Unsafe defaults | `config.dart` defaults; settings defaults | ✅ Sound |

Static tooling run (see §6 for full output):
- `flutter analyze` → **No issues found** (before and after changes).
- `flutter test` → **147 tests pass** (141 baseline + 6 new from this audit; no regressions).
- Secret scan: `AIza…`, `sk-live…`, `xox…`, `glpat-…`, `AKIA…`, `ghp_…`,
  `github_pat_…`, `-----BEGIN … PRIVATE KEY-----`, `password =` → **no matches** except
  in the redaction regex inside `settings_service.dart` (the *defence*, not a leak).

---

## 2. Confirmed Issues Found

### 2.1 (Fix F1) Misleading TLS “certificate pinning” — security theatre + an active fail-open footgun
**Severity:** Medium (privacy/integrity of all cloud traffic; dormant, not exploited today).

The shipped TLS module was named and documented as a certificate-pinning
infrastructure. Two facts made that claim false and, in one state, actively
harmful:

1. **Pinning could never enforce fail-closed behaviour.** Dart's
   `HttpClient.badCertificateCallback` is only invoked *after* standard OS
   validation has **already failed**. So the callback can only *override an
   OS-trust failure* (the only real value: trusting a self-signed/internal leaf);
   it **cannot reject an OS-trusted-but-impersonating certificate**, because the
   callback simply never fires for a cert the OS already trusts.
   (`pinned_http_client.dart`, former lines 26–39, 246–266.)
2. **The fail-open default was a downgrade footgun.** The pure helper
   `badCertificateCallbackResult(PinDecision.rejectPin)` returned `true`
   (`accept a cert that already failed OS validation`) whenever
   `kCertificatePinningEnforced == false` — i.e. whenever a maintainer populated
   pins but left the documented default switch off. With the shipped empty
   allow-lists this was behaviourally a no-op (every host deferred to the OS),
   but the wiring meant *activating* pins without also flipping enforcement would
   have made HTTPS **weaker** than standard TLS.

No public README/CHANGELOG text over-claimed pinning (good), but the source name
(`createPinnedHttpClient`), the file's `library;` doc ("Certificate-pinning HTTP
infrastructure"), the `captureLeafCertificateDescription` tooling, and the inline
comments at each call site all implied active protection that was not real.

### 2.2 (Fix F2) Cross-app TCC reset + PATH reliance in the macOS troubleshooting UI
**Severity:** Low–Medium (privacy: unilateral revocation of *other* apps' privacy permissions; hygiene: PATH-based process lookup).

`_resetPermissions` (`widgets/settings/pages/troubleshooting_page.dart`, former
lines 92–93) ran:

```dart
await Process.run('tccutil', ['reset', 'Accessibility']);   // resets ALL apps
await Process.run('tccutil', ['reset', 'AppleEvents']);     // resets ALL apps
```

Three issues, none exploited:
- `tccutil reset Accessibility` **without a bundle-id argument clears the
  Accessibility (and Automation) privacy entries for every application on the
  machine** — a far broader action than the confirm dialog promised ("This
  revokes Accessibility permission for Beeamvo") and than the native
  `resetAccessibilityEntry` helper performs (which is scoped to
  `com.beeamvo.app` via `/usr/bin/tccutil reset Accessibility <bundleId>`).
- The bare executable name resolved via `PATH`, unlike the absolute path used by
  the native helper (minor PATH-hijack hygiene gap).
- The accompanying `AppleEvents` reset is vestigial (the Automation permission is
  no longer used — confirmed in the troubleshooting FAQ), but clearing it for all
  apps is still a needless cross-app effect.

---

## 3. Remediations Applied

### 3.1 F1 — Honest TLS posture, no security theatre

**`frontend/lib/services/pinned_http_client.dart` (rewritten):**
- Renamed the public factory **`createPinnedHttpClient` → `createSecureHttpClient`**.
- Its body now returns `IOClient(HttpClient())` with **no `badCertificateCallback`
  override** → standard platform TLS validation only, with no code path that can
  weaken it. This removes the fail-open footgun.
- Removed the dead, misleading `_onBadCertificate` wiring helper, the now-unused
  `_debugLog`, and the unused `createTrustingHttpClient` alias.
- **Retained** the pure, unit-tested pin-evaluation scaffolding
  (`PinnedHostConfig`, `evaluateCertificatePin`, `computeLeafPinHash`,
  `PinDecision`, `badCertificateCallbackResult`, `captureLeafCertificateDescription`,
  `kCertificatePinningEnforced`, `_kPinnedHostAllowLists`) with rewritten doc
  comments stating it is **un-wired** and *why* a `badCertificateCallback`-based
  wiring is unsafe (so a future maintainer implementing *sound* native pinning has
  a tested matching layer + capture workflow and a clear warning).
- The library-level doc now leads with the honest posture: **no pinning is
  active; standard OS TLS is relied upon.**

**Call sites updated** (`gemini_api_service.dart:18`, `update_check_service.dart:93`,
`whisper_model_download_service.dart:208`) to use `createSecureHttpClient` with
accurate comments. (Vertex AI uses `googleapis_auth`'s own client, which is also
standard platform TLS — consistent posture.)

**Tests:** `pinned_http_client_test.dart` and `pinning_behavior_test.dart` were
re-annotated to state they validate the *un-wired* pure helpers (no behaviour
change to their assertions; both still pass).

**Net security effect:** identical to before for end users (still OS trust store),
**minus** the ability for a future pin-activation to accidentally weaken TLS, and
**plus** honest naming/docs/UI/README disclosure. Standard platform TLS
validation is retained and never weakened anywhere.

### 3.2 F2 — Scoped, absolute-path TCC reset (no cross-app blast radius)

- **New module `frontend/lib/services/macos_tcc_reset.dart`** exposes
  `tccutilExecutable` (constant `/usr/bin/tccutil`) and a pure, fail-safe helper
  `scopedTccutilArgs({service, bundleId})` which returns `['reset', service, bundleId]`
  or `null` when the bundle id is empty/blank (so a caller never falls back to an
  unscoped, machine-wide reset).
- **`troubleshooting_page.dart` `_resetPermissions`** now resolves Beeamvo's own
  bundle id from `PackageInfo.packageName`, builds scoped args for
  `Accessibility` (and the vestigial `AppleEvents`), and invokes the absolute
  `/usr/bin/tccutil`. If the bundle id can't be resolved it **fails safe**
  (skips the reset, tells the user to use Auto-repair instead) rather than
  silently clearing every app's TCC entries.
- The reset callout copy was clarified: now reads "revokes **Beeamvo's**
  Accessibility (and Automation) entries — other apps are unaffected", matching
  the native `resetAccessibilityEntry` / `autoRepair` behaviour that already
  existed via the `beeamvo/permission` channel.
- **Regression test added:** `frontend/test/macos_tcc_reset_test.dart` (6 new
  tests) covering scoped arg shape, whitespace trimming, fail-safe null returns
  for empty/whitespace bundle ids, the constant absolute path, and the invariant
  that a valid id always produces a 3-arg (never unscoped) reset.

---

## 4. Areas Confirmed Sound (evidence)

These were scrutinised because the task brief flagged them; no change was needed.

- **Credentials.** Gemini API key lives in the macOS Keychain
  (`SecItemAdd` … `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, device-only
  → not iCloud-synced) on macOS and `flutter_secure_storage` on Windows/Linux;
  the `InMemorySecureCredentialStore` is test-only. The key travels only in the
  `x-goog-api-key` header (`gemini_api_service.dart:280`). Vertex uses
  Application-Default Credentials (no stored secret) with the narrow
  `cloud-platform` scope (`vertex_ai_service.dart:21–22`). The macOS native
  `KeychainCredentials` migrates a legacy plaintext store
  (`~/Library/Application Support/com.beamvo/credentials.json`, written `0o600`)
  into the Keychain on first read and **deletes the plaintext value/file
  afterwards** (`MainFlutterWindow.swift` `read`→`write`→`removeLegacyValue`).
  *(Residual: see §5.1.)*
- **dotenv.** Release builds ignore dotenv entirely; `.env.example` is
  documentation-only (tracked, values blank); real `.env` is gitignored
  (`config.dart:203-211`, `frontend/.gitignore`).
- **Error messages / logging.** Gemini never echoes upstream error bodies to the
  UI and logs them only in `kDebugMode` (`gemini_api_service.dart:287-300`);
  Vertex likewise (`vertex_ai_service.dart:468-481`, debug-only). User-facing
  failures are generic status-mapped messages. Credentials are never logged
  (only method names + `bool` results, debug-only). *(Residual: §5.4.)*
- **Recording lifecycle / temp files.** Recorded WAVs are written under
  `getTemporaryDirectory()` and deleted on success, cancel, abort, and
  retry-clear (`main.dart:1730,1754,1812,1839,1880`). A failure during start
  best-effort-stops the recorder so the mic can't be left hot
  (`recording_service.dart:138-170`). A force-quit may leave one temp WAV (in the
  OS temp dir, which the OS reaps) — acceptable.
- **Clipboard sensitive-text filter.** `shouldSkipClipboardHistoryText`
  (`settings_service.dart:615-638`) skips common secret shapes (API keys,
  bearer/JWT/GitHub/GitLab/Slack/AWS/Stripe tokens, `-----BEGIN … PRIVATE KEY-----`).
  Clipboard history is stored as plaintext in `settings.json` — already disclosed
  in the in-app troubleshooting FAQ.
- **Update checks.** `UpdateCheckService` hits a hardcoded HTTPS GitHub endpoint,
  is rate-limited to once/24h, is fully best-effort (never blocks startup), and
  only uses the parsed `tag_name`, `html_url`, `body`, `published_at` — never
  auto-runs/installs anything; the user only gets a link to the release page.
- **Endpoint construction.** All cloud URLs are `Uri.https` with hardcoded hosts
  except the **Vertex project id**, which is validated with
  `isValidVertexProjectId` (`^` human-style or all-numeric) *before* being
  interpolated into the path (`vertex_ai_service.dart:104-128`) — prevents URL /
  path-injection from a hand-edited `settings.json`. The two `Uri.parse` call
  sites (`update_check_service.dart:97`, `whisper_model_download_service.dart:222`)
  parse hardcoded constant URLs.
- **Model downloads / integrity / path traversal.** Each shipped `WhisperModelInfo`
  carries a pinned **SHA-256** (and a legacy SHA-1), enforced before the temp
  file is renamed to its final path (`whisper_model_download_service.dart:510-537`);
  downloads are size-capped (`_validateExpectedSize`) and any mismatch/oversize
  triggers cleanup + error. `WhisperService.validateModelFileName` /
  `resolveAllowedModelPath` (`whisper_service.dart`) restrict inputs to a strict
  `^ggml-[…].bin$` basename, reject absolute/traversal/cross-dir paths, and
  resolve via `resolveSymbolicLinksSync` + `p.isWithin` against the allowed model
  dirs — defeating path-traversal into model load.
- **Native FFI / memory.** Windows PCM decode bounds-checks via
  `num_samples = bytes/2/channels` so `int16` accesses stay in range
  (`whisper_plugin.cpp:214-223`); the SendInput path in
  `keyboard_service_windows.dart` keeps strict `calloc`/`free` discipline. macOS
  iterates `min(int16Ptr.count, …)` (`WhisperPlugin.swift:126-131`). No
  attacker-controlled pointers/strings reach native from Dart beyond the
  validated model path.
- **Prompt-injection / data disclosure.** Cross-prompting is bounded by the
  immutable `_coreRules` (treat audio/transcript content as data, never commands)
  and `buildTranscriptDraftInput` framing transcript text as inert
  `<transcript-draft>` material (`models/system_prompt.dart`). `TranscriptionResultGuard`
  rejects empty / `[NO_TRANSCRIPT]` outputs (`transcription_result_guard.dart`).
- **App Transport Security.** `Info.plist` declares **no** `NSAppTransportSecurity`
  exception → ATS defaults apply (HTTPS required, OS-trusted certs). Nothing
  disables ATS.
- **Secret scan.** Repo-wide search for common secret shapes found **no** secrets
  other than the redaction regex itself.

---

## 5. Residual Risks (documented; not changed — each needs work outside this task's safe-scope)

### 5.1 Legacy plaintext credential file location
`KeychainCredentials` (`MainFlutterWindow.swift`) still *reads from and migrates
away from* `~/Library/Application Support/com.beamvo/credentials.json`. New
installs never create it; legacy installs migrate + self-delete on first read. A
very old pre-migration machine could therefore still hold the Gemini key in
plaintext until Beeamvo next reads it. No code change recommended here (the
migration is correct); **publication recommendation**: a one-time note in the
v0.2 release notes that v0.1 → v0.2 upgrades move the key to the Keychain.

### 5.2 macOS App Sandbox disabled (baseline B7)
`Release.entitlements` sets `com.apple.security.app-sandbox = false`. Enabling
the sandbox is **not** a safe, behaviour-preserving change: Beeamvo relies on
Accessibility + cross-application `CGEvent` injection for auto-paste
(`MacOsPermissionService.pasteCmdV` → `pasteWithCmdV`) and on
`LSSharedFileList` for launch-at-login (`MainFlutterWindow.swift`), both of which
are restricted/disallowed under the sandbox. Entitlements are already minimal
(`network.client` + `device.audio-input`) and the Debug-only
`allow-jit`/debug entitlement is not shipped. **Publication recommendation**:
for **distributed binaries** (not source), the packaging phase must enable
Hardened Runtime + Developer-ID notarization (the existing signing scripts are
explicitly dev-only — `CODESIGN_README.md`). Source users who build/run locally
inherit their own machine's trust boundary.

### 5.3 Vertex AI uses `googleapis_auth`'s own HTTP client
Vertex traffic does not flow through `createSecureHttpClient`; it uses the
`googleapis_auth` client, which is itself a standard `dart:io` `HttpClient`
relying on the OS trust store. This is **consistent** with the app's overall
standard-TLS posture and is not a weakness, but readers should not assume every
cloud call goes through `createSecureHttpClient`.

### 5.4 Native debug/log primitives write non-sensitive metadata in release
The macOS `WhisperPlugin` uses `NSLog` (and Windows `OutputDebugStringA`),
which are not gated by `kDebugMode`/`#if DEBUG` and thus emit to the platform's
unified/debug log in release builds. The logged content is **metadata only**
(model file path, thread count, sample count, output character count — never
audio bytes or transcripts), so the privacy impact is low. Hardening to
`#if DEBUG`/debug-log-only is a future, low-priority cleanup and is out of scope
here.

### 5.5 Clipboard history stored as plaintext
By design, clipboard/history entries (including transcriptions, unless they match
the secret redaction filter) are stored in plaintext in `settings.json` in the
app-data directory. This is already disclosed to users in the in-app
troubleshooting FAQ ("If Clipboard History is enabled, its entries are stored as
plaintext in Beeamvo's application-data settings file").

---

## 6. Validation

Run from `frontend/` on this worker (Flutter 3.44.2 / Dart 3.12.2, Windows host):

| Command | Before | After |
|---|---|---|
| `flutter analyze` | `No issues found!` | `No issues found!` |
| `flutter test` | 141 pass | **147 pass** (6 new; no regressions) |

New tests: `frontend/test/macos_tcc_reset_test.dart` (6 tests exercising the
scoped, fail-safe `tccutil` arg builder). The two pre-existing pinning test
files were re-documented to reflect that they validate the un-wired pure
scaffolding; their assertions are unchanged and still pass.

---

## 7. Files Changed

**Code (security fixes):**
- `frontend/lib/services/pinned_http_client.dart` — renamed factory to
  `createSecureHttpClient` (standard platform TLS, no callback override, fail-open
  footgun removed); removed `_onBadCertificate`, `_debugLog`, `createTrustingHttpClient`;
  rewrote all docs to be honest; pure pin helpers retained un-wired.
- `frontend/lib/services/gemini_api_service.dart` — call site → `createSecureHttpClient`.
- `frontend/lib/services/update_check_service.dart` — call site → `createSecureHttpClient`.
- `frontend/lib/services/whisper_model_download_service.dart` — call site → `createSecureHttpClient`.
- `frontend/lib/services/macos_tcc_reset.dart` — **new**: `/usr/bin/tccutil` constant + scoped, fail-safe `scopedTccutilArgs`.
- `frontend/lib/widgets/settings/pages/troubleshooting_page.dart` — `_resetPermissions` now scoped + absolute-path + fail-safe; reset callout copy clarified.

**Tests:**
- `frontend/test/macos_tcc_reset_test.dart` — **new** (6 tests).
- `frontend/test/pinned_http_client_test.dart`, `frontend/test/pinning_behavior_test.dart` — header comments clarified.

**Docs (security/privacy):**
- `docs/security-privacy-audit.md` — **new** (this file).
- `docs/release-baseline-audit.md` — B6 marked RESOLVED; B7 marked residual risk; §3.5/§1.4 pinning references updated to `createSecureHttpClient`.
- `README.md` — added one accurate "Cloud connections use standard TLS … pinning is not used" bullet under *Privacy & Security*.

---

## 8. Publication Recommendations

1. **Source release (v0.1.x public):** safe to publish from a security/privacy
   standpoint after the baseline P1 items (B1–B4: orphan parakeet gitlink,
   `_maindiff.txt`, `frontend/old_main.txt`) land — those are owned by the
   remediation phase and are not security defects, but they bloat the release
   surface.
2. **Binary release (macOS `.app`/`.dmg`, Windows):** before distributing, the
   packaging phase must add Hardened Runtime + Developer-ID signing +
   notarization for macOS (§5.2). Source builds are unaffected.
3. **Release notes accuracy:** may state "cloud traffic uses standard HTTPS / OS
   trust store." Must **not** claim certificate pinning or "pinned transport."
4. **Docs to add in a later task (not blocking):** a formal `SECURITY.md` (the
   README already references a private-reporting policy, baseline B12) and a
   `SECURITY`-flagged Dependabot config — owned by the docs/CI phases.

## 9. Unresolved Blockers

None. All confirmed, safely-fixable issues were remediated and verified. The
remaining items (§5) are either by-design behaviour, packaging prerequisites, or
low-priority hardening and are explicitly documented as residual risks rather
than left implicit.
