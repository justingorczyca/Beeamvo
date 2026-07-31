# Release Baseline Audit — Task 1 of 7

> **Scope of this document.** This is the *baseline inventory & release-scope* pass (Task 1). It maps the repository, identifies platforms/builds/tests, inventories manifests/licenses/CI/artifacts, separates source from generated/suspicious files, and flags release blockers + follow-ups for the downstream audit phases (security, supply-chain, correctness, CI/build, documentation, remediation, final verification). It deliberately does **not** perform deep security review, make code changes, or run builds/tests — those are later tasks.
>
> **Method.** Findings are evidence-backed with repository paths and (where useful) line numbers. Claims that could not be confirmed from the repo are marked *(unverified)* or omitted. All file sizes/line counts were captured from the current working tree at audit time.

---

> **Phase tracker.** Task 1 (this baseline) ✅ · Task 2 (security/privacy) ✅ · Task 3
> (supply-chain) ✅ · Task 4 (code correctness) ✅ · Task 5 (build/CI/packaging)
> ✅ · Task 6 (documentation sync & publication-readiness) ✅ · **Task 7 (final
> publication polish & verification) ✅ COMPLETE.**
> Task 5 rewrote `.github/workflows/ci.yml` (lockfile enforcement,
> pinned Flutter, format gate, Linux in the build matrix, caching/timeouts/
> concurrency, least privilege), resolved the SDK-floor mismatch (B13),
> canonicalized 36 files and added the `dart format` gate (B15), verified the
> Windows native build from a pinned whisper.cpp FetchContent, and separated
> source-CI from signed-binary-release requirements. Task 6 synchronized all
> public docs (README, CHANGELOG, setup/audit docs) against code/config, added
> community-health files (B12), and reconciled the README bundled-whisper.cpp
> v1.8.4 mention (B10) — see `docs/documentation-publication-audit.md`.
> **Task 7** re-ran the complete local release gate (lockfile/format/analyze/151
> tests/Windows release build, secret scan, gitlink/junk hygiene, doc link
> check), added conservative Dependabot (`.github/dependabot.yml`), documented
> SBOM as a binary-release follow-up, **downgraded B9 to non-blocking with
> evidence**, and rendered go/no-go for (a) public source push **(GO)**,
> (b) tag `v0.1.0` **(NO-GO until hosted CI green)**, (c) publish binaries
> **(NO-GO)** — see `docs/publication-polish-audit.md`.
> macOS Hardened Runtime + signing/notarization (B7/B8) remain open for the
> binary-release/packaging phase. See `docs/build-ci-packaging-audit.md`,
> `docs/documentation-publication-audit.md`, and `docs/publication-polish-audit.md`.
> Outstanding later phases: SBOM / installer packaging, optional binary-signing
> maturity.

## 1. Executive Summary

Beeamvo is a Flutter desktop app (Windows / macOS, experimental Linux) for offline-first voice-to-text with global hotkeys, auto-paste, and optional cloud transcription via Google Gemini API or Vertex AI. The Dart application (`frontend/lib`, ~62 files, ~23.5k LOC, 26 test files) is clean, MIT-licensed, and well-structured. Source hygiene is generally good: no secrets, no committed `.env`, generated/ephemeral Flutter artifacts are correctly gitignored.

However, several **release blockers** were found that must be resolved before a public open-source release:

