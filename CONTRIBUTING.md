# Contributing to Beeamvo

Thanks for considering a contribution! Beeamvo is a small, community-maintained
desktop app, and good fixes and docs are welcome. Because security and privacy
are a core part of this project, please read the notes below before opening a PR.

## Prerequisites

Beeamvo is a Flutter desktop app. See the [README](README.md) for platform
prerequisites. In short, from `frontend/`:

```bash
flutter pub get --enforce-lockfile   # use the pinned pubspec.lock versions
flutter analyze                      # must report "No issues found"
flutter test                         # must pass
dart format lib test                 # keep the tree formatter-clean
```

`pubspec.lock` is the source of truth for dependency versions — please do not
re-lock to different versions unless that is the point of your change.

## Before you start

- **Open an issue first** for new features or large changes, so work isn't
  duplicated or rejected after the fact.
- **Keep changes focused.** Prefer one logical change per PR.
- **No secrets.** Never commit API keys, real transcripts, recordings, or `.env`
  files. `.env` is gitignored; `.env.example` is documentation-only with blank
  values.
- **Platform scope.** This is a Windows + macOS app with an experimental Linux
  runner. There are no Android/iOS/web targets.

## Making a change

1. Fork and branch from `main`.
2. Make your change, keeping the tree `flutter analyze`-clean and
   `dart format`-clean.
3. Add or update tests where practical, and confirm `flutter test` passes.
4. If you changed user-visible behaviour, update the relevant docs (README,
   CHANGELOG, or `docs/`).
5. If you add or upgrade a dependency, verify its license is permissive and
   MIT-compatible, and update [`docs/THIRD_PARTY_NOTICES.md`](docs/THIRD_PARTY_NOTICES.md)
   if needed.
6. Open a pull request using the PR template and link any related issue.

## Code style

- Follow the existing style: the project uses `flutter_lints` with a few
  tightened rules (`frontend/analysis_options.yaml`).
- `dart format lib test` must produce no diff.
- Keep security-sensitive handling (credential storage, TLS, external process
  invocation, file paths) defensive and minimal. If your change touches any of
  these, note it in the PR description.

## Native code

The whisper.cpp integration lives under `frontend/{windows,macos,linux}/runner`.
On macOS the bundled `frontend/macos/Runner/whisper.cpp/` source is linked; on
Windows/Linux the pinned upstream `v1.8.4` commit is fetched by CMake
`FetchContent` at build time. Do **not** introduce a git/submodule dependency on
untracked sources.

## Reporting issues

- Bug reports and feature requests: use the issue templates on GitHub.
- **Security issues:** follow [SECURITY.md](SECURITY.md) — do **not** open a
  public issue.

## License

By contributing, you agree your contributions are licensed under the project's
[MIT license](LICENSE).
