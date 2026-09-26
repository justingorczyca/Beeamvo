import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/system_prompt.dart';
import 'cloud_transcription_client.dart';
import 'codex_oauth_manager.dart';
import 'pinned_http_client.dart';
import 'responses_stream_parser.dart';
import 'settings_service.dart';

/// Cloud transcription client backed by the ChatGPT Codex Responses backend
/// (`{base}/responses`), authenticated via OAuth rather than an API key.
///
/// Codex is a **text-only, polish-only** provider: the backend does not
/// accept audio input, so [transcribeAudio] and [transcribeAndImprove] fail
/// with a clear error and callers should pair Codex with offline Whisper (or
/// another provider) for the transcription step.
///
/// The backend is stream-only in practice: every request sets
/// `"stream": true` and the response body is consumed as server-sent events.
/// `response.output_text.delta` events are concatenated, with
/// `response.completed` used as a fallback when no deltas arrive.
class CodexService implements CloudTranscriptionClient {
  CodexService({
    http.Client? httpClient,
    this.oauthManager,
    @visibleForTesting Duration? requestTimeout,
  }) : _httpClient = httpClient ?? createSecureHttpClient(),
       _requestTimeout = requestTimeout ?? const Duration(seconds: 120);

  static const List<Duration> _transientRetryDelays = <Duration>[
    Duration(milliseconds: 250),
    Duration(milliseconds: 750),
    Duration(milliseconds: 1500),
  ];

  final http.Client _httpClient;

  /// Injected OAuth manager; when null the manager is taken from the attached
  /// [SettingsService]. Tests inject one directly.
  final CodexOAuthManager? oauthManager;
  final Duration _requestTimeout;
  bool _isInitialized = false;
  bool _isDisposed = false;
  GeminiModelConfig _currentModel = AppConfig.getModelById(
    AppConfig.defaultCodexModelId,
  );
  SettingsService? _settingsService;
  late final String _sessionId = _generateSessionId();

  static String _generateSessionId() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  CodexOAuthManager get _oauth {
    final manager = oauthManager ?? _settingsService?.codexOAuth;
    if (manager == null) {
      throw const CodexSignInRequiredException();
    }
    return manager;
  }

  @override
  void attachSettings(SettingsService settings) {
    _settingsService = settings;
  }

  @override
  Future<void> initialize() async {
    if (_isDisposed) {
      throw StateError('CodexService has been disposed.');
    }
    _isInitialized = true;
  }