1. **Unresolvable submodule with no `.gitmodules`** — `native/parakeet_runtime/third_party/parakeet.cpp` is tracked as a gitlink (mode `160000`, commit `e8acc617…`) but there is **no `.gitmodules` file**, so no one cloning the repo can initialize it. Furthermore, **nothing in the app references parakeet** — it appears to be vestigial/orphaned.
2. **Accidentally committed junk** — `_maindiff.txt` (root) is a 68 KB UTF-16-LE `git diff` dump; `frontend/old_main.txt` is an empty 0-byte orphan. Both are tracked.
3. **Linux is claimed but not built in CI** — README/CHANGELOG advertise (experimental) Linux support and a full `frontend/linux/` runner exists, but `.github/workflows/ci.yml` only builds macOS + Windows.
4. **TLS certificate pinning was ship-disabled / non-functional** — `kCertificatePinningEnforced = false` and all pin allow-lists were empty, and the `badCertificateCallback` could only react when OS validation *already* failed (so it could never enforce fail-closed pinning, and its fail-open branch would in fact *accept* an OS-rejected cert). *(Resolved in Task 2 / this security pass — see `docs/security-privacy-audit.md`. The misleading pinning wiring was removed, the factory was renamed `createSecureHttpClient` (standard platform TLS only), and an explicit "no pinning" disclosure was added to the README & troubleshooting UI. Standard OS TLS validation is retained everywhere.)*
5. **macOS ships with App Sandbox disabled** (`Release.entitlements:5-6`) and only ad-hoc/self-signed code-signing tooling — relevant for binary-distribution readiness. *(Not changed here: enabling the sandbox breaks CGEvent auto-paste and the `LSSharedFileList` login-item path, which is a product redesign. Documented as a residual risk + packaging-phase prerequisite in `docs/security-privacy-audit.md`.)*

---

## 2. Repository Inventory (high level)

| Area | Path | Notes |
|---|---|---|
| Root docs | `README.md`, `LICENSE`, `CHANGELOG.md`, `.gitignore`, `.gitattributes`, `_maindiff.txt` | MIT license (Copyright 2026 Beeamvo contributors). `_maindiff.txt` is junk — see §6. |
| Workflows | `.github/workflows/ci.yml` | Single CI workflow; tests on Linux, builds on macOS+Windows. See §4.4. |
| Frontend app | `frontend/lib/**` | 62 `.dart` files, ~23,540 lines. See §3. |
| Frontend platform | `frontend/{windows,macos,linux}/` | Native runners + whisper.cpp plugin per platform. |
| Vendored native | `frontend/macos/Runner/whisper.cpp/**` | 146 tracked entries committed inline (NOT a submodule). See §5.2. |
| Orphan native | `native/parakeet_runtime/third_party/parakeet.cpp` | Submodule gitlink, no `.gitmodules`, unused. See §6.1. |
| Tests | `frontend/test/**` | 26 `*_test.dart` files. See §4.4. |
| Docs | `docs/**` | 6 audit/setup/notice docs incl. `THIRD_PARTY_NOTICES.md`, `open-source-release-checklist.md`. |
| Build scripts | `frontend/scripts/**`, `frontend/macos/*.sh` | Icon conversion, macOS (dev) code-sign, signed build. |

**Scale:** tracked app-tree blobs (excluding the vendored whisper.cpp source) are dominated by PNG icons (`frontend/assets/app_icon.png` 2.4 MB, `app_icon_rounded.png` 2.3 MB, `beamvo_logo_transparent.png` 1.5 MB) — these are unusually large for distributed source icons and could be optimized. Largest source file is `frontend/lib/main.dart` (~76 KB, 2034 lines).

---

## 3. Architecture & Major Data Flows

### 3.1 Entry point and orchestration
- `main()` (`frontend/lib/main.dart:38-78`) initializes `AppConfig`, `window_manager`, then runs `BeeamvoApp`, which owns a single eagerly-initialized `SettingsService`.
- `BeeamvoHome._initialize()` (`main.dart:307-443`) wires: audio device readiness → onboarding → cloud service → usage stats → (optional) Whisper → tray → global hotkeys → clipboard monitor → background update check.

### 3.2 Transcription backend selection (central data-flow switch)
- `TranscriptionBackend { cloud, whisper }` (`frontend/lib/models/enums.dart:2-8`).
- `CloudProvider { geminiApiKey, vertexAi }` (`enums.dart:35`).
- `models/transcription_backend_resolver.dart` resolves effective backend at recording start; `_BeeamvoHomeState._activeRecordingBackend` pins the backend for the whole session so a mid-session settings change cannot redirect captured audio (`main.dart:214-222`).

### 3.3 Recording lifecycle
1. Global hotkey (`services/hotkey_service.dart`, default `Ctrl+Shift+V`, `config.dart:226`) starts/stops recording.
2. `services/recording_service.dart` captures audio (default format `wav`, `config.dart:228`); `assessMicReadiness()` verifies the saved device still exists (`main.dart:323-337`).
3. On stop (toggle) or release (hold), audio is dispatched to the pinned backend.

