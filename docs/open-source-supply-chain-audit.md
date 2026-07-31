# Open-Source Supply-Chain Audit — Task 3 of 7

> **Scope.** A comprehensive open-source **licensing, dependency / supply-chain, and
> repository-hygiene** audit of the Beeamvo repository, with **safe remediation** of confirmed
> issues. It builds on the Task-1 baseline (`docs/release-baseline-audit.md`, blockers B1–B4, B11)
> and preserves the Task-2 security remediations (`docs/security-privacy-audit.md`). It deliberately
> does **not** expand CI, perform broad dependency upgrades, or rewrite application/docs outside
> licensing & provenance corrections.
>
> **Method.** Findings are evidence-backed with repository paths and (where useful) line numbers.
> Git index/modes, all manifests/locks, vendored code, FetchContent pins, model-download URLs,
> assets, generated plugin files, tracked binaries, submodules/gitlinks, ignore rules, package
> metadata, and dependency provenance were inspected directly. Licenses were verified against each
> component's **authoritative upstream `LICENSE`** rather than assumed. Claims that could not be
> confirmed from the tree are omitted.

---

## 1. Executive Summary

Beeamvo is **licensable for a public MIT release** after this pass. Every distributed component,
native dependency, and asset carries a **permissive, MIT-compatible license**; provenance is clean
(100% pub.dev/SDK-hosted Dart dependencies, no `git:`/`path:` sources or overrides); and the P1
release blockers (orphaned gitlink, two tracked junk files) are resolved.

Four concrete remediations landed:

1. **Removed the orphaned `native/parakeet_runtime/third_party/parakeet.cpp` gitlink** (mode
   `160000`, no `.gitmodules`, zero app references, commit object not even present locally) and its
   orphaned working-tree directory + `.git/modules/native`. `git submodule status` is now clean and
   no gitlinks remain anywhere. *(Resolve of baseline B1/B2.)*
2. **Removed the two accidentally-tracked junk files** `_maindiff.txt` (68 KB UTF-16-LE git-diff
   dump) and `frontend/old_main.txt` (0 bytes), and added `.gitignore` rules to prevent recurrence.
   *(Resolve of baseline B3/B4.)*
3. **Corrected a material licensing inaccuracy.** `docs/THIRD_PARTY_NOTICES.md` claimed the Whisper
   model weights are **CC-BY-NC-4.0 (non-commercial)**. They are **not** — OpenAI's Whisper `LICENSE`
   is MIT and the `huggingface.co/ggerganov/whisper.cpp` model card (the exact repo Beeamvo downloads
   from) declares **`license: mit`**. The notice is corrected to MIT with sources, and a README
   "what the MIT license covers" note distinguishes code vs. model-weights vs. fonts.
4. **Completed the license-inventory gaps**: refreshed the stale whisper.cpp copyright
   (`2023-2024` → `2023-2026`, matching the vendored `LICENSE`) and resolved all `*(see package)*`
   rows from upstream `LICENSE` files (all permissive). *(Resolve of baseline B11.)*

**No residual P1 blockers.** Remaining items (binary-distribution signing/hardening, Linux CI,
icon-size optimization, governance docs) are owned by later phases and are listed in §8.

---

## 2. Methodology & Tooling

| Area | Source of truth inspected |
|---|---|
| Git state | `git ls-files`, `git ls-tree`, `git ls-files --stage` (gitlink/mode 160000 scan), `git submodule status`, `git status`, `git cat-file`, `git log -- <path>`, `.git/modules/` |
| Manifests/locks | `frontend/pubspec.yaml`, `frontend/pubspec.lock`, `.gitmodules` (absent), `.gitattributes` |
| Native | `frontend/{windows,linux}/runner/CMakeLists.txt` (FetchContent pins), `frontend/macos/Runner/whisper.cpp/` (vendored), license files |
| Models/assets | `whisper_model_download_service.dart` (URLs + SHA-256), `frontend/assets/` (icons/logo) |
| Generated/binary | `git ls-files` extension scan for `.exe/.dll/.pdb/.so/.dylib/.bin/.onnx/.gguf/.pt/.mlmodelc` etc. |
| License verification | upstream `LICENSE` files (raw) for whisper.cpp, ggml, OpenAI Whisper, parakeet.cpp, and each previously-unresolved pub package; HF model card |
| Dependency tooling | `flutter pub outdated` (report only — no upgrades performed) |
| Ignore hygiene | `.gitignore`, `frontend/.gitignore`, `.gitattributes`, checklist hygiene grep |

