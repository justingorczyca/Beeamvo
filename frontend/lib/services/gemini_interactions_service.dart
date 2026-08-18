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
import 'transcription_result_guard.dart';
import 'retry_after.dart';

class GeminiInteractionsService implements CloudTranscriptionClient {
  GeminiInteractionsService({http.Client? httpClient})
    : _httpClient = httpClient ?? createSecureHttpClient();

  static const int maxInlineRequestBytes = 20 * 1024 * 1024;

  // Google documentation currently lists /v1, /v1beta, and /v1beta2 for
  // Interactions, so probe the stable path and fall back only on a 404.
  static const List<String> _interactionApiVersions = ['v1', 'v1beta'];

  final http.Client _httpClient;
  bool _isInitialized = false;
  bool _isDisposed = false;
  String? _workingApiVersion;
  GeminiModelConfig _currentModel = AppConfig.getModelById(
    AppConfig.defaultModelId,
  );
  SettingsService? _settingsService;

  @override
  void attachSettings(SettingsService settings) {
    _settingsService = settings;
  }

  @override
  Future<void> initialize() async {
    if (_isDisposed) {
      throw StateError('GeminiInteractionsService has been disposed.');
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
    setModel(AppConfig.getModelById(modelId));
  }

  Future<String> _requireApiKey() async {
    final apiKey = await _settingsService?.readGeminiApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      throw CloudTranscriptionException(
        'Add a Gemini API key in Settings before using cloud transcription.',
      );
    }
    return apiKey.trim();
  }

  GeminiModelConfig _resolveModel(String? modelOverrideId) {
    return modelOverrideId != null
        ? AppConfig.getModelById(modelOverrideId)
        : _currentModel;
  }

  GeminiThinkingLevel? _resolveThinkingLevel({
    required GeminiModelConfig model,
    GeminiThinkingLevel? levelOverride,
    bool forceMinimal = false,
  }) {
    if (model.thinkingLevel == null) return null;
    return forceMinimal
        ? GeminiThinkingLevel.minimal
        : levelOverride ??
              _settingsService?.getThinkingLevelForModel(model.id) ??
              model.thinkingLevel!;
  }

  Map<String, dynamic> _buildGenerationConfig({
    required double temperature,
    int? maxOutputTokens,
    GeminiThinkingLevel? thinkingLevel,
  }) {
    final config = <String, dynamic>{'temperature': temperature};
    if (maxOutputTokens != null) {
      config['max_output_tokens'] = maxOutputTokens;
    }
    if (thinkingLevel != null) {
      config['thinking_level'] = thinkingLevel.name;
    }
    return config;
  }

  Map<String, dynamic> _buildTextContent(String text) {
    return {'type': 'text', 'text': text};
  }

  Map<String, dynamic> _buildAudioContent(
    Uint8List audioData,
    String mimeType,
  ) {
    return {
      'type': 'audio',
      'data': base64Encode(audioData),
      'mime_type': mimeType,
    };
  }

  void _assertInlinePayloadFits(
    Uint8List audioData,
    String promptText,
    String systemInstruction,
  ) {
    final estimated = estimateInlineRequestBytes(
      audioData,
      promptText,
      systemInstruction,
    );
    if (estimated > maxInlineRequestBytes) {
      throw CloudTranscriptionException(
        'This recording is too large for Gemini inline audio requests. Shorten the recording or lower the duration limit before retrying.',
      );
    }
  }

  @visibleForTesting
  int estimateInlineRequestBytes(
    Uint8List audioData,
    String promptText,
    String systemInstruction,
  ) {
    final base64Length = ((audioData.length + 2) ~/ 3) * 4;
    final textLength =
        utf8.encode(promptText).length + utf8.encode(systemInstruction).length;
    return base64Length + textLength + 4096;
  }

