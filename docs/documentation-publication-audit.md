# Documentation Synchronization & Publication-Readiness Audit — Task 6 of 7

> **Scope.** A complete documentation synchronization and contributor/publication-readiness
> pass. Every tracked Markdown/text setup or audit document was read and its public claims were
> compared against the current implementation, manifests, CI, tests, platform files, settings UI,
> and the prior audit findings (Tasks 1–5). Stale or contradictory claims, broken links, and
> references to removed components were corrected; standard, factual community-health files were
> added. This pass **does not** implement release packaging, signing automation, or application
> refactors — only documentation and one trivial inline-comment fix.
>
> **Method.** Each documentation claim was checked against its source-of-truth file
> (`frontend/pubspec.yaml`, `frontend/pubspec.lock`, `frontend/lib/config.dart`, the platform
> runners, entitlements, the `CODESIGN` tooling, `.github/workflows/ci.yml`, and the test suite).
> A repo-wide relative-link/path checker was run; stale-version greps and a `flutter analyze` /
> `flutter test` re-run were performed after the one code-comment touch. Evidence is cited below.

---

## 1. Executive Summary

The public documentation is now **synchronized and truthful**. Beeamvo's README, CHANGELOG,
setup guides, platform notes, and the new community-health files all reflect the actual product:
a Flutter desktop app (Windows + macOS supported, Linux experimental) with offline Whisper
transcription and optional Gemini API / Vertex AI cloud, using standard platform TLS with **no**
certificate pinning, OS-secure credential storage, and a clearly documented macOS sandbox/signing
posture.

Seventeen files were changed (nine modified, eight created). The key corrections:

1. **CHANGELOG de-fabricated.** A `[0.1.0] - 2026-06-12` entry with a `releases/tag/v0.1.0` link
   asserted a public release that has not occurred. It was consolidated under **[Unreleased]**;
   only the real `0.1.0` version in `pubspec.yaml` and the genuinely-unreleased changes remain. No
   fabricated release date/tag.
2. **README expanded and corrected** — supported-platforms table (incl. experimental Linux),
   Linux prerequisites/commands, macOS 13.0 deployment target, cloud data-flow/consent, plaintext
   clipboard-history disclosure, standard-TLS posture, macOS sandbox/signing-distinction, a
   troubleshooting section, and known limitations.
3. **Community-health files added** (baseline B12): `SECURITY.md`, `CONTRIBUTING.md`,
   `CODE_OF_CONDUCT.md` (Contributor Covenant 2.1), `.github/ISSUE_TEMPLATE/` (bug, feature,
   config), and `.github/PULL_REQUEST_TEMPLATE.md` — with **no invented SLA, private contact
   address, or governance promise**.
4. **Platform/setup docs corrected** — `CODESIGN_README.md` verification line now matches the
   actual certificate common name (`com.beamvo.codesign`, which the script writes) instead of the
   non-existent `com.beeamvo.codesign`; the cloud setup guides now state the consent/data-flow and
   platform status.
5. **Internal audits clarified** — the baseline phase tracker and blockers B10/B12 were updated
   (resolved by Task 6) so the record has no contradictory "outstanding" labels for closed items;
   the workflow-visualization audit's stale product title ("BeamVo") was annotated as historical
   and its status clarified.

**Validation:** `flutter analyze` → **No issues found!**; `flutter test` → **151 / 151 pass**;
all tracked Markdown relative links resolve (22 files checked).

---

## 2. Files Reviewed (every tracked Markdown/text setup or audit doc)