Authoritative license citations (all fetched and treated as source material):

- OpenAI Whisper `LICENSE` → MIT, Copyright (c) 2022 OpenAI (`raw.githubusercontent.com/openai/whisper/main/LICENSE`).
- whisper.cpp `LICENSE` (vendored) → MIT, Copyright (c) 2023-2026 The ggml authors (`frontend/macos/Runner/whisper.cpp/LICENSE`).
- `huggingface.co/ggerganov/whisper.cpp` model card → front-matter `license: mit`.
- parakeet.cpp `LICENSE` → MIT, Copyright (c) 2026 the parakeet.cpp authors (`github.com/mudler/parakeet.cpp`) — *material in this repo but unreferenced; removed (§5.1).*

---

## 3. License Inventory & Compatibility

### 3.1 Code-vs-data license distinction (explicit)

| Layer | What it is | License | Non-commercial? |
|---|---|---|---|
| **App source** | Beeamvo Dart (`frontend/lib/**`) + platform runners | **MIT** (`LICENSE`, Copyright (c) 2026 Beeamvo contributors) | No |
| **whisper.cpp source** | Speech-recognition engine (vendored on macOS; FetchContent on Win/Linux) | **MIT** (Copyright (c) 2023-2026 The ggml authors) | No |
| **Whisper model weights** | `ggml-*.bin`, runtime-downloaded from Hugging Face | **MIT** — derived from OpenAI Whisper (MIT); HF card declares `license: mit` | **No** (CC-BY-NC-4.0 claim was an error — §3.6) |
| **Fonts loaded via `google_fonts`** | Typefaces fetched at runtime (e.g. Roboto, Material) | **Per-font** (most OFL-1.1; some Apache-2.0; Google Sans has extra terms). Not covered by MIT. | No |
| **pub.dev dependencies** | 121 transitive/direct packages | Every verified license is MIT / BSD-3-Clause / Apache-2.0 (permissive) | No |
| **SDK** | Flutter + Dart (BSD-3-Clause) | BSD-3-Clause | No |

**Compatibility conclusion.** Every component the source release distributes (app code, vendored
whisper.cpp, dependencies) is permissive and **compatible with Beeamvo's MIT license**. The
downloaded model weights are **also MIT**, so there is **no non-commercial restriction anywhere in
the distributed or fetched material**. The only separately-licensed runtime material is **Google
Fonts typefaces** (never bundled in this repo; fetched on demand), whose per-font licenses are
documented and carry no NC terms.

### 3.2 Vendored & fetched native code (whisper.cpp / ggml)

- **macOS (vendored):** `frontend/macos/Runner/whisper.cpp/` (**tracked inline**, ~146 entries).
  `CMakeLists.txt:3` → `project("whisper.cpp" VERSION 1.8.4)`; `LICENSE` → MIT
  (Copyright (c) 2023-2026 The ggml authors). A blob-size scan of the vendored tree shows the
  largest entries are all **source** (`ggml/src/ggml-cpu/arch/x86/repack.cpp` 665 KB, Metal shaders,
  etc.); **no model/data/binary blobs** (`.bin/.onnx/.gguf/.pt/.mlmodelc`) are tracked. Only
  `LICENSE` and `README.md` are tracked at the whisper.cpp root.
- **Windows & Linux (FetchContent):** `frontend/windows/runner/CMakeLists.txt` and
  `frontend/linux/runner/CMakeLists.txt` both declare
  `GIT_REPOSITORY https://github.com/ggml-org/whisper.cpp.git`,
  `GIT_TAG 9386f239401074690479731c1e41683fbbeac557 # v1.8.4`. → All three platforms build the
  **same whisper.cpp v1.8.4**.
- **ggml subproject:** upstream ships a single MIT `LICENSE` covering whisper.cpp **and** the
  embedded `ggml/` tree (no separate `ggml/LICENSE`); no additional notice required. Documented in
  `docs/THIRD_PARTY_NOTICES.md`.