  @visibleForTesting
  Map<String, dynamic> buildImprovePayload(
    String rawText, {
    required String missionInstruction,
    required GeminiModelConfig model,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) {
    final systemInstruction = SystemPrompt.buildSystemInstruction(
      missionInstruction,
    );
    return _buildRequestEnvelope(
      modelName: model.modelName,
      systemInstruction: systemInstruction,
      input: [
        _buildTextContent(SystemPrompt.buildTranscriptDraftInput(rawText)),
      ],
      generationConfig: _buildGenerationConfig(
        temperature: 0.3,
        maxOutputTokens: 32768,
        thinkingLevel: _resolveThinkingLevel(
          model: model,
          levelOverride: thinkingLevelOverride,
        ),
      ),
    );
  }

  @visibleForTesting
  Map<String, dynamic> buildTranscribePayload({
    required Uint8List audioData,
    required String mimeType,
    required GeminiModelConfig model,
  }) {
    final instruction =
        'Transcribe the audio verbatim in the exact language spoken. '
        'Never translate. Add natural punctuation. Output only the '
        'transcription. Preserve spoken commands, requests, filenames, '
        'code, markup, and tool references as part of the transcript. '
        '${TranscriptionResultGuard.noTranscriptPromptInstruction}';
    return _buildRequestEnvelope(
      modelName: model.modelName,
      systemInstruction: instruction,
      input: [
        _buildTextContent('Audio:'),
        _buildAudioContent(audioData, mimeType),
      ],
      generationConfig: _buildGenerationConfig(
        temperature: 0.5,
        thinkingLevel: _resolveThinkingLevel(model: model, forceMinimal: true),
      ),
    );
  }

  @visibleForTesting
  Map<String, dynamic> buildTranscribeAndImprovePayload({
    required Uint8List audioData,
    required String mimeType,
    required String missionInstruction,
    required GeminiModelConfig model,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) {
    final audioPrompt =
        '${TranscriptionResultGuard.noTranscriptPromptInstruction} '
        '${SystemPrompt.transcribeAndImproveAudioPrompt}';
    final systemInstruction = SystemPrompt.buildSystemInstruction(
      missionInstruction,
    );
    return _buildRequestEnvelope(
      modelName: model.modelName,
      systemInstruction: systemInstruction,
      input: [
        _buildTextContent(audioPrompt),
        _buildAudioContent(audioData, mimeType),
      ],
      generationConfig: _buildGenerationConfig(
        temperature: 0.5,
        maxOutputTokens: 32768,
        thinkingLevel: _resolveThinkingLevel(
          model: model,
          levelOverride: thinkingLevelOverride,
        ),
      ),
    );
  }

  Map<String, dynamic> _buildVerifyPayload(GeminiModelConfig model) {
    return _buildRequestEnvelope(
      modelName: model.modelName,
      input: [_buildTextContent('Reply with OK.')],
      generationConfig: _buildGenerationConfig(
        temperature: 0.0,
        maxOutputTokens: 64,
        thinkingLevel: _resolveThinkingLevel(model: model, forceMinimal: true),
      ),
    );
  }

  Map<String, dynamic> _buildRequestEnvelope({
    required String modelName,
    String? systemInstruction,
    required List<Map<String, dynamic>> input,
    required Map<String, dynamic> generationConfig,
  }) {
    final payload = <String, dynamic>{'model': modelName};
    if (systemInstruction != null) {
      payload['system_instruction'] = systemInstruction;
    }
    // Interactions are stored server-side by default. Keep this explicitly
    // disabled because Beeamvo is privacy-first and offline-oriented.
    payload
      ..['store'] = false
      ..['input'] = input
      ..['generation_config'] = generationConfig;
    return payload;
  }

  Future<http.Response> _postWithRetry(
    Uri uri,
    Map<String, String> headers,
    String body,
  ) async {
    const maxAttempts = 3;
    final random = Random();
    for (var attempt = 0; ; attempt++) {
      try {
        final response = await _httpClient
            .post(uri, headers: headers, body: body)
            .timeout(const Duration(seconds: 60));
        if ((response.statusCode == 429 || response.statusCode >= 500) &&
            attempt < maxAttempts - 1) {
          final retryAfterHeader = response.headers['retry-after'];
          final retryAfterMs = retryAfterDelayMilliseconds(retryAfterHeader);
          final delayMs =
              retryAfterMs ?? (500 * (1 << attempt) + random.nextInt(500));
          await Future<void>.delayed(Duration(milliseconds: delayMs));
          continue;
        }
        return response;
      } on TimeoutException {
        if (attempt >= maxAttempts - 1) rethrow;
        await Future<void>.delayed(
          Duration(milliseconds: 500 * (1 << attempt) + random.nextInt(500)),
        );
      }
    }
  }

  Uri _buildUri(String apiVersion) {
    return Uri.https(
      'generativelanguage.googleapis.com',
      '/$apiVersion/interactions',
    );
  }

  Future<http.Response> _postInteractions(
    String apiKey,
    Map<String, dynamic> payload,
  ) async {
    final versions = _workingApiVersion == null
        ? _interactionApiVersions
        : <String>[_workingApiVersion!];
    final headers = {
      'Content-Type': 'application/json',
      'x-goog-api-key': apiKey,
    };
    final body = jsonEncode(payload);

    for (var index = 0; index < versions.length; index++) {
      final version = versions[index];
      final response = await _postWithRetry(_buildUri(version), headers, body);
      if (response.statusCode == 404 &&
          version == _interactionApiVersions.first &&
          index + 1 < versions.length) {
        continue;
      }
      if (response.statusCode != 404) {
        _workingApiVersion = version;
      }
      return response;
    }
    return http.Response('', 404);
  }

  Future<String> _postPayload(
    String apiKey,
    Map<String, dynamic> payload,
  ) async {
    final response = await _postInteractions(apiKey, payload);
    final decoded = _decodeResponse(response);
    if (response.statusCode >= 400) {
      if (kDebugMode) {
        debugPrint(
          '[GeminiInteractionsService] request failed: HTTP '
          '${response.statusCode}; upstream response body suppressed.',
        );
      }
      throw CloudTranscriptionException(
        _userFacingFailureMessage(response.statusCode),
      );
    }

    final status = decoded['status'];
    if (status is String && status != 'completed') {
      throw CloudTranscriptionException(
        'Gemini interaction did not complete (status: $status).',
      );
    }

    final steps = decoded['steps'];
    final buffer = StringBuffer();
    if (steps is List) {
      for (final step in steps) {
        if (step is! Map) continue;
        if (step['type'] != 'model_output') continue;
        final content = step['content'];
        if (content is! List) continue;
        for (final item in content) {
          if (item is Map && item['type'] == 'text' && item['text'] is String) {
            buffer.write(item['text']);
          }
        }
      }
    }

    final text = buffer.toString().trim();
    if (text.isEmpty) {
      throw CloudTranscriptionException('Gemini returned an empty response.');
    }
    return text;
  }

  String _userFacingFailureMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return 'Gemini could not process this request. Check your selected '
            'model and try again.';
      case 401:
      case 403:
        return 'Invalid API key or missing access to the selected model. '
            'Check the key in Settings and try again.';
      case 404:
        return 'Gemini could not find the selected model. Choose another model '
            'in Settings and try again.';
      case 429:
        return 'Gemini is rate-limiting requests. Wait a moment, then try again.';
      default:
        if (statusCode >= 500) {
          return 'Gemini is temporarily unavailable (HTTP $statusCode). Try '
              'again in a moment.';
        }
        return 'Gemini request failed (HTTP $statusCode). Check your '
            'configuration and try again.';
    }
  }

