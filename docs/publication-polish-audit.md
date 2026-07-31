# Publication Polish & Final Verification Audit — Task 7 of 7

> **Scope.** The final source-release polish and verification pass. It inspects
> the *aggregate* working tree produced by Tasks 1–6 for coherence, accidental
> artifacts, contradictory edits, malformed config, over-broad formatting side
> effects, stale debug output, and release-hostile files; re-runs the **complete
> local release gate**; addresses remaining safe source-release items; records
> the **B9 large-icon** decision with evidence; and renders a single, precise
> **go/no-go** for each of (a) pushing the public source repository,
> (b) tagging `v0.1.0`, and (c) publishing downloadable binaries. It does **not**
> implement a signed binary-distribution pipeline, and it does **not** fabricate
> any hosted-CI or signing result.
>
> **Method.** Every check below was executed on the working tree (not merely
> asserted). Commands and outcomes are recorded verbatim where practical. Claims
> that require hosted infrastructure are explicitly labelled as such.

---

## 1. Executive Summary

The aggregate working tree is **publication-clean and coherent** for a public
source release. The complete local release gate passes end-to-end on the host:

| Local gate | Command | Result |
|---|---|---|
| Toolchain | `flutter --version` | Flutter **3.44.2** (stable, rev `c9a6c48423`) / Dart **3.12.2** |
| Lockfile | `flutter pub get --enforce-lockfile` | **OK** — no resolution drift; `pubspec.lock` unchanged |
| Format | `dart format --output=none --set-exit-if-changed lib test` | **91 files, 0 changed** (exit 0) |
| Analyze | `flutter analyze` | **No issues found!** (exit 0) |
| Test | `flutter test` | **151 / 151 passed** (exit 0) |
| Host release build | `flutter build windows --release` | **Built `Beeamvo.exe`** (1.4 MB, exit 0, ~39 s) |

**Decisions (full evidence in §5):**
- **(a) Push the public source repository → GO.** Code is clean, coherent,
  license/notices consistent, community files truthful, no secrets, no tracked
  junk/gitlinks, docs links resolve, no fabricated release tag.
- **(b) Tag `v0.1.0` → NO-GO until hosted CI is observed green.** Every step the
  CI gate runs passes locally, but **no hosted GitHub Actions run has been
  observed**. Per the no-fabrication requirement, a release tag must wait for a
  green hosted run of all matrix jobs (analyze/format/test + macOS/Windows/Linux
  builds).
- **(c) Publish downloadable binaries → NO-GO.** No installer/artifact pipeline,
  no SBOM, macOS lacks Hardened Runtime / Developer-ID / notarization, Windows
  has no code-signing, and there is no hosted Linux build evidence at release
  time.

---

## 2. Aggregate Coherence Review (Tasks 1–6)

Each prior task's changes were re-inspected as a *whole* for contradictions,
artifacts, and side effects.

### 2.1 No contradictions across audit records
- The baseline tracker (`docs/release-baseline-audit.md`) marks Tasks 1–6
  complete and resolves B1–B6, B10–B15; B7/B8 (macOS binary signing/hardening),
  and B9 (icon size) are the only open items. This is consistent with the
  security, supply-chain, correctness, build/CI, and documentation audits. No
  audit records a blocker as both "open" and "resolved."
- The README/CHANGELOG/SECURITY/setup docs all state the same TLS posture
  (**standard platform TLS; no pinning**), the same platform matrix
  (Windows/macOS supported, Linux experimental), and the same Flutter/Dart
  floors. No doc over-claims a shipped capability.

### 2.2 No accidental artifacts or malformed config
- `.github/workflows/ci.yml` — well-formed YAML; parses; two jobs
  (`analyze-and-test` on `ubuntu-latest`, `build` matrix on
  `[macos, windows, ubuntu]`); top-level `permissions: contents: read`;
  concurrency guard; pinned Flutter `3.44.2`; `--enforce-lockfile`; `dart format`
  gate; pub-dep cache; timeouts. No `secrets.*` referenced.
- `.github/ISSUE_TEMPLATE/config.yml`, `bug_report.md`, `feature_request.md`,
  `.github/PULL_REQUEST_TEMPLATE.md` — read; front-matter valid; no broken
  YAML/markdown.
