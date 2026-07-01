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

Copyright (c) 2023-2024 The ggml authors

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

## Whisper model weights (Hugging Face)

When a Whisper model is chosen for local transcription, Beeamvo downloads the corresponding `ggml-*.bin` model files at **runtime** from Hugging Face:

- Source: <https://huggingface.co/ggerganov/whisper.cpp>

These converted `ggml` model weights are derived from OpenAI's Whisper models. Per the OpenAI Whisper fair-use guidance and the model card, the weights are made available under **CC-BY-NC-4.0** (Creative Commons Attribution-NonCommercial 4.0 International). This is a *non-commercial* license and imposes different obligations than the MIT-licensed source code above — confirm the current terms on the model card and on the Hugging Face page above before using or redistributing the weights. (The corresponding model files are intentionally gitignored via the `**/ggml-*.bin` rule.)

## Google Fonts (`google_fonts`)

Beeamvo uses the [`google_fonts`](https://pub.dev/packages/google_fonts) package to load typefaces at runtime. The **package itself** is licensed under **Apache-2.0** (<https://github.com/material-foundation/google-fonts-flutter/blob/main/LICENSE>).

The **fonts** served through Google Fonts are licensed separately from the package. Most of them — including **Roboto** and **Material Icons** / **Material Symbols** — are released under the **SIL Open Font License (OFL) 1.1** (<https://scripts.sil.org/OFL>); some legacy font files were previously offered under **Apache-2.0**. **Google Sans** carries additional usage terms — verify on <https://fonts.google.com/>. Always check the per-font license shown on Google Fonts before redistributing any bundled font files.

## Flutter, Dart, and pub.dev dependencies

Beeamvo is built with the **Flutter SDK** and **Dart SDK** (each released under **BSD-3-Clause** — see <https://github.com/flutter/flutter/blob/master/LICENSE> and <https://github.com/dart-lang/sdk/blob/main/LICENSE>) and uses open-source packages from pub.dev. Pinned versions are listed in `frontend/pubspec.yaml` and `frontend/pubspec.lock`. The license names below are best-effort; where a license is uncertain it is marked *(see package)* — confirm on the package's pub.dev page before redistributing.

| Package | License (best-effort) |
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
| screen_retriever | MIT *(see package)* |
| flutter_secure_storage | BSD-3-Clause *(see package)* |
| record | *(see package)* |
| super_clipboard | *(see package)* |
| launch_at_startup | *(see package)* |
| flutter_dotenv | *(see package)* |

When producing binary distributions, include any license files generated by the Flutter build process and any notices required by native dependencies bundled into the app.
