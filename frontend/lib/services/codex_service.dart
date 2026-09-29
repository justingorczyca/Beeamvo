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

/// Cloud transcription and text polishing through ChatGPT Codex OAuth.
///
/// Audio uses ChatGPT's dedicated `/transcribe` endpoint; prompt-capable
/// models use the stream-only Codex Responses backend.
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
  Uri get _transcribeUri => Uri.parse(AppConfig.codexTranscribeUrl);

  CloudTranscriptionException _timeoutException() =>
      CloudTranscriptionException(
        'ChatGPT Codex did not respond within '
        '${_requestTimeout.inSeconds} seconds. Try again in a moment.',
      );

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

  Future<http.StreamedResponse> _sendWithAuthRetry({
    required bool streaming,
    required bool transcriptionEndpoint,
    required Future<http.StreamedResponse> Function(Map<String, String> headers)
    requestBuilder,
  }) async {
    var refreshAttempted = false;
    for (var attempt = 0; ; attempt++) {
      http.StreamedResponse streamed;
      try {
        final headers = await _authHeaders(streaming: streaming);
        streamed = await requestBuilder(headers).timeout(_requestTimeout);
      } on TimeoutException {
        throw _timeoutException();
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
        _throwHttpFailure(
          streamed.statusCode,
          transcriptionEndpoint: transcriptionEndpoint,
        );
      }

      return streamed;
    }
  }

  /// Sends [payload] to the Codex Responses endpoint and aggregates the SSE
  /// stream into final text.
  Future<String> _postResponses(Map<String, dynamic> payload) async {
    final streamed = await _sendWithAuthRetry(
      streaming: true,
      transcriptionEndpoint: false,
      requestBuilder: (headers) {
        final request = http.Request('POST', _responsesUri)
          ..headers.addAll(headers)
          ..body = jsonEncode(payload);
        return _httpClient.send(request);
      },
    );
    return _collectStreamedText(streamed.stream);
  }

  Future<http.StreamedResponse> _postTranscription(
    Uint8List audioData,
    String mimeType,
  ) {
    final normalizedMimeType = mimeType.toLowerCase().split(';').first.trim();
    final (filename, contentType) = switch (normalizedMimeType) {
      'audio/mp4' => ('audio.m4a', http.MediaType('audio', 'mp4')),
      'audio/m4a' => ('audio.m4a', http.MediaType('audio', 'm4a')),
      'audio/mpeg' => ('audio.mp3', http.MediaType('audio', 'mpeg')),
      'audio/webm' => ('audio.webm', http.MediaType('audio', 'webm')),
      _ => ('audio.wav', http.MediaType('audio', 'wav')),
    };
    final language = _settingsService?.spokenLanguage;
    return _sendWithAuthRetry(
      streaming: false,
      transcriptionEndpoint: true,
      requestBuilder: (headers) {
        headers.remove(HttpHeaders.contentTypeHeader);
        final request = http.MultipartRequest('POST', _transcribeUri)
          ..headers.addAll(headers)
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              audioData,
              filename: filename,
              contentType: contentType,
            ),
          );
        if (language != null && language != 'auto') {
          request.fields['language'] = language;
        }
        return _httpClient.send(request);
      },
    );
  }

  static Uint8List _silentWav() {
    const sampleRate = 16000;
    const channels = 1;
    const bitsPerSample = 16;
    const dataLength = sampleRate * channels * bitsPerSample ~/ 8;
    final wav = Uint8List(44 + dataLength);
    final header = ByteData.sublistView(wav);
    void writeAscii(int offset, String value) {
      wav.setAll(offset, ascii.encode(value));
    }

    writeAscii(0, 'RIFF');
    header.setUint32(4, 36 + dataLength, Endian.little);
    writeAscii(8, 'WAVE');
    writeAscii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(
      28,
      sampleRate * channels * bitsPerSample ~/ 8,
      Endian.little,
    );
    header.setUint16(32, channels * bitsPerSample ~/ 8, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    writeAscii(36, 'data');
    header.setUint32(40, dataLength, Endian.little);
    return wav;
  }

  @visibleForTesting
  String parseTranscriptionResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwHttpFailure(response.statusCode, transcriptionEndpoint: true);
    }
    late final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw CloudTranscriptionException(
        'ChatGPT returned an invalid transcription response.',
      );
    }
    if (decoded is! Map || decoded['text'] is! String) {
      throw CloudTranscriptionException(
        'ChatGPT returned an invalid transcription response.',
      );
    }
    return (decoded['text'] as String).trim();
  }

  /// Aggregates `data:` SSE lines into final output text.
  Future<String> _collectStreamedText(Stream<List<int>> byteStream) {
    return ResponsesStreamParser(
      providerLabel: 'ChatGPT Codex',
      timeout: _requestTimeout,
    ).collect(byteStream);
  }

  Never _throwHttpFailure(
    int statusCode, {
    bool transcriptionEndpoint = false,
  }) {
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
      case 405:
        if (transcriptionEndpoint) {
          throw CloudTranscriptionException(
            "ChatGPT's transcription endpoint is unavailable (HTTP "
            '$statusCode). Try again later or contact support.',
          );
        }
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
      if (_currentModel.isTranscriptionOnly) {
        final response = await _postTranscription(_silentWav(), 'audio/wav');
        try {
          await response.stream.drain<void>().timeout(_requestTimeout);
        } on TimeoutException {
          throw _timeoutException();
        }
      } else {
        await _postResponses(buildVerifyPayload(_currentModel));
      }
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
    final model = _resolveModel(modelOverrideId);
    if (!model.isTranscriptionOnly) {
      throw CloudTranscriptionException(
        '${model.displayName} does not accept audio input. Choose ChatGPT '
        'Transcribe in Settings.',
      );
    }
    try {
      final streamed = await _postTranscription(audioData, mimeType);
      late final http.Response response;
      try {
        response = await http.Response.fromStream(
          streamed,
        ).timeout(_requestTimeout);
      } on TimeoutException {
        throw _timeoutException();
      }
      return parseTranscriptionResponse(response);
    } on CodexSignInRequiredException catch (e) {
      throw CloudTranscriptionException(e.toString());
    }
  }

  @override
  Future<String> transcribeAndImprove(
    Uint8List audioData,
    String mimeType, {
    String? missionInstruction,
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) async {
    final model = _resolveModel(modelOverrideId);
    if (!model.isTranscriptionOnly) {
      throw CloudTranscriptionException(
        '${model.displayName} does not accept audio input. Choose ChatGPT '
        'Transcribe in Settings.',
      );
    }
    return transcribeAudio(audioData, mimeType, modelOverrideId: model.id);
  }
}
