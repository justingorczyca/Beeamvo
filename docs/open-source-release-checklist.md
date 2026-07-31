# Open-Source Release Checklist

> **Release-candidate state (Task 7 verification).** This checklist records the
> final publication-polish pass. Items are checked `[x]` **only** where there is
> local, reproducible evidence in this working tree; items that require a hosted
> CI run or binary-signing infrastructure are explicitly left `[ ]` and tagged
> **(host-pending)** or **(binary/signing-pending)**. Full evidence and the three
> go/no-go decisions (public source push / tag v0.1.0 / publish binaries) are in
> [`docs/publication-polish-audit.md`](publication-polish-audit.md).

Use this checklist before publishing a source archive, GitHub release, or binary distribution.

## Source hygiene

- [x] Create the public release from tracked files only, preferably from a fresh clone or `git archive`. *(Verified: `git ls-files` clean; no ignored files are tracked — see `docs/publication-polish-audit.md`.)*
- [x] Do not zip the working directory if ignored files are present. *(Guidance; release from a commit/clone, not a `zip` of the working tree.)*
- [x] Confirm no tracked gitlink/submodule remains unless it has a matching `.gitmodules` entry (`git submodule status` must be clean; `git ls-files --stage | grep 160000` must be empty). An orphaned `native/parakeet_runtime/…` gitlink was removed in the supply-chain audit — do not re-add it. *(Verified clean: `git submodule status` empty; no mode-`160000` entries.)*
- [x] Confirm no stray scratch/diff/dump files are tracked (`_maindiff.txt`, `old_main.txt`, `*.diff.txt` — now gitignored). *(Verified: staged deletion of `_maindiff.txt`, `frontend/old_main.txt`; recurrence guarded by `.gitignore`.)*
- [x] Confirm no local environment files are included:
  - `frontend/.env`
  - `.env.local`, `.env.production`, `.env.*.local`
  *(Verified: only `frontend/.env.example` (blank, documentation-only) is tracked.)*
- [x] Confirm no generated Flutter or build artifacts are included:
  - `frontend/.dart_tool/`
  - `frontend/build/`
  - `frontend/.flutter-plugins-dependencies`
  - `frontend/android/local.properties`
  - `frontend/ios/Flutter/Generated.xcconfig`
  - `frontend/ios/Flutter/flutter_export_environment.sh`
  - `frontend/linux/flutter/ephemeral/` and `.plugin_symlinks/`
  - `frontend/macos/Flutter/ephemeral/`
  - `frontend/windows/flutter/ephemeral/`
  *(Verified: tracked-source hygiene grep returns clean.)*
- [x] Confirm no diagnostic logs are included:
  - `*.log`
  - `build_log.txt`, `run_log.txt`, `analysis.txt`
  *(Verified: `frontend/flutter_01.log`, `flutter_02.log` are present only in the working tree and are gitignored.)*
- [x] Confirm no signing or credential material is included:
  - `*.pem`, `*.key`, `*.p8`, `*.p12`, `*.pfx`, `*.jks`, `*.keystore`
  - `*.mobileprovision`, `*.provisionprofile`, `*.cer`, `*.crt`, `*.der`
  - `service-account*.json`, `credentials*.json`, `client_secret*.json`
  *(Verified: none tracked; reproduce with the grep below.)*

## Verification commands (local release gate)

These were run locally (Flutter **3.44.2** / Dart **3.12.2**, Windows host) and
all passed — see `docs/publication-polish-audit.md` for full output.

From the repository root:

```bash
git ls-files | grep -E '(^|/)(\.env$|\.dart_tool/|build/|ephemeral/|\.plugin_symlinks/|\.flutter-plugins-dependencies$|local\.properties$|Generated\.xcconfig$|flutter_export_environment\.sh$|generated_config\.cmake$|build_log\.txt$|run_log(_utf8)?\.txt$|analysis(_output)?\.txt$)|\.(pem|key|p8|p12|pfx|jks|keystore|mobileprovision|provisionprofile|cer|crt|der|log|pdb)$' && echo "Remove the files above" || echo "Tracked source hygiene check passed"
```

From `frontend/` (results captured in `docs/publication-polish-audit.md`):

```bash
flutter pub get --enforce-lockfile     # OK — no lockfile drift
dart format --output=none --set-exit-if-changed lib test   # 91 files, 0 changed (exit 0)
flutter analyze                         # No issues found! (exit 0)
flutter test                           # 151/151 passed (exit 0)
flutter build windows --release        # Built Beeamvo.exe (exit 0) [host = Windows]
```

The host release build could only be run for **Windows** on this worker; macOS and
Linux native builds require Xcode / a Linux GTK toolchain that the Windows host
does not have, so those two are **host-pending** in `.github/workflows/ci.yml`.

The same four steps (plus a native `flutter build` per target OS) run in
`.github/workflows/ci.yml` on push/PR — that is the authoritative, hermetic,
least-privilege (`permissions: contents: read`) source-build gate. It requires
**no** signing identities, tokens, or secrets.

## Documentation and community

