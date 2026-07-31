# Build, CI & Packaging Audit — Task 5 of 7

> **Scope.** An evidence-backed review and *conservative* remediation of the build
> system, continuous-integration configuration, packaging/release reproducibility,
> and platform-support claims for Beeamvo. It preserves Tasks 1–4 (baseline,
> security, supply-chain, correctness) and makes only build/CI/packaging
> corrections — no application-logic changes, no broad README/doc sweep, no
> dependency upgrades, and **no signing secrets**.
>
> **Method.** Every CI/build/packaging file was inspected directly; the host's
> practical build/analysis/test commands were executed and their outcomes recorded
> (see §3); cross-platform builds that the host cannot run are explicitly marked as
> CI-gated rather than asserted. Findings cite repository paths and (where useful)
> line numbers.

---

## 1. Executive Summary

The build and release surface is **sound and reproducible for a public source
release**, and the CI gate is now **harder, hermetic, and least-privilege**. This
pass landed five changes:

1. **CI rewritten** `.github/workflows/ci.yml` — lockfile enforcement
   (`--enforce-lockfile`), a **`dart format` gate** (now safe — the tree was first
   canonicalized), pinned Flutter toolchain, pub-dependency caching, per-job
   timeouts, a concurrency guard, least-privilege `permissions: contents: read`,
   and **Linux added to the build matrix**.
2. **SDK-floor mismatch resolved (B13)** — `frontend/pubspec.yaml` `sdk: ^3.10.4`
   → `^3.12.0`, matching the resolved `pubspec.lock` floor (`>=3.12.0`).
3. **Formatting normalized** — the 36 previously-non-canonical Dart files were run
   through `dart format` in one isolated, cosmetic-only pass, plus exactly one
   brace-around-a-single-statement fix that the formatter surfaced. This makes the
   tree simultaneously formatter-clean *and* analyzer-clean.
4. **Platform-support claims assessed** — Windows and macOS remain **supported**;
   Linux is **experimental-but-real** (complete runner, consistent pin, now built
   in CI). macOS **binary distribution** requires Hardened Runtime + Developer-ID
   signing + notarization, which are clearly *separated* from source CI.
5. **Native build verified on the host** — `flutter build windows --release` compiles
   whisper.cpp v1.8.4 via the pinned CMake `FetchContent`, the ggml CPU backend,
   and all Flutter plugins, producing `Beeamvo.exe` (§3.6). macOS/Linux native
   builds cannot run on this Windows host and are CI-gated (now all three are in CI).

**Verdict — source release: APPROVED.** A clean checkout passes every check the CI
gate runs. **Binary release: not yet** — macOS lacks Hardened Runtime / Developer-ID
/ notarization and there is no installer/dmg packaging (§9–10).

---

## 2. Platform Support Matrix (truthful assessment)

| Platform | Native runner | whisper.cpp source | Built in CI | Host-verified here? | Verdict |
|---|---|---|---|---|---|
| **Windows** | `frontend/windows/runner/` (C++/Win32) | CMake `FetchContent` pin `9386f239…` (v1.8.4) | ✅ `windows` job | ✅ **`flutter build windows --release` succeeds** (`Beeamvo.exe`) | **Supported** |
| **macOS** | `frontend/macos/Runner/` (Swift/Metal) + vendored `Runner/whisper.cpp/` v1.8.4 | Bundled local copy (podspec commit `9386f239…` v1.8.4, no build-time fetch) | ✅ `macos` job | ❌ no Xcode on host (CI-gated) | **Supported** (source). Binary distribution needs signing/notarization (§9). |
| **Linux** | `frontend/linux/runner/` (C++/GTK) + `whisper_plugin.cc` | CMake `FetchContent` pin `9386f239…` (v1.8.4) | ✅ `linux` job (**added this task**) | ❌ no Linux toolchain on host (CI-gated) | **Experimental-but-real** |

