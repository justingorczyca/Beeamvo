# Open-Source Release Checklist

Use this checklist before publishing a source archive, GitHub release, or binary distribution.

## Source hygiene

- [ ] Create the public release from tracked files only, preferably from a fresh clone or `git archive`.
- [ ] Do not zip the working directory if ignored files are present.
- [ ] Confirm no local environment files are included:
  - `frontend/.env`
  - `.env.local`, `.env.production`, `.env.*.local`
- [ ] Confirm no generated Flutter or build artifacts are included:
  - `frontend/.dart_tool/`
  - `frontend/build/`
  - `frontend/.flutter-plugins-dependencies`
  - `frontend/android/local.properties`
  - `frontend/ios/Flutter/Generated.xcconfig`
  - `frontend/ios/Flutter/flutter_export_environment.sh`
  - `frontend/linux/flutter/ephemeral/` and `.plugin_symlinks/`
  - `frontend/macos/Flutter/ephemeral/`
  - `frontend/windows/flutter/ephemeral/`
- [ ] Confirm no diagnostic logs are included:
  - `*.log`
  - `build_log.txt`, `run_log.txt`, `analysis.txt`
- [ ] Confirm no signing or credential material is included:
  - `*.pem`, `*.key`, `*.p8`, `*.p12`, `*.pfx`, `*.jks`, `*.keystore`
  - `*.mobileprovision`, `*.provisionprofile`, `*.cer`, `*.crt`, `*.der`
  - `service-account*.json`, `credentials*.json`, `client_secret*.json`

## Verification commands

From the repository root:

```bash
git ls-files | grep -E '(^|/)(\.env$|\.dart_tool/|build/|ephemeral/|\.plugin_symlinks/|\.flutter-plugins-dependencies$|local\.properties$|Generated\.xcconfig$|flutter_export_environment\.sh$|generated_config\.cmake$|build_log\.txt$|run_log(_utf8)?\.txt$|analysis(_output)?\.txt$)|\.(pem|key|p8|p12|pfx|jks|keystore|mobileprovision|provisionprofile|cer|crt|der|log|pdb)$' && echo "Remove the files above" || echo "Tracked source hygiene check passed"
```

From `frontend/`:

```bash
flutter pub get --enforce-lockfile
flutter analyze --fatal-infos
flutter test
```

## Documentation and community

- [ ] README prerequisites match the Flutter version used for development and release builds.
- [ ] `LICENSE` and `CHANGELOG.md` (root) and `docs/THIRD_PARTY_NOTICES.md` are present, and `CHANGELOG.md` has an entry for the new version.
- [ ] Any release notes disclose whether transcription runs locally, through Gemini API, or through Vertex AI.

## Binary release checks

- [ ] Build on a clean machine/runner for each target OS.
- [ ] Verify app bundles do not contain `.env`, local SDK paths, debug symbols, or generated logs.
- [ ] Verify local Whisper model downloads go to the user's app data/support directory, not the installation directory.
- [ ] Verify API keys are entered through the UI and stored in OS secure storage.
