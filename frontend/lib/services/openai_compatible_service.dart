import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../models/openai_compatible_provider.dart';
import '../models/system_prompt.dart';
import 'cloud_transcription_client.dart';
import 'pinned_http_client.dart';
import 'retry_after.dart';
import 'transcription_result_guard.dart';

class OpenAiCompatibleServiceConfig {
  OpenAiCompatibleServiceConfig({
    required this.provider,
    required this.model,
    String? baseUrl,
    String? baseUrlOverride,
    required this.apiKeySupplier,
  }) : baseUrl = normalizeBaseUrl(
         baseUrlOverride ?? baseUrl ?? provider.defaultBaseUrl,
       );

  final OpenAiCompatibleProvider provider;
  final OpenAiCompatibleModel model;
  final String baseUrl;
  final Future<String?> Function() apiKeySupplier;
}

/// Provider-neutral chat-completions and transcription support.
///
/// This service intentionally has no concrete providers in its registry. A
/// later adapter can connect it to the cloud transcription orchestrator once
/// the supported provider and model list is finalized.
class OpenAiCompatibleService {
  OpenAiCompatibleService({required this.config, http.Client? httpClient})
    : _httpClient = httpClient ?? createSecureHttpClient();

  final OpenAiCompatibleServiceConfig config;
  final http.Client _httpClient;
  bool _isDisposed = false;