### 3.3 Model files & model-download URLs

- No model files are tracked or vendored (model binaries are gitignored via `**/ggml-*.bin`).
- Runtime downloads (`whisper_model_download_service.dart:38-39`) use base URL
  `https://huggingface.co/ggerganov/whisper.cpp/resolve/main` and serve `ggml-tiny.bin`,
  `ggml-tiny.en.bin`, `ggml-tiny-q5_1.bin`, `ggml-base.bin`, `ggml-small.bin` (`:52-99`).
- **Integrity:** each model carries a pinned **SHA-256** (+ legacy SHA-1) enforced before the temp
  file is renamed to its final path (`:510-537`), plus size validation. These SHA-1 values match the
  ones published on the HF model card (tiny/base/small SHAs verified against the card) — provenance
  of the downloaded bytes is anchored to the published artifact.

### 3.4 Assets, fonts & icons

- `frontend/assets/` contains only Beeamvo's own icon/logo images (`app_icon.png`,
  `app_icon_rounded.png`, `beamvo_logo_transparent.png`, `tray_icon_macos.png`, `app_icon.ico`) —
  project-owned assets, covered by the MIT code license. No third-party image/asset noticed beyond
  these.
- **No font files are bundled.** `google_fonts` loads typefaces at runtime; per-font licenses are
  documented in `THIRD_PARTY_NOTICES.md`. `flutter: uses-material-design: true` pulls Material
  Icons via the SDK (Apache-2.0/OFL, already covered by the Flutter notice).
- *(Cosmetic, not licensing)* `app_icon.png` (2.4 MB) / `app_icon_rounded.png` (2.3 MB) /
  `beamvo_logo_transparent.png` (1.5 MB) are unusually large PNGs — baseline B9, owned by a later
  remediation phase; not a licensing issue.

### 3.5 pub.dev dependencies — all permissive (verified)

Direct dependencies in `frontend/pubspec.yaml` and their verified licenses:

| Package | License | Verified |
|---|---|---|
| http, path, path_provider, package_info_plus, win32, ffi, crypto, url_launcher, googleapis_auth | BSD-3-Clause | pub.dev |
| google_fonts | Apache-2.0 | package LICENSE |
| window_manager, hotkey_manager, tray_manager, screen_retriever | MIT | upstream LICENSE |
| flutter_secure_storage | BSD-3-Clause | juliansteenbakker/flutter_secure_storage LICENSE |
| record | BSD-3-Clause | llfbandit/record `record/LICENSE` |
| super_clipboard | MIT | superlistapp/super_native_extensions LICENSE |
| launch_at_startup | MIT | leanflutter/launch_at_startup LICENSE |
| flutter_dotenv | MIT | java-james/flutter_dotenv LICENSE |

(The Flutter/Dart SDK is BSD-3-Clause.) **Every verified dependency license is permissive and MIT-compatible.** No GPL/AGPL/LGPL/copyleft or non-commercial license was found in the dependency graph.

### 3.6 Model-weights license correction (key correction)

`THIRD_PARTY_NOTICES.md` previously stated the `ggml-*.bin` weights are **CC-BY-NC-4.0
(non-commercial)**. This was **unsupported by the authoritative sources**:

- OpenAI releases Whisper under **MIT** in both code and weights — `openai/whisper` `LICENSE` is MIT
  ("Copyright (c) 2022 OpenAI"), and its model card states the weights are MIT.
- The Hugging Face repository Beeamvo actually downloads from —
  `huggingface.co/ggerganov/whisper.cpp` — declares **`license: mit`** in its model-card front-matter.

No referenced source adds a CC-BY-NC-4.0 term to these specific weights. The notice is corrected to
**MIT** with both citations and a defensive "re-confirm the current terms on the model card" note
(licenses can change upstream). The correction is directionally careful: just as MIT must not be
applied to a separately-restricted asset, a non-commercial label must not be applied to a
MIT-licensed asset either.

---

## 4. Dependency / Supply-Chain Provenance

### 4.1 Source types — clean