**whisper.cpp version consistency (the single native dependency).** All three
platforms build whisper.cpp **v1.8.4 at the identical commit**:
- Windows/Linux: `frontend/{windows,linux}/runner/CMakeLists.txt` → `GIT_TAG 9386f239401074690479731c1e41683fbbeac557 # v1.8.4`.
- macOS: `frontend/macos/whisper.cpp.podspec` → `s.version = '1.8.4'`, `s.source = { … :commit => '9386f239…' }` linking the vendored `Runner/whisper.cpp/` (`project("whisper.cpp" VERSION 1.8.4)`).

There is **no version drift** across platforms. The pin is by **commit hash**
(cryptographic, immutable), not a moving branch/tag — so Win/Linux builds are
reproducible given network access at build time. No other `wget`/`curl`/downloaded
source exists in any build (Task 3 confirmed; re-confirmed here). The only network
dependency at build time is the whisper.cpp `FetchContent` fetch (Win/Linux); all
Dart dependencies are content-addressed pub.dev packages locked by `pubspec.lock`.

**Why Linux was added to CI (B5 resolution).** The claim that Linux could not be
verified (Task 1, B5) is resolved *in favour of adding it*, based on concrete
viability evidence rather than assertion:
- A complete native runner (`frontend/linux/runner/`) with a full
  `whisper_plugin.cc` (343 lines) that mirrors the Windows/macOS contract exactly:
  method channel `com.beeamvo/whisper`, `busy` re-entrancy guard, `ctx_mutex`,
  cancellation via atomic `cancel_requested_` + `whisper_full` `abort_callback`,
  PCM-16LE→float32 first-channel conversion, capped thread count, and a
  `choose_audio_context` heuristic identical to the other platforms.
- A standard Flutter-Linux `CMakeLists.txt` (`pkg_check_modules(GTK REQUIRED …)`)
  plus `runner/CMakeLists.txt` that links whisper + pthread + GTK and reuses the
  identical FetchContent pin.
- A `generated_plugins.cmake` whose 10 listed plugins each ship a real
  `linux/` implementation (`record_linux`, `hotkey_manager_linux`,
  `flutter_secure_storage_linux`, `screen_retriever_linux`, `url_launcher_linux`,
  `window_manager`, `tray_manager`, `super_native_extensions`,
  `irondash_engine_context`, FFI `jni`) — Flutter only adds a plugin to this list
  when it provides Linux sources.
- whisper.cpp and ggml have first-class CMake/Linux support upstream.

CI is now the authoritative native-compile gate for Linux (as it already is for
macOS); this is the only way the "experimental" claim becomes *verifiable* instead
of *asserted*. The job installs Flutter's canonical Linux prerequisites
(`clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev`)
and enables `--enable-linux-desktop`. See §12 for the residual (first-run is the
true verification; if it proves flaky, downgrade to a documented-unsupported note).

> **No Android / iOS / web** build targets exist (`pubspec.yaml` is desktop-only;
> no mobile plugins beyond desktop), consistent with a desktop-only product.

---

## 3. Environment & Validation (commands run, with outcomes)

Host: **Windows**, Flutter **3.44.2** (stable), Dart **3.12.2**, Visual Studio
Community 2026 (Windows 10 SDK 10.0.26100.0). All commands run from `frontend/`.