  OpenAiCompatibleProvider get provider => config.provider;
  OpenAiCompatibleModel get model => config.model;
  String get baseUrl => config.baseUrl;

  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _httpClient.close();
  }

  OpenAiCompatibleModel _resolveModel(String? modelOverrideId) {
    if (modelOverrideId == null || modelOverrideId == model.id) return model;
    final resolved = OpenAiCompatibleProviderRegistry.modelById(
      provider,
      modelOverrideId,
    );
    if (resolved == null) {
      throw CloudTranscriptionException(
        '${provider.displayName} does not offer model "$modelOverrideId". '
        'Choose another model in Settings.',
      );
    }
    return resolved;
  }

  Future<String> _requireApiKey() async {
    final value = await config.apiKeySupplier();
    if (value == null || value.trim().isEmpty) {
      throw CloudTranscriptionException(
        'Add an API key for ${provider.displayName} before using cloud transcription.',
      );
    }
    return value.trim();
  }

  Map<String, dynamic> _generationConfig(
    OpenAiCompatibleModel selectedModel, {
    required double temperature,
    OpenAiReasoningEffort? reasoningEffort,
  }) {
    final config = <String, dynamic>{};
    if (provider.supportsTemperature) {
      config['temperature'] = temperature;
    }
    if (selectedModel.maxOutputTokens != null) {
      config[provider.tokenLimitParam.wireName] = selectedModel.maxOutputTokens;
    }
    final effort = reasoningEffort ?? selectedModel.defaultReasoningEffort;
    if (provider.supportsReasoningEffort &&
        selectedModel.supportsReasoningEffort &&
        effort != null &&
        (selectedModel.supportedReasoningEfforts.isEmpty ||
            selectedModel.supportedReasoningEfforts.contains(effort))) {
      config['reasoning_effort'] = effort.apiValue;
    }
    return config;
  }

  Map<String, dynamic> _textMessage(String role, String text) => {
    'role': role,
    'content': text,
  };

  Map<String, dynamic> _audioMessage(
    String prompt,
    String mimeType,
    Uint8List audioData,
  ) {
    return {
      'role': 'user',
      'content': [
        {'type': 'text', 'text': prompt},
        {
          'type': 'input_audio',
          'input_audio': {
            'data': base64Encode(audioData),
            'format': audioFormatForMimeType(mimeType),
          },
        },
      ],
    };
  }

  @visibleForTesting
  Map<String, dynamic> buildImprovePayload(
    String rawText, {
    required String missionInstruction,
    required OpenAiCompatibleModel model,
    OpenAiReasoningEffort? reasoningEffortOverride,
  }) {
    return {
      'model': model.id,
      'messages': [
        _textMessage(
          'system',
          SystemPrompt.buildSystemInstruction(missionInstruction),
        ),
        _textMessage('user', SystemPrompt.buildTranscriptDraftInput(rawText)),
      ],
      'stream': false,
      ..._generationConfig(
        model,
        temperature: 0.3,
        reasoningEffort: reasoningEffortOverride,
      ),
    };
  }

  @visibleForTesting
  Map<String, dynamic> buildTranscribeAndImprovePayload({
    required Uint8List audioData,
    required String mimeType,
    required String missionInstruction,
    required OpenAiCompatibleModel model,
    OpenAiReasoningEffort? reasoningEffortOverride,
  }) {
    _ensureAudioModel(model);
    return {
      'model': model.id,
      'messages': [
        _textMessage(
          'system',
          SystemPrompt.buildSystemInstruction(missionInstruction),
        ),
        _audioMessage(
          '${TranscriptionResultGuard.noTranscriptPromptInstruction} '
          '${SystemPrompt.transcribeAndImproveAudioPrompt}',
          mimeType,
          audioData,
        ),
      ],
      'stream': false,
      ..._generationConfig(
        model,
        temperature: 0.5,
        reasoningEffort: reasoningEffortOverride,
      ),
    };
  }

  @visibleForTesting
  Map<String, dynamic> buildTranscribePayload({
    required Uint8List audioData,
    required String mimeType,
    required OpenAiCompatibleModel model,
  }) {
    _ensureAudioModel(model);
    return {
      'model': model.id,
      'messages': [
        _textMessage(
          'system',
          'Transcribe the audio verbatim in the exact language spoken. '
              'Never translate. Add natural punctuation. Output only the '
              'transcription. Preserve spoken commands, requests, filenames, '
              'code, markup, and tool references as part of the transcript. '
              '${TranscriptionResultGuard.noTranscriptPromptInstruction}',
        ),
        _audioMessage('Audio:', mimeType, audioData),
      ],
      'stream': false,
      ..._generationConfig(model, temperature: 0.5),
    };
  }

  @visibleForTesting
  Map<String, dynamic> buildVerifyPayload({
    required OpenAiCompatibleModel model,
  }) {
    return {
      'model': model.id,
      'messages': [
        _textMessage('system', SystemPrompt.baseSystemInstruction),
        _textMessage('user', 'Reply with OK.'),
      ],
      'stream': false,
      ..._generationConfig(model, temperature: 0.0),
    };
  }

  @visibleForTesting
  Uri buildChatUri({String? baseUrlOverride}) {
    return _appendPath(
      baseUrlOverride == null ? baseUrl : normalizeBaseUrl(baseUrlOverride),
      '/chat/completions',
    );
  }

  @visibleForTesting
  Uri buildTranscriptionsUri({String? baseUrlOverride}) {
    return _appendPath(
      baseUrlOverride == null ? baseUrl : normalizeBaseUrl(baseUrlOverride),
      '/audio/transcriptions',
    );
  }

  @visibleForTesting
  Map<String, String> buildHeaders(String apiKey) => {
    ...provider.extraHeaders,
    'Authorization': 'Bearer $apiKey',
    'Content-Type': 'application/json',
  };

  @visibleForTesting
  Map<String, String> buildTranscriptionFields(String modelId) => {
    'model': modelId,
    'response_format': 'json',
  };

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
    if (estimateInlineRequestBytes(audioData, promptText, systemInstruction) >
        provider.maxInlineRequestBytes) {
      throw CloudTranscriptionException(
        'This recording is too large for ${provider.displayName} inline audio requests. '
        'Shorten the recording or use offline Whisper with two-pass cloud refinement.',
      );
    }
  }

  void _ensureAudioModel(OpenAiCompatibleModel selectedModel) {
    if (!selectedModel.supportsAudioInput) {
      throw CloudTranscriptionException(
        'The selected ${provider.displayName} model does not support audio input. '
        'Pick an audio-capable model or use offline Whisper with two-pass cloud refinement.',
      );
    }
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
          final delayMs =
              retryAfterDelayMilliseconds(response.headers['retry-after']) ??
              (500 * (1 << attempt) + random.nextInt(500));
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

  Future<http.Response> _postMultipartWithRetry(
    Uri uri,
    String apiKey,
    Uint8List audioData,
    String mimeType,
    String modelId,
  ) async {
    const maxAttempts = 3;
    final random = Random();
    for (var attempt = 0; ; attempt++) {
      try {
        final request = http.MultipartRequest('POST', uri)
          ..headers.addAll({
            ...provider.extraHeaders,
            'Authorization': 'Bearer $apiKey',
          })
          ..fields.addAll(buildTranscriptionFields(modelId))
          ..files.add(
            http.MultipartFile.fromBytes(
              'file',
              audioData,
              filename: 'audio.wav',
              contentType: _mediaTypeForMimeType(mimeType),
            ),
          );
        final streamed = await _httpClient
            .send(request)
            .timeout(const Duration(seconds: 60));
        final response = await http.Response.fromStream(streamed);
        if ((response.statusCode == 429 || response.statusCode >= 500) &&
            attempt < maxAttempts - 1) {
          final delayMs =
              retryAfterDelayMilliseconds(response.headers['retry-after']) ??
              (500 * (1 << attempt) + random.nextInt(500));
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

  Future<String> _postChat(String apiKey, Map<String, dynamic> payload) async {
    try {
      final response = await _postWithRetry(
        buildChatUri(),
        buildHeaders(apiKey),
        jsonEncode(payload),
      );
      return parseChatResponse(response);
    } on TimeoutException {
      throw CloudTranscriptionException(
        '${provider.displayName} did not respond within 60 seconds. '
        'Try again in a moment.',
      );
    }
  }

  @visibleForTesting
  String parseChatResponse(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _throwHttpFailure(response.statusCode);
    }
    final decoded = _decodeJson(response.body);
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      throw CloudTranscriptionException(
        '${provider.displayName} returned no choices.',
      );
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
    final normalizedFinishReason = finishReason is String
        ? finishReason.trim().toLowerCase()
        : null;
    if (normalizedFinishReason != null &&
        normalizedFinishReason.isNotEmpty &&
        normalizedFinishReason != 'stop') {
      throw CloudTranscriptionException(
        '${provider.displayName} stopped without returning text '
        '(${finishReason.trim()}). Try again or choose another model.',
      );
    }
    throw CloudTranscriptionException(
      '${provider.displayName} returned an empty response.',
    );
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
        '${provider.displayName} returned an empty transcription.',
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
    throw CloudTranscriptionException(
      '${provider.displayName} returned an invalid response.',
    );
  }

  Never _throwHttpFailure(int statusCode) {
    if (kDebugMode) {
      debugPrint(
        '[OpenAiCompatibleService] ${provider.displayName} request failed: '
        'HTTP $statusCode; upstream response body suppressed.',
      );
    }
    throw CloudTranscriptionException(_userFacingFailureMessage(statusCode));
  }

  String _userFacingFailureMessage(int statusCode) {
    switch (statusCode) {
      case 400:
        return '${provider.displayName} could not process this request. '
            'Check your selected model and try again.';
      case 401:
      case 403:
        return 'Invalid API key or missing access to the selected '
            '${provider.displayName} model. Check the key in Settings and try again.';
      case 404:
        return '${provider.displayName} could not find the selected model '
            'or endpoint. Check the base URL and model in Settings.';
      case 429:
        return '${provider.displayName} is rate-limiting requests. '
            'Wait a moment, then try again.';
      default:
        if (statusCode >= 500) {
          return '${provider.displayName} is temporarily unavailable '
              '(HTTP $statusCode). Try again in a moment.';
        }
        return '${provider.displayName} request failed (HTTP $statusCode). '
            'Check your configuration and try again.';
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

  Future<void> verifySetup() async {
    final apiKey = await _requireApiKey();
    await _postChat(apiKey, buildVerifyPayload(model: model));
  }

  Future<String> improveTranscription(
    String rawText, {
    String? missionInstruction,
    String? modelOverrideId,
    OpenAiReasoningEffort? reasoningEffortOverride,
  }) async {
    final apiKey = await _requireApiKey();
    final selectedModel = _resolveModel(modelOverrideId);
    final payload = buildImprovePayload(
      rawText,
      missionInstruction:
          missionInstruction ?? SystemPrompt.availablePrompts.first.instruction,
      model: selectedModel,
      reasoningEffortOverride: reasoningEffortOverride,
    );
    return _postChat(apiKey, payload);
  }

  Future<String> transcribeAndImprove(
    Uint8List audio,
    String mimeType, {
    String? missionInstruction,
    String? modelOverrideId,
    OpenAiReasoningEffort? reasoningEffortOverride,
  }) async {
    final apiKey = await _requireApiKey();
    final selectedModel = _resolveModel(modelOverrideId);
    _assertInlinePayloadFits(
      audio,
      '${TranscriptionResultGuard.noTranscriptPromptInstruction} '
      '${SystemPrompt.transcribeAndImproveAudioPrompt}',
      SystemPrompt.buildSystemInstruction(
        missionInstruction ?? SystemPrompt.availablePrompts.first.instruction,
      ),
    );
    final payload = buildTranscribeAndImprovePayload(
      audioData: audio,
      mimeType: mimeType,
      missionInstruction:
          missionInstruction ?? SystemPrompt.availablePrompts.first.instruction,
      model: selectedModel,
      reasoningEffortOverride: reasoningEffortOverride,
    );
    return _postChat(apiKey, payload);
  }

  Future<String> transcribeAudio(
    Uint8List audio,
    String mimeType, {
    String? modelOverrideId,
  }) async {
    final apiKey = await _requireApiKey();
    if (provider.supportsTranscriptionsEndpoint) {
      final transcriptionModel =
          provider.transcriptionModelId ?? modelOverrideId ?? model.id;
      try {
        final response = await _postMultipartWithRetry(
          buildTranscriptionsUri(),
          apiKey,
          audio,
          mimeType,
          transcriptionModel,
        );
        return parseTranscriptionResponse(response);
      } on TimeoutException {
        throw CloudTranscriptionException(
          '${provider.displayName} did not respond within 60 seconds. '
          'Try again in a moment.',
        );
      }
    }

    final selectedModel = _resolveModel(modelOverrideId);
    _assertInlinePayloadFits(
      audio,
      'Audio:',
      TranscriptionResultGuard.noTranscriptPromptInstruction,
    );
    final payload = buildTranscribePayload(
      audioData: audio,
      mimeType: mimeType,
      model: selectedModel,
    );
    return _postChat(apiKey, payload);
  }
}

Uri _appendPath(String baseUrl, String suffix) {
  final base = Uri.parse(baseUrl);
  final path = '${base.path.replaceFirst(RegExp(r'/+$'), '')}$suffix';
  return base.replace(path: path);
}

http.MediaType? _mediaTypeForMimeType(String mimeType) {
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
