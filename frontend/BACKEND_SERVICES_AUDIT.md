# Backend Services Audit — Transcription / AI Service Layer

**Scope:** Deep-dive audit of the transcription/AI backend service layer for
Beeamvo (Flutter desktop: macOS/Windows/Linux).

**Files audited (every one read in full):**

| # | File | Lines | Role |
|---|------|-------|------|
| 1 | `lib/services/whisper_service.dart` | 473 | Local Whisper.cpp integration via method channel (`ChangeNotifier`) |
| 2 | `lib/services/cloud_transcription_service.dart` | 147 | Orchestrator over the cloud backends (Gemini / Vertex) |
| 3 | `lib/services/cloud_transcription_client.dart` | 45 | Interface + `CloudTranscriptionException` |
| 4 | `lib/services/gemini_api_service.dart` | 438 | Google Gemini API integration (API-key auth) |
| 5 | `lib/services/vertex_ai_service.dart` | 587 | Vertex AI REST integration (ADC OAuth) |
| 6 | `lib/services/transcription_result_guard.dart` | 30 | Validation / sanitization of transcripts |
| 7 | `lib/services/update_check_service.dart` | 176 | GitHub-Releases update checker |
| 8 | `lib/services/usage_stats_service.dart` | 193 | Usage tracking + achievements (`ChangeNotifier`) |
| 9 | `lib/services/pinned_http_client.dart` | 308 | (Un-wired) HTTPS transport + pinning scaffolding |

**Context files read for interfaces (not audited):** `lib/models/transcription_backend_resolver.dart`,
`lib/models/usage_stats.dart`, `lib/models/usage_achievements.dart`,
`lib/models/prompt_settings.dart`, `lib/models/system_prompt.dart`, `lib/config.dart`,
`lib/models/enums.dart`.

**Native call-targets read to evaluate thread isolation:** `macos/Runner/WhisperPlugin.swift`
(273 lines), `linux/runner/whisper_plugin.cc` (343 lines).

**TL;DR — the layer is broadly well-engineered.** Defensive JSON parsing, path-traversal guards,
atomic usage-stats writes, ADC-client generation coalescing, 60 s API timeouts, an inline-payload
size cap, project-id regex validation, and disciplined suppression of upstream error bodies are all
present and correct. The notable issues cluster in four areas: (1) **Whisper inference blocks the
native UI/main thread**, (2) **a lost-update data race in usage tracking**, (3) **missing retry/
backoff for transient cloud failures**, and (4) **a few result-validation gaps** (no length cap,
no control-character stripping). No API key is ever logged, embedded in a URL, or echoed in a
user-facing error — credential handling is the strongest part of this layer.

---

## Executive Summary