| File | Type | Outcome |
|---|---|---|
| `README.md` | Public | **Modified** — platforms, prerequisites, build/run, engines, privacy, dev, platform-notes, troubleshooting, limitations. |
| `CHANGELOG.md` | Public | **Modified** — consolidated fabricated release into [Unreleased]. |
| `LICENSE` | Public | Reviewed — MIT, Copyright (c) 2026 Beeamvo contributors. Accurate; no change. |
| `docs/THIRD_PARTY_NOTICES.md` | Public | Reviewed — Whisper MIT, whisper.cpp/ggml MIT, weights MIT (corrected in Task 3), Google Fonts, Flutter/Dart BSD, dependency-provenance. Accurate; no change. |
| `docs/gemini-api-setup.md` | Public setup | **Modified** — added platform status + consent/data-flow. |
| `docs/vertex-rest-setup.md` | Public setup | **Modified** — added platform status + consent/data-flow. |
| `docs/open-source-release-checklist.md` | Public release eng | **Modified** — community-files item, link-check item, no-fabricate-date note. |
| `frontend/macos/CODESIGN_README.md` | Public-ish platform | **Modified** — fixed cert CN mismatch vs `setup_codesign.sh`; added scope note. |
| `frontend/scripts/README_signing.md` | Contributor | Reviewed — accurate dev-signing guidance (stable "Beeamvo Dev" cert, scoped TCC auto-repair). No change. |
| `frontend/.env.example` | Public env | Reviewed — `GEMINI_API_KEY=` / `VERTEX_PROJECT_ID=` (blank, documentation-only). Accurate; no change. |
| `docs/release-baseline-audit.md` | Internal audit | **Modified** — phase tracker + B10/B12 resolved status + follow-ups 7/9. |
| `docs/security-privacy-audit.md` | Internal audit | Reviewed — accurate; "no pinning" posture consistent with code. No change. |
| `docs/open-source-supply-chain-audit.md` | Internal audit | Reviewed — accurate; model-weights MIT correction intact. No change. |
| `docs/build-ci-packaging-audit.md` | Internal audit | Reviewed — accurate; CI matrix, signing-distinction, residuals intact. No change. |
| `docs/code-correctness-audit.md` | Internal audit | Reviewed — accurate; C1 fix intact. No change. |
| `docs/cloud-switch-dialog-audit.md` | Internal audit | Reviewed — accurate engineering record. No change. |
| `docs/transcription-pipeline-audit.md` | Internal audit | Reviewed — accurate engineering record. No change. |
| `docs/workflow-visualization-and-audit.md` | Internal audit | **Modified** — title spelling fixed + status/history note. |

**New community-health / publication files added:**
`SECURITY.md`, `CONTRIBUTING.md`, `CODE_OF_CONDUCT.md`, `.github/ISSUE_TEMPLATE/config.yml`,
`.github/ISSUE_TEMPLATE/bug_report.md`, `.github/ISSUE_TEMPLATE/feature_request.md`,
`.github/PULL_REQUEST_TEMPLATE.md`, and this `docs/documentation-publication-audit.md`.

**One code-comment fix** (documentation accuracy, not application logic):
`frontend/lib/widgets/settings/pages/ai_models_page.dart` — comment referenced the misspelled
class `_BeamVoHomeState`; corrected to the real `_BeeamvoHomeState`.

---

## 3. Coverage Verification (claim ↔ source of truth)

Every area named in the task brief was checked against the implementation:

| Area | Claim location | Verified against | Status |
|---|---|---|---|
| Product name & feature set | README features table | `config.dart` (models), `enums.dart`, settings UI | ✅ Accurate |
| Local vs Gemini API vs Vertex AI behaviour | README engines, setup docs | `cloud_transcription_service.dart`, `gemini_api_service.dart`, `vertex_ai_service.dart` | ✅ Accurate |
| Consent / data flow (audio leaves only on Cloud) | README privacy, setup docs | `prompt_cloud_switch_dialog.dart`, `mode_cloud_confirm_popup.dart` | ✅ Added/accurate |
| Windows/macOS supported; Linux experimental | README supported-platforms, CHANGELOG | `frontend/{windows,macos,linux}/`, `ci.yml` matrix | ✅ Accurate (was understated; now explicit) |
| Prerequisites | README prerequisites | pubspec/CI toolchain pins, Podfile (`platform :osx, '13.0'`) | ✅ Accurate (Linux added, macOS 13.0 added) |
| Exact Flutter/Dart floors & lockfile setup | README prereqs, CHANGELOG, checklist | `pubspec.yaml` (`sdk: ^3.12.0`), `pubspec.lock` (`dart >=3.12.0`, `flutter >=3.44.0`), CI (`flutter-version: '3.44.2'`) | ✅ Aligned |
| Build/test/format commands | README development, checklist, CHANGELOG | `ci.yml` (`pub get --enforce-lockfile`, `dart format --set-exit-if-changed`, `analyze`, `test`, per-OS `build`) | ✅ Match |
| Model download / source / license | README, THIRD_PARTY_NOTICES | `whisper_model_download_service.dart` (HF URL, SHA-256), whisper.cpp v1.8.4 pin | ✅ MIT, accurate |
| Credential storage | README privacy, setup docs, SECURITY.md | `secure_credential_store.dart`, `MainFlutterWindow.swift` (Keychain) | ✅ Accurate |
| Privacy / local storage / clipboard history | README privacy, troubleshooting | `settings_service.dart` (plaintext history + sensitive-text filter) | ✅ Added/accurate |
| Standard TLS, no pinning | README privacy, SECURITY.md | `pinned_http_client.dart` (renamed `createSecureHttpClient`) | ✅ Accurate |
| Permissions | README, CODESIGN_README | `macos_permission_service.dart`, entitlements | ✅ Accurate |
| Troubleshooting | README troubleshooting, CODESIGN_README | `troubleshooting_page.dart`, macOS TCC auto-repair | ✅ Added/accurate |
| macOS sandbox / Hardened Runtime / signing / notarization distinction | README platform-notes, CODESIGN_README, checklist | `Release.entitlements` (`app-sandbox=false`), `setup_codesign.sh` (dev only), build audit §9 | ✅ Distinct & accurate |
| Linux first-CI verification caveat | README platform-notes, build audit §2/§12 | `ci.yml` linux job | ✅ Caveat retained ("if flaky, downgrade to community-maintained") |
| Release process & source-vs-binary readiness | README, CHANGELOG, checklist | build/CI/packaging audit | ✅ "source-only; binary release not yet" |
| Third-party notices | THIRD_PARTY_NOTICES | supply-chain audit (license inventory) | ✅ Accurate, no change |
| Known limitations | README known-limitations | implementation realities | ✅ Added |

