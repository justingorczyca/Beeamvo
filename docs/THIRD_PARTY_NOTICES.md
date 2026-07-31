# Third-Party Notices

Beeamvo is licensed under the MIT License. This file collects notices for prominent third-party components and assets used by the application. Package-level dependencies are declared in `frontend/pubspec.yaml` and resolved in `frontend/pubspec.lock`; contributors should review upstream package licenses before adding or updating dependencies.

## Whisper

Beeamvo can use Whisper model files originally developed by OpenAI for local speech recognition workflows.

Repository: <https://github.com/openai/whisper>

```text
MIT License

Copyright (c) 2022 OpenAI

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## whisper.cpp / ggml

Beeamvo includes native integration with whisper.cpp for offline transcription.

Repository: <https://github.com/ggerganov/whisper.cpp>

```text
MIT License

Copyright (c) 2023-2026 The ggml authors

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

> **Note on ggml.** The macOS-bundled `whisper.cpp/` tree includes a `ggml/` subproject. The upstream `ggml-org/whisper.cpp` ships a single MIT `LICENSE` that covers both the whisper.cpp and the embedded ggml sources; there is no separate `ggml/LICENSE` file, so no additional notice is required. Both the macOS-vendored copy and the Windows/Linux `FetchContent` pin resolve to whisper.cpp **v1.8.4** (commit `9386f239401074690479731c1e41683fbbeac557`).

## whisper.cpp source provenance (build)

The whisper.cpp / ggml **source code** enters the build in two equivalent ways, both resolving to upstream **v1.8.4** (commit `9386f239401074690479731c1e41683fbbeac557`):

- **macOS:** a vendored local copy under `frontend/macos/Runner/whisper.cpp/` (tracked in this repository; no build-time network needed). Its tracked `LICENSE` is reproduced verbatim above.
- **Windows & Linux:** fetched at build time by CMake `FetchContent` from `https://github.com/ggml-org/whisper.cpp.git`, pinned to `9386f239…` (v1.8.4). See `frontend/windows/runner/CMakeLists.txt` and `frontend/linux/runner/CMakeLists.txt`.

## Whisper model weights (runtime download)

When a Whisper model is chosen for local transcription, Beeamvo downloads the corresponding `ggml-*.bin` model files at **runtime** (never from this repository — they are gitignored via `**/ggml-*.bin`) from Hugging Face:

- Source: <https://huggingface.co/ggerganov/whisper.cpp> (`whisper_model_download_service.dart:38-39`) — e.g. `ggml-tiny.bin`, `ggml-tiny.en.bin`, `ggml-tiny-q5_1.bin`, `ggml-base.bin`, `ggml-small.bin`.
- Integrity: each download is pinned to a **SHA-256** (+ legacy SHA-1) and size, validated before the temp file is moved to its final path (`whisper_model_download_service.dart:510-537`).

**License.** These converted `ggml` model weights are derived from **OpenAI's Whisper** models, which OpenAI releases under the **MIT License** (Copyright (c) 2022 OpenAI — <https://github.com/openai/whisper/blob/main/LICENSE>). The Hugging Face model repository Beeamvo downloads from declares **`license: mit`** in its model card (<https://huggingface.co/ggerganov/whisper.cpp>). The weights are therefore **MIT-licensed** — the same permissive license as the whisper.cpp source. There is **no non-commercial restriction** on these specific weights.

> *Correction note (supply-chain audit — see `docs/open-source-supply-chain-audit.md` §3).* A prior version of this section stated the weights were "CC-BY-NC-4.0 (non-commercial)". That did not match the authoritative sources: OpenAI's Whisper `LICENSE` and the `ggerganov/whisper.cpp` model card both state MIT, and none add a non-commercial term. Licensing can change upstream; re-confirm the current terms on the model card and the OpenAI Whisper repository before redistributing the weights.

## Google Fonts (`google_fonts`)

Beeamvo uses the [`google_fonts`](https://pub.dev/packages/google_fonts) package to load typefaces at runtime. The **package itself** is licensed under **Apache-2.0** (<https://github.com/material-foundation/google-fonts-flutter/blob/main/LICENSE>).

The **fonts** served through Google Fonts are licensed separately from the package. Most of them — including **Roboto** and **Material Icons** / **Material Symbols** — are released under the **SIL Open Font License (OFL) 1.1** (<https://scripts.sil.org/OFL>); some legacy font files were previously offered under **Apache-2.0**. **Google Sans** carries additional usage terms — verify on <https://fonts.google.com/>. Always check the per-font license shown on Google Fonts before redistributing any bundled font files.

## Flutter, Dart, and pub.dev dependencies

Beeamvo is built with the **Flutter SDK** and **Dart SDK** (each released under **BSD-3-Clause** — see <https://github.com/flutter/flutter/blob/master/LICENSE> and <https://github.com/dart-lang/sdk/blob/main/LICENSE>) and uses open-source packages from pub.dev.

**Dependency provenance (supply-chain audit).** Every dependency resolves to a **pub.dev-hosted** package or a Flutter **SDK** package — there are **no `git:` or `path:` sources and no `dependency_overrides`** (verified in `frontend/pubspec.yaml` and `frontend/pubspec.lock`: 116 `hosted` + 5 `sdk` entries, 121 total). Pinned versions are resolved in `frontend/pubspec.lock`. The licenses below were verified against each package's upstream `LICENSE` during the supply-chain audit (see `docs/open-source-supply-chain-audit.md`). Every one is a permissive license (MIT / BSD-3-Clause / Apache-2.0) and is compatible with Beeamvo's MIT release.

| Package | License |
|---|---|
| http | BSD-3-Clause |
| path | BSD-3-Clause |
| path_provider | BSD-3-Clause |
| package_info_plus | BSD-3-Clause |
| win32 | BSD-3-Clause |
| ffi | BSD-3-Clause |
| crypto | BSD-3-Clause |
| url_launcher | BSD-3-Clause |
| googleapis_auth | BSD-3-Clause |
| google_fonts | Apache-2.0 |
| window_manager | MIT |
| hotkey_manager | MIT |
| tray_manager | MIT |
| screen_retriever | MIT |
| flutter_secure_storage | BSD-3-Clause |
| record | BSD-3-Clause |
| super_clipboard | MIT |
| launch_at_startup | MIT |
| flutter_dotenv | MIT |

The four rows previously marked `*(see package)*` were resolved from each package's upstream `LICENSE`: `record` ([llfbandit/record](https://github.com/llfbandit/record) — BSD-3-Clause), `super_clipboard` ([superlistapp/super_native_extensions](https://github.com/superlistapp/super_native_extensions) — MIT), `launch_at_startup` ([leanflutter/launch_at_startup](https://github.com/leanflutter/launch_at_startup) — MIT), and `flutter_dotenv` ([java-james/flutter_dotenv](https://github.com/java-james/flutter_dotenv) — MIT). The two partials were confirmed: `screen_retriever` ([leanflutter/screen_retriever](https://github.com/leanflutter/screen_retriever) — MIT) and `flutter_secure_storage` ([juliansteenbakker/flutter_secure_storage](https://github.com/juliansteenbakker/flutter_secure_storage) — BSD-3-Clause).

When producing binary distributions, include any license files generated by the Flutter build process and any notices required by native dependencies bundled into the app.