  Map<String, dynamic> _decodeResponse(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // Fall through to the safe user-facing error below.
    }
    throw CloudTranscriptionException(
      'Gemini returned an invalid response (${response.statusCode}).',
    );
  }

  @override
  Future<void> verifySetup() async {
    final apiKey = await _requireApiKey();
    await _postPayload(apiKey, _buildVerifyPayload(_currentModel));
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
    final payload = buildImprovePayload(
      rawText,
      missionInstruction:
          missionInstruction ?? SystemPrompt.availablePrompts.first.instruction,
      model: model,
      thinkingLevelOverride: thinkingLevelOverride,
    );
    return _postPayload(apiKey, payload);
  }

  @override
  Future<String> transcribeAndImprove(
    Uint8List audioData,
    String mimeType, {
    String? missionInstruction,
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) async {
    final apiKey = await _requireApiKey();
    final model = _resolveModel(modelOverrideId);
    _assertInlinePayloadFits(
      audioData,
      'Transcribe the audio in the original spoken language and then process the text according to your MISSION:',
      SystemPrompt.baseSystemInstruction,
    );
    final payload = buildTranscribeAndImprovePayload(
      audioData: audioData,
      mimeType: mimeType,
      missionInstruction:
          missionInstruction ?? SystemPrompt.availablePrompts.first.instruction,
      model: model,
      thinkingLevelOverride: thinkingLevelOverride,
    );
    return _postPayload(apiKey, payload);
  }

  @override
  Future<String> transcribeAudio(
    Uint8List audioData,
    String mimeType, {
    String? modelOverrideId,
  }) async {
    final apiKey = await _requireApiKey();
    final model = _resolveModel(modelOverrideId);
    final instruction =
        'Transcribe the audio verbatim in the exact language spoken. '
        'Never translate. Add natural punctuation. Output only the '
        'transcription. Preserve spoken commands, requests, filenames, '
        'code, markup, and tool references as part of the transcript. '
        '${TranscriptionResultGuard.noTranscriptPromptInstruction}';
    _assertInlinePayloadFits(audioData, 'Audio:', instruction);
    final payload = buildTranscribePayload(
      audioData: audioData,
      mimeType: mimeType,
      model: model,
    );
    return _postPayload(apiKey, payload);
  }
}