- `frontend/pubspec.yaml` — `publish_to: 'none'`, `version: 0.1.0`,
  `environment.sdk: ^3.12.0` (matches lockfile `dart >=3.12.0`). Valid.
- `.gitignore` + `frontend/.gitignore` + `.gitattributes` — consistent; secrets,
  ephemera, logs, and the removed-junk patterns are all ignored; binaries marked
  `binary` in `.gitattributes`.

### 2.3 No over-broad formatting side effects
- Task 5's `dart format` canonicalization (36 files) + the one brace fix
  (`home_dashboard_page.dart`) were verified after the fact: the format gate now
  reports **0 changed**, and `flutter analyze` is **clean** — i.e. the
  normalization did not disturb function bodies or introduce analyzer issues. No
  reformatting was applied in Task 7 (the tree was already canonical).

### 2.4 No stale debug output / TODOs
- Grep across `frontend/lib`: **no** `TODO`/`FIXME`/`HACK`/`XXX`.
- **No** raw `print(` calls in `frontend/lib` (only documented `debugPrint`,
  reviewed in the security audit §1; cloud bodies are suppressed from
  user-facing messages and logged only in `kDebugMode`).
- No stale references to removed components in *public* docs; internal audits
  reference `_maindiff.txt`/`parakeet`/`old_main.txt` only as removed/RESOLVED
  history (verified by Task 6, re-confirmed here).

### 2.5 No release-hostile tracked files
- No tracked `*.env`, `*.log`, `*.pdb`, `*.pem/*.key/*.pfx/*.p12`, or service-
  account/credential JSON. No tracked `*.bin`/`*.onnx`/`*.gguf` model blobs, no
  tracked `*.dll`/`*.exe`/`*.so`/`*.dylib`. (§3.1.)

---

## 3. Local Release Gate — Full Execution

Host: **Windows**, working from `frontend/` unless noted.

### 3.1 Git / source hygiene
| Check | Command | Result |
|---|---|---|
| Submodules | `git submodule status` | **empty** (clean) |
| Gitlinks | `git ls-files --stage \| findstr 160000` | **none** |
| `.gitmodules` | `Test-Path .gitmodules` | **absent** (expected) |
| Staged deletions | `git diff --cached --name-status` | `D _maindiff.txt`, `D frontend/old_main.txt`, `D native/parakeet_runtime/third_party/parakeet.cpp` |
| Tracked junk grep | `git ls-files \| findstr "_maindiff.txt old_main.txt parakeet"` | **no tracked junk/gitlink references** |
| Tracked env/secrets/logs/blobs | hygiene greps (`.env`, `.log`, `.pdb`, `*.pem/.key/.p12/.pfx`, `.bin/.onnx/.gguf`, `.dll/.exe/.so`) | **all empty** |
| `flutter_0*.log` ignored? | `git check-ignore frontend/flutter_01.log frontend/flutter_02.log` | **ignored** (present in tree, not tracked) |

### 3.2 Secret scan
Patterns `AIza[…]`, `sk-live[…]`, `glpat-[…]`, `AKIA[…]`, `ghp_[…]`,
`github_pat_[…]`, `xox[…]`, `-----BEGIN … PRIVATE KEY-----`, and
`(password|api_key|secret|token)="…"` assignments were grepped across
`frontend/lib` and `frontend/test`. **No matches** except none. The only
secret-shaped strings anywhere are the *defensive* redaction regexes in
`settings_service.dart` (the filter, not a leak) — unchanged from the security
audit.

### 3.3 Build / quality gate
| # | Command | Outcome |
|---|---|---|
| 1 | `flutter pub get --enforce-lockfile` | **OK** — `Got dependencies!`; 27 incompatible newer versions reported, **none applied**; `pubspec.lock` unchanged |
| 2 | `dart format --output=none --set-exit-if-changed lib test` | **91 files (0 changed)**, exit 0 |
| 3 | `flutter analyze` | **No issues found!** (ran in 2.6 s), exit 0 |
| 4 | `flutter test` | **151 / 151 passed**, exit 0 |
| 5 | `flutter build windows --release` | **Built `build/windows/x64/runner/Release/Beeamvo.exe`** (1,445,376 bytes), exit 0 (~39 s incl. whisper.cpp `FetchContent` + ggml + plugins) |