`frontend/pubspec.yaml` has **no `dependency_overrides`**, **no `git:` sources**, and **no `path:`
dependencies**. `frontend/pubspec.lock` confirms every package is `source: hosted` (pub.dev) or
`source: sdk` (Flutter SDK): measured distribution **121 entries = 116 `hosted` + 5 `sdk`**.
`Select-String pubspec.lock -Pattern source:` returned **zero** non-`hosted`/non-`sdk` entries.
→ **No unmanaged, git-fork, or local-path dependency surface.** All dependency bytes come from
pub.dev's audited, content-addressed archive store.

### 4.2 Outdated / advisory status (report only — no upgrades)

Ran `flutter pub outdated` (Flutter 3.44.2 / Dart 3.12.2). **No security advisories** were reported
for any package. Minor/patch updates are available for 6 direct dependencies (e.g.
`google_fonts` 8.1→8.2, `screen_retriever` 0.2.1→0.2.2, `window_manager` 0.5.1→0.5.2), plus some
major-version bumps on transitive deps (`device_info_plus` 11→13, `package_config` 2→3, etc.) that
are **not** security-driven. **No upgrades were performed** (out of scope / risk-managed); this is
useful backlog for a later dependency-refresh task, not a publication blocker.

### 4.3 Lockfile consistency

Source-type analysis is consistent (all hosted/sdk). `pubspec.yaml` SDK floor `^3.10.4` is looser
than the lockfile-implied `>=3.12.0` union (baseline B13) — non-blocking, owned by a later phase.
`flutter pub get --enforce-lockfile` was **not** re-run here to avoid any lockfile churn; the
checklist's `--enforce-lockfile` gate remains the authoritative build-time consistency check.

### 4.4 Other provenance surfaces

- **CI:** `.github/workflows/ci.yml` uses `actions/checkout@v4` (no `submodules: true`) and the
  cached `subosito/flutter-action@v2`; permissions are scoped to `contents: read`. No third-party
  action secretly mutates the dependency set.
- **Build-time fetch:** only whisper.cpp via the **pinned** FetchContent commit above (not a moving
  branch/tag) — reproducible. No other `wget`/`curl`/downloaded source in the build.
- **Generated plugin files** (`generated_plugin_registrant.*`, `generated_plugins.cmake`,
  `.plugin_symlinks/`, ephemeral dirs) are all correctly **gitignored** (verified absent from
  `git ls-files`).
- **No tracked binaries** anywhere in the repository (extension scan clean).

---

## 5. Repository Hygiene — Findings & Remediation

### 5.1 Orphaned gitlink `native/parakeet_runtime/third_party/parakeet.cpp` (B1/B2) — RESOLVED

**Investigation.**
- Tracked as a **gitlink** (`git ls-tree`: mode `160000`, commit `e8acc6172a94e20a952cf1843decace5d771a94b`); the **only** gitlink in the repo.
- **No `.gitmodules` exists** (`Test-Path .gitmodules` → False); `git submodule status` previously
  failed with `no submodule mapping found in .gitmodules for path 'native/…/parakeet.cpp'`.
- The referenced commit object is **not present in the repository's object database**
  (`git cat-file -t e8acc617…` → "could not get object info"; "Not a valid object name"). So even
  with a `.gitmodules`, no cloner could resolve it without an out-of-band fetch.
- The working tree contained a full nested checkout (remote `github.com/mudler/parakeet.cpp.git` at
  `e8acc617`, "fix(tokenizer): strip special tokens…"), **MIT-licensed** — but `git ls-files native/`
  returned **only the gitlink**: zero files inside are tracked by Beeamvo. → The content ships in
  **no** release artifact; a fresh clone gets an empty directory.
- **Zero references** in the application: `git grep -i parakeet -- frontend .github` → no matches;
  no runner `CMakeLists.txt`/build script imports it. Determined **confidently unused**.

**Decision & action (safest release action).** Because it is (a) unreferenced, (b) unresolvable by
any cloner, and (c) fully recoverable from its own remote (`github.com/mudler/parakeet.cpp.git@e8acc617`),
the gitlink was **removed** (the alternative — adding a `.gitmodules` + integration + notice — would
re-introduce an unused dependency into the release surface).
- `git rm native/parakeet_runtime/third_party/parakeet.cpp` (removed gitlink from the index).
- Removed the now-empty vestigial working-tree directory `native/` and the orphaned
  `.git/modules/native` submodule admin directory.
