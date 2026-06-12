import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/system_prompt.dart';
import 'cloud_transcription_client.dart';
import 'settings_service.dart';
import 'transcription_result_guard.dart';

typedef VertexAdcClientFactory = Future<http.Client> Function();

class VertexAiService implements CloudTranscriptionClient {
  VertexAiService({VertexAdcClientFactory? adcClientFactory})
    : _adcClientFactory = adcClientFactory ?? _defaultAdcClientFactory;

  static const int maxInlineRequestBytes = 20 * 1024 * 1024;
  static const String _cloudPlatformScope =
      'https://www.googleapis.com/auth/cloud-platform';

  final VertexAdcClientFactory _adcClientFactory;

  http.Client? _adcClient;
  bool _isInitialized = false;
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
    _isInitialized = true;
  }

  @override
  void dispose() {
    _adcClient?.close();
    _adcClient = null;
  }

  @override
  bool get isInitialized => _isInitialized;

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

  static Future<http.Client> _defaultAdcClientFactory() {
    return clientViaApplicationDefaultCredentials(
      scopes: [_cloudPlatformScope],
    );
  }

  GeminiModelConfig _resolveModel(String? modelOverrideId) {
    return modelOverrideId != null
        ? AppConfig.getModelById(modelOverrideId)
        : _currentModel;
  }

  Future<String> _requireProjectId() async {
    final projectId = _settingsService?.vertexProjectId?.trim();
    if (projectId == null || projectId.isEmpty) {
      throw CloudTranscriptionException(
        'Set a Vertex AI project ID in Settings before using Vertex.',
      );
    }
    return projectId;
  }

  Future<http.Client> _getAdcClient() async {
    final cachedClient = _adcClient;
    if (cachedClient != null) return cachedClient;

    try {
      final client = await _adcClientFactory();
      _adcClient = client;
      return client;
    } catch (_) {
      throw CloudTranscriptionException(
        'Vertex ADC is not configured. Run gcloud auth application-default login or set GOOGLE_APPLICATION_CREDENTIALS, then retry.',
      );
    }
  }

  Future<http.Client> _resolveHttpClient() async {
    return _getAdcClient();
  }

  Future<Map<String, String>> _buildHeaders() async {
    return {'Content-Type': 'application/json'};
  }

  @visibleForTesting
  Uri buildUri({required String projectId, required GeminiModelConfig model}) {
    final location = model.vertexLocation;
    final host = location == 'global'
        ? 'aiplatform.googleapis.com'
        : '$location-aiplatform.googleapis.com';
    return Uri.https(
      host,
      '/v1/projects/$projectId/locations/$location/publishers/google/models/${model.modelName}:generateContent',
    );
  }

  Map<String, dynamic>? _buildThinkingConfig({
    GeminiModelConfig? model,
    GeminiThinkingLevel? levelOverride,
    bool forceMinimal = false,
  }) {
    final effectiveModel = model ?? _currentModel;

    if (effectiveModel.thinkingLevel != null) {
      final resolvedLevel = forceMinimal
          ? GeminiThinkingLevel.minimal
          : levelOverride ??
                _settingsService?.getThinkingLevelForModel(effectiveModel.id) ??
                effectiveModel.thinkingLevel!;
      return {
        'thinkingConfig': {'thinkingLevel': resolvedLevel.apiValue},
      };
    }

    if (effectiveModel.thinkingBudget != null) {
      return {
        'thinkingConfig': {'thinkingBudget': effectiveModel.thinkingBudget},
      };
    }

    return null;
  }

  Map<String, dynamic> _buildGenerationConfig({
    required double temperature,
    int? maxOutputTokens,
    Map<String, dynamic>? thinkingConfig,
  }) {
    final config = <String, dynamic>{'temperature': temperature};
    if (maxOutputTokens != null) {
      config['maxOutputTokens'] = maxOutputTokens;
    }
    if (thinkingConfig != null) {
      config.addAll(thinkingConfig);
    }
    return config;
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
        'This recording is too large for Vertex inline audio requests. Shorten the recording or lower the duration limit before retrying.',
      );
    }
  }

  Map<String, dynamic> _buildSystemInstruction(String instruction) {
    return {
      'parts': [
        {'text': instruction},
      ],
    };
  }

  Map<String, dynamic> _buildTextContent(String text) {
    return {
      'role': 'user',
      'parts': [
        {'text': text},
      ],
    };
  }

  Map<String, dynamic> _buildAudioContent(
    String promptText,
    String mimeType,
    Uint8List audioData,
  ) {
    return {
      'role': 'user',
      'parts': [
        {'text': promptText},
        {
          'inlineData': {'mimeType': mimeType, 'data': base64Encode(audioData)},
        },
      ],
    };
  }

  @visibleForTesting
  Map<String, dynamic> buildImprovePayload(
    String rawText, {
    required String missionInstruction,
    required GeminiModelConfig model,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) {
    return {
      'systemInstruction': _buildSystemInstruction(
        SystemPrompt.buildSystemInstruction(missionInstruction),
      ),
      'generationConfig': _buildGenerationConfig(
        temperature: 0.3,
        maxOutputTokens: 32768,
        thinkingConfig: _buildThinkingConfig(
          model: model,
          levelOverride: thinkingLevelOverride,
        ),
      ),
      'contents': [
        _buildTextContent(SystemPrompt.buildTranscriptDraftInput(rawText)),
      ],
    };
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

    return {
      'systemInstruction': _buildSystemInstruction(instruction),
      'generationConfig': _buildGenerationConfig(
        temperature: 0.5,
        thinkingConfig: _buildThinkingConfig(model: model, forceMinimal: true),
      ),
      'contents': [_buildAudioContent('Audio:', mimeType, audioData)],
    };
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

    return {
      'systemInstruction': _buildSystemInstruction(
        SystemPrompt.buildSystemInstruction(missionInstruction),
      ),
      'generationConfig': _buildGenerationConfig(
        temperature: 0.5,
        maxOutputTokens: 32768,
        thinkingConfig: _buildThinkingConfig(
          model: model,
          levelOverride: thinkingLevelOverride,
        ),
      ),
      'contents': [_buildAudioContent(audioPrompt, mimeType, audioData)],
    };
  }

  Future<Map<String, dynamic>> _decodeResponse(http.Response response) async {
    try {
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw CloudTranscriptionException(
        'Vertex returned an invalid response (${response.statusCode}).',
      );
    }
  }

  Future<String> _postGenerateContent(
    String projectId,
    GeminiModelConfig model,
    Map<String, dynamic> payload,
  ) async {
    final response = await (await _resolveHttpClient())
        .post(
          buildUri(projectId: projectId, model: model),
          headers: await _buildHeaders(),
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 60));

    final decoded = await _decodeResponse(response);
    if (response.statusCode >= 400) {
      final error = decoded['error'];
      final message =
          error is Map<String, dynamic> && error['message'] is String
          ? error['message'] as String
          : 'Vertex request failed with status ${response.statusCode}.';
      throw CloudTranscriptionException(message);
    }

    final candidates = decoded['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw CloudTranscriptionException('Vertex returned no candidates.');
    }

    final buffer = StringBuffer();
    for (final candidate in candidates) {
      final content = candidate is Map<String, dynamic>
          ? candidate['content']
          : null;
      final parts = content is Map<String, dynamic> ? content['parts'] : null;
      if (parts is! List) continue;
      for (final part in parts) {
        if (part is Map<String, dynamic> && part['text'] is String) {
          buffer.write(part['text'] as String);
        }
      }
    }

    final text = buffer.toString().trim();
    if (text.isEmpty) {
      throw CloudTranscriptionException('Vertex returned an empty response.');
    }
    return text;
  }

  @override
  Future<void> verifySetup() async {
    final projectId = await _requireProjectId();
    await _getAdcClient();
    final payload = {
      'contents': [_buildTextContent('Reply with OK.')],
      'generationConfig': {'temperature': 0.0, 'maxOutputTokens': 8},
    };
    await _postGenerateContent(projectId, _currentModel, payload);
  }

  @override
  Future<String> improveTranscription(
    String rawText, {
    String? missionInstruction,
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) async {
    final projectId = await _requireProjectId();
    final model = _resolveModel(modelOverrideId);
    final payload = buildImprovePayload(
      rawText,
      missionInstruction:
          missionInstruction ?? SystemPrompt.availablePrompts.first.instruction,
      model: model,
      thinkingLevelOverride: thinkingLevelOverride,
    );
    return _postGenerateContent(projectId, model, payload);
  }

  @override
  Future<String> transcribeAndImprove(
    Uint8List audioData,
    String mimeType, {
    String? missionInstruction,
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) async {
    final projectId = await _requireProjectId();
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
    return _postGenerateContent(projectId, model, payload);
  }

  @override
  Future<String> transcribeAudio(
    Uint8List audioData,
    String mimeType, {
    String? modelOverrideId,
  }) async {
    final projectId = await _requireProjectId();
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
    return _postGenerateContent(projectId, model, payload);
  }
}