| ID | Severity | File | Lines | Finding |
|----|----------|------|-------|---------|
| H-1 | **High** | `whisper_service.dart` (+ native `WhisperPlugin.swift` / `whisper_plugin.cc`) | dart 404–409; mac 73–143, 188–255; linux 236–305 | Whisper inference (`whisper_full`) runs **synchronously on the native platform/UI thread** → app window/tray freezes during local transcription |
| H-2 | **High** | `usage_stats_service.dart` | 95–130 | `recordTranscription` is a read-modify-write across `await _save()` with **no mutex** → overlapping recordings cause a **lost update** (stats/achievements silently lost) |
| M-1 | Medium | `whisper_service.dart` | 411–413 | `transcribeRawPcm` wraps every native `PlatformException` in a generic `Exception('Transcription failed: $e')`, **discarding structured error codes** (`busy`/`not_initialized`) and embedding native detail in the message |
| M-2 | Medium | `gemini_api_service.dart`, `vertex_ai_service.dart` | gem 269–325; vertex 439–507 | **No retry/backoff for transient failures** (Gemini: none at all; Vertex: only one 401/403 retry). 429 / 5xx surface immediately to the user |
| M-3 | Medium | `vertex_ai_service.dart` | 87–91, 130–175 | ADC client creation (`clientViaApplicationDefaultCredentials`) has **no timeout** → can hang indefinitely on stalled auth/network |
| M-4 | Medium | `gemini_api_service.dart` | 301–324 | Safety/content blocks return an empty `candidates[].content` → user sees the misleading **"Gemini returned an empty response"** instead of "blocked by safety filter" |
| M-5 | Medium | `gemini_api_service.dart`, `vertex_ai_service.dart` | gem 218–239; vertex 328–349 | Plain audio **transcription** payload sets no `maxOutputTokens` → unbounded/oversized model response can reach the UI/clipboard |
| M-6 | Medium | `transcription_result_guard.dart` | 20–29 | `requireTranscript` does **no length cap** and does **not strip BiDi/control/terminal-escape chars** → prompt-injection-into-paste risk + memory exposure |
| M-7 | Medium | `pinned_http_client.dart`, `gemini_api_service.dart` | pinned 61–63; gem 18, 279 | **No certificate pinning** is wired (documented as out-of-scope). The long-lived Gemini API key travels as a bearer header over standard TLS only |
| M-8 | Medium | `usage_stats_service.dart` | 13, 95 | `_file` is a `late` field; calling `recordTranscription` before `initialize()` throws an unrecoverable `LateInitializationError` |
| L-1 | Low | `update_check_service.dart` | 89, 137 | `force` parameter is **accepted but never used** — "Check now" may silently no-op |
| L-2 | Low | `usage_stats_service.dart` | 157–159 | Word counting splits on whitespace only → **CJK/other unsegmented languages** undercount to ~1 word, distorting stats & achievements |
| L-3 | Low | `vertex_ai_service.dart` | 471–475 | Debug-mode logging dumps the **full upstream response body** to logs (may contain project metadata / residual PII) |
| L-4 | Low | `update_check_service.dart` | 155–174 | Version compare keeps only the first 3 components → `1.2.3.4` is treated as `1.2.3.0` |
| L-5 | Low | `update_check_service.dart` | 89–98 | Unauthenticated GitHub API (60 req/h/IP), no `ETag`/conditional request → users behind NAT silently get "no update" on rate-limit |
| L-6 | Low | `whisper_service.dart` | 312–377 | `initialize` / `unloadModel` are **not serialized internally**; correctness depends on the caller serializing transitions (fragile contract) |
| L-7 | Low | `gemini_api_service.dart`, `vertex_ai_service.dart` | gem 269–283; vertex 439–451 | No **request cancellation** for in-flight cloud POSTs — user "cancel" does not abort the network request |
| L-8 | Low | `gemini_api_service.dart`, `vertex_ai_service.dart` | gem 178–191; vertex 287–300 | Inline payload keeps the raw `Uint8List` + a base64 `String` copy + the encoded JSON body in memory simultaneously (~3× peak for large recordings) |
| L-9 | Low | `pinned_http_client.dart` | 273–307 | `captureLeafCertificateDescription` has no `.timeout()` (manual maintainer tool, but shipped) |
| L-10 | Low | `cloud_transcription_service.dart` | 75–79 | `initialize()` is a no-op flag flip in both clients; switching provider mid-session can briefly use a "fresh" client with no readiness proven |
| I-1 | Info | `cloud_transcription_service.dart`, `transcription_backend_resolver.dart` | — | By-design: **no automatic local→cloud fallback**; a Whisper failure surfaces an error rather than retrying on cloud (good for cost/predictability — confirm intent) |
| I-2 | Info | `usage_stats_service.dart` | 11 | `UsageStatsService extends ChangeNotifier` but never overrides `dispose()` / calls `super.dispose()`; `dailyWordCount` grows ~365 entries/year (negligible) |

**Severity counts:** High ×2 · Medium ×8 · Low ×10 · Info ×2.

---

## Detailed Findings

### H-1 — Whisper inference blocks the native UI / main thread
**Severity:** High · **Files:** `lib/services/whisper_service.dart` (dart 404–409),
`macos/Runner/WhisperPlugin.swift` (73–143, 188–255), `linux/runner/whisper_plugin.cc` (236–305)

**What's wrong.** `WhisperService.transcribeRawPcm` invokes `'transcribeRaw'` over a method
channel. On the Dart side the call is correctly `await`ed and non-blocking. The problem is the
**native** impl: on macOS `handleTranscribeRaw` (Swift, line 73) runs in the FlutterMacOS method
handler, which executes on the **main thread**, and calls `transcribePcm` (line 135) which runs
`whisper_full(...)` **inline** (line 232) — no `DispatchQueue.global(...)` / background thread. The
same is true on Linux (`whisper_plugin.cc` line 236–305, `transcribe_pcm` called inline before
`fl_method_call_respond`). `whisper_full` for even a few seconds of audio takes multiple CPU
seconds; during that time the **native main/event thread is blocked**, so window dragging/resizing,
the tray menu, menu-bar interactions, and ALL other platform-channel messages (e.g. hotkey/clipboard
plumbing) stall → spinning beach-ball / frozen window until inference completes.

The native code already has the locking (`contextLock`, atomic `busy`) it would need to dispatch
inference off-thread; it just never does the dispatch.

**Recommended fix (macOS).** Move inference to a background queue and call `result` from there
(`FlutterResult` is thread-safe to invoke off the main thread):

