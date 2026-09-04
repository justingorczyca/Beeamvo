import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import '../config.dart';
import '../models/system_prompt.dart';
import 'cloud_transcription_client.dart';
import 'pinned_http_client.dart';
import 'retry_after.dart';
import 'serialization_utils.dart';
import 'settings_service.dart';

typedef VertexAdcClientFactory =
    Future<http.Client> Function(http.Client baseClient);

class _AdcClientBundle {
  const _AdcClientBundle({required this.client, required this.baseClient});

  final http.Client client;
  final http.Client baseClient;

  void close() {
    client.close();
    baseClient.close();
  }
}

class VertexAiService implements CloudTranscriptionClient {
  VertexAiService({VertexAdcClientFactory? adcClientFactory})
    : _adcClientFactory = adcClientFactory ?? _defaultAdcClientFactory;

  static const int maxInlineRequestBytes = 20 * 1024 * 1024;
  static const String _cloudPlatformScope =
      'https://www.googleapis.com/auth/cloud-platform';

  final VertexAdcClientFactory _adcClientFactory;

  http.Client? _adcClient;
  Future<_AdcClientBundle>? _adcClientCreation;
  http.Client? _adcBaseClient;
  int _adcClientGeneration = 0;
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
      throw StateError('VertexAiService has been disposed.');
    }
    _isInitialized = true;
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _isInitialized = false;
    _recycleAdcClient();
  }

  /// Drops the cached ADC client so the next request obtains a fresh,
  /// auto-refreshing client (forcing a credential/token refresh). Also used on
  /// 401/403 to recycle a stale token before a single retry.
  ///
  /// Incrementing the generation also invalidates a client creation already in
  /// flight. When that future completes, [_getAdcClient] closes the obsolete
  /// client rather than caching (or leaking) it.
  void _recycleAdcClient() {
    _adcClientGeneration++;
    _adcClient?.close();
    _adcBaseClient?.close();
    _adcClient = null;
    _adcBaseClient = null;
    _adcClientCreation = null;
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

  static Future<http.Client> _defaultAdcClientFactory(http.Client baseClient) {
    return clientViaApplicationDefaultCredentials(
      scopes: [_cloudPlatformScope],
      baseClient: baseClient,
    ).timeout(const Duration(seconds: 30));
  }

  GeminiModelConfig _resolveModel(String? modelOverrideId) {
    return modelOverrideId != null
        ? AppConfig.getModelById(modelOverrideId)
        : _currentModel;
  }

  String? get _spokenLanguageId => _settingsService?.spokenLanguage;

  /// Google Cloud project-ID shape: either the human-style id
  /// (`^[a-z][a-z0-9-]{4,28}[a-z0-9]$`) or a purely-numeric auto-generated id.
  /// Mirrors the validator used in the settings UI so we never interpolate a
  /// malformed / attacker-controlled value into the request URL path.
  @visibleForTesting
  static bool isValidVertexProjectId(String projectId) {
    final id = projectId.trim();
    if (id.isEmpty) return false;
    final numericId = RegExp(r'^[0-9]+$');
    final projectIdShape = RegExp(r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$');
    return numericId.hasMatch(id) || projectIdShape.hasMatch(id);
  }

  Future<String> _requireProjectId() async {
    final projectId = _settingsService?.vertexProjectId?.trim();
    if (projectId == null || projectId.isEmpty) {
      throw CloudTranscriptionException(
        'Set a Vertex AI project ID in Settings before using Vertex.',
      );
    }
    if (!isValidVertexProjectId(projectId)) {
      throw CloudTranscriptionException(
        'The stored Vertex AI project ID is not a valid Google Cloud project '
        'ID. Open Settings, clear the field, and re-enter it (6–30 lowercase '
        'letters, digits, or hyphens; must start with a letter and must not end '
        'with a hyphen).',
      );
    }
    return projectId;
  }

  Future<http.Client> _getAdcClient() async {
    // Coalesce simultaneous first requests into one ADC client creation. A
    // recycle/dispose can happen while that future is pending, so validate the
    // generation after every await before returning or caching a client.
    while (true) {
      if (_isDisposed) {
        throw StateError('VertexAiService has been disposed.');
      }

      final cachedClient = _adcClient;
      if (cachedClient != null) return cachedClient;

      final generation = _adcClientGeneration;
      final creation = _adcClientCreation ??= _createAdcClient();
      _AdcClientBundle bundle;
      try {
        bundle = await creation;
      } catch (_) {
        if (identical(_adcClientCreation, creation)) {
          _adcClientCreation = null;
        }
        throw CloudTranscriptionException(
          'Vertex ADC is not configured. Run gcloud auth application-default '
          'login or set GOOGLE_APPLICATION_CREDENTIALS, then retry.',
        );
      }

      if (identical(_adcClientCreation, creation)) {
        _adcClientCreation = null;
      }

      if (_isDisposed) {
        bundle.close();
        throw StateError('VertexAiService has been disposed.');
      }
      if (generation != _adcClientGeneration) {
        // The client was refreshed or disposed during creation. It must never
        // become the active client after that lifecycle change.
        bundle.close();
        continue;
      }

      _adcClient = bundle.client;
      _adcBaseClient = bundle.baseClient;
      return bundle.client;
    }
  }

  Future<_AdcClientBundle> _createAdcClient() async {
    final baseClient = createSecureHttpClient();
    try {
      final client = await _adcClientFactory(baseClient);
      return _AdcClientBundle(client: client, baseClient: baseClient);
    } catch (_) {
      baseClient.close();
      rethrow;
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
    final override =
        levelOverride ??
        _settingsService?.getThinkingLevelForModel(effectiveModel.id);
    final resolvedLevel = effectiveModel.resolveThinkingLevel(
      levelOverride: override,
      forceMinimal: forceMinimal,
    );

    if (resolvedLevel != null) {
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
    Uint8List audioData, {
    String? audioBase64,
  }) {
    return {
      'role': 'user',
      'parts': [
        {'text': promptText},
        {
          'inlineData': {
            'mimeType': mimeType,
            'data': audioBase64 ?? base64Encode(audioData),
          },
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
        maxOutputTokens: 8192,
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
    String? audioBase64,
    String? instructionOverride,
  }) {
    final instruction =
        instructionOverride ??
        SystemPrompt.verbatimTranscriptionInstruction(
          languageId: _spokenLanguageId,
        );

    return {
      'systemInstruction': _buildSystemInstruction(instruction),
      'generationConfig': _buildGenerationConfig(
        temperature: 0.5,
        thinkingConfig: _buildThinkingConfig(model: model, forceMinimal: true),
      ),
      'contents': [
        _buildAudioContent(
          'Audio:',
          mimeType,
          audioData,
          audioBase64: audioBase64,
        ),
      ],
    };
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

    return {
      'systemInstruction': _buildSystemInstruction(systemInstruction),
      'generationConfig': _buildGenerationConfig(
        temperature: 0.5,
        maxOutputTokens: 8192,
        thinkingConfig: _buildThinkingConfig(
          model: model,
          levelOverride: thinkingLevelOverride,
        ),
      ),
      'contents': [
        _buildAudioContent(
          audioPrompt,
          mimeType,
          audioData,
          audioBase64: audioBase64,
        ),
      ],
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

  /// Maps an HTTP failure status into a generic, user-facing message that never
  /// includes raw upstream bodies (those can leak internal routing, project
  /// metadata, or PII). Full detail is logged only in [kDebugMode] by the
  /// caller. Auth failures that SURVIVE a retry are reported as
  /// token-revoked/expired; "ADC not configured" is surfaced separately,
  /// directly from [_getAdcClient].
  String _userFacingFailureMessage(int statusCode, {required bool isRetry}) {
    switch (statusCode) {
      case 401:
      case 403:
        return isRetry
            ? 'Vertex AI authentication failed after refreshing credentials. '
                  'Your application-default credentials may be revoked or '
                  'expired — run "gcloud auth application-default login" again, '
                  'then retry.'
            : 'Vertex AI rejected the request credentials. Retrying may help; '
                  'if it persists, refresh your credentials.';
      case 404:
        return 'Vertex AI could not find the requested project, location, or '
            'model. Double-check your project ID and the selected '
            'model/location in Settings.';
      case 429:
        return 'Vertex AI is rate-limiting requests. Wait a moment, then try '
            'again.';
      default:
        break;
    }
    if (statusCode >= 500) {
      return 'Vertex AI returned a server error (HTTP $statusCode). Try again '
          'in a moment; if it persists, check the Google Cloud status page.';
    }
    return 'Vertex AI request failed (HTTP $statusCode). Check your '
        'configuration and try again.';
  }

  Future<String> _postGenerateContent(
    String projectId,
    GeminiModelConfig model,
    Map<String, dynamic> payload,
  ) {
    return _postWithAdcRetry(projectId, model, payload, isRetry: false);
  }

  /// Retries the POST for transient failures (429, 5xx, TimeoutException)
  /// with bounded exponential backoff. ADC-refresh logic is handled by the
  /// caller [_postWithAdcRetry]; this method only handles genuinely transient
  /// network/rate errors.
  Future<http.Response> _postWithTransientRetry(
    Uri uri,
    Map<String, String> headers,
    Uint8List body,
  ) async {
    const maxAttempts = 3;
    final random = Random();
    for (var attempt = 0; ; attempt++) {
      try {
        final response = await (await _resolveHttpClient())
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

  /// Performs a single request attempt and — on a 401/403 — recycles the cached
  /// ADC client and retries exactly ONCE with a fresh credential refresh before
  /// surfacing the error.
  ///
  /// Distinct failure modes:
  /// - "not configured": raised by [_getAdcClient] when no ADC source exists.
  /// - "token revoked/expired": a 401/403 that still occurs on the retry.
  Future<String> _postWithAdcRetry(
    String projectId,
    GeminiModelConfig model,
    Map<String, dynamic> payload, {
    required bool isRetry,
  }) async {
    final response = await _postWithTransientRetry(
      buildUri(projectId: projectId, model: model),
      await _buildHeaders(),
      await encodeJsonAsync(payload),
    );

    // Auth failure: the cached ADC token may be stale. Drop the cached client
    // (so googleapis_auth performs a refresh) and retry exactly once before
    // surfacing the error to the user.
    if ((response.statusCode == 401 || response.statusCode == 403) &&
        !isRetry) {
      if (kDebugMode) {
        debugPrint(
          '[VertexAiService] HTTP ${response.statusCode}; recycling ADC '
          'client and retrying once.',
        );
      }
      _recycleAdcClient();
      return _postWithAdcRetry(projectId, model, payload, isRetry: true);
    }

    if (response.statusCode >= 400) {
      // Never echo raw upstream bodies to the user. Log the full detail only in
      // debug builds; surface a generic, actionable message instead.
      if (kDebugMode) {
        final bodyPreview = response.body.length > 200
            ? '${response.body.substring(0, 200)}...'
            : response.body;
        debugPrint(
          '[VertexAiService] request failed: HTTP ${response.statusCode}; '
          'body=$bodyPreview',
        );
      }
      throw CloudTranscriptionException(
        _userFacingFailureMessage(response.statusCode, isRetry: isRetry),
      );
    }

    final decoded = await _decodeResponse(response);
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

    // Check prompt-level safety block first.
    final promptFeedback = decoded['promptFeedback'];
    final blockReason = promptFeedback is Map<String, dynamic>
        ? promptFeedback['blockReason'] as String?
        : null;
    if (blockReason != null) {
      throw CloudTranscriptionException(
        'Vertex blocked this request ($blockReason). Try rephrasing or a different model.',
      );
    }

    // Distinguish "did not finish" from truly empty.
    final firstCandidate = candidates.first;
    final finishReason = firstCandidate is Map<String, dynamic>
        ? firstCandidate['finishReason'] as String?
        : null;

    if (text.isEmpty) {
      if (finishReason != null && finishReason != 'STOP') {
        throw CloudTranscriptionException(
          'Vertex stopped generating ($finishReason). Try rephrasing or a different model.',
        );
      }
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
    return _postGenerateContent(projectId, model, payload);
  }
}