- [x] README prerequisites match the Flutter version used for development and release builds (Flutter 3.44+, Dart `>=3.12.0` per `pubspec.lock`/`pubspec.yaml`). *(Verified: README badge + prerequisites ↔ `pubspec.yaml: sdk: ^3.12.0`, `pubspec.lock` dart `>=3.12.0` / flutter `>=3.44.0`, CI pin `3.44.2`.)*
- [x] `LICENSE` and `CHANGELOG.md` (root) and `docs/THIRD_PARTY_NOTICES.md` are present, and `CHANGELOG.md` has an entry for the new version — **do not fabricate a release date/tag; only add a dated version entry when a tag is actually cut and published**. *(Verified: `CHANGELOG.md` is `[Unreleased]` with a "no tag published yet" banner; `LICENSE` MIT; `THIRD_PARTY_NOTICES.md` consistent.)*
- [x] `docs/THIRD_PARTY_NOTICES.md` is consistent with the actual dependency set (see `docs/open-source-supply-chain-audit.md` for the last verified inventory: all deps pub.dev/SDK-hosted; whisper.cpp MIT v1.8.4; Whisper weights MIT). *(Verified: notice ↔ supply-chain audit; no unresolved `(see package)` rows.)*
- [x] Any release notes disclose whether transcription runs locally, through Gemini API, or through Vertex AI. *(Verified: README, CHANGELOG, SECURITY.md, setup docs all disclose the data flow.)*
- [x] Community-health files are present and truthful: `SECURITY.md` (private vulnerability reporting, no invented SLA/contact), `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, and `.github/ISSUE_TEMPLATE/` + `.github/PULL_REQUEST_TEMPLATE.md`. (Added in the documentation sync — see `docs/documentation-publication-audit.md`.) *(Verified: all present; no fabricated contacts/SLAs.)*
- [x] Relative links and referenced paths resolve (run a link/path check before cutting a release). *(Verified: 23 Markdown files (tracked + new untracked) — all relative links resolve; the only relative-link "misses" are inside the vendored upstream `frontend/macos/Runner/whisper.cpp/README.md`, which references non-vendored upstream `examples/`/`bindings/` directories.)*

## Source-build CI (no secrets required)

- [ ] `.github/workflows/ci.yml` is green on a clean checkout (hosted run): analyze +
      format + test on `ubuntu-latest`, and `flutter build --release` on
      `macos-latest`, `windows-latest`, and `ubuntu-latest` (experimental Linux).
      **(host-pending)** — the workflow YAML was inspected locally and the local
      equivalents of every step pass (see "Verification commands" above), but no
      hosted GitHub Actions run has been observed. A hosted green run is required
      before tagging/publishing.
- [x] The workflow uses `permissions: contents: read` and references no secrets. *(Verified: `.github/workflows/ci.yml`; no `secrets.*` anywhere.)*
- [x] `flutter pub get --enforce-lockfile` is the lockfile gate (no silent drift). *(Verified locally: exits 0 with no resolution drift; `pubspec.lock` unchanged.)*
- [x] The Flutter toolchain version pinned in CI matches the README "Flutter 3.44+" prerequisite and the `pubspec.lock` SDK floor. *(Verified: CI `flutter-version: '3.44.2'` ↔ README ↔ lockfile `flutter >=3.44.0`.)*

## Non-blocking supply-chain follow-ups (documented, not gates)

- [x] **Dependabot** added (`.github/dependabot.yml`): conservative, no-secrets,
      weekly `github-actions` + `pub` (`/frontend`) update PRs, grouped minor/patch.
      It is additive and cannot break CI (every PR still passes `ci.yml`). It does
      **not** replace manual review — pub security-update coverage is not
      exhaustive; `pubspec.lock` + the CMake FetchContent pins remain the
      authoritative dependency record. *(Not a release gate.)*
- [ ] **SBOM / SPDX generation** — intentionally **not** added as a workflow. A
      reliable SBOM for this Dart + vendored-whisper.cpp + CMake `FetchContent`
      hybrid needs tooling with good coverage in all layers; an incomplete SBOM
      would itself be a false assurance. For the source release, `pubspec.lock` +
      `frontend/pubspec.yaml` + the pinned `FetchContent`/podspec commits are the
      reviewable dependency record. *(Documented as a binary-release-deliverable
      follow-up — see `docs/publication-polish-audit.md`.)*

## Signed binary release checks (separate from source CI; needs private secrets)

These remain entirely unchecked — binary distribution is not ready. See
`docs/build-ci-packaging-audit.md` §9–10 and `docs/publication-polish-audit.md`.

- [ ] Build on a clean machine/runner for each target OS.

### macOS binary release (gates B7/B8)
- [ ] **Hardened Runtime** enabled on the Runner target (`ENABLE_HARDENED_RUNTIME = YES`);
      it is a prerequisite for notarization and is currently **off** in the project.
- [ ] Signed with a **Developer ID Application** identity + team (the committed
      `CODE_SIGN_IDENTITY = "-"` ad-hoc signing and the `setup_codesign.sh`
      self-signed flow are **dev-only — not for distribution**).
- [ ] **Notarized** (`xcrun notarytool submit` + `xcrun stapler staple`).
- [ ] App Sandbox is intentionally left **off** (CGEvent auto-paste + legacy
      login-item API require it); document this in release notes.
- [ ] Entitlements stay minimal (`network.client`, `device.audio-input`).

### Windows binary release
- [ ] Optionally **AuthentiCode-signed** (standard/EV cert) to avoid SmartScreen
      warnings (the Windows runner has no committed `.pfx`/MSIX config).

### All platforms (output hygiene)
- [ ] Verify app bundles do not contain `.env`, local SDK paths, debug symbols, or generated logs.
- [ ] Verify local Whisper model downloads go to the user's app data/support directory, not the installation directory (model files are gitignored `**/ggml-*.bin` and fetched at runtime).
- [ ] Verify API keys are entered through the UI and stored in OS secure storage.
- [ ] Produce an end-user artifact (`.dmg`, MSIX/MSI, or Linux archive); plain
      `flutter build` output is not an installer.