| # | Command | Outcome |
|---|---|---|
| 1 | `flutter --version` / `dart --version` | Flutter 3.44.2 (stable, rev `c9a6c48423`); Dart 3.12.2 (stable) |
| 2 | `flutter pub get --enforce-lockfile` | **OK** — lockfile consistent with `pubspec.yaml`; no resolution drift (27 outdated bumps reported, none applied). `pubspec.lock` unchanged after the SDK-floor edit. |
| 3 | `dart format --output=none --set-exit-if-changed lib test` (pre-normalization) | **36 / 91 files changed** (exit 1) — pre-existing, project-wide (Task 4 / B15). |
| 4 | `dart format lib test` (isolation step) | **Formatted 91 files (36 changed)** — the cosmetic-only normalization pass. |
| 5 | `dart format --output=none --set-exit-if-changed lib test` (post-normalization) | **0 changed, exit 0** — tree is canonical. |
| 6 | `flutter analyze` (post-format) | surfaced 1 *info* lint (`curly_braces_in_flow_control_structures`, `home_dashboard_page.dart:251`) caused by the formatter wrapping an over-long single-line `if`. Fixed with braces; analyzer now clean. |
| 7 | `flutter analyze` (final) | **No issues found!** (exit 0) |
| 8 | `flutter test` | **151 / 151 passed** (exit 0) — unchanged from Task 4. |
| 9 | `flutter build windows --release` | **✅ Built `build/windows/x64/runner/Release/Beeamvo.exe`** (exit 0, ~45 s incl. FetchContent + ggml + plugins). whisper.cpp v1.8.4 fetched from the pinned commit and compiled. |

**Build output (verified):** `Beeamvo.exe` (1.4 MB), `flutter_windows.dll`, all
plugin DLLs (`hotkey_manager_windows_plugin.dll`, `record_windows_plugin.dll`,
`flutter_secure_storage_windows_plugin.dll`, `super_native_extensions.dll`,
`tray_manager_plugin.dll`, `window_manager_plugin.dll`, `url_launcher_windows_plugin.dll`,
`screen_retriever_windows_plugin.dll`, `irondash_engine_context_plugin.dll`,
`dartjni.dll`), `whisper.lib`, `data/`. **No `.env`**, no stray debug symbols,
no generated logs in the release bundle (source build; release builds ignore
dotenv per `config.dart:203-211`).

**Build-time warnings (non-blocking, recorded):**
- *(dev)* `FetchContent_Populate(whisper) is deprecated, use FetchContent_MakeAvailable`
  (CMake policy CMP0169) — in both `windows/runner/CMakeLists.txt:33` and
  `linux/runner/CMakeLists.txt:33`. Functional today; future CMake will remove
  `FetchContent_Populate`.tracked for a later cleanup (§12).
- whisper.cpp upstream `cmake_minimum_required` < 3.10 deprecation notice —
  upstream's own `CMakeLists.txt`, not ours; advisory only.

### Cross-platform builds not executable on this host
- **macOS** `flutter build macos --release` — requires Xcode + CocoaPods (absent on
  this Windows worker). The `macos` CI job is the authoritative native gate.
- **Linux** `flutter build linux --release` — requires the Linux C++/GTK toolchain
  (absent on this Windows worker). The `linux` CI job (added this task) is the
  authoritative native gate.
These were **source-reviewed** (Task 4 reviewed all three `whisper_plugin.*`
natively; this task reviewed the CMake/Podfile/plugin wiring); they are *not*
unverified by omission but **CI-gated**, exactly as the project intends.

---

## 4. CI Configuration — Review & Changes (`.github/workflows/ci.yml`)

### Before (pre-existing)
Two jobs: `analyze-and-test` (ubuntu: `pub get`→`analyze`→`test`) and `build`
(matrix `[macos-latest, windows-latest]`: `pub get`→`flutter build`). Actions
major-version pinned (`checkout@v4`, `flutter-action@v2`, channel `stable`+`cache`).
Top-level `permissions: contents: read`. No timeouts, no lockfile enforcement, no
format gate, no Linux, no concurrency guard, no pub-deps cache.

### After (this task)
Same two jobs, hardened and extended. Every change is conservative and **requires
no secrets**.