```swift
private func handleTranscribeRaw(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
        result(FlutterError(code: "invalid_args", message: "Missing arguments", details: nil)); return
    }
    contextLock.lock()
    if busy { contextLock.unlock()
        result(FlutterError(code: "busy", message: "Transcription already in progress", details: nil)); return }
    busy = true
    contextLock.unlock()
    cancelLock.lock(); cancelRequested = false; cancelLock.unlock()

    guard let pcmBytes = args["pcmBytes"] as? FlutterStandardTypedData else {
        contextLock.lock(); busy = false; contextLock.unlock()
        result(FlutterError(code: "invalid_args", message: "Missing pcmBytes", details: nil)); return
    }
    let sampleRate = args["sampleRate"] as? Int ?? 16000
    let channels   = args["channels"]   as? Int ?? 1
    let language   = args["language"]   as? String ?? "auto"

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
        guard let self else { return }
        let samples = self.toFloatSamples(pcmBytes.data, channels: channels)   // extracted helper
        let text = self.transcribePcm(samples: samples, sampleRate: sampleRate, language: language)
        self.contextLock.lock(); self.busy = false; self.contextLock.unlock()
        DispatchQueue.main.async { result(text) }   // or just `result(text)` — it is safe off-thread
    }
}
```

Apply the equivalent `std::thread` / `g_task_run_in_thread` move on Linux (`whisper_plugin.cc`)
and on Windows (`windows/runner/whisper_plugin.cpp`). Inference, PCM→float conversion, and context
init should all run off the platform thread.

---

### H-2 — UsageStats lost-update race in `recordTranscription`
**Severity:** High (data integrity) · **File:** `lib/services/usage_stats_service.dart` (95–130)

**What's wrong.** `recordTranscription` performs a classic read-modify-write of the in-memory
`_stats` and then `await _save()`. The `await` is an interleaving point. The class is a
`ChangeNotifier` with no internal serialization, so two near-simultaneous completions (e.g. a
two-pass finish racing the next session, or two recordings ending back-to-back) interleave like
this:

```
A: read _stats (totalWords=100)            ─┐
B: read _stats (totalWords=100)            ─┤ both see the pre-update snapshot
A: compute += 50   → _stats.totalWords=150 │
A: await _save()   ─ yields to event loop  │
B: compute += 80   → _stats.totalWords=180 ─┘ (recomputed from STALE 100)
B: await _save()
```

B's write wins → A's 50 words are silently lost. The same race loses `totalRecordings`,
`dailyWordCount`, streak recomputation, and achievement thresholds. Because `_save` itself does
`await tmp.writeAsString(...)` *before* the assignment-overwrite, even the on-disk file reflects the
last writer only.

**Recommended fix.** Serialize all mutating ops through a single-flight task chain so writes are
strictly ordered:

```dart
Future<void>? _writeChain;

Future<void> recordTranscription(String text, Duration recordingDuration) {
  // Chain onto the previous op so nothing interleaves across the `await _save()`.
  final next = (_writeChain ?? Future<void>.value()).then((_) => _recordTranscriptionUnserialized(text, recordingDuration));
  // Keep the chain reference even if it fails, so a bad write doesn't break future ones.
  _writeChain = next.catchError((_) {});
  return next;
}

Future<void> _recordTranscriptionUnserialized(String text, Duration recordingDuration) async {
  // ...existing read-modify-write + await _save() + notifyListeners() ...
}
```

(For higher fidelity, also guard `_load`/`initialize` against a `recordTranscription` that starts
before `initialize` finishes — see M-8.)

---

### M-1 — `transcribeRawPcm` swallows the structured native error code
**Severity:** Medium · **File:** `lib/services/whisper_service.dart` (411–413)

**What's wrong.**
```dart
try {
  final text = await _invokeNative<String>('transcribeRaw', { ... });
  return text ?? '';
} catch (e) {
  throw Exception('Transcription failed: $e');   // ← loses code; embeds raw native detail
}
```
The native layer returns meaningful `FlutterError(code: "busy"|"not_initialized"|"invalid_args",
...)`. Wrapping everything in a bare `Exception` with a string-concatenated message (1) discards the
`code` so callers **cannot distinguish "busy/temporary" from a hard failure**, and (2) bakes the
native `details` string into a user-presentable message. The sentinel the app uses for flow control
is `CloudTranscriptionException`; a generic `Exception` here can't be pattern-matched cleanly.

**Recommended fix.** Preserve a usable code/message and never leak native internals:

```dart
try {
  final text = await _invokeNative<String>('transcribeRaw', {
    'pcmBytes': pcm16Bytes,
    'sampleRate': sampleRate,
    'channels': channels,
    'language': language,
  });
  return text ?? '';
} on PlatformException catch (e) {
  // Surface a clean, actionable message; keep the code for caller logic.
  throw CloudTranscriptionException(
    e.code == 'busy'
        ? 'Local transcription is already running. Try again shortly.'
        : 'Local transcription failed. Check that the Whisper model is installed and try again.',
  );
} catch (e) {
  throw CloudTranscriptionException('Local transcription failed. Please try again.');
}
```