**Build-time warnings (non-blocking, unchanged from Task 5):**
`FetchContent_Populate(whisper) is deprecated` (CMP0169) in
`windows/runner/CMakeLists.txt:33`; upstream whisper.cpp
`cmake_minimum_required < 3.10` notice. Both are advisory; the build succeeds.

### 3.4 Release-bundle hygiene
`build/windows/x64/runner/Release/` was scanned for `.env`, `.key`, `.pem`,
`.log`, `.pdb` → **none**. `Beeamvo.exe` present (1.4 MB). No stray debug
symbols or generated logs in the bundle.

### 3.5 Host build limitation (documented)
Only the **Windows** release build could run on this host. macOS requires Xcode +
CocoaPods and Linux requires a GTK/C++ toolchain — neither is present — so those
two builds are **host-pending** and are the authoritative native-compile gates in
`.github/workflows/ci.yml`. This is a host limitation, not an unverified-by-
omission claim: the whisper plugin sources and CMake/Podfile wiring were reviewed
in Tasks 4–5.

### 3.6 Documentation link/path check
A repo-wide relative-link resolver was run over the **23** Markdown files in the
working tree (tracked + the new untracked community/audit docs), excluding the
vendored upstream tree and build output.
- **All Beeamvo-authored Markdown links resolve.**
- The only relative-link "misses" are inside the vendored *upstream*
  `frontend/macos/Runner/whisper.cpp/README.md`, which references upstream
  `examples/`/`bindings/`/`models/` directories that are intentionally not
  vendored (only the core MIT source needed to link is included). This is
  third-party upstream content, not Beeamvo documentation, and is left intact.

### 3.7 Git-link / tracked-artifact hygiene checks
`git submodule status` clean; no mode-`160000` entries; the three release
blockers (parakeet gitlink, `_maindiff.txt`, `old_main.txt`) are staged for
deletion and confirmed no longer tracked in the index. No tracked build/ephemeral/
generated artifacts.

---

## 4. Items Addressed in This Pass

### 4.1 Community/license/metadata — re-verified, no change required
- `LICENSE` (MIT, Copyright 2026 Beeamvo contributors), `CHANGELOG.md`
  (`[Unreleased]`, no fabricated tag/date), `docs/THIRD_PARTY_NOTICES.md`
  (Whisper MIT, whisper.cpp/ggml MIT, weights **MIT**, dependency-provenance
  table complete) — all consistent.
- `frontend/.env.example` = `GEMINI_API_KEY=` / `VERTEX_PROJECT_ID=` (blank,
  documentation-only); real `.env` gitignored.
- `frontend/pubspec.yaml` metadata (`name`, `description`, `publish_to: 'none'`,
  `version: 0.1.0`, `sdk: ^3.12.0`) and the `flutter_launcher_icons` config are
  consistent.
- Ignore/export behavior is correct: `.gitignore`/`frontend/.gitignore` exclude
  secrets, ephemera, logs, and the junk patterns; no release-hostile file is
  tracked. `.gitattributes` marks binaries `binary` and normalizes text to LF.
- Community-health files (`SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`,
  issue/PR templates) are present, truthful, and contain **no invented SLA,
  contact address, or governance promise**.

### 4.2 Dependabot — added (conservative, non-blocking)
Added `.github/dependabot.yml` (validated as YAML): weekly `github-actions`
(`/`) and `pub` (`/frontend`) update PRs, `open-pull-requests-limit: 5`, minor/
patch grouped for pub. It is **additive**: it changes no CI behavior, it
references no secrets, and every PR it opens still must pass `ci.yml`
(`--enforce-lockfile`, `dart format`, `analyze`, `test`, per-OS build). The file
carries an explicit, honest "no false assurances" note: pub *security-update*
coverage is not exhaustive, so `pubspec.lock` + the CMake `FetchContent`/podspec
pins remain the authoritative, reviewable dependency record. This satisfies the
"reliable, least-privilege, no false assurance, no secrets" bar.

### 4.3 SBOM / license-generation workflow — documented as a follow-up (not added)
Intentionally **not** added as a workflow. A trustworthy SBOM for this
**Dart + vendored-whisper.cpp + CMake `FetchContent`** hybrid requires tooling
with good coverage across all three layers; an incomplete SBOM would itself be a
**false assurance**. For a *source* release, `frontend/pubspec.lock` +
`frontend/pubspec.yaml` + the pinned `FetchContent`/podspec commits *are* the
reviewable dependency record (verified in the supply-chain audit: 100%
pub.dev/SDK-hosted, no git/path sources, whisper.cpp v1.8.4 pinned by commit).
SBOM generation is recorded as a **binary-release-deliverable** follow-up.