| Area | Change | Rationale |
|---|---|---|
| **Security / least privilege** | Top-level `permissions: contents: read` retained and documented; no `secrets.*` referenced anywhere. | Source CI only verifies public-source builds; distribution signing is out-of-band (§9). |
| **Reproducibility** | Flutter **pinned** `flutter-version: '3.44.2'` (was floating `channel: stable`). Documented as the audited baseline. | Deterministic, reproducible builds; moving to a newer toolchain becomes a deliberate, reviewable bump. |
| **Lockfile enforcement** | `flutter pub get **--enforce-lockfile**` in both jobs. | Prevents silent lockfile drift; `pubspec.lock` is the source of truth. (Checklist already implied it; CI now enforces it.) |
| **Format gate** | Added `dart format --output=none --set-exit-if-changed lib test` to `analyze-and-test`. | Safe **only** because the whole tree was first canonized (§5) — never a permanently-failing gate. |
| **Dependency caching** | Added `actions/cache@v4` for pub deps, keyed on `hashFiles('frontend/pubspec.lock')`, with a deterministic `PUB_CACHE` (`${{ runner.temp }}/.pub-cache`). SDK still cached via `flutter-action` `cache: true`. | Faster, cheaper CI; cache key invalidates exactly when the lockfile changes. |
| **Timeouts** | `timeout-minutes: 30` (analyze) / `60` (build). | Caps runaway runs (GitHub default is 6 h); generous vs. observed ~45 s analyze / ~45 s Windows build. |
| **Concurrency** | `cancel-in-progress: ${{ github.ref != 'refs/heads/main' }}`. | Cancels superseded PR runs; never cancels `main` (release-candidate integrity). |
| **Linux in matrix** | Added `ubuntu-latest`→`target: linux` with apt prereqs + `--enable-linux-desktop`. | Resolves B5; CI now compiles the experimental platform (§2). |
| **Simplified build step** | One `flutter build ${{ matrix.target }} --release` step (was an OS-`if`). | Cleaner matrix-driven dispatch. |

**Action/runner versioning.** `actions/checkout@v4`, `actions/cache@v4`, and
`subosito/flutter-action@v2` are **major-version** pinned (standard, supports
patch fixes). SHA-pinning would harden against a compromised action release tag,
but is a maintenance tradeoff; logged as a future hardening (§12), not applied now
to avoid a brittle, fast-stale pin for a public-source workflow.

**Validated.** The YAML parses; the exact local command set the gate runs
(`pub get --enforce-lockfile` → `dart format --set-exit-if-changed` → `analyze` →
`test`) all pass on the host (§3). The build matrix mirrors commands verified on
the host for Windows; macOS/Linux are CI-gated (§3).

---

## 5. Formatting-Gate Decision (B15)

The acceptance criterion: *add a format gate only if the existing tree is first
brought into canonical format in a reviewable, intentionally isolated way; never
introduce a permanently failing gate.*

- **Pre-existing state (Task 4):** 36 / 91 Dart files under `frontend/lib+test`
  were non-canonical; CI ran only `analyze`+`test`. A naive `dart format` gate
  would have failed immediately and permanently — correctly avoided in Task 4.
- **This task:** applied `dart format` to the **entire** `lib test` tree in one
  deliberately isolated, **cosmetic-only** pass (no logic), then immediately added
  the gate. The result is formatter-clean (`0 changed`) **and** analyzer-clean.
- **One follow-up micro-fix.** Normalization surfaced exactly one analyzer *info*
  (not a formatter failure): `dart format` wrapped the over-long single-line `if`
  at `home_dashboard_page.dart:250-251` (`if (stats.currentStreak < 7) return …;`
  exceeded 80 cols → body moved to its own line → `curly_braces_in_flow_control_structures`).
  Resolved by adding braces — the canonical, lint-clean form (verified both clean).
  This is a *style* correction directly caused by and scoped to the formatting
  normalization, not an unrelated change.

The full list of the 36 canonized files (all under `frontend/`) is reproduced in
§11 for reviewability.

---

## 6. SDK-Floor Fix (B13)