---

### M-2 — No retry / backoff for transient cloud failures
**Severity:** Medium · **Files:** `gemini_api_service.dart` (269–325),
`vertex_ai_service.dart` (439–507)

**What's wrong.** Both clients translate HTTP status into a user-facing message but only Vertex
retries, and only for 401/403 (a single, immediate retry). There is **no retry for the genuinely
transient statuses** — `429` (rate limit, which the Gemini message explicitly tells the user to
"try again"), `500/502/503/504`, or transient socket/`TimeoutException` on the POST. With a 60 s
timeout, even a brief blip or a single rate-limit hit stops a whole recording's transcription.

**Recommended fix (shared helper).** Wrap the POST with bounded exponential backoff for the
idempotent-or-safely-replayable statuses; honor `Retry-After` when present:

```dart
Future<http.Response> _postWithRetry(
  Future<http.Response> Function() send, {
  int maxAttempts = 3,
}) async {
  var attempt = 0;
  for (;;) {
    try {
      final res = await send().timeout(const Duration(seconds: 60));
      if (res.statusCode == 429 || res.statusCode >= 500) {
        if (++attempt >= maxAttempts) return res;
        final ra = int.tryParse(res.headers['retry-after'] ?? '') ??
                   (1 << attempt) + Random().nextInt(500); // ms-ish
        await Future<void>.delayed(Duration(milliseconds: ra));
        continue;
      }
      return res;
    } on TimeoutException {
      if (++attempt >= maxAttempts) rethrow;
      await Future<void>.delayed(Duration(milliseconds: 500 * (1 << attempt)));
    }
  }
}
```
(Audio transcription POSTs carry the audio inline, so they are safe to retry as identical
requests.)

---

### M-3 — Vertex ADC client creation has no timeout
**Severity:** Medium · **File:** `lib/services/vertex_ai_service.dart` (87–91, 130–175)

**What's wrong.** The POSTs each have `.timeout(60s)`, but the cached ADC client is created via
`_defaultAdcClientFactory()` → `clientViaApplicationDefaultCredentials(...)` with **no timeout**. If
`GOOGLE_APPLICATION_CREDENTIALS` points at a remote metadata server, or the token endpoint is
unreachable but TCP-handshakes, the `_adcClientCreation` future canpend **indefinitely**; the first
transcription after app start then hangs forever instead of failing fast.

**Recommended fix.** Bound creation. Keep the generation-aware caching already present:

```dart
static Future<http.Client> _defaultAdcClientFactory() {
  return clientViaApplicationDefaultCredentials(scopes: [_cloudPlatformScope])
      .timeout(const Duration(seconds: 30));
}
```
(`_getAdcClient` already converts creation errors into a `CloudTranscriptionException`, so a
`TimeoutException` will be surfaced as "Vertex ADC is not configured…", which is acceptable — or
add a distinct timeout message.)

---

### M-4 — Gemini safety/content blocks surface as "empty response"
**Severity:** Medium · **File:** `gemini_api_service.dart` (301–324) (same shape in Vertex 482–506)

**What's wrong.** When Gemini refuses the content (`promptFeedback.blockReason` set, or a candidate
`finishReason` of `SAFETY`/`RECITATION`/`PROHIBITED_CONTENT`), `candidates` may be non-empty but
contain **no `text` part**. The extractor builds an empty buffer and throws
`'Gemini returned an empty response.'` — an unhelpful diagnostic for the user, who just hears
"empty" with no actionable cause.

**Recommended fix.** Inspect the block reasons before declaring emptiness:

```dart
final promptFeedback = decoded['promptFeedback'];
final blockReason = promptFeedback is Map
    ? promptFeedback['blockReason'] as String?
    : null;
if (blockReason != null) {
  throw CloudTranscriptionException(
    'Gemini blocked this request ($blockReason). Try rephrasing or a different model.',
  );
}
final finishReason = (candidates.first is Map)
    ? (candidates.first as Map)['finishReason'] as String?
    : null;
if (text.isEmpty) {
  if (finishReason != null && finishReason != 'STOP') {
    throw CloudTranscriptionException('Gemini did not finish the response ($finishReason).');
  }
  throw CloudTranscriptionException('Gemini returned an empty response.');
}
```

---

### M-5 — Plain audio transcription sets no output-size cap
**Severity:** Medium · **Files:** `gemini_api_service.dart` (218–239), `vertex_ai_service.dart` (328–349)