### 3.4 Offline path (Whisper)
- `services/whisper_service.dart` → platform FFI/method-channel to native whisper plugin:
  - macOS: Swift/ObjC plugin `frontend/macos/Runner/WhisperPlugin.{h,m,swift}` + `WhisperBridgingHeader.h` linking the **vendored inline** `whisper.cpp/` (v1.8.4, see §5.2).
  - Windows: C++ `frontend/windows/runner/whisper_plugin.cpp` linking whisper.cpp fetched via CMake `FetchContent`.
  - Linux: C++ `frontend/linux/runner/whisper_plugin.cc` linking whisper.cpp fetched via CMake `FetchContent`.
- `services/whisper_model_download_service.dart` downloads `ggml-*.bin` model weights at runtime from `https://huggingface.co/ggerganov/whisper.cpp/resolve/main` (`whisper_model_download_service.dart:39`) into the user data dir.

### 3.5 Cloud path (Gemini / Vertex)
- `services/cloud_transcription_service.dart` + `cloud_transcription_client.dart` route to:
  - **Gemini API key** → `services/gemini_api_service.dart` → `generativelanguage.googleapis.com` (`gemini_api_service.dart:129`), key sent via `x-goog-api-key` header (`gemini_api_service.dart:280`).
  - **Vertex AI** → `services/vertex_ai_service.dart` using `googleapis_auth` + `cloud-platform` OAuth scope (`vertex_ai_service.dart:22`) to `aiplatform.googleapis.com` / `$location-aiplatform.googleapis.com` (`vertex_ai_service.dart:191-192`).
- API key/credentials stored via `services/secure_credential_store.dart` (storage key `'gemini_api_key'`, `secure_credential_store.dart:17`); Vertex uses Application Default Credentials (no stored secret).
- All three cloud-networking clients are constructed with `createSecureHttpClient()` (standard platform TLS; former name `createPinnedHttpClient()` — pinning was a non-functional no-op and has been removed, see `docs/security-privacy-audit.md`) (`gemini_api_service.dart:19`, `update_check_service.dart:93`, `whisper_model_download_service.dart:208`).

### 3.6 Auxiliary flows
- **Auto-paste / keyboard injection**: `services/keyboard_service*.dart` (platform variants for macOS/Windows, stub fallback) simulate typing at cursor.
- **Clipboard history**: poll-based monitor (`main.dart:485-513`) saves transcriptions; sensitive-text best-effort filter (`settings_service.dart:624` bearer/token regex) skips common API keys/tokens.
- **System tray**: `services/tray_service.dart`.
- **Update check**: `services/update_check_service.dart` → `https://api.github.com/repos/justingorczyca/Beeamvo/releases/latest` (`update_check_service.dart:79`), rate-limited to once/24h, best-effort (`main.dart:445-469`).
- **Permissions (macOS)**: `services/macos_permission_service.dart` requests Accessibility at runtime; `NSMicrophoneUsageDescription` declared in `frontend/macos/Runner/Info.plist:31-32`.

---

## 4. Platforms, Builds, Tests, Packaging

### 4.1 Claimed vs. actual platform coverage

| Platform | Claimed (README / CHANGELOG) | Native runner present | Built in CI | Verdict |
|---|---|---|---|---|
| Windows | Yes | `frontend/windows/runner/` | Yes | ✅ Claimed + supported |
| macOS | Yes | `frontend/macos/Runner/` | Yes | ✅ Claimed + supported |
| Linux | "experimental" (`README.md:152`; `CHANGELOG.md:45`) | `frontend/linux/runner/` (full runner + `whisper_plugin.cc`) | **No** | ⚠️ Claimed but not exercised in CI |

No Android/iOS/web targets — `pubspec.yaml` has no mobile plugins beyond desktop, consistent with a desktop-only product.

### 4.2 Build commands (discoverable)
- From repo README (`README.md:41-53`) and `docs/open-source-release-checklist.md:38-44`:
  - `flutter pub get` (`--enforce-lockfile` per checklist)
  - `flutter run -d windows|macos`
  - `flutter build windows --release` / `flutter build macos --release`