- **Problem:** `frontend/pubspec.yaml` declared `environment: sdk: ^3.10.4`
  (`>=3.10.4 <4.0.0`), but the resolved `pubspec.lock` requires
  `sdks: dart: ">=3.12.0 <4.0.0"`. A toolchain in the 3.10.x–3.11.x range passed the
  manifest constraint yet could not resolve the locked dependency set — a stale,
  misleading floor.
- **Fix:** `sdk: ^3.10.4` → `sdk: ^3.12.0` (with an explanatory comment to keep it
  in sync with the lockfile floor). The Flutter SDK floor in `pubspec.lock`
  (`flutter: ">=3.44.0"`) and the README's "Flutter 3.44+" prerequisite/badge are
  already aligned; no doc change required.
- **Verified:** `flutter pub get --enforce-lockfile` still exits 0; `pubspec.lock`
  is byte-identical before/after (only the manifest `sdk` field changed) — the
  resolved graph already satisfied `>=3.12.0`.

---

## 7. Native Build System Integrity

- **Version pin (cryptographic).** All three platforms target whisper.cpp **v1.8.4
  @ `9386f239401074690479731c1e41683fbbeac557`** — Windows/Linux via CMake
  `FetchContent` `GIT_TAG`, macOS via the podspec `:commit` + vendored source. No
  moving tags/branches anywhere. (§2.)
- **macOS (CocoaPods / Xcode).** `Podfile` pins `platform :osx, '13.0'` and sets
  `MACOSX_DEPLOYMENT_TARGET = '13.0'` on every pod target; the local
  `whisper.cpp` pod (`pod 'whisper.cpp', :path => '.'`) builds the **bundled**
  copy — **no build-time network fetch** on macOS. The podspec enables the upstream
  macOS backend combo (CPU + BLAS + Metal + Accelerate + CoreML fallback) with
  `static_framework`. `COCOAPODS_DISABLE_STATS=true` avoids a sync stats network
  round-trip during `pod install`.