**What's wrong.** `buildImprovePayload` and `buildTranscribeAndImprovePayload` set
`maxOutputTokens: 32768`, but `buildTranscribePayload` (audio-only transcription) does **not**. A
hallucinating or degenerate model can therefore emit an arbitrarily large string that flows
straight into `TranscriptionResultGuard.requireTranscript` and out to the clipboard/paste-target
with no bound.

**Recommended fix.** Cap output on the transcription payload too (and/or enforce a hard cap in the
guard — see M-6):

```dart
'generationConfig': _buildGenerationConfig(
  temperature: 0.5,
  maxOutputTokens: 8192,                       // ← add
  thinkingConfig: _buildThinkingConfig(model: model, forceMinimal: true),
),
```

---

### M-6 — `requireTranscript` enforces no length cap or character sanitization
**Severity:** Medium · **File:** `transcription_result_guard.dart` (20–29)

**What's wrong.** The guard trims and checks for the no-transcript sentinels, but it does **not**
(a) cap the length of the returned text, or (b) strip/neutralize dangerous characters. Two concrete
exposures follow from that:

1. **No length cap** combines with M-5 (and even with the 32768-token improve cap) to allow a very
   large transcript into the typing/paste path (memory + UI churn).
2. **No control/BiDi stripping.** A cloud model (or a malicious speaker whose words the model
   preserves verbatim) can emit terminal escape sequences (`\x1b[...]`), BiDi overrides
   (`U+202E`/`U+202C`), or zero-width characters. Depending on the app's "type it out" path this
   can spoof text or inject control bytes into the paste target (notably a terminal). The guard is
   the correct chokepoint to harden this for every backend.

**Recommended fix.**

```dart
/// Reasonable transcript ceiling; the UI/clipboard shouldn't get megabytes.
static const int maxTranscriptChars = 20000;

static String requireTranscript(String text) {
  var normalized = text.trim();
  if (normalized.isEmpty) {
    throw CloudTranscriptionException(noTranscriptMessage);
  }
  final marker = normalized.toUpperCase();
  if (marker == noTranscriptMarker || marker == 'NO_TRANSCRIPT') {
    throw CloudTranscriptionException(noTranscriptMessage);
  }
  normalized = _sanitize(normalized);
  if (normalized.length > maxTranscriptChars) {
    normalized = normalized.substring(0, maxTranscriptChars);
  }
  return normalized;
}

/// Remove BiDi controls, C0/C1 controls (except \t \n \r), and common terminal
/// escape sequences so a transcript can never smuggle formatting/escapes.
static String _sanitize(String s) {
  // ESC + CSI/OSC sequences
  s = s.replaceAll(RegExp(r'\x1B\[[0-?]*[ -/]*[@-~]'), '');
  s = s.replaceAll(RegExp(r'\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)'), '');
  // BiDi / format controls U+202A–U+202E, U+2066–U+2069, RTL/LTR marks, BOM
  s = s.replaceAll(
    RegExp(r'[\u202A-\u202E\u2066-\u2069\u200E\u200F\u200B\uFEFF]'),
    '',
  );
  // C0/C1 controls except tab/newline/CR
  s = s.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]'), '');
  return s;
}
```

---

### M-7 — No certificate pinning; the Gemini API key travels over plain OS-TLS only
**Severity:** Medium (residual, documented) · **Files:** `pinned_http_client.dart` (61–63),
`gemini_api_service.dart` (18, 274–282)

**What's wrong / assessment.** `createSecureHttpClient()` returns `IOClient(HttpClient())` with the
default OS trust store and **no** `badCertificateCallback`. The pinning machinery in the rest of the
file is, **correctly and honestly, not wired** — the file's own docs explain that a Dart
`badCertificateCallback` cannot soundly enforce pinning and that the fail-open `rejectPin` branch
would make TLS *weaker*. The genuine residual risk: the **Gemini API key is a long-lived bearer
secret** sent in the `x-goog-api-key` header on every request; without pinning, any attacker who can
present an OS-trusted certificate (compromised/enterprise CA, a trusted root sub-CA) can MITM and
extract it. The Vertex path uses short-lived ADC OAuth tokens, so it is less exposed.

**Recommended fix.** Accept and document the risk explicitly at the transport boundary (good for an
open-source desktop app), **and** prefer the following mitigations order:
1. Keep documenting that pinning is unimplemented (already done well).
2. Prefer the **Vertex/ADC** path where possible (rotating tokens vs. static key) — document this as
   the recommended deployment.
3. If pinning is desired, implement **sound fail-closed pinning in native code** (per-host TLS
   intercept / custom `SecurityContext`), re-using the pure `evaluateCertificatePin` layer, and
   **never** wire `badCertificateCallbackResult`'s fail-open branch (it returns `true` and would
   accept a cert that already failed OS validation).