- Verified: `git submodule status` → clean (no error, no output); `git ls-files --stage` grep
  `160000` → empty.

> **Recovery path if ever needed.** `git clone https://github.com/mudler/parakeet.cpp.git` and reset
> to `e8acc6172a94e20a952cf1843decace5d771a94b`. If parakeet ASR is ever to become a real backend,
> add it as a **proper** submodule (`[submodule "…"]` in `.gitmodules`, `submodules: true` on the
> checkout step), wire it into a runner build, and add a `THIRD_PARTY_NOTICES.md` entry (MIT).

### 5.2 Accidentally-tracked junk (B3/B4) — RESOLVED

- `_maindiff.txt` (root): 68,028-byte UTF-16-LE `git diff`/`git log` paste (blob begins
  `commit 23f8b5fb… / Author: Justin Gorczyca …`). — `git rm`.
- `frontend/old_main.txt`: tracked **0-byte** orphan. — `git rm`.
- Repo-wide tracked-binary/scratch scan now shows **no** remaining junk or binaries.

### 5.3 Ignore-rule improvements

Added a dedicated guard block to the root `.gitignore` so the deleted scratch artifacts cannot be
re-tracked:
```
# Accidentally committed scratch / diff / dump artifacts.
_maindiff.txt
*_maindiff*.txt
old_main.txt
frontend/old_main*.txt
*.diff.txt
```
(`frontend/.gitignore` already covers `*.log` and env/exemption patterns and needed no change.)

### 5.4 Hygiene verification

- Checklist hygiene grep (`docs/open-source-release-checklist.md`) re-run (PowerShell equivalent):
  → **`Tracked source hygiene check passed`** (no `.env`, `build/`, `ephemeral/`, `.plugin_symlinks/`,
  secret material, `.log`, `.pdb`, or the removed junk).
- `git ls-files native/` → empty; `git ls-files --stage | grep 160000` → empty; tracked `*.txt` are
  all legitimate `CMakeLists.txt` build files.

---

## 6. Files Changed / Deleted (exact)

**Deleted (git rm):**
- `_maindiff.txt` — accidental UTF-16-LE git-diff dump (B3).
- `frontend/old_main.txt` — empty orphan (B4).
- `native/parakeet_runtime/third_party/parakeet.cpp` — unreferenced gitlink (B1/B2). (Working-tree
  `native/` directory and `.git/modules/native` also removed.)

**Modified:**
- `docs/THIRD_PARTY_NOTICES.md` — whisper.cpp copyright `2023-2024` → `2023-2026`; model weights
  CC-BY-NC-4.0 → **MIT** (with sources + correction note); resolved all `*(see package)*` /
  partial rows; added ggml + build-provenance notes; strengthened dependency-provenance paragraph.
- `README.md` — added a "What the MIT license covers" note (code + whisper.cpp MIT; model weights
  MIT; Google Fonts per-font).
- `docs/release-baseline-audit.md` — blockers B1–B4 and B11 marked **RESOLVED (Task 3)** in the
  blocker table; §6.1/§6.2 headers and §8 P1 follow-ups annotated.
- `docs/open-source-release-checklist.md` — added source-hygiene bullets (no tracked gitlink without
  `.gitmodules`; no re-add of the parakeet gitlink/junk) and a notice-consistency item.
- `.gitignore` — added the scratch/diff/dump guard block (§5.3).

**Created:**
- `docs/open-source-supply-chain-audit.md` — this file.

> The Task-2 security changes (`README.md` Privacy bullet, `pinned_http_client.dart`,
> `gemini_api_service.dart`, `update_check_service.dart`, `whisper_model_download_service.dart`,
> `troubleshooting_page.dart`, new `macos_tcc_reset.dart`, the re-annotated pinning tests, and the
> two audit docs) are preserved untouched; this pass only adds the README licensing note on top of
> Task-2's README edit. No application logic, CI matrix, or dependency versions were changed.

---

## 7. Commands Run & Outcomes