- Native whisper.cpp is built by the platform CMake build automatically:
  - Windows/Linux: CMake `FetchContent` pins upstream whisper.cpp commit `9386f239401074690479731c1e41683fbbeac557` (v1.8.4) — `frontend/windows/runner/CMakeLists.txt:18-22`, `frontend/linux/runner/CMakeLists.txt:18-22`. Requires network + platform C++ toolchain at build time.
  - macOS: links the **bundled local copy** in `frontend/macos/Runner/whisper.cpp/` (no build-time network needed).
- CUDA auto-detection: both runners enable `GGML_CUDA` if a CUDA toolkit is found (`windows/runner/CMakeLists.txt:9-15`, `linux/runner/CMakeLists.txt:9-15`).

### 4.3 Analysis commands
- `flutter analyze` (CI + README `Development` section, `README.md:131-136`).
- `analysis_options.yaml` includes `flutter_lints` with a few tightened rules; deliberately conservative (comments at `analysis_options.yaml:3-18`).

### 4.4 Test commands & inventory
- `flutter test` (headless; CI runs it on `ubuntu-latest`, `ci.yml:34-35`).
- 26 test files in `frontend/test/`, covering: transcription backend resolver, result guard, Gemini/Vertex services, hotkeys, pinned HTTP/pinning behavior, recording audio format, settings privacy/provider, prompt flows, usage stats/achievements, whisper lifecycle/model security/download, and UI (theme contrast, bee hover, ai-models page, cloud-switch dialog). All are pure Dart (unit/widget); **no native device integration tests** — consistent with running on a Linux CI runner.

### 4.5 Packaging / signing
- macOS dev signing: `frontend/macos/setup_codesign.sh`, `CODESIGN_README.md`, `frontend/scripts/build_signed_macos.sh`, `README_signing.md`. `CODESIGN_README.md:45-46` explicitly states this self-signed flow is **dev-only, not for distribution**.
- No installer/packaging config (no MSIX `.appinstaller`, no `.dmg` build script beyond the signed build helper) for end-user distribution. *(Verify in CI/build phase whether binary artifacts are produced via release automation; none found in-repo.)*

---

## 5. Key Manifests, Lockfiles, Licenses, CI, Docs

### 5.1 Flutter manifest & lockfile
- `frontend/pubspec.yaml`: name `beeamvo`, version `0.1.0`, `publish_to: 'none'`, Dart SDK `^3.10.4`, Flutter `>=3.44.0` (via lockfile). **20 direct deps** (http, hotkey_manager, record, super_clipboard, path_provider, path, window_manager, screen_retriever, tray_manager, win32, ffi, launch_at_startup, package_info_plus, google_fonts, googleapis_auth, flutter_secure_storage, flutter_dotenv, crypto, url_launcher, flutter_localizations) + flutter_lints/flutter_launcher_icons dev deps.
- `frontend/pubspec.lock`: ~123 package entries. **All dependencies resolve to `pub.dev` hosted packages** (no `git:` or `path`-source deps); only the Flutter SDK plugins are `source: sdk`. Recorded environment: dart `>=3.12.0 <4.0.0`, flutter `>=3.44.0`. *Minor: `pubspec.yaml` SDK floor `^3.10.4` is looser than the lockfile-implied `>=3.12.0` union — non-blocking.* See §6 (supply-chain phase owns deep SBOM).

### 5.2 Native manifests & vendored code
- macOS: `frontend/macos/Podfile` + `Podfile.lock`, `Runner.xcodeproj`, `whisper.cpp.podspec`, `add_whisper_plugin.rb`, entitlements (`Release.entitlements`, `DebugProfile.entitlements`), `Info.plist`.
- **Vendored whisper.cpp** (`frontend/macos/Runner/whisper.cpp/`, **146 tracked entries**): inline copy, `CMakeLists.txt` project version `1.8.4`, license **MIT** (Copyright 2023-2026 The ggml authors). Matches the Windows/Linux pinned upstream version — so all three platforms ultimately build the same whisper.cpp version. *Note: the in-tree ggml/ tree has no separate `ggml/LICENSE` file; its terms are folded into the `whisper.cpp / ggml` notice in `docs/THIRD_PARTY_NOTICES.md`.*
- Windows/Linux runner CMakeLists use `FetchContent` (no separate lockfile — pinned by commit hash).