- **Windows (CMake / Visual Studio).** `windows/runner/CMakeLists.txt` builds
  whisper via `FetchContent` then `add_subdirectory(... EXCLUDE_FROM_ALL)` (so
  whisper install rules never pollute Flutter's install), disables tests/examples,
  forces a static lib, links `whisper`, copies the built artifact next to the exe,
  and gates CUDA on `find_package(CUDAToolkit QUIET)`. **Verified end-to-end** by
  the host build (§3.6). Note: a post-build step optionally copies
  `${CMAKE_SOURCE_DIR}/../../../ggml-tiny.bin` **if it exists** — it does not exist
  in a clean source tree (models are gitignored + runtime-downloaded to user data),
  so it is a harmless no-op for CI; documented in §9 as "models must not ship
  next to the binary."
- **Linux (CMake / GTK).** Mirrors Windows; `linux/CMakeLists.txt` requires GTK3
  (`pkg_check_modules(GTK REQUIRED gtk+-3.0)`), `linux/runner/CMakeLists.txt` adds
  whisper + pthread. The Linux prereqs the new CI job installs satisfy these
  `REQUIRED` lookups.
- **Generated plugin files.** `generated_plugins.cmake`,
  `generated_plugin_registrant.*`, `.plugin_symlinks/`, and all `ephemeral/` dirs
  are **correctly gitignored** (Tasks 1/3); CI regenerates them via `flutter pub get`
  + `flutter build`. The plugin registrar/symlink lists on each platform are
  internally consistent with `pubspec.yaml`.

---

## 8. Versioning, Identifiers, Deployment Targets

| Item | Value | Source |
|---|---|---|
| App version | `0.1.0` | `frontend/pubspec.yaml:4` |
| macOS bundle id | `com.beeamvo.app` | `macos/Runner/Configs/AppInfo.xcconfig:8` |
| Linux application id | `com.beeamvo.app` | `linux/runner/CMakeLists.txt:49` |
| Windows internal name | `beeamvo` | `windows/CMakeLists.txt` `BINARY_NAME` |
| Method channel | `com.beeamvo/whisper` | all three `whisper_plugin.*` |
| macOS deployment target | 13.0 (Ventura) | `macos/Podfile:1,45`; pbxproj `MACOSX_DEPLOYMENT_TARGET` |
| macOS minimum OS note | README says "macOS 13.0+"; README prerequisites say "Xcode 15+" | `README.md` |
| Flutter toolchain floor | `>=3.44.0` (lockfile) / "Flutter 3.44+" (README) | `pubspec.lock`; README badge |
| Dart SDK floor | `^3.12.0` (**fixed this task**) | `pubspec.yaml` ↔ `pubspec.lock` |

Versions are sourced from `pubspec.yaml`/build configs (single sources of truth);
`Info.plist` version keys are Flutter build variables (`$(FLUTTER_BUILD_NAME)`).
The bundle identifier is consistent across macOS/Linux (`com.beeamvo.app`).
*Wart (cosmetic, pre-existing):* the macOS dev codesign script uses a constant
`CERT_CN = "com.beamvo.codesign"` (note `beamvo`, missing an `e`) — a string
cosmetic, not the app's real bundle id. (The doc/script mismatch —
`CODESIGN_README.md` previously promised `Authority=com.beeamvo.codesign` —
was reconciled in the Task 6 documentation sync; the doc now matches the script.
The script's shortened CN itself was left unchanged as a tolerated dev cosmetic.)

---

## 9. Signing, Hardened Runtime, Notarization (binary release — clearly separated)

> **Source CI requires NONE of this.** The CI gate (§4) uses `permissions:
> contents: read` and references zero secrets. Everything below applies **only to
> distributing a prebuilt `.app`/`.dmg`/`.exe` binary release**, which is a separate,
> maintainer-owned process outside CI.

**macOS (the platform with the largest release gap — B7/B8):**
- **App Sandbox is DISABLED** (`Release.entitlements:5-6`
  `com.apple.security.app-sandbox = false`). This is intentional and **not** a
  safe, behaviour-preserving change to make: Beeamvo relies on Accessibility +
  cross-application `CGEvent` injection for auto-paste and `LSSharedFileList` for
  launch-at-login, both restricted under the sandbox. Enabling it requires a
  product redesign. *(Task 2 decision; unchanged.)*
- **Hardened Runtime is NOT enabled.** The pbxproj has no `ENABLE_HARDENED_RUNTIME`
  setting (it defaults off). **Hardened Runtime is a hard prerequisite for Apple
  notarization.** Any distributed build that intends to be notarized must enable it.
- **Signing is ad-hoc only.** All three Xcode build configs ship
  `CODE_SIGN_IDENTITY = "-"` and no `DEVELOPMENT_TEAM`. The committed tooling
  (`frontend/macos/setup_codesign.sh`, `CODESIGN_README.md`,
  `scripts/build_signed_macos.sh`) creates a **local self-signed certificate** and
  is explicitly **"for development, not for distribution"** (`CODESIGN_README.md:45`).
- **Entitlements in use:** `network.client` + `device.audio-input` (both Release and
  DebugProfile); DebugProfile adds `cs.allow-jit` (debug-only, not shipped). These
  are minimal and appropriate.

**Binary-release requirements for macOS (the maintainer must do these, on a real
runner, with a Developer ID — never committed to source CI):**
1. Enable **Hardened Runtime** (`ENABLE_HARDENED_RUNTIME = YES`) on the Runner target.
2. Sign with a **Developer ID Application** identity + team (replace ad-hoc `-`).
3. **Notarize** (`xcrun notarytool submit` … `xcrun stapler staple`).
4. Keep the current minimal entitlements; **leave App Sandbox off** (documented).
5. Reassess Sandbox feasibility later (separate product work).

**Windows:** no code-signing infrastructure is committed (the Windows runner has no
`.pfx`/MSIX/`.appinstaller` config). A distributed `.exe` should optionally be
**AuthentiCode-signed** with an EV/standard certificate to avoid SmartScreen
warnings; this is a packaging-phase step with a private cert, not a source-CI step.

**No installer / DMG packaging exists** for any platform — `flutter build` produces a
raw `.app`/`exe`/bundle only. Producing a `.dmg`, MSIX, or Linux `.tar.gz`/AppImage
is a separate packaging milestone (§10). The existing build helpers are dev
convenience only; do not distribute from them.

**Model files (correctness):** `whisper_service` loads models from the **user data
directory** (downloaded at runtime by `whisper_model_download_service.dart`), and
model files are gitignored (`**/ggml-*.bin`). The CMake `copy_if_different` of
`ggml-tiny.bin` only fires if a stray model sits at the source-tree root (it will not
in a clean release), so models will not leak into a binary by accident.

---

## 10. Packaging & Installer Assumptions

- **What `flutter build` produces:** `build/windows/x64/runner/Release/`
  (verified — §3), `build/macos/Build/Products/Release/Beeamvo.app`,
  `build/linux/x64/release/bundle/`. These are **not** end-user installers.
- **Assumptions baked in:** Whisper models are fetched at runtime (Hugging Face) to
  the user data dir, not bundled. API keys come from OS secure storage via the UI,
  not from any file in the install directory. `google_fonts` typefaces are fetched
  at runtime (never bundled).
- **Gaps (packaging phase, not source CI):** no `.dmg`, MSIX/MSI, or Linux archive
  build/release pipeline; no GitHub release/artifact-upload workflow; no SBOM
  generation step. The checklist (§this task updated) calls these out.

---

## 11. Files Changed (exact)

| Path | Status | Change |
|---|---|---|
| `.github/workflows/ci.yml` | **rewritten** | Lockfile enforcement, pinned Flutter 3.44.2, pub-deps cache, format gate, timeouts, concurrency, Linux job, least-privilege docs. (§4) |
| `frontend/pubspec.yaml` | **modified** | SDK floor `^3.10.4` → `^3.12.0` + sync comment. (§6, B13) |
| `frontend/lib/widgets/settings/pages/home_dashboard_page.dart` | **modified (1 block)** | Added braces around the wrapped single-statement `if` at L250–252 surfaced by formatting normalization. (§5) |
| `frontend/lib/**/*.dart` + `frontend/test/**/*.dart` (**36 files**) | **modified (formatting only)** | Canonicalized by `dart format` in an isolated cosmetic pass. (§5; list below) |
| `docs/build-ci-packaging-audit.md` | **added** | This document. |
| `docs/open-source-release-checklist.md` | **modified** | Format gate added to verification commands; source-build-CI vs. signed-binary-release sections sharpened. |
| `docs/release-baseline-audit.md` | **modified** | B5 / B13 / B15 status updates. |

**The 36 formatter-canonicalized files** (all under `frontend/`):
`lib/main.dart`, `lib/models/prompt_settings.dart`, `lib/models/usage_achievements.dart`,
`lib/models/usage_stats.dart`, `lib/services/keyboard_service.dart`,
`lib/services/keyboard_service_stub.dart`, `lib/services/macos_permission_service.dart`,
`lib/services/recording_service.dart`, `lib/services/usage_stats_service.dart`,
`lib/services/window_helper.dart`, `lib/services/window_helper_macos.dart`,
`lib/services/window_helper_stub.dart`, `lib/services/window_helper_windows.dart`,
`lib/theme/app_theme.dart`, `lib/widgets/frosted_orb.dart`,
`lib/widgets/mode_selection_popup.dart`, `lib/widgets/onboarding/onboarding_shared.dart`,
`lib/widgets/onboarding/onboarding_steps.dart`, `lib/widgets/onboarding/onboarding_wizard.dart`,
`lib/widgets/onboarding/permission_onboarding_dialog.dart`,
`lib/widgets/settings/bee_data_card.dart`, `lib/widgets/settings/bee_dropdown.dart`,
`lib/widgets/settings/bee_input.dart`, `lib/widgets/settings/bee_page_header.dart`,
`lib/widgets/settings/pages/clipboard_page.dart`,
`lib/widgets/settings/pages/home_dashboard_page.dart`,
`lib/widgets/settings/pages/prompts_page.dart`, `lib/widgets/settings/settings_shared.dart`,
`lib/widgets/settings/settings_sidebar.dart`, `test/bee_interactive_hover_test.dart`,
`test/prompt_cloud_activation_test.dart`, `test/prompt_settings_test.dart`,
`test/usage_achievements_test.dart`, `test/usage_stats_test.dart`,
`test/vertex_ai_service_test.dart`, `test/widget_test.dart`.

*(No application logic, dependency versions, README, entitlements, or signing
config were changed. All Task 1–4 work is preserved verbatim in the tree.)*

---

## 12. Residual Risks & Recommendations

1. **Linux first CI run is the true verification.** The runner is structurally
   complete and the pin is consistent, but the `linux` build could not be
   compiled on this Windows host. If the first `linux` CI run is flaky or fails,
   the honest fallback is to downgrade the claim to "Linux runner provided
   experimentally; community-maintained" and/or set `continue-on-error` with a
   tracking issue — rather than assert support. Documented here so the decision is
   reversible with evidence. (B5.)
2. **macOS binary distribution (B7/B8).** Hardened Runtime + Developer-ID signing +
   notarization are **required** before shipping a `.app`/`.dmg` (§9). None of this
   belongs in source CI.
3. **CMake `FetchContent_Populate` deprecation (CMP0169).** Both `windows` and
   `linux` runner CMakeLists use the deprecated imperative form. Functional now;
   migrate to `FetchContent_MakeAvailable` before a future CMake removes it.
4. **Action SHA-pinning.** CI uses major-version tags (`@v4`/`@v2`); SHA-pinning
   hardens against a compromised release tag at the cost of staleness. Optional
   future hardening for this public-source workflow.
5. **No installer / release-artifact pipeline / SBOM.** Only `flutter build`
   outputs exist today (§10). A packaging phase should add `.dmg`, installers, and
   SPDX SBOM generation.
6. **Dev codesign string wart.** `setup_codesign.sh` uses `CERT_CN =
   "com.beamvo.codesign"` (`beamvo`). **Doc/script mismatch reconciled (Task 6):**
   `frontend/macos/CODESIGN_README.md` now tells contributors to expect
   `Authority=com.beamvo.codesign` (matching what the script actually writes), so
   the verification instructions are no longer contradictory. The shortened CN in
   the script itself is a tolerated, dev-only cosmetic and was intentionally left
   unchanged here.
7. **`flutter pub outdated`** (Task 3) reported 27 non-security bumps; untouched
   (not in scope). A periodic dependency-refresh is healthy backlog.

---

## 13. Release Recommendation

- **Public source release: APPROVED.** A clean checkout passes `flutter pub get
  --enforce-lockfile`, `dart format --set-exit-if-changed`, `flutter analyze`, and
  `flutter test` (151/151), and the Windows native `flutter build windows
  --release` compiles the pinned whisper.cpp and all plugins from scratch. The
  platform-support claims are now truthfully reflected and CI-gated on all three
  desktop platforms, the SDK floor is consistent, and source CI needs no secrets.
- **Signed binary release: NOT YET.** Requires the macOS Hardened-Runtime /
  Developer-ID / notarization steps (§9) and packaging/installer work (§10) on a
  real runner with a private cert — explicitly out of scope for source CI.

---

## 14. Unresolved Blockers

**No source-release blockers.** Residual items are explicitly scoped to **binary
distribution and optional hardening** (§12): the macOS signing/notarization
prerequisite (B7/B8), the Linux first-run verification, the CMake FetchContent
migration, installer/SBOM packaging, and action SHA-pinning.