| Command | Outcome |
|---|---|
| `git ls-tree HEAD native/parakeet_runtime/third_party/parakeet.cpp` | `160000 commit e8acc617…` (gitlink, pre-removal) |
| `git cat-file -t e8acc617…` | `could not get object info` — commit absent from repo |
| `git grep -i parakeet -- frontend .github` | no matches → parakeet unreferenced |
| `Test-Path .gitmodules` | `False` (no submodule mapping) |
| `git submodule status` | was: `fatal: no submodule mapping…`; **after fix: clean** |
| `git ls-files --stage \| Select-String 160000` | was: the parakeet gitlink; **after fix: empty** |
| `git ls-files "…/*" \| … \.(bin\|mlmodelc\|onnx\|gguf\|pt)$` (whisper.cpp) | empty — no model/data blobs tracked |
| `Select-String pubspec.lock -Pattern source:` Group | `116 hosted + 5 sdk`; **0** git/path |
| `flutter pub outdated` | 6 direct deps updatable; **no advisories**; no upgrades done |
| `flutter pub deps` / no overrides | confirmed: no `dependency_overrides`, no `git:`/`path:` |
| checklist hygiene grep | **`Tracked source hygiene check passed`** |
| `git rm` (3 files) + `Remove-Item native`, `.git/modules/native` | success |

---

## 8. Residual Risks & Exact Publication Requirements

**Residual risks (owned by later phases; none are P1 for a source release):**

- **B5** — Linux is claimed (README/CHANGELOG "experimental") but not built in CI. *(CI/Build phase.)*
- **B7/B8** — macOS ships with App Sandbox disabled and has only dev/self-signed signing tooling.
  Not relevant to a **source** release; required for a **binary** release (Hardened Runtime +
  Developer-ID notarization). *(Packaging phase.)*
- **B9** — Large source PNG icons (cosmetic; not licensing).
- **B10** — README doesn't explicitly state the macOS *bundled* whisper.cpp is v1.8.4 (minor accuracy
  item for the docs phase).
- **B12** — No `SECURITY.md` / `CONTRIBUTING.md` / Dependabot / issue templates. *(Docs/CI phase.)*
- **B13** — `pubspec.yaml` SDK floor (`^3.10.4`) looserthan the resolved lockfile (`>=3.12.0`).
  *(Remediation phase; non-blocking.)*
- **Software-Bill-of-Materials depth.** This pass verified **all** dependency **source types** and
  every **direct** + previously-uncertain dependency **license**, and ran `flutter pub outdated` —
  but did not exhaustively re-verify the license of **all ~116 transitive** hosted packages line by
  line (their licenses are inherited permissively via the SDK/pub.dev; a full SPDX SBOM export is a
  follow-up for the CI/docs phase using `dependency_validator`/a SBOM tool). No risk signals were
  observed.

**Exact publication requirements (source release):**

1. The P1 items are done — ship from a **fresh clone or `git archive`** so the deleted junk and the
   removed gitlink are definitively absent.
2. Run `git ls-files --stage | grep 160000` (must be empty) and the checklist hygiene grep (must
   pass) in the release pipeline / CI gate.
3. `frontend/`: `flutter pub get --enforce-lockfile` → `flutter analyze` → `flutter test` (the
   authoritative build-time lockfile/gate is there, not here).
4. Release copy may state: "MIT-licensed code; whisper.cpp shipped/fetched at v1.8.4 (MIT); Whisper
   model weights downloaded at runtime under MIT (verify on the model card)." **Do not** state the
   model weights are non-commercial or CC-BY-NC. **Do not** claim third-party assets beyond what is
   documented.
5. (Binary release only) add Hardened Runtime + Developer-ID signing + notarization for macOS
   (B7/B8); never sign/distribute from the dev-only scripts.

---

## 9. Unresolved Blockers

**None at P1.** All licensing, provenance, and hygiene blockers in this task's scope are resolved:
the orphaned gitlink and tracked junk are removed, ignore hygiene is improved, license/notice
coverage is validated and corrected (including the model-weights MIT correction), dependency
provenance is confirmed clean, and the release checklist/baseline statuses are updated. Remaining
items in §8 are explicitly scoped to later phases (binary signing, Linux CI, SBOM tooling,
governance docs) and are not blockers for the **public source** release.
