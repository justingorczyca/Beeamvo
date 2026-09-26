import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/system_prompt.dart';
import 'cloud_transcription_client.dart';
import 'pinned_http_client.dart';
import 'settings_service.dart';
import 'transcription_request.dart';

/// OpenAI-compatible cloud transcription client.
///
/// Serves two wire surfaces off a configurable base URL:
///
/// * `POST {base}/audio/transcriptions` — dedicated speech models
///   (`gpt-transcribe`, `gpt-4o-transcribe`, `whisper-1`, ...) as multipart
///   uploads. These models return `{ "text": ... }` verbatim.
/// * `POST {base}/chat/completions` — prompt-capable chat models used for
///   refinement and for the polish half of a chained single pass.
///
/// Reasoning-family chat models (entries with [supportedThinkingLevels]) are
/// sent `reasoning_effort` + `max_completion_tokens`; classic chat models get
/// `temperature` + `max_tokens`.
///
/// The base URL defaults to `https://api.openai.com/v1` and can be pointed at
/// any OpenAI-compatible server via Settings (`openai_base_url`).
class OpenAiCompatibleService implements CloudTranscriptionClient {
  OpenAiCompatibleService({
    http.Client? httpClient,
    @visibleForTesting Duration? requestTimeout,
  }) : _httpClient = httpClient ?? createSecureHttpClient(),
       _requestTimeout = requestTimeout ?? const Duration(seconds: 60);

  static const int maxInlineRequestBytes = 20 * 1024 * 1024;

  final http.Client _httpClient;
  final Duration _requestTimeout;
  bool _isInitialized = false;
  bool _isDisposed = false;
  GeminiModelConfig _currentModel = AppConfig.getModelById(
    AppConfig.defaultOpenAiModelId,
  );
  SettingsService? _settingsService;

  int get _requestTimeoutSeconds =>
      max(1, (_requestTimeout.inMilliseconds + 999) ~/ 1000);

  @override
  void attachSettings(SettingsService settings) {
    _settingsService = settings;
  }

  @override
  Future<void> initialize() async {
    if (_isDisposed) {
      throw StateError('OpenAiCompatibleService has been disposed.');
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
    for (final model in AppConfig.openAiModels) {
      if (model.id == modelId) {
        _currentModel = model;
        return;
      }
    }
    _currentModel = AppConfig.getModelById(AppConfig.defaultOpenAiModelId);
  }

  GeminiModelConfig _resolveModel(String? modelOverrideId) {
    return AppConfig.requireModelForProvider(
      CloudProvider.openaiApiKey,
      modelOverrideId ?? _currentModel.id,
    );
  }

  /// Validates and normalizes a user-supplied OpenAI-compatible base URL.
  ///
  /// Rules (kept identical to the previous OpenAI-compatible layer):
  /// absolute URL, HTTPS required except `http://localhost`/`127.0.0.1`, and
  /// the path must not already end in `/chat/completions` or `/completions`.
  static String normalizeBaseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      throw CloudTranscriptionException(
        'Enter a base URL for the OpenAI-compatible service.',
      );
    }

    late final Uri uri;
    try {
      uri = Uri.parse(trimmed);
    } catch (_) {
      throw CloudTranscriptionException(
        'Enter a valid absolute HTTPS base URL for the OpenAI-compatible '
        'service.',
      );
    }

    if (!uri.isAbsolute || uri.host.isEmpty) {
      throw CloudTranscriptionException(
        'The OpenAI-compatible base URL must be an absolute URL.',
      );
    }
    final isLocalHttp =
        uri.scheme == 'http' &&
        (uri.host == 'localhost' || uri.host == '127.0.0.1');
    if (uri.scheme != 'https' && !isLocalHttp) {
      throw CloudTranscriptionException(
        'The OpenAI-compatible base URL must use HTTPS. HTTP is only allowed '
        'for localhost or 127.0.0.1.',
      );
    }

    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    final lowerPath = path.toLowerCase();
    if (lowerPath.endsWith('/chat/completions') ||
        lowerPath.endsWith('/completions')) {
      throw CloudTranscriptionException(
        'Enter the service base URL without /chat/completions or '
        '/completions.',
      );
    }