### 4.4 B9 — large source PNG icons: DOWNGRADED to non-blocking with evidence
Investigated thoroughly and **closed as non-blocking (P3)**:

| Asset | Size | Runtime use | Source role |
|---|---|---|---|
| `assets/app_icon.png` | 2.4 MB | Tray icon (`tray_service.dart`) + `flutter_launcher_icons` generator input | Primary icon master |
| `assets/app_icon_rounded.png` | 2.4 MB | **None at runtime** (0 `Image.asset`/`AssetImage`/`setIcon` references) | **Source image for `scripts/convert_icons.py`** (its documented default input) |
| `assets/beamvo_logo_transparent.png` | 1.5 MB | Onboarding/logo `Image.asset` (`onboarding_shared.dart`) | Logo master |
| `assets/tray_icon_macos.png` | 294 B | macOS tray `setIcon` | Tray icon |
| `assets/app_icon.ico` | 113 KB | Windows tray `setIcon` | Windows tray icon |

Findings:
- **Not a licensing/notice problem** — the icons are project-owned, covered by
  the MIT license (supply-chain audit §3.4).
- **Not a functional/security problem** — they build, load, and do not block
  clone, build, test, or analyze.
- `app_icon_rounded.png` is **not** loaded at runtime, but it **is** the
  documented default input to `frontend/scripts/convert_icons.py` ("Generate app
  icons from the rounded source image"). Because `pubspec.yaml` declares
  `assets: - assets/` (whole directory), it is nonetheless bundled into every
  build (`build/.../flutter_assets/assets/app_icon_rounded.png`).
- **Why no code change here:** re-encoding the primary app icon / logo would risk
  altering the project's visual identity and cannot be visually verified on this
  host; removing `app_icon_rounded.png` would orphan the icon generator's
  documented input; narrowing the `assets:` glob would reduce *binary* bloat (not
  the *source*-clone size, which is the relevant metric for a source release) at
  the cost of a packaging-behavior change. Each available "optimization" carries
  risk that exceeds the benefit of a non-blocking P3 item during a source
  release.

**Safe, optional future optimizations (deferred, documented):** (1) re-encode the
PNG masters to smaller dimensions with visual QA before and after; (2) narrow
`pubspec.yaml` `assets:` to explicit runtime paths (`app_icon.png`,
`beamvo_logo_transparent.png`, `tray_icon_macos.png`, `app_icon.ico`) so the
unused `app_icon_rounded.png` stops being bundled into binaries. Neither is a
publication gate.

### 4.5 Clean-clone onboarding — verified
A contributor following `README.md` runs `git clone … && cd Beeamvo/frontend &&
flutter pub get && flutter run -d windows`. The clone contains no broken
gitlink, no junk, no generated artifacts, and no `.env`; prerequisites, build
commands, and the lockfile-enforced first-resolution all check out. The
`docs/open-source-supply-chain-audit.md`, `security-privacy-audit.md`, and
`build-ci-packaging-audit.md` together form the onboarding evidence chain.

---

## 5. Go / No-Go Decisions (separate, evidence-backed)

### (a) Push the public source repository — **GO** ✅
The working tree is publication-clean:
- No secrets (§3.2), no tracked junk/gitlinks/generated artifacts (§3.1, §3.7),
  no stale debug output (§2.4), no malformed/contradictory config (§2.2).
- The complete local quality gate passes: format/analyze clean, 151/151 tests
  pass, Windows release build succeeds with a clean bundle (§3.3–§3.4).
- License/notice/community/metadata are truthful and consistent (§4.1); all
  Beeamvo-authored doc links resolve (§3.6); the CHANGELOG contains **no
  fabricated release tag/date**.
- The source-build CI workflow requires no secrets and is least-privilege.
- **Condition:** make the working-tree changes a commit on `main` (staged
  deletions + new files) before/with pushing, and observe the first hosted CI run
  after it appears (see (b)).

### (b) Tag `v0.1.0` — **NO-GO until hosted CI is observed green** ⛔
- Every step the CI gate runs passes **locally** (§3.3), but **no hosted GitHub
  Actions run has been observed.**
- Tagging implies "this commit is the released version." Per the
  **no-fabrication** requirement, a tag that asserts release-readiness must wait
  for a green hosted run of **all** matrix jobs: `analyze-and-test`
  (ubuntu-latest: lockfile + format + analyze + test) and `build`
  (macos/windows/ubuntu-latest `flutter build --release`), including the
  experimental Linux build and the macOS/Xcode build that cannot be run here.
- Then add a dated `## [0.1.0] - YYYY-MM-DD` entry to `CHANGELOG.md` and create
  the `v0.1.0` tag (the README/security docs already state no tag exists yet).
- **Manual gate before tagging:** a green hosted CI run on the intended commit.

### (c) Publish downloadable binaries — **NO-GO** ⛔
A signed, packaged, distributable binary does not exist and the tooling is
incomplete:
- **macOS:** `ENABLE_HARDENED_RUNTIME` is **off** (a hard prerequisite for
  notarization); only ad-hoc/self-signed dev signing (`CODE_SIGN_IDENTITY = "-"`,
  `setup_codesign.sh` — "for development, not for distribution"); no Developer
  ID, no notarization, no `.dmg` (build/CI/packaging audit §9).
- **Windows:** no committed `.pfx`/MSIX/`.appinstaller`; optional AuthentiCode
  signing not set up.
- **No installer/artifact-release pipeline or SBOM** for any platform
  (`flutter build` output is not an installer).
- **Linux** has no hosted build evidence at release time (it is built in CI but
  not distributed; first hosted build is authoritative).
- All of these require private secrets/config outside the scope of a source
  release. They remain open as the binary-release milestone.

---

## 6. Files Changed (exact)

| Path | Status | Change |
|---|---|---|
| `.github/dependabot.yml` | **added** | Conservative weekly `github-actions` + `pub` update config; no secrets; honest no-false-assurance note (§4.2). |
| `docs/open-source-release-checklist.md` | **modified** | Converted to a clearly-marked **release-candidate** state: items `[x]` only where local evidence exists; hosted-CI and all binary/signing items left `[ ]`; Dependabot recorded, SBOM documented as a follow-up (§4.3). |
| `docs/release-baseline-audit.md` | **modified** | Phase tracker extended to mark Task 7 complete; B9 downgraded to non-blocking with evidence. |
| `docs/publication-polish-audit.md` | **added** | This document. |

No application logic, tests, manifests, CI workflow, or assets were modified in
this pass (the tree was already gate-clean after Tasks 1–6).

---

## 7. Remaining Manual Actions (before tag/publish)

1. **Commit the release tree** to `main`: the staged deletions
   (`_maindiff.txt`, `frontend/old_main.txt`, the parakeet gitlink), all Task 1–6
   + Task 7 modified/new files, and this pass's two new files
   (`.github/dependabot.yml`, `docs/publication-polish-audit.md`).
2. **Publish/go public the source repository** — **(a) is GO** once committed.
3. **Observe a hosted CI run** of `.github/workflows/ci.yml` on the release
   commit. Require green on `analyze-and-test` and all three `build` jobs. If the
   experimental Linux job is flaky, apply the documented fallback (mark Linux
   "community-maintained/experimental") rather than risk a red release gate.
4. **Only after hosted green:** add a dated `[0.1.0]` entry to `CHANGELOG.md`,
   then create the `v0.1.0` tag — **(b)**.
5. **Binary release (later milestone):** stand up macOS Hardened Runtime +
   Developer-ID signing + notarization, Windows code-signing, an
   installer/`.dmg`/MSIX/artifact-release pipeline, and SBOM generation — **(c)**.

## 8. Audit Limitations

- Hosted CI was not exercised (no run observed); **(b)** is explicitly gated on
  it. No hosted or signing success is claimed.
- macOS and Linux `flutter build` could not run on this Windows host (no Xcode /
  GTK toolchain); they are CI-gated (§3.5), consistent with Tasks 4–5.
- Dependency security is *not* asserted as continuously monitored: Dependabot is
  additive and pub security-update coverage is not exhaustive (§4.2); the
  authoritative record remains `pubspec.lock` + the pinned native commits.
- B9 icon optimization is deferred as a non-blocking quality item with two
  concrete, safe options documented (§4.4); it is not gated.
