import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/system_prompt.dart';
import 'cloud_transcription_client.dart';
import 'pinned_http_client.dart';
import 'retry_after.dart';
import 'serialization_utils.dart';
import 'settings_service.dart';

class GeminiInteractionsService implements CloudTranscriptionClient {
  GeminiInteractionsService({http.Client? httpClient})
    : _httpClient = httpClient ?? createSecureHttpClient();

  static const int maxInlineRequestBytes = 20 * 1024 * 1024;

  // The Interactions API is served exclusively under /v1beta
  // (https://ai.google.dev/api/interactions-api). There is no /v1 surface;
  // probing other versions can pin a broken endpoint.
  static const String _interactionApiVersion = 'v1beta';

  // All official REST examples pin the wire format with this dated revision
  // header (https://ai.google.dev/gemini-api/docs/interactions/quickstart).
  static const String apiRevision = '2026-05-20';

  final http.Client _httpClient;
  bool _isInitialized = false;
  bool _isDisposed = false;
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

  String? get _spokenLanguageId => _settingsService?.spokenLanguage;

  GeminiThinkingLevel? _resolveThinkingLevel({
    required GeminiModelConfig model,
    GeminiThinkingLevel? levelOverride,
    bool forceMinimal = false,
  }) {
    final override =
        levelOverride ?? _settingsService?.getThinkingLevelForModel(model.id);
    return model.resolveThinkingLevel(
      levelOverride: override,
      forceMinimal: forceMinimal,
    );
  }

  /// Builds the Interactions API `generation_config`.
  ///
  /// Unlike generateContent's `generationConfig`, the Interactions API has no
  /// `temperature` field — unknown fields are rejected with HTTP 400 — so
  /// sampling temperature cannot be configured here.
  Map<String, dynamic> _buildGenerationConfig({
    int? maxOutputTokens,
    GeminiThinkingLevel? thinkingLevel,
  }) {
    final config = <String, dynamic>{};
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
    String mimeType, {
    String? audioBase64,
  }) {
    return {
      'type': 'audio',
      'data': audioBase64 ?? base64Encode(audioData),
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
        maxOutputTokens: 8192,
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
    String? audioBase64,
    String? instructionOverride,
  }) {
    if (model.isTranscriptionOnly) {
      return _buildTranscribeOnlyPayload(
        audioData: audioData,
        mimeType: mimeType,
        model: model,
        audioBase64: audioBase64,
      );
    }

    final instruction =
        instructionOverride ??
        SystemPrompt.verbatimTranscriptionInstruction(
          languageId: _spokenLanguageId,
        );
    return _buildRequestEnvelope(
      modelName: model.modelName,
      systemInstruction: instruction,
      input: [
        _buildTextContent('Audio:'),
        _buildAudioContent(audioData, mimeType, audioBase64: audioBase64),
      ],
      generationConfig: _buildGenerationConfig(
        thinkingLevel: _resolveThinkingLevel(model: model, forceMinimal: true),
      ),
    );
  }

  Map<String, dynamic> _buildTranscribeOnlyPayload({
    required Uint8List audioData,
    required String mimeType,
    required GeminiModelConfig model,
    String? audioBase64,
  }) {
    final settings = _settingsService;
    final language = settings?.spokenLanguage ?? 'auto';

    final transcriptionConfig = <String, dynamic>{};
    if (language != 'auto') {
      transcriptionConfig['language_codes'] = [language];
    }
    transcriptionConfig['mode'] = const {'type': 'verbatim'};

    return _buildRequestEnvelope(
      modelName: model.modelName,
      systemInstruction: null,
      input: [
        _buildAudioContent(audioData, mimeType, audioBase64: audioBase64),
      ],
      generationConfig: {'transcription_config': transcriptionConfig},
    );
  }