    return uri.replace(path: path).toString();
  }

  String get _baseUrl {
    final stored = _settingsService?.openAiBaseUrl;
    if (stored == null || stored.trim().isEmpty) {
      return AppConfig.openAiDefaultBaseUrl;
    }
    return normalizeBaseUrl(stored);
  }

  Future<String> _requireApiKey() async {
    final apiKey = await _settingsService?.readOpenAiApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw CloudTranscriptionException(
        'Add an OpenAI API key in Settings before using cloud transcription.',
      );
    }
    return apiKey.trim();
  }

  Uri _appendPath(String suffix) {
    final base = Uri.parse(_baseUrl);
    final path = '${base.path.replaceFirst(RegExp(r'/+$'), '')}$suffix';
    return base.replace(path: path);
  }

  @visibleForTesting
  Uri buildChatUri() => _appendPath('/chat/completions');

  @visibleForTesting
  Uri buildTranscriptionsUri() => _appendPath('/audio/transcriptions');

  Map<String, String> _headers(String apiKey) => {
    'Authorization': 'Bearer $apiKey',
    'Content-Type': 'application/json',
  };

  /// Reasoning-family models take `reasoning_effort` and
  /// `max_completion_tokens`; everything else takes `temperature` +
  /// `max_tokens` (which reasoning models reject).
  Map<String, dynamic> _generationConfig(
    GeminiModelConfig model, {
    required double temperature,
    GeminiThinkingLevel? thinkingLevel,
  }) {
    final config = <String, dynamic>{};
    if (model.supportedThinkingLevels.isNotEmpty) {
      final effort =
          model.resolveThinkingLevel(levelOverride: thinkingLevel) ??
          model.thinkingLevel;
      if (effort != null) {
        config['reasoning_effort'] = effort.name;
      }
      config['max_completion_tokens'] = 8192;
    } else {
      config['temperature'] = temperature;
      config['max_tokens'] = 8192;
    }
    return config;
  }

  Map<String, dynamic> _textMessage(String role, String text) => {
    'role': role,
    'content': text,
  };

  @visibleForTesting
  Map<String, dynamic> buildImprovePayload(
    String rawText, {
    required String missionInstruction,
    required GeminiModelConfig model,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) {
    return {
      'model': model.modelName,
      'messages': [
        _textMessage(
          'system',
          SystemPrompt.buildSystemInstruction(missionInstruction),
        ),
        _textMessage('user', SystemPrompt.buildTranscriptDraftInput(rawText)),
      ],
      ..._generationConfig(
        model,
        temperature: 0.3,
        thinkingLevel: thinkingLevelOverride,
      ),
    };
  }

  @visibleForTesting
  Map<String, dynamic> buildVerifyPayload({required GeminiModelConfig model}) {
    return {
      'model': model.modelName,
      'messages': [
        _textMessage('system', SystemPrompt.baseSystemInstruction),
        _textMessage('user', 'Reply with OK.'),
      ],
      ..._generationConfig(model, temperature: 0.0),
    };
  }

  @visibleForTesting
  Map<String, String> buildTranscriptionFields(String modelId) {
    final fields = <String, String>{
      'model': modelId,
      'response_format': 'json',
    };
    final language = _settingsService?.spokenLanguage;
    if (language != null && language != 'auto') {
      fields['language'] = language;
    }
    return fields;
  }

  Future<http.Response> _postChat(String apiKey, Map<String, dynamic> payload) {
    return TranscriptionRequest().send(
      () => _httpClient.post(
        buildChatUri(),
        headers: _headers(apiKey),
        body: jsonEncode(payload),
      ),
    );
  }

  Future<http.Response> _postTranscription(
    String apiKey,
    Uint8List audioData,
    String mimeType,
    String modelId,
  ) {
    final uri = buildTranscriptionsUri();
    final fields = buildTranscriptionFields(modelId);
    final format = audioFormatForMimeType(mimeType);
    return TranscriptionRequest().send(() async {
      final request = http.MultipartRequest('POST', uri)
        ..headers['Authorization'] = 'Bearer $apiKey'
        ..fields.addAll(fields)
        ..files.add(
          http.MultipartFile.fromBytes(
            'file',
            audioData,
            filename: 'audio.$format',
            contentType: mediaTypeForMimeType(mimeType),
          ),
        );
      final streamed = await _httpClient.send(request);
      return http.Response.fromStream(streamed);
    });
  }

  @visibleForTesting
  String parseChatResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwHttpFailure(response.statusCode);
    }
    final decoded = _decodeJson(response.body);
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw CloudTranscriptionException('OpenAI returned no choices.');
    }
    final choice = choices.first as Map;
    final message = choice['message'];
    final content = message is Map ? message['content'] : null;
    final buffer = StringBuffer();
    if (content is String) {
      buffer.write(content);
    } else if (content is List) {
      for (final part in content) {
        if (part is Map && part['type'] == 'text' && part['text'] is String) {
          buffer.write(part['text'] as String);
        }
      }
    }
    final text = buffer.toString().trim();
    if (text.isNotEmpty) return text;

    final finishReason = choice['finish_reason'];
    final normalized = finishReason is String
        ? finishReason.trim().toLowerCase()
        : null;
    if (normalized != null && normalized.isNotEmpty && normalized != 'stop') {
      throw CloudTranscriptionException(
        'OpenAI stopped without returning text (${finishReason.trim()}). '
        'Try again or choose another model.',
      );
    }
    throw CloudTranscriptionException('OpenAI returned an empty response.');
  }

  @visibleForTesting
  String parseTranscriptionResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwHttpFailure(response.statusCode);
    }
    final decoded = _decodeJson(response.body);
    final text = decoded['text'];
    if (text is! String || text.trim().isEmpty) {
      throw CloudTranscriptionException(
        'OpenAI returned an empty transcription.',
      );
    }
    return text.trim();
  }

  Map<String, dynamic> _decodeJson(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {
      // Use the provider-safe error below.
    }
    throw CloudTranscriptionException('OpenAI returned an invalid response.');
  }

  Never _throwHttpFailure(int statusCode) {
    if (kDebugMode) {
      debugPrint(
        '[OpenAiCompatibleService] request failed: HTTP $statusCode; '
        'upstream response body suppressed.',
      );
    }
    throw CloudTranscriptionException(_userFacingFailureMessage(statusCode));
  }

  String _userFacingFailureMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'OpenAI could not process this request. Check your selected '
            'model and try again.';
      case 401:
      case 403:
        return 'Invalid API key or missing access to the selected OpenAI '
            'model. Check the key in Settings and try again.';
      case 404:
        return 'OpenAI could not find the selected model or endpoint. Check '
            'the base URL and model in Settings.';
      case 429:
        return 'OpenAI is rate-limiting requests. Wait a moment, then try '
            'again.';
      default:
        if (statusCode >= 500) {
          return 'OpenAI is temporarily unavailable (HTTP $statusCode). Try '
              'again in a moment.';
        }
        return 'OpenAI request failed (HTTP $statusCode). Check your '
            'configuration and try again.';
    }
  }

  @visibleForTesting
  String audioFormatForMimeType(String mimeType) {
    switch (mimeType.toLowerCase().trim()) {
      case 'audio/wav':
      case 'audio/x-wav':
      case 'audio/wave':
        return 'wav';
      case 'audio/mpeg':
      case 'audio/mp3':
        return 'mp3';
      default:
        throw CloudTranscriptionException(
          'Unsupported audio format "$mimeType". Use WAV or MP3 audio.',
        );
    }
  }

  static http.MediaType mediaTypeForMimeType(String mimeType) {
    switch (mimeType.toLowerCase().trim()) {
      case 'audio/wav':
      case 'audio/x-wav':
      case 'audio/wave':
        return http.MediaType('audio', 'wav');
      case 'audio/mpeg':
      case 'audio/mp3':
        return http.MediaType('audio', 'mpeg');
      default:
        throw CloudTranscriptionException(
          'Unsupported audio format "$mimeType". Use WAV or MP3 audio.',
        );
    }
  }

  void _assertInlinePayloadFits(Uint8List audioData) {
    // base64 inflation + envelope overhead; mirrors the Gemini guard so very
    // long recordings fail before upload.
    final estimated = ((audioData.length + 2) ~/ 3) * 4 + 8192;
    if (estimated > maxInlineRequestBytes) {
      throw CloudTranscriptionException(
        'This recording is too large for OpenAI requests. Shorten the '
        'recording or use offline Whisper with two-step cloud refinement.',
      );
    }
  }

  /// A tiny silent WAV used to verify transcription-model credentials without
  /// needing real speech from the user.
  @visibleForTesting
  static Uint8List buildSilentWavBytes({int sampleRate = 16000}) {
    final sampleCount = sampleRate ~/ 4; // 250 ms of silence
    final dataSize = sampleCount * 2; // 16-bit mono
    final bytes = ByteData(44 + dataSize);
    void ascii(int offset, String s) {
      for (var i = 0; i < s.length; i++) {
        bytes.setUint8(offset + i, s.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    bytes.setUint32(4, 36 + dataSize, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    bytes.setUint32(16, 16, Endian.little);
    bytes.setUint16(20, 1, Endian.little); // PCM
    bytes.setUint16(22, 1, Endian.little); // mono
    bytes.setUint32(24, sampleRate, Endian.little);
    bytes.setUint32(28, sampleRate * 2, Endian.little);
    bytes.setUint16(32, 2, Endian.little);
    bytes.setUint16(34, 16, Endian.little);
    ascii(36, 'data');
    bytes.setUint32(40, dataSize, Endian.little);
    return bytes.buffer.asUint8List();
  }

  @override
  Future<void> verifySetup() async {
    final apiKey = await _requireApiKey();
    if (_currentModel.isTranscriptionOnly) {
      // Transcription models need an audio probe; a short silent WAV
      // validates the key and endpoint without real speech.
      try {
        final response = await _postTranscription(
          apiKey,
          buildSilentWavBytes(),
          'audio/wav',
          _currentModel.modelName,
        );
        if (response.statusCode < 200 || response.statusCode >= 300) {
          _throwHttpFailure(response.statusCode);
        }
      } on TimeoutException {
        throw _timeoutException();
      }
      return;
    }
    try {
      final response = await _postChat(
        apiKey,
        buildVerifyPayload(model: _currentModel),
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        _throwHttpFailure(response.statusCode);
      }
    } on TimeoutException {
      throw _timeoutException();
    }
  }

  @override
  Future<String> improveTranscription(
    String rawText, {
    String? missionInstruction,
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) async {
    final apiKey = await _requireApiKey();
    final model = _resolveModel(modelOverrideId);
    if (model.isTranscriptionOnly) {
      throw CloudTranscriptionException(
        '${model.displayName} only transcribes and cannot apply a writing '
        'style. Choose a different AI model.',
      );
    }
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
      return parseChatResponse(await _postChat(apiKey, payload));
    } on TimeoutException {
      throw _timeoutException();
    }
  }

  /// Chat models cannot receive audio. Two requests must be explicitly
  /// orchestrated as two-pass transcription by CloudTranscriptionService.
  @override
  Future<String> transcribeAndImprove(
    Uint8List audioData,
    String mimeType, {
    String? missionInstruction,
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) async {
    _resolveModel(modelOverrideId);
    throw CloudTranscriptionException(
      'OpenAI chat models cannot receive audio. Enable two-step refinement '
      'and choose OpenAI for the polish step.',
    );
  }

  @override
  Future<String> transcribeAudio(
    Uint8List audioData,
    String mimeType, {
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) async {
    final apiKey = await _requireApiKey();
    final model = _resolveModel(modelOverrideId);
    if (!model.isTranscriptionOnly) {
      throw CloudTranscriptionException(
        '${model.displayName} does not accept audio input. Choose a '
        'transcription model in Settings.',
      );
    }
    _assertInlinePayloadFits(audioData);
    try {
      return parseTranscriptionResponse(
        await _postTranscription(apiKey, audioData, mimeType, model.modelName),
      );
    } on TimeoutException {
      throw _timeoutException();
    }
  }

  CloudTranscriptionException _timeoutException() {
    return CloudTranscriptionException(
      'OpenAI did not respond within $_requestTimeoutSeconds seconds. '
      'Try again in a moment.',
    );
  }
}