---

### M-8 — `UsageStatsService._file` is `late`; record-before-init throws
**Severity:** Medium · **File:** `lib/services/usage_stats_service.dart` (13, 33, 95)

**What's wrong.** `_file` is declared `late File _file;` and assigned only in `initialize()`.
`_save()` (and therefore `recordTranscription`) dereferences `_file`. If any code path calls
`recordTranscription` before `initialize()` finishes (e.g. a recording completing during startup, or
a provider initialized out of order), it throws `LateInitializationError`, which is **not caught**
by `_save()`'s try/catch — `_save` does `try { ... await _writeAtomic(_file, encoded); }` but
reading the `late` field happens *inside* the try, so the `LateInitializationError` *would* be
caught… however the `_stats` mutation in `recordTranscription` itself already ran, so the in-memory
state advances while nothing is persisted, and `notifyListeners()` still fires.

**Recommended fix.** Make the field nullable and no-op/save-defer cleanly until initialized:

```dart
File? _file;
bool _initialized = false;

Future<void> recordTranscription(String text, Duration recordingDuration) async {
  if (!_initialized) return; // or: buffer until initialize() completes
  // ...
}
```
(Equivalently, `if (_file == null) return;` inside `_save`.)

---

### L-1 — `force` parameter in update check is a no-op
**Severity:** Low · **File:** `update_check_service.dart` (89, 137)

**What's wrong.** Both `checkWithStatus({force})` and `check({force})` accept a `force` argument
that is never referenced in the body. A UI "Check now for updates" button passing `force: true`
will be indistinguishable from the cached/deferred background path. If a 24 h cache is enforced in
the caller, "force" silently does nothing; if it isn't, the parameter is simply dead.

**Recommended fix.** Either thread `force` through to whichever layer applies the 24 h cache, or
remove the parameter so the contract is honest.

---

### L-2 — Word counting undercounts CJK / unsegmented scripts
**Severity:** Low · **File:** `usage_stats_service.dart` (157–159)

**What's wrong.** `_countWords` splits on `\s+`. For Chinese/Japanese/Korean (no inter-word
spaces), an entire utterance collapses to a **single** "word", so `totalWords`, the time-saved
estimate (÷40 WPM), word-based achievements ("Wordsmith"/"Storyteller"/"Prolific"), and the daily
heatmap are all wrong for those languages — even though transcription supports `language: 'auto'`.

**Recommended fix.** Count CJK ideographs individually and merge with whitespace splits:

```dart
int _countWords(String text) {
  final cjk = RegExp(r'[\u3400-\u9FFF\uF900-\uFAFF\u3040-\u30FF\uAC00-\uD7AF]').allMatches(text).length;
  final spaced = text
      .split(RegExp(r'[\s\u3400-\u9FFF\uF900-\uFAFF\u3040-\u30FF\uAC00-\uD7AF]+'))
      .where((t) => t.isNotEmpty).length;
  return spaced + cjk;
}
```

---

### L-3 — Debug-mode logging dumps the full upstream Vertex body
**Severity:** Low · **File:** `vertex_ai_service.dart` (471–475)

**What's wrong.**
```dart
if (kDebugMode) {
  debugPrint('[VertexAiService] request failed: HTTP ${response.statusCode}; body=${response.body}');
}
```
The Gemini path (gem 290–295) deliberately suppresses the body and only logs the status. The Vertex
path logs the **entire upstream error body**, which can echo project metadata, internal routing, or
PII from the prompt to the console/logs. The user-facing message is correctly generic; this is only
a debug-log hygiene issue.

**Recommended fix.** Match the Gemini behavior — log only the status code in debug, or
length-cap/redact the body (`body=${response.body.characters.take(200)}`). Note Gemini logs only the
status today, so align them.

---

### L-4 — Version comparison ignores components past the third
**Severity:** Low · **File:** `update_check_service.dart` (155–174)

**What's wrong.** `_components` keeps only 3 index slots. A 4-component version like `1.2.3.4` is
read as `1.2.3` and the `.4` is discarded, so `1.2.3.4` vs `1.2.3.0` compares equal (no update
surfaced). Build numbers are occasionally used as the 4th component.

**Recommended fix.** Compare all numeric segments up to the longer of the two, or at least include
a 4th slot. Minimal change:

```dart
final n = max(a.length, b.length);
for (var i = 0; i < n; i++) {
  final av = i < a.length ? a[i] : 0;
  final bv = i < b.length ? b[i] : 0;
  if (bv != av) return bv > av;
}
```
(and extend `_components` to as many segments as present, default 0).

---

### L-5 — Update check uses unauthenticated GitHub API with no conditional request
**Severity:** Low · **File:** `update_check_service.dart` (89–98)