### 5.3 Licensing & notices
- Root `LICENSE`: MIT, Copyright (c) 2026 Beeamvo contributors.
- `docs/THIRD_PARTY_NOTICES.md`: covers Whisper (MIT, OpenAI), whisper.cpp/ggml (MIT), model weights (CC-BY-NC-4.0 from Hugging Face — **correctly flagged as non-commercial**), Google Fonts, Flutter/Dart (BSD-3-Clause), and a pub.dev license table. *Gaps for the docs phase:* several table rows unresolved (`record`, `super_clipboard`, `launch_at_startup`, `flutter_dotenv` marked *(see package)*); whisper.cpp notice copyright year says `2023-2024` while the vendored LICENSE says `2023-2026`; `parakeet.cpp` is not mentioned (arguably N/A since unused — see §6.1).

### 5.4 CI
- `.github/workflows/ci.yml`: two jobs — `analyze-and-test` (ubuntu-latest: `pub get` → `analyze` → `test`) and `build` (matrix `[macos-latest, windows-latest]`: `pub get` → `flutter build --release`). Uses `actions/checkout@v4`, `subosito/flutter-action@v2` (stable, cached). Permissions scoped to `contents: read`.
- *No `dependabot.yml`, security workflow, release workflow, or issue/PR templates* exist. No `submodules: true` on checkout (relevant only if parakeet were to become a real submodule).

### 5.5 Release/release-engineering docs present
- `docs/open-source-release-checklist.md` (source/binary hygiene checklist + a `git ls-files` hygiene grep), `docs/gemini-api-setup.md`, `docs/vertex-rest-setup.md`, and three existing audit docs (`cloud-switch-dialog-audit.md`, `transcription-pipeline-audit.md`, `workflow-visualization-and-audit.md`).

---

## 6. Source vs. Generated / Ephemeral / Suspicious Artifacts

### 6.1 ✅ Orphaned submodule (release blocker) — RESOLVED in Task 3
- `native/parakeet_runtime/third_party/parakeet.cpp` is tracked as a **gitlink** (`git ls-tree` mode `160000`, commit `e8acc6172a94e20a952cf1843decace5d771a94b`).
- **No `.gitmodules` exists** anywhere in the repo (`cat .gitmodules` → empty; `git submodule status` → empty). A fresh clone will have an empty directory here and `git submodule update --init` will fail/silently skip it.
- **The app does not reference parakeet at all**: `git grep -l -i parakeet` outside its own subtree returns nothing; no Dart file in `frontend/lib` references it; no runner `CMakeLists.txt`/build script references it. Determined to be **vestigial/orphaned** with respect to the released app.
- *Outcome options for remediation phase:* either (a) remove the gitlink entirely, or (b) add a proper `.gitmodules` + integrate it if it's actually intended as a future backend. Until resolved it should not ship.

### 6.2 ✅ Accidentally committed junk (release blocker) — RESOLVED in Task 3
- **`_maindiff.txt`** (root): 68,028 bytes, UTF-16-LE encoded. Begins with `commit 23f8b5fb78a7ccfd05bd95be8be231c42b4ba0ca / Author: Justin Gorczyca ...` — i.e. a **captured `git diff`/`git log` paste committed by accident**. Not UTF-8 (fails normal text read). Should be deleted.
- **`frontend/old_main.txt`**: tracked **0-byte** file (blob `e69de29…`). Orphan; delete.

### 6.3 ✅ Correctly excluded (verified gitignored, present only in working tree)
- Flutter ephemeral/generated: `frontend/{linux,windows,macos}/flutter/ephemeral/`, all `generated_plugin_registrant.*`, `generated_plugins.cmake`, `.plugin_symlinks/`, `.dart_tool/`, `build/`, `.flutter-plugins`, `.flutter-plugins-dependencies`.
- Logs: `frontend/flutter_01.log`, `frontend/flutter_02.log` (correctly ignored by `*.log`).
- Secrets templates: only `.env.example` is tracked; real `.env` files are gitignored (`frontend/.gitignore:38-41`).
- Windows build binaries in `frontend/windows/flutter/ephemeral/` (e.g. `flutter_windows.dll`, `.pdb`, `icudtl.dat`) are present in the tree but **not tracked**.