---

## 4. Detailed Changes

### 4.1 `CHANGELOG.md` — removed a fabricated release
The prior file asserted `## [0.1.0] - 2026-06-12` "Initial public release" plus a
`[0.1.0]: …/releases/tag/v0.1.0` comparison link. No public release/tag exists at this pre-release
stage (no installer/artifact pipeline — see the build/CI/packaging audit). Per "reconcile … without
fabricating a released tag/date," the dated entry and tag link were **removed**; all content now
lives under a single `[Unreleased]` header (initial-release features under **Added**, audit
hardening under **Fixed**/**Security & Privacy**/**Build & CI**/**Removed**), with a status banner
stating a dated version entry will appear only when a tag is cut. The `0.1.0` value is preserved as
the truth (it is the `version:` in `pubspec.yaml`).

### 4.2 `README.md` — full synchronization
- Replaced the empty GitHub-releases link badge with License/Platform/Flutter/whisper.cpp badges
  (no dead `releases` link while no release exists).
- Added a **Supported platforms** table (Windows 10/11, macOS 13.0+, Linux experimental) and a
  macOS 13.0 deployment-target prerequisite; added Linux prerequisites and `flutter run/build -d linux`.
- Clarified the whisper.cpp build model note (all three platforms build the same v1.8.4).
- Added cloud consent/data-flow sentences to the Gemini and Vertex sections.
- Expanded **Privacy & Security** (cloud opt-in consent, ADC/no-stored-secret, plaintext clipboard
  history + best-effort filter) and linked `SECURITY.md`.
- Added **Platform & build notes** (sandbox intentionally off; dev-only signing; Linux caveat;
  no mobile/web), **Troubleshooting**, and **Known limitations** sections.
- Linked `CONTRIBUTING.md` and `.github/workflows/ci.yml`.

### 4.3 Cloud setup docs (`gemini-api-setup.md`, `vertex-rest-setup.md`)
Each now leads with the platform status and an explicit consent/data-flow note (Whisper Local =
nothing leaves the machine; cloud audio only after an explicit choice, with a first-switch
confirmation dialog).

### 4.4 `frontend/macos/CODESIGN_README.md` — verification truth
The "Verification" section previously told users to expect `Authority=com.beeamvo.codesign`, but
`setup_codesign.sh` writes `CERT_CN="com.beamvo.codesign"` (`beamvo`). Corrected to the actual
common name with an explanatory note, and added an explicit scope note (dev-only; real distribution
needs Developer ID + Hardened Runtime + notarization, which this flow does not provide).

### 4.5 `docs/workflow-visualization-and-audit.md` — status/history
The title used the older spelling "BeamVo"; rather than silently edit/deny the engineering diagrams
(which embed the name in many ASCII boxes), the title was restored to "Beeamvo" and a Status &
history banner was added clarifying the doc is internal/architectural history with potentially-drifted
line numbers.

### 4.6 `docs/release-baseline-audit.md`, `docs/open-source-release-checklist.md`
Baseline phase tracker extended to mark Task 6 complete; blockers **B10** (README bundled-whisper.cpp
v1.8.4 mention) and **B12** (community files) marked RESOLVED. The release checklist gained a
community-health checklist item, a relative-link/path check item, and a "do not fabricate a release
date/tag" note for the CHANGELOG.

### 4.7 Community-health files (no invented promises)
- `SECURITY.md` — private reporting (GitHub Security Advisories) preferred; explicit "no formal SLA"
  statement; lists scope & current TLS/credential/clipboard posture. **No** private email invented.
- `CONTRIBUTING.md` — `pub get --enforce-lockfile` / `analyze` / `test` / `format` workflow; security
  and license-update guidance; points to SECURITY.md.
- `CODE_OF_CONDUCT.md` — Contributor Covenant 2.1 verbatim (standard, no bespoke governance).
- Issue templates (bug, feature) + `config.yml` (blank issues disabled; security contact link) and a
  PR template with the verification checklist.

### 4.8 `frontend/lib/widgets/settings/pages/ai_models_page.dart`
One inline comment referenced `_BeamVoHomeState`; the real class is `_BeeamvoHomeState`
(`frontend/lib/main.dart`). Corrected the typo. No logic change.

---

## 5. Checks Run (with results)

| Check | Command | Result |
|---|---|---|
| Markdown relative-link/path resolution | repo-wide resolver (22 tracked files) | **ALL TRACKED MARKDOWN LINKS RESOLVE** (broken links only in untracked `_deps/whisper-src/` build output & gitignored ephemeral plugin symlinks) |
| Stale "BeamVo" spelling | grep | Fixed in `workflow-visualization-and-audit.md`; only the historical-doc banner remains (intentional) |
| Removed-component refs (parakeet/gitlink/junk) | grep across tracked docs | Public docs (README/CHANGELOG/setup/THIRD_PARTY_NOTICES) contain **none**; internal audits reference them only as "removed/RESOLVED" history (retained per scope) |
| Stale license (CC-BY-NC) | grep | Present only inside audit **correction** notes; no public claim |
| Stale TLS/pinning claims | grep | All assertions state pinning is **not** active; consistent with code |
| Stale SDK floor (3.10.4) | grep / `pubspec.yaml` | Only in audit history; live manifest is `^3.12.0` |
| `flutter analyze` (after .dart comment edit) | `flutter analyze` (from `frontend/`) | **No issues found!** |
| `flutter test` (after .dart comment edit) | `flutter test` (from `frontend/`) | **151 / 151 passed** (no change from baseline) |

---

## 6. Remaining Publication Caveats (residual; out of scope for this phase)

These are **truthfully disclosed** in the docs now; they are future work, not contradictions:

1. **No signed/notarized binary release.** macOS needs Hardened Runtime + Developer-ID +
   notarization; Windows would optionally be AuthentiCode-signed. `flutter build` output is not an
   installer. No `.dmg`/MSIX/installer, GitHub release/artifact pipeline, or SBOM exists yet.
2. **Linux first CI run is the true verification.** The runner is structurally complete and built in
   CI, but the first hosted Linux build is authoritative. If it proves flaky, the documented fallback
   is "experimental / community-maintained" (stated in README & build audit §12).
3. **App Sandbox stays intentionally off** (Accessibility + cross-app event injection + legacy
   login-item API). Enabling it is a product redesign, not a doc fix.
4. **Dev-signing string wart** — `setup_codesign.sh` uses `CERT_CN="com.beamvo.codesign"` (shortened).
   Left as-is (tolerated cosmetic, dev-only); the *documentation* now matches it. Renaming the CN
   would be a script change, out of scope here.
5. **Large source PNG icons** (B9) and exhaustive transitive SPDX SBOM remain backlog items.
6. **Dependabot** is an optional future CI addition (not introduced here; not a blocker).

## 7. Source-release vs. binary-release recommendation

- **Public source release: documentation APPROVED.** README, CHANGELOG, setup/platform docs, and
  community-health files are consistent with code/config/CI, links resolve, removed components are
  not referenced as present, and no release date/tag is fabricated.
- **Binary release: documentation is accurate but the capability does not yet exist.** Docs clearly
  state a signed, notarized, packaged binary release is a separate, not-yet-built milestone.

## 8. Unresolved Publication Blockers

None at the documentation level. Every residual in §6 is an engineering/packaging milestone that is
now **clearly and consistently disclosed** rather than implied or contradicted.