**What's wrong.** The request hits `api.github.com/releases/latest` unauthenticated (no
`Authorization`, no `Accept` media type, no `If-None-Match`/ETag caching). Unauthenticated requests
are rate-limited to **60/hour/IP**. Multiple users behind one NAT/corporate egress (or a shared dev
machine) can blow the budget, collapsing the check to `UpdateCheckResult.failure()` and silently
"no update."

**Recommended fix.** Optional but cheap: send `Accept: application/vnd.github+json`, persist the
ETag/`Last-Modified` and use `If-None-Match`/`If-Modified-Since`; or ship a fine-grained PAT
read-only token. At minimum, surface rate-limit as retryable (which the `succeeded=false` design
already supports, so callers should retry rather than treat as "up to date").

---

### L-6 — Whisper transitions not serialized inside the service
**Severity:** Low · **File:** `whisper_service.dart` (312–377)

**What's wrong.** `initialize`, `unloadModel`, and `dispose` mutate shared state
(`_isInitialized`, `_loadedModelPath`) across native `await`s with **no internal lock**; the class
explicitly delegates serialization to callers ("Callers that can request concurrent
initialize/unload operations must serialize those operations"). The dispose-race guards
(re-checking `_isDisposed` after each await) are good, but the contract is fragile — any caller that
overlaps an unload with a new init (e.g. switching models quickly) races.

**Recommended fix.** Gate the mutating methods on an internal `Future<void>` / `Mutex` so the
service enforces its own invariants instead of trusting callers:

```dart
final _transitionMutex = Mutex(); // package:mutex, or a chained Future
Future<bool> initialize({required String modelPath, int threads = 0}) async {
  return _transitionMutex.protect(() => _initializeLocked(modelPath: modelPath, threads: threads));
}
```

---

### L-7 — Cloud POSTs are not cancellable
**Severity:** Low · **Files:** `gemini_api_service.dart` (269–283), `vertex_ai_service.dart` (439–451)

**What's wrong.** Neither cloud POST exposes a cancellation handle; a user pressing "cancel" on a
cloud transcription cannot abort the in-flight request — it runs to its 60 s timeout regardless,
consuming quota and bandwidth (and, for Gemini, a billable API call). Local Whisper *does* have a
native `cancel`/abort_callback path (`WhisperService.cancelTranscription`). The asymmetry means
cancel works for local but not cloud.

**Recommended fix.** Build the request with a cancellable client. With `http`/`IOClient`, wrap the
POST in a `Future` controlled by a `Completer`, or adopt a client that supports abort; on cancel,
complete with a `CloudTranscriptionException("Cancelled")`. (The Vertex ADC client comes from
`googleapis_auth`; cancelling there means closing/reusing a fresh client.)

---

### L-8 — Inline audio payload roughly triples peak memory
**Severity:** Low · **Files:** `gemini_api_service.dart` (178–191), `vertex_ai_service.dart` (287–300)

**What's wrong.** For a single transcription the code simultaneously holds: the original
`Uint8List audioData`, a `String` of `base64Encode(audioData)` (~1.33×), and the full
`jsonEncode(payload)` body (another copy of the base64 string + prompt). Near the 20 MB inline cap
that is ~50–60 MB live for one request. Not a leak — short-lived — but worth noting for
memory-constrained machines and for choosing the inline cap.

**Recommended fix.** Acceptable for the current 20 MB cap. If you raise the cap, switch to
multipart/streaming upload (`media upload` endpoint for Gemini, resumable upload for Vertex) instead
of inline base64 to avoid the 3× peak.

---

### L-9 — Maintainer capture helper has no timeout
**Severity:** Low (not a production path) · **File:** `pinned_http_client.dart` (273–307)

**What's wrong.** `captureLeafCertificateDescription` is a documented maintainer-only tool. It
opens a raw `HttpClient()` GET with **no `.timeout()`**, so pointing it at a dead host blocks until
the socket times out (platform default, often minutes). It is not invoked from any shipped path, so
impact is limited to a developer running it manually.

**Recommended fix.** Add `.timeout(const Duration(seconds: 10))` to the `request.close()` /
`response.drain<void>()` chain.

---

### L-10 — `initialize()` is a no-op flag for both cloud clients
**Severity:** Low · **File:** `cloud_transcription_service.dart` (75–79), `gemini_api_service.dart`
(36–42), `vertex_ai_service.dart` (42–47)

**What's wrong.** `_initializeIfNeeded` checks `client.isInitialized`, but each client's
`initialize()` merely sets `_isInitialized = true` — it does no network/credential work. So the
"initialize" guard provides no real readiness guarantee (key existence, project-id presence, ADC
availability are all deferred to the first real request). A provider switch mid-session creates a
"user-hit" on the first request that discovers a missing key/project rather than failing early at
switch time. `verifySetup()` is the real readiness test; it just isn't auto-invoked on switch.

**Recommended fix.** Either (a) have `initialize()` run the cheap preconditions (key configured /
project-id present) so a bad switch fails fast, or (b) drop the flag and rely on `verifySetup()`,
documenting that first-request latency is expected.

---

### I-1 — No automatic local→cloud fallback (confirm intent)
**Severity:** Info · **Files:** `cloud_transcription_service.dart`, `transcription_backend_resolver.dart`

**Observation.** The orchestrator resolves exactly one provider (`geminiApiKey` or `vertexAi`) and
`resolveSessionBackend` pins exactly one backend (cloud or whisper) for a session. A local Whisper
failure propagates the error to the UI (no error swallowing — good), but there is **no automatic
fallback** (e.g. failed Whisper → retry on cloud). This is almost certainly intentional for
cost/predictability and offline-first semantics. Flagged only so reviewers can confirm the intent
explicitly; if silent resilience is desired, hook the fallback here.

---

### I-2 — `UsageStatsService` lacks `dispose()`; minor unbounded growth
**Severity:** Info · **File:** `usage_stats_service.dart` (11)

**Observation.** `UsageStatsService extends ChangeNotifier` but does not override `dispose()` or
call `super.dispose()`. Held for app lifetime in practice, so not a real leak. `dailyWordCount`
gains one key/active-day per calendar day (~365/year) — negligible. No action required; noted for
completeness.

---

## Areas That Are Already Strong (verified during this audit)

These were specifically checked and found correct — included so the gaps above are not over-read:

- **Credentials are never logged or echoed.** API keys are read via `SettingsService.readGeminiApiKey()
  → SecureCredentialStore` (macOS Keychain / `flutter_secure_storage` elsewhere), sent only in the
  `x-goog-api-key` header (never in the URL), and *deliberately suppressed* from debug logs and
  user-facing error bodies (`gemini_api_service.dart` 286–299, `vertex_ai_service.dart` 468–480).
  `.env` secrets are disabled in release builds (`config.dart` 211–219).
- **Path-traversal is locked down.** `WhisperService` validates model basenames against
  `^ggml-[A-Za-z0-9][A-Za-z0-9._-]*\.bin$`, rejects absolute/relative-escapes, and confines the
  resolved real path to an allowed model directory via `resolveSymbolicLinksSync` +
  `p.isWithin` (`whisper_service.dart` 71–185).
- **Defensive, never-crashing JSON parsing.** Every JSON decode (`gemini_api_service.dart` 351–359,
  `vertex_ai_service.dart` 379–387, `update_check_service.dart` 102–105, `usage_stats_service.dart`
  50–62) is wrapped and yields a safe error/null rather than throwing an uncaught
  `FormatException`/`_TypeError`.
- **Atomic usage-stats persistence with recovery.** `_writeAtomic` + `_load` (.live → .bak → .tmp)
  survive mid-write crashes (`usage_stats_service.dart` 33–90); `UsageStats` fields are cast-safe
  and `dailyWordCount` is `Map.unmodifiable`.
- **Vertex project-ID injection guard.** `isValidVertexProjectId` rejects anything but numeric or
  `^[a-z][a-z0-9-]{4,28}[a-z0-9]$`, so an attacker-controlled string can't reach the URL path
  (`vertex_ai_service.dart` 99–128).
- **Inline-payload size cap before send.** `_assertInlinePayloadFits` (20 MB) prevents oversized
  inline audio requests on both providers.
- **60 s request timeouts** are present on every Gemini/Vertex POST and an 8 s timeout on the update
  check (the gaps are *retry/backoff*, not absence of timeout — see M-2, M-3).
- **Prompt-injection hardening in prompts.** `SystemPrompt._coreRules` frames spoken commands as
  inert data and forbids execution/code generation; transcript drafts are wrapped in
  `<transcript-draft>` markers (`system_prompt.dart` 78–133).
- **Honest, fail-closed-by-default TLS posture.** `pinned_http_client.dart` accurately documents
  why a Dart `badCertificateCallback` can't soundly pin, and deliberately does **not** wire the
  fail-open `rejectPin → true` branch.

---

## Suggested Fix Order

1. **H-1** (dispatch Whisper inference off the native UI thread) — biggest user-visible win.
2. **H-2** (serialize usage-stats writes) — silent data loss today.
3. **M-7 / M-5 / M-6** (transport + result-validation: pinning docs, output cap, guard hardening).
4. **M-1, M-2, M-3, M-4** (structured Whisper errors; retry/backoff; ADC timeout; safety-block UX).
5. **M-8** + Low-severity items as cleanup.