  @override
  bool get isInitialized => _isInitialized;

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _isInitialized = false;
    _httpClient.close();
  }

  @override
  GeminiModelConfig get currentModel => _currentModel;

  @override
  void setModel(GeminiModelConfig model) {
    _currentModel = model;
  }

  @override
  void setModelById(String modelId) {
    for (final model in AppConfig.codexModels) {
      if (model.id == modelId) {
        _currentModel = model;
        return;
      }
    }
    _currentModel = AppConfig.getModelById(AppConfig.defaultCodexModelId);
  }

  GeminiModelConfig _resolveModel(String? modelOverrideId) {
    return AppConfig.requireModelForProvider(
      CloudProvider.codexOAuth,
      modelOverrideId ?? _currentModel.id,
    );
  }

  Uri get _responsesUri =>
      Uri.parse('${AppConfig.codexDefaultBaseUrl}/responses');

  Future<Map<String, String>> _authHeaders({required bool streaming}) async {
    final credentials = await _oauth.loadCredentials();
    if (credentials == null) {
      throw const CodexSignInRequiredException();
    }
    final accessToken =
        credentials.expiresWithin(
          CodexOAuthManager.refreshBuffer,
          _oauth.currentTime(),
        )
        ? (await _oauth.refreshCredentials(credentials)).accessToken
        : credentials.accessToken;
    return <String, String>{
      HttpHeaders.authorizationHeader: 'Bearer $accessToken',
      HttpHeaders.contentTypeHeader: 'application/json',
      if (streaming) HttpHeaders.acceptHeader: 'text/event-stream',
      'originator': 'beeamvo',
      HttpHeaders.userAgentHeader: 'Beeamvo/1.0',
      'session_id': _sessionId,
      if (credentials.accountId != null && credentials.accountId!.isNotEmpty)
        'ChatGPT-Account-Id': credentials.accountId!,
    };
  }

  @visibleForTesting
  Map<String, dynamic> buildImprovePayload(
    String rawText, {
    required String missionInstruction,
    required GeminiModelConfig model,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) {
    final effort =
        model.resolveThinkingLevel(levelOverride: thinkingLevelOverride) ??
        model.thinkingLevel;
    return <String, dynamic>{
      'model': model.modelName,
      'instructions': SystemPrompt.buildSystemInstruction(missionInstruction),
      'input': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'message',
          'role': 'user',
          'content': <Map<String, dynamic>>[
            <String, dynamic>{
              'type': 'input_text',
              'text': SystemPrompt.buildTranscriptDraftInput(rawText),
            },
          ],
        },
      ],
      'store': false,
      'stream': true,
      if (effort != null) 'reasoning': <String, dynamic>{'effort': effort.name},
    };
  }

  @visibleForTesting
  Map<String, dynamic> buildVerifyPayload(GeminiModelConfig model) {
    final effort =
        model.resolveThinkingLevel(levelOverride: GeminiThinkingLevel.low) ??
        model.thinkingLevel;
    return <String, dynamic>{
      'model': model.modelName,
      'instructions': SystemPrompt.baseSystemInstruction,
      'input': <Map<String, dynamic>>[
        <String, dynamic>{
          'type': 'message',
          'role': 'user',
          'content': <Map<String, dynamic>>[
            <String, dynamic>{'type': 'input_text', 'text': 'Reply with OK.'},
          ],
        },
      ],
      'store': false,
      'stream': true,
      if (effort != null) 'reasoning': <String, dynamic>{'effort': effort.name},
    };
  }

  /// Sends [payload] to the Codex Responses endpoint and aggregates the SSE
  /// stream into final text.
  ///
  /// A `401` triggers one forced credential refresh and a single retry.
  /// `429`/5xx statuses retry with bounded delays.
  Future<String> _postResponses(Map<String, dynamic> payload) async {
    var refreshAttempted = false;
    for (var attempt = 0; ; attempt++) {
      http.StreamedResponse streamed;
      try {
        final headers = await _authHeaders(streaming: true);
        final request = http.Request('POST', _responsesUri)
          ..headers.addAll(headers)
          ..body = jsonEncode(payload);
        streamed = await _httpClient.send(request).timeout(_requestTimeout);
      } on TimeoutException {
        throw CloudTranscriptionException(
          'ChatGPT Codex did not respond within '
          '${_requestTimeout.inSeconds} seconds. Try again in a moment.',
        );
      }

      if (streamed.statusCode == HttpStatus.unauthorized && !refreshAttempted) {
        refreshAttempted = true;
        await streamed.stream.drain<void>();
        try {
          await _oauth.forceRefreshAccessToken();
        } on CodexSignInRequiredException {
          rethrow;
        } catch (_) {
          throw const CodexSignInRequiredException(
            'ChatGPT Codex session expired. Sign in again.',
          );
        }
        continue;
      }

      if ((streamed.statusCode == 429 || streamed.statusCode >= 500) &&
          attempt < _transientRetryDelays.length) {
        await streamed.stream.drain<void>();
        await Future<void>.delayed(_transientRetryDelays[attempt]);
        continue;
      }

      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        await streamed.stream.drain<void>();
        _throwHttpFailure(streamed.statusCode);
      }

      return _collectStreamedText(streamed.stream);
    }
  }

  /// Aggregates `data:` SSE lines into final output text.
  Future<String> _collectStreamedText(Stream<List<int>> byteStream) {
    return ResponsesStreamParser(
      providerLabel: 'ChatGPT Codex',
      timeout: _requestTimeout,
    ).collect(byteStream);
  }

  Never _throwHttpFailure(int statusCode) {
    if (kDebugMode) {
      debugPrint(
        '[CodexService] request failed: HTTP $statusCode; '
        'upstream response body suppressed.',
      );
    }
    switch (statusCode) {
      case 400:
        throw CloudTranscriptionException(
          'ChatGPT Codex could not process this request. Check your selected '
          'model and try again.',
        );
      case 401:
      case 403:
        throw const CodexSignInRequiredException(
          'ChatGPT Codex session expired. Sign in again in Settings.',
        );
      case 404:
        throw CloudTranscriptionException(
          'ChatGPT Codex could not find the selected model. Choose another '
          'model in Settings.',
        );
      case 429:
        throw CloudTranscriptionException(
          'ChatGPT Codex is rate-limiting requests. Wait a moment, then try '
          'again.',
        );
      default:
        if (statusCode >= 500) {
          throw CloudTranscriptionException(
            'ChatGPT Codex is temporarily unavailable (HTTP $statusCode). '
            'Try again in a moment.',
          );
        }
        throw CloudTranscriptionException(
          'ChatGPT Codex request failed (HTTP $statusCode). Check your '
          'configuration and try again.',
        );
    }
  }

  @override
  Future<void> verifySetup() async {
    try {
      await _postResponses(buildVerifyPayload(_currentModel));
    } on CodexSignInRequiredException {
      rethrow;
    }
  }

  @override
  Future<String> improveTranscription(
    String rawText, {
    String? missionInstruction,
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) async {
    final model = _resolveModel(modelOverrideId);
    final payload = buildImprovePayload(
      rawText,
      missionInstruction:
          missionInstruction ?? SystemPrompt.availablePrompts.first.instruction,
      model: model,
      thinkingLevelOverride:
          thinkingLevelOverride ??
          _settingsService?.getRefinementThinkingLevel(model.id),
    );
    try {
      return await _postResponses(payload);
    } on CodexSignInRequiredException catch (e) {
      throw CloudTranscriptionException(e.toString());
    }
  }

  @override
  Future<String> transcribeAudio(
    Uint8List audioData,
    String mimeType, {
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) async {
    throw CloudTranscriptionException(
      'ChatGPT Codex models cannot transcribe audio. Transcribe with Gemini '
      'or the Offline engine, then choose ChatGPT for the two-step polish.',
    );
  }

  @override
  Future<String> transcribeAndImprove(
    Uint8List audioData,
    String mimeType, {
    String? missionInstruction,
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) async {
    return transcribeAudio(audioData, mimeType);
  }
}