> **Implication for releases:** Because junk is *tracked* (§6.2) and the parakeet gitlink is *tracked* (§6.1), a `git archive`/fresh-clone release would include them. The ignored files in §6.3 will *not* be included, so they are non-issues for a clone-based release. *Recommendation:* also run the `git ls-files` hygiene grep from `docs/open-source-release-checklist.md:35` in the release pipeline.

### 6.4 Source-code health (no secrets found)
- No hardcoded API keys/tokens in `frontend/lib`; secrets flow through `secure_credential_store.dart` and the Gemini key travels only in the `x-goog-api-key` header. The `frontend/.env.example` is documentation-only (README `Privacy & Security`, `README.md:125`) and release builds ignore dotenv entirely (`config.dart:203-211`).

---

## 7. Release Blockers & Inconsistencies (prioritized)

> Priority key: **P1 = blocks public source release**, **P2 = blocks binary release / should fix before v0.2**, **P3 = quality/consistency**, **P4 = nice-to-have.**

| # | Pri | Finding | Evidence / File | Owning phase |
|---|---|---|---|---|
| B1 | **P1 → ✅ RESOLVED (Task 3)** | Submodule gitlink with no `.gitmodules` → unclonable, mixes hidden 3rd-party code into the release surface | `native/parakeet_runtime/third_party/parakeet.cpp` (mode 160000); no `.gitmodules`; **gitlink + working-tree dir + `.git/modules/native` removed** — `git submodule status` now clean, no gitlinks remain. See `docs/open-source-supply-chain-audit.md` §5 | Supply-chain (Task 3) |
| B2 | **P1 → ✅ RESOLVED (Task 3)** | Orphaned/unused native module committed but never wired into the app | §6.1 (no Dart/runner references to parakeet — `git grep -i parakeet -- frontend .github` returns nothing) → removed as confidently unused (recoverable from `github.com/mudler/parakeet.cpp.git@e8acc617`) | Supply-chain (Task 3) |
| B3 | **P1 → ✅ RESOLVED (Task 3)** | Accidentally committed junk: `_maindiff.txt` (UTF-16LE git diff dump) | `_maindiff.txt` (68 KB) — `git rm`'d; recurrence guarded by new `.gitignore` rules | Supply-chain (Task 3) |
| B4 | **P1 → ✅ RESOLVED (Task 3)** | Orphan empty tracked file: `frontend/old_main.txt` (0 bytes) | `frontend/old_main.txt` — `git rm`'d; recurrence guarded by new `.gitignore` rules | Supply-chain (Task 3) |
| B5 | **P2 → ✅ RESOLVED (Task 5)** | CI never builds Linux despite "experimental Linux" claim | `.github/workflows/ci.yml` now includes an `ubuntu-latest`→`target: linux` build job with Flutter's Linux prerequisites + `--enable-linux-desktop`; the runner is structurally complete (`whisper_plugin.cc` mirrors Win/macOS, consistent v1.8.4 pin). First CI run is the authoritative native verification. See `docs/build-ci-packaging-audit.md` §2 | CI/Build (Task 5) |
| B6 | **P2 → RESOLVED (Task 2)** | TLS certificate pinning was non-functional by design (enforce=false, empty pins, callback only fires on OS-trust failure, fail-open would accept an OS-rejected cert). | `frontend/lib/services/pinned_http_client.dart` (live wiring removed; factory renamed `createSecureHttpClient`; pure pin helpers retained un-wired); `docs/security-privacy-audit.md` | Security |
| B7 | **P2 (residual risk; documented)** | macOS release build runs with App Sandbox disabled (required by CGEvent paste + legacy login-item API; enabling needs a product redesign). Hardened Runtime + Developer-ID notarization are packaging-phase prerequisites for distributed binaries. | `frontend/macos/Runner/Release.entitlements:5-6` (`app-sandbox=false`); see `docs/security-privacy-audit.md` | Security/Packaging |
| B8 | **P2** | No distribution-grade macOS signing (only ad-hoc/self-signed dev tooling; `CODESIGN_README.md:45-46` says not for distribution). Hardened-runtime/notarization readiness for public `.app`/`.dmg` unverified | `frontend/macos/setup_codesign.sh`, `frontend/scripts/build_signed_macos.sh` | Packaging |
| B9 | **P3 → ✅ DOWNGRADED/CLOSED (Task 7; non-blocking)** | Large unoptimized PNG icons bloat source | `frontend/assets/app_icon.png` (2.4 MB), `app_icon_rounded.png` (2.4 MB), `beamvo_logo_transparent.png` (1.5 MB). Closed as non-blocking with evidence: icons are project-owned & MIT-licensed (no notice issue), do not break clone/build/test; `app_icon_rounded.png` is unused at runtime but is the documented input to `scripts/convert_icons.py`. Re-encoding the primary icon/logo risks the visual identity (no visual-QA on host); removing the file orphans the icon generator; narrowing the `assets:` glob reduces only *binary* bloat, not source-clone size. Two safe optional optimizations documented as deferred follow-ups. See `docs/publication-polish-audit.md` §4.4 | Final verification (Task 7) |
| B10 | **P3 → ✅ RESOLVED (Task 6)** | README omits that the macOS *bundled* whisper.cpp is also v1.8.4 (could imply version drift) | `README.md` now states all three platforms build the same whisper.cpp v1.8.4 (`README.md` "whisper.cpp build model" note). See `docs/documentation-publication-audit.md` | Documentation (Task 6) |
| B11 | **P3 → ✅ RESOLVED (Task 3)** | `THIRD_PARTY_NOTICES.md` had unresolved license rows + a stale whisper.cpp copyright year; the model-weights license was **also inaccurate (stated CC-BY-NC-4.0; actually MIT)** | `docs/THIRD_PARTY_NOTICES.md` — year fixed (`2023-2026`), all 6 `(see package)`/partial rows resolved, model weights corrected to **MIT** (OpenAI Whisper + HF card) w/ provenance. README licensing note added. See `docs/open-source-supply-chain-audit.md` §3 | Supply-chain (Task 3) |
| B12 | **P4 → ✅ RESOLVED (Task 6)** | No `SECURITY.md` / `CONTRIBUTING.md` / `CODE_OF_CONDUCT.md`; no Dependabot; no issue/PR templates (security policy only informally in README `README.md:127`) | Added `SECURITY.md` (private reporting, no invented SLA/contact), `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1), `.github/ISSUE_TEMPLATE/` (bug, feature, config), and `.github/PULL_REQUEST_TEMPLATE.md`. See `docs/documentation-publication-audit.md` | Documentation (Task 6) |
| B13 | **P4 → ✅ RESOLVED (Task 5)** | SDK floor mismatch (non-blocking) | `frontend/pubspec.yaml` `sdk: ^3.10.4` → `^3.12.0` to match `pubspec.lock` (`sdks.dart >=3.12.0`); `--enforce-lockfile` still passes, lockfile byte-identical. See `docs/build-ci-packaging-audit.md` §6 | CI/Build (Task 5) |
| B14 | **P3 → ✅ RESOLVED (Task 4)** | Recording auto-stop `durationLimit` was read **unclamped** in `SettingsService` (the recording path arms `Timer(Duration(seconds: durationLimit))`). The duration dialog enforces `[5,3600]` and the sibling `clipboardHistoryMaxItems` already clamps, but this one did not — a corrupt/hand-edited `duration_limit ≤ 0` would arm a zero-length timer and instantly stop a recording once auto-stop is on. | `frontend/lib/services/settings_service.dart` (getter+setter now `clampDurationLimit` `[5,3600]`); `frontend/test/settings_duration_limit_test.dart` (4 regression tests). See `docs/code-correctness-audit.md` §4 (C1) | Correctness (Task 4) |
| B15 | **P3 → ✅ RESOLVED (Task 5)** | `dart format` is **not enforced**: 36/91 Dart files under `frontend/lib+test` were not canonical-formatter-clean (pre-existing; CI ran only `analyze`+`test`). | Tree canonicalized in one isolated cosmetic pass (`dart format lib test`); a `dart format --output=none --set-exit-if-changed lib test` gate added to CI. One brace fix (`home_dashboard_page.dart`) needed for the formatter/analyzer interaction. Tree is now both formatter-clean and analyzer-clean. See `docs/build-ci-packaging-audit.md` §5 | CI/Build (Task 5) |

---

## 8. Prioritized Follow-Up Items (with file references)

**Immediate (P1) — required before tagging/cutting a public source release:**
1. Decide parakeet's fate (B1/B2): remove the gitlink, *or* add `.gitmodules` + a documented integration + THIRD_PARTY_NOTICE. Verify with `git ls-files native/` (presently returns only the gitlink). — **✅ RESOLVED (Task 3):** removed the gitlink + working-tree dir + `.git/modules/native`; `git submodule status` is clean. See `docs/open-source-supply-chain-audit.md` §5.
2. `git rm _maindiff.txt` (B3) and `git rm frontend/old_main.txt` (B4). — **✅ RESOLVED (Task 3).**
3. Re-run the hygiene grep from `docs/open-source-release-checklist.md:35` and confirm a clean `Tracked source hygiene check passed`. — **✅ DONE (Task 3): hygiene check now passes.**

**Before a public binary release (P2):**
4. Security phase: produce an accurate statement of the cloud TLS posture — today the app trusts OS stores for all Gemini/Vertex/HuggingFace/GitHub traffic (B6, `pinned_http_client.dart`). Avoid any "pinned/secure transport" claim in release notes until pins are populated and enforced (note the documented `badCertificateCallback` limitation that prevents full fail-closed pinning).
5. CI/build phase: add Linux to the build matrix or explicitly drop the Linux claim from README/CHANGELOG (B5). — **✅ RESOLVED (Task 5):** Linux `ubuntu-latest`→`target: linux` build job added with prerequisites; runner assessed structurally complete. See `docs/build-ci-packaging-audit.md` §2.
6. Packaging phase: verify hardened-runtime + notarization + proper Developer-ID signing for macOS binaries; reassess whether App Sandbox can be enabled (B7/B8).

**Quality/consistency (P3–P4):**
7. Docs phase: tighten `THIRD_PARTY_NOTICES.md` — resolve the four `(see package)` license rows and refresh the whisper.cpp copyright year; mention macOS bundled whisper.cpp = v1.8.4 in README (B10, B11). — **B11 ✅ RESOLVED (Task 3)** (license rows resolved, year fixed, plus the model-weights license corrected to MIT and a README licensing note added). **B10 ✅ RESOLVED (Task 6)** (README now states all three platforms build the same whisper.cpp v1.8.4).
8. Remediation: optimize/shrink source PNG icons in `frontend/assets/` and align `pubspec.yaml` SDK floor with the resolved lockfile (B9, B13). — **B13 ✅ RESOLVED (Task 5)** (SDK floor → `^3.12.0`). **B9 (icon optimization) remains** for a remediation phase.
9. Documentation: add `SECURITY.md` (formalize the private-reporting policy referenced at `README.md:127`), `CONTRIBUTING.md`, and a Dependabot config (B12). — **B12 ✅ RESOLVED (Task 6)** (added `SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, issue/PR templates). Dependabot remains an optional future CI addition; it is not a publication blocker. See `docs/documentation-publication-audit.md`.

---

## 9. Audit Limitations

- This pass is **read-only inventory**. No builds were run (no native toolchain on this worker), so build-time behavior of the Windows/Linux CMake `FetchContent` step and macOS vendored-link step is inferred from the committed CMakeLists, not observed.
- `flutter analyze` and `flutter test` were **not executed** here (deferred to the correctness/CI phases). Test pass/fail status is therefore unknown.
- Supply-chain depth (full transitive SBOM, license verification for every locked package, known-vuln scan) is out of Task-1 scope and owned by the supply-chain phase; here I only confirmed all deps are pub.dev-hosted with no git/path sources.
- Deep security review (TLS handling, secure-storage implementation, clipboard sensitive-data filtering, permission scope) is flagged for evidence but **not** assessed for exploitability here — that is the security phase.
- Items marked *(unverified)* in §4.5 (release-artifact packaging) could not be confirmed from in-repo files.
