import '../config.dart';
import '../services/cloud_transcription_client.dart';

/// Selects the provider-specific token-cap parameter.
///
/// OpenAI deprecated `max_tokens` in favor of `max_completion_tokens`, while
/// many compatible servers still only accept `max_tokens`.
enum OpenAiTokenLimitParam {
  maxTokens('max_tokens'),
  maxCompletionTokens('max_completion_tokens');

  const OpenAiTokenLimitParam(this.wireName);

  final String wireName;
}

enum OpenAiReasoningEffort {
  none('none'),
  minimal('minimal'),
  low('low'),
  medium('medium'),
  high('high');

  const OpenAiReasoningEffort(this.apiValue);

  final String apiValue;

  static OpenAiReasoningEffort fromGeminiThinkingLevel(
    GeminiThinkingLevel level,
  ) {
    switch (level) {
      case GeminiThinkingLevel.minimal:
        return minimal;
      case GeminiThinkingLevel.low:
        return low;
      case GeminiThinkingLevel.medium:
        return medium;
      case GeminiThinkingLevel.high:
        return high;
    }
  }
}

extension OpenAiReasoningEffortGeminiMapping on GeminiThinkingLevel {
  OpenAiReasoningEffort get openAiReasoningEffort {
    return OpenAiReasoningEffort.fromGeminiThinkingLevel(this);
  }
}

class OpenAiCompatibleModel {
  const OpenAiCompatibleModel({
    required this.id,
    required this.displayName,
    this.supportsAudioInput = false,
    this.supportsReasoningEffort = false,
    this.maxOutputTokens,
    this.defaultReasoningEffort,
    this.supportedReasoningEfforts = const [],
  });

  final String id;
  final String displayName;

  /// True only for models accepting multimodal `input_audio` content parts.
  final bool supportsAudioInput;
  final bool supportsReasoningEffort;
  final int? maxOutputTokens;
  final OpenAiReasoningEffort? defaultReasoningEffort;
  final List<OpenAiReasoningEffort> supportedReasoningEfforts;
}

class OpenAiCompatibleProvider {
  const OpenAiCompatibleProvider({
    required this.id,
    required this.displayName,
    required this.defaultBaseUrl,
    required this.models,
    required this.tokenLimitParam,
    required this.supportsReasoningEffort,
    this.supportsTemperature = true,
    this.supportsTranscriptionsEndpoint = false,
    this.extraHeaders = const {},
    this.transcriptionModelId,
    this.maxInlineRequestBytes = 20 * 1024 * 1024,
  });

  final String id;
  final String displayName;
  final String defaultBaseUrl;
  final List<OpenAiCompatibleModel> models;
  final OpenAiTokenLimitParam tokenLimitParam;
  final bool supportsReasoningEffort;
  final bool supportsTemperature;
  final bool supportsTranscriptionsEndpoint;
  final Map<String, String> extraHeaders;
  final String? transcriptionModelId;
  final int maxInlineRequestBytes;
}

class OpenAiCompatibleProviderRegistry {
  /// Providers are intentionally added here as one const entry each once the
  /// supported provider list is finalized.
  static const List<OpenAiCompatibleProvider> builtIn =
      <OpenAiCompatibleProvider>[];

  static OpenAiCompatibleProvider? byId(String id) {
    for (final provider in builtIn) {
      if (provider.id == id) return provider;
    }
    return null;
  }

  static OpenAiCompatibleModel? modelById(
    OpenAiCompatibleProvider provider,
    String id,
  ) {
    for (final model in provider.models) {
      if (model.id == id) return model;
    }
    return null;
  }
}

String normalizeBaseUrl(String value) {
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
      'Enter a valid absolute HTTPS base URL for the OpenAI-compatible service.',
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
      'The OpenAI-compatible base URL must use HTTPS. HTTP is only allowed for localhost or 127.0.0.1.',
    );
  }

  final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
  final lowerPath = path.toLowerCase();
  if (lowerPath.endsWith('/chat/completions') ||
      lowerPath.endsWith('/completions')) {
    throw CloudTranscriptionException(
      'Enter the service base URL without /chat/completions or /completions.',
    );
  }

  return uri.replace(path: path).toString();
}