  @visibleForTesting
  Map<String, dynamic> buildTranscribeAndImprovePayload({
    required Uint8List audioData,
    required String mimeType,
    required String missionInstruction,
    required GeminiModelConfig model,
    GeminiThinkingLevel? thinkingLevelOverride,
    String? audioBase64,
    String? systemInstructionOverride,
    String? audioPromptOverride,
  }) {
    final audioPrompt =
        audioPromptOverride ??
        SystemPrompt.transcribeAndImproveAudioPrompt(
          languageId: _spokenLanguageId,
        );
    final systemInstruction =
        systemInstructionOverride ??
        SystemPrompt.buildSystemInstruction(missionInstruction);
    return _buildRequestEnvelope(
      modelName: model.modelName,
      systemInstruction: systemInstruction,
      input: [
        _buildTextContent(audioPrompt),
        _buildAudioContent(audioData, mimeType, audioBase64: audioBase64),
      ],
      generationConfig: _buildGenerationConfig(
        maxOutputTokens: 8192,
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
    Uint8List body,
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

  Uri _buildUri() {
    return Uri.https(
      'generativelanguage.googleapis.com',
      '/$_interactionApiVersion/interactions',
    );
  }

  Future<http.Response> _postInteractions(
    String apiKey,
    Map<String, dynamic> payload,
  ) async {
    final headers = {
      'Content-Type': 'application/json',
      'x-goog-api-key': apiKey,
      'Api-Revision': apiRevision,
    };
    return _postWithRetry(_buildUri(), headers, await encodeJsonAsync(payload));
  }

  Future<String> _postPayload(
    String apiKey,
    Map<String, dynamic> payload, {
    bool allowAnyStepType = false,
  }) async {
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
        if (!allowAnyStepType && step['type'] != 'model_output') continue;
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
    if (_currentModel.isTranscriptionOnly) {
      // Transcription-only models cannot be verified with a text probe.
      // The Interactions path is already checked by the caller.
      return;
    }
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
    return _postPayload(
      apiKey,
      payload,
      allowAnyStepType: model.isTranscriptionOnly,
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
    final apiKey = await _requireApiKey();
    final model = _resolveModel(modelOverrideId);
    final resolvedMission =
        missionInstruction ?? SystemPrompt.availablePrompts.first.instruction;
    final audioPrompt = SystemPrompt.transcribeAndImproveAudioPrompt(
      languageId: _spokenLanguageId,
    );
    final systemInstruction = SystemPrompt.buildSystemInstruction(
      resolvedMission,
    );
    _assertInlinePayloadFits(audioData, audioPrompt, systemInstruction);
    final audioBase64 = await encodeBase64Async(audioData);
    final payload = buildTranscribeAndImprovePayload(
      audioData: audioData,
      mimeType: mimeType,
      missionInstruction: resolvedMission,
      model: model,
      thinkingLevelOverride: thinkingLevelOverride,
      audioBase64: audioBase64,
      systemInstructionOverride: systemInstruction,
      audioPromptOverride: audioPrompt,
    );
    return _postPayload(
      apiKey,
      payload,
      allowAnyStepType: model.isTranscriptionOnly,
    );
  }

  @override
  Future<String> transcribeAudio(
    Uint8List audioData,
    String mimeType, {
    String? modelOverrideId,
  }) async {
    final apiKey = await _requireApiKey();
    final model = _resolveModel(modelOverrideId);
    final instruction = model.isTranscriptionOnly
        ? null
        : SystemPrompt.verbatimTranscriptionInstruction(
            languageId: _spokenLanguageId,
          );
    _assertInlinePayloadFits(audioData, 'Audio:', instruction ?? '');
    final audioBase64 = await encodeBase64Async(audioData);
    final payload = buildTranscribePayload(
      audioData: audioData,
      mimeType: mimeType,
      model: model,
      audioBase64: audioBase64,
      instructionOverride: instruction,
    );
    return _postPayload(
      apiKey,
      payload,
      allowAnyStepType: model.isTranscriptionOnly,
    );
  }
}
