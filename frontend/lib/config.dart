/// App configuration for Beeamvo.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import 'models/enums.dart';

/// Thinking level for reasoning-capable models.
///
/// Gemini 3+ models expose this as `thinkingLevel`; OpenAI-compatible and
/// Codex models map `.name` onto `reasoning_effort` / `reasoning.effort` on
/// the wire. `none`, `xhigh` and `max` are only offered by models that list
/// them in `supportedThinkingLevels` (no Gemini model does). Levels persist by
/// [GeminiThinkingLevelExtension.apiValue], never by index.
enum GeminiThinkingLevel { none, minimal, low, medium, high, xhigh, max }

extension GeminiThinkingLevelExtension on GeminiThinkingLevel {
  String get apiValue {
    switch (this) {
      case GeminiThinkingLevel.none:
        return 'NONE';
      case GeminiThinkingLevel.minimal:
        return 'MINIMAL';
      case GeminiThinkingLevel.low:
        return 'LOW';
      case GeminiThinkingLevel.medium:
        return 'MEDIUM';
      case GeminiThinkingLevel.high:
        return 'HIGH';
      case GeminiThinkingLevel.xhigh:
        return 'XHIGH';
      case GeminiThinkingLevel.max:
        return 'MAX';
    }
  }

  String get displayLabel {
    switch (this) {
      case GeminiThinkingLevel.none:
        return 'Off';
      case GeminiThinkingLevel.minimal:
        return 'Minimal';
      case GeminiThinkingLevel.low:
        return 'Low';
      case GeminiThinkingLevel.medium:
        return 'Medium';
      case GeminiThinkingLevel.high:
        return 'High';
      case GeminiThinkingLevel.xhigh:
        return 'X-High';
      case GeminiThinkingLevel.max:
        return 'Max';
    }
  }

  String get description {
    switch (this) {
      case GeminiThinkingLevel.none:
        return 'No reasoning — fastest response, ideal for dictation';
      case GeminiThinkingLevel.minimal:
        return 'Fastest, lowest cost, best for simple tasks';
      case GeminiThinkingLevel.low:
        return 'Balanced, light reasoning, great default';
      case GeminiThinkingLevel.medium:
        return 'Deeper reasoning, better accuracy, slightly slower';
      case GeminiThinkingLevel.high:
        return 'Strong reasoning, high quality, higher token cost';
      case GeminiThinkingLevel.xhigh:
        return 'Very deep reasoning for demanding text, slower and costlier';
      case GeminiThinkingLevel.max:
        return 'Maximum reasoning effort, slowest, highest token cost';
    }
  }

  static GeminiThinkingLevel? fromString(String? value) {
    if (value == null) return null;
    for (final level in GeminiThinkingLevel.values) {
      if (level.apiValue == value.toUpperCase()) {
        return level;
      }
    }
    return null;
  }
}

/// Represents a cloud model shared across the provider clients.
///
/// The name predates multi-provider support: Gemini, Vertex, OpenAI-compatible,
/// and Codex catalogs all use this descriptor. Provider-specific wire fields
/// are derived from [supportedThinkingLevels]/[isTranscriptionOnly] by each
/// client.
class GeminiModelConfig {
  final String id;
  final String name;
  final String modelName;

  /// Vertex AI location. Preview models use `global`.
  final String vertexLocation;

  final bool isPreview;

  /// For Gemini 2.x models.
  final int? thinkingBudget;
  final GeminiThinkingLevel? interactionsThinkingLevel;

  /// For Gemini 3+ models.
  final GeminiThinkingLevel? thinkingLevel;

  final List<GeminiThinkingLevel> supportedThinkingLevels;

  /// True when this model is a dedicated speech-to-text model. It can be used
  /// for any raw audio-to-text pass (single-pass or Pass 1 of two-pass), but
  /// it cannot follow mission prompts, so it is excluded from refinement and
  /// transcribe-and-improve paths.
  final bool isTranscriptionOnly;

  /// Audio support on the provider API used by this application.
  final bool supportsAudio;

  /// One-line summary shown in model pickers; empty falls back to generic
  /// copy in the UI.
  final String description;

  const GeminiModelConfig({
    required this.id,
    required this.name,
    required this.modelName,
    this.vertexLocation = 'global',
    this.isPreview = false,
    this.thinkingBudget,
    this.interactionsThinkingLevel,
    this.thinkingLevel,
    this.supportedThinkingLevels = const [],
    this.isTranscriptionOnly = false,
    this.supportsAudio = false,
    this.description = '',
  });

  bool get hasSelectableThinkingLevel => supportedThinkingLevels.isNotEmpty;

  String get displayName => isPreview ? '$name (Preview)' : name;

  /// Returns a thinking level that is guaranteed to be supported by this model.
  ///
  /// - For 2.x models (no [thinkingLevel]) it returns `null`.
  /// - [levelOverride] is honored only when it appears in [supportedThinkingLevels].
  /// - When [forceMinimal] is `true`, the lowest supported level is used. This
  ///   prevents sending `minimal` to models such as Gemini 3.7 Flash that do
  ///   not support it, which would return an HTTP 400.
  GeminiThinkingLevel? resolveThinkingLevel({
    GeminiThinkingLevel? levelOverride,
    bool forceMinimal = false,
  }) {
    if (thinkingLevel == null) return null;
    final levels = supportedThinkingLevels;
    if (levels.isEmpty) return null;

    GeminiThinkingLevel candidate;
    if (forceMinimal) {
      candidate = levels.contains(GeminiThinkingLevel.minimal)
          ? GeminiThinkingLevel.minimal
          : levels.first;
    } else {
      candidate = levelOverride ?? thinkingLevel!;
    }

    return levels.contains(candidate) ? candidate : thinkingLevel!;
  }

  Map<String, dynamic>? thinkingConfigWithLevel([
    GeminiThinkingLevel? levelOverride,
  ]) {
    final effective = resolveThinkingLevel(levelOverride: levelOverride);
    if (effective != null) {
      return {'thinkingLevel': effective.apiValue};
    }
    if (thinkingBudget != null) {
      return {'thinkingBudget': thinkingBudget};
    }
    return null;
  }

  Map<String, dynamic>? get thinkingConfig => thinkingConfigWithLevel();
}

class AppConfig {
  static const List<GeminiModelConfig> availableModels = [
    GeminiModelConfig(
      id: 'gemini-3.7-flash',
      name: 'Gemini 3.7 Flash',
      modelName: 'gemini-3.7-flash',
      supportsAudio: true,
      vertexLocation: 'global',
      thinkingLevel: GeminiThinkingLevel.low,
      supportedThinkingLevels: [
        GeminiThinkingLevel.low,
        GeminiThinkingLevel.medium,
        GeminiThinkingLevel.high,
      ],
      description: 'Most capable. Advanced reasoning at Flash speed.',
    ),
    GeminiModelConfig(
      id: 'gemini-3.6-flash',
      name: 'Gemini 3.6 Flash',
      modelName: 'gemini-3.6-flash',
      supportsAudio: true,
      vertexLocation: 'global',
      thinkingLevel: GeminiThinkingLevel.minimal,
      supportedThinkingLevels: [
        GeminiThinkingLevel.minimal,
        GeminiThinkingLevel.low,
        GeminiThinkingLevel.medium,
        GeminiThinkingLevel.high,
      ],
      description: 'Strong reasoning, fast — a great all-rounder.',
    ),
    GeminiModelConfig(
      id: 'gemini-3.5-flash',
      name: 'Gemini 3.5 Flash',
      modelName: 'gemini-3.5-flash',
      supportsAudio: true,
      vertexLocation: 'global',
      thinkingLevel: GeminiThinkingLevel.minimal,
      supportedThinkingLevels: [
        GeminiThinkingLevel.minimal,
        GeminiThinkingLevel.low,
        GeminiThinkingLevel.medium,
        GeminiThinkingLevel.high,
      ],
      description: 'Latest stable Flash. Strong reasoning with high speed.',
    ),
    GeminiModelConfig(
      id: 'gemini-3.5-flash-lite',
      name: 'Gemini 3.5 Flash Lite',
      modelName: 'gemini-3.5-flash-lite',
      supportsAudio: true,
      vertexLocation: 'global',
      thinkingLevel: GeminiThinkingLevel.minimal,
      supportedThinkingLevels: [
        GeminiThinkingLevel.minimal,
        GeminiThinkingLevel.low,
        GeminiThinkingLevel.medium,
        GeminiThinkingLevel.high,
      ],
      description: 'Fastest and lightest — the recommended default.',
    ),
    GeminiModelConfig(
      id: 'gemini-3-flash',
      name: 'Gemini 3 Flash',
      modelName: 'gemini-3-flash-preview',
      supportsAudio: true,
      vertexLocation: 'global',
      isPreview: true,
      thinkingLevel: GeminiThinkingLevel.minimal,
      supportedThinkingLevels: [
        GeminiThinkingLevel.minimal,
        GeminiThinkingLevel.low,
        GeminiThinkingLevel.medium,
        GeminiThinkingLevel.high,
      ],
      description: 'Newest generation. Advanced reasoning (Preview).',
    ),
    GeminiModelConfig(
      id: 'gemini-3.1-flash-lite',
      name: 'Gemini 3.1 Flash Lite',
      modelName: 'gemini-3.1-flash-lite',
      supportsAudio: true,
      thinkingLevel: GeminiThinkingLevel.minimal,
      supportedThinkingLevels: [
        GeminiThinkingLevel.minimal,
        GeminiThinkingLevel.low,
        GeminiThinkingLevel.medium,
        GeminiThinkingLevel.high,
      ],
      description: 'Next-gen lightweight. Fast with upgraded reasoning.',
    ),
    GeminiModelConfig(
      id: 'gemini-2.5-flash',
      name: 'Gemini 2.5 Flash',
      modelName: 'gemini-2.5-flash',
      supportsAudio: true,
      thinkingBudget: 0,
      interactionsThinkingLevel: GeminiThinkingLevel.low,
      description: 'Stable Flash model for transcription and writing styles.',
    ),
    GeminiModelConfig(
      id: 'gemini-2.5-flash-lite',
      name: 'Gemini 2.5 Flash Lite',
      modelName: 'gemini-2.5-flash-lite',
      supportsAudio: true,
      thinkingBudget: 0,
      description: 'Ultra-fast responses, lighter reasoning.',
    ),
    GeminiModelConfig(
      id: 'gemini-3.5-transcribe',
      name: 'Gemini 3.5 Transcribe',
      modelName: 'gemini-3.5-transcribe',
      vertexLocation: 'global',
      isPreview: true,
      isTranscriptionOnly: true,
      supportsAudio: true,
      description:
          'Dedicated speech-to-text model. Writing styles are not applied.',
    ),
  ];

  /// OpenAI-compatible models served through `POST {base}/chat/completions`
  /// and `POST {base}/audio/transcriptions`.
  ///
  /// `isTranscriptionOnly` models go to the dedicated transcriptions endpoint;
  /// every other entry is a chat model used for refinement (and for the
  /// polish half of a chained single pass).
  static const List<GeminiModelConfig> openAiModels = [
    GeminiModelConfig(
      id: 'gpt-transcribe',
      name: 'GPT Transcribe',
      modelName: 'gpt-transcribe',
      isTranscriptionOnly: true,
      supportsAudio: true,
      description: 'OpenAI speech-to-text model.',
    ),
    GeminiModelConfig(
      id: 'gpt-4o-transcribe',
      name: 'GPT-4o Transcribe',
      modelName: 'gpt-4o-transcribe',
      isTranscriptionOnly: true,
      supportsAudio: true,
      description: 'OpenAI speech-to-text model.',
    ),
    GeminiModelConfig(
      id: 'gpt-4o-mini-transcribe',
      name: 'GPT-4o Mini Transcribe',
      modelName: 'gpt-4o-mini-transcribe',
      isTranscriptionOnly: true,
      supportsAudio: true,
      description: 'OpenAI speech-to-text model.',
    ),
    GeminiModelConfig(
      id: 'whisper-1',
      name: 'Whisper v1',
      modelName: 'whisper-1',
      isTranscriptionOnly: true,
      supportsAudio: true,
      description: 'Legacy Whisper speech-to-text model.',
    ),
    _gpt6Astra,
    _gpt6Sol,
    _gpt6Luna,
    _gpt56Sol,
    _gpt56Terra,
    _gpt56Luna,
    _gpt55,
    GeminiModelConfig(
      id: 'gpt-5.4-mini',
      name: 'GPT-5.4 Mini',
      modelName: 'gpt-5.4-mini',
      thinkingLevel: GeminiThinkingLevel.none,
      supportedThinkingLevels: [
        GeminiThinkingLevel.none,
        GeminiThinkingLevel.low,
        GeminiThinkingLevel.medium,
        GeminiThinkingLevel.high,
      ],
      description: 'Compact and fast — great for everyday dictation.',
    ),
    GeminiModelConfig(
      id: 'gpt-5.4-nano',
      name: 'GPT-5.4 Nano',
      modelName: 'gpt-5.4-nano',
      thinkingLevel: GeminiThinkingLevel.none,
      supportedThinkingLevels: [
        GeminiThinkingLevel.none,
        GeminiThinkingLevel.low,
        GeminiThinkingLevel.medium,
        GeminiThinkingLevel.high,
      ],
      description: 'Smallest and cheapest OpenAI model.',
    ),
  ];

  /// GPT-6/GPT-5.6 flagships shared by the OpenAI-compatible and ChatGPT
  /// Codex catalogs — the Codex backend serves the same model ids.
  static const GeminiModelConfig _gpt6Astra = GeminiModelConfig(
    id: 'gpt-6-astra',
    name: 'GPT-6 Astra',
    modelName: 'gpt-6-astra',
    thinkingLevel: GeminiThinkingLevel.low,
    supportedThinkingLevels: [
      GeminiThinkingLevel.low,
      GeminiThinkingLevel.medium,
      GeminiThinkingLevel.high,
      GeminiThinkingLevel.xhigh,
      GeminiThinkingLevel.max,
    ],
    description: 'OpenAI frontier model. Highest quality polish.',
  );

  static const GeminiModelConfig _gpt6Sol = GeminiModelConfig(
    id: 'gpt-6-sol',
    name: 'GPT-6 Sol',
    modelName: 'gpt-6-sol',
    thinkingLevel: GeminiThinkingLevel.low,
    supportedThinkingLevels: [
      GeminiThinkingLevel.none,
      GeminiThinkingLevel.low,
      GeminiThinkingLevel.medium,
      GeminiThinkingLevel.high,
      GeminiThinkingLevel.xhigh,
      GeminiThinkingLevel.max,
    ],
    description: 'GPT-6 frontier model for complex professional writing.',
  );

  static const GeminiModelConfig _gpt6Luna = GeminiModelConfig(
    id: 'gpt-6-luna',
    name: 'GPT-6 Luna',
    modelName: 'gpt-6-luna',
    thinkingLevel: GeminiThinkingLevel.none,
    supportedThinkingLevels: [
      GeminiThinkingLevel.none,
      GeminiThinkingLevel.low,
      GeminiThinkingLevel.medium,
      GeminiThinkingLevel.high,
      GeminiThinkingLevel.xhigh,
      GeminiThinkingLevel.max,
    ],
    description: 'Cost-optimized GPT-6. Fast, lightweight polish.',
  );

  static const GeminiModelConfig _gpt56Sol = GeminiModelConfig(
    id: 'gpt-5.6-sol',
    name: 'GPT-5.6 Sol',
    modelName: 'gpt-5.6-sol',
    thinkingLevel: GeminiThinkingLevel.low,
    supportedThinkingLevels: [
      GeminiThinkingLevel.none,
      GeminiThinkingLevel.low,
      GeminiThinkingLevel.medium,
      GeminiThinkingLevel.high,
      GeminiThinkingLevel.xhigh,
      GeminiThinkingLevel.max,
    ],
    description: 'Frontier model for complex professional writing.',
  );

  static const GeminiModelConfig _gpt56Terra = GeminiModelConfig(
    id: 'gpt-5.6-terra',
    name: 'GPT-5.6 Terra',
    modelName: 'gpt-5.6-terra',
    thinkingLevel: GeminiThinkingLevel.low,
    supportedThinkingLevels: [
      GeminiThinkingLevel.none,
      GeminiThinkingLevel.low,
      GeminiThinkingLevel.medium,
      GeminiThinkingLevel.high,
      GeminiThinkingLevel.xhigh,
      GeminiThinkingLevel.max,
    ],
    description: 'Balanced intelligence and cost — the recommended default.',
  );

  static const GeminiModelConfig _gpt56Luna = GeminiModelConfig(
    id: 'gpt-5.6-luna',
    name: 'GPT-5.6 Luna',
    modelName: 'gpt-5.6-luna',
    thinkingLevel: GeminiThinkingLevel.none,
    supportedThinkingLevels: [
      GeminiThinkingLevel.none,
      GeminiThinkingLevel.low,
      GeminiThinkingLevel.medium,
      GeminiThinkingLevel.high,
      GeminiThinkingLevel.xhigh,
      GeminiThinkingLevel.max,
    ],
    description: 'Cost-optimized. Fast, lightweight polish.',
  );

  static const GeminiModelConfig _gpt55 = GeminiModelConfig(
    id: 'gpt-5.5',
    name: 'GPT-5.5',
    modelName: 'gpt-5.5',
    thinkingLevel: GeminiThinkingLevel.low,
    supportedThinkingLevels: [
      GeminiThinkingLevel.none,
      GeminiThinkingLevel.low,
      GeminiThinkingLevel.medium,
      GeminiThinkingLevel.high,
    ],
    description: 'Previous flagship reasoning model.',
  );

  /// ChatGPT-account models served through the Codex Responses backend
  /// (`https://chatgpt.com/backend-api/codex/responses`, stream-only).
  ///
  /// Prompt-capable models use the Codex Responses backend. ChatGPT
  /// transcription uses the dedicated `/transcribe` endpoint without a model
  /// field. `supportedThinkingLevels` map directly onto `reasoning.effort`
  /// (`none` maps to `reasoning.effort: none`); `chat-latest` sends no
  /// `reasoning` block.
  static const List<GeminiModelConfig> codexModels = [
    _gpt6Astra,
    _gpt6Sol,
    _gpt6Luna,
    _gpt56Sol,
    _gpt56Terra,
    _gpt56Luna,
    GeminiModelConfig(
      id: 'gpt-5-6-thinking',
      name: 'GPT-5.6 Thinking',
      modelName: 'gpt-5-6-thinking',
      thinkingLevel: GeminiThinkingLevel.medium,
      supportedThinkingLevels: [
        GeminiThinkingLevel.none,
        GeminiThinkingLevel.low,
        GeminiThinkingLevel.medium,
        GeminiThinkingLevel.high,
      ],
      description: 'Deep multi-step reasoning. Slowest, most thorough polish.',
    ),
    _gpt55,
    GeminiModelConfig(
      id: 'gpt-5.4',
      name: 'GPT-5.4',
      modelName: 'gpt-5.4',
      thinkingLevel: GeminiThinkingLevel.low,
      supportedThinkingLevels: [
        GeminiThinkingLevel.none,
        GeminiThinkingLevel.low,
        GeminiThinkingLevel.medium,
        GeminiThinkingLevel.high,
      ],
      description: 'Previous-generation model. Solid everyday polish.',
    ),
    GeminiModelConfig(
      id: 'chat-latest',
      name: 'ChatGPT Latest',
      modelName: 'chat-latest',
      description:
          'The model behind ChatGPT. No reasoning step — quickest reply.',
    ),
    GeminiModelConfig(
      id: 'chatgpt-transcribe',
      name: 'ChatGPT Transcribe',
      modelName: 'chatgpt-transcribe',
      isTranscriptionOnly: true,
      supportsAudio: true,
      description:
          "ChatGPT's dictation speech model on your ChatGPT plan. Writing "
          'styles are not applied.',
    ),
  ];

  /// xAI-account models served through the Grok Responses API
  /// (`https://api.x.ai/v1/responses`).
  ///
  /// None of these accept audio input — Grok is a polish/refinement provider.
  /// `supportedThinkingLevels` map onto `reasoning.effort` (`low`/`medium`/
  /// `high`); xAI cannot disable reasoning on effort-capable models, so
  /// `minimal` is not offered and unresolved levels clamp to `low`.
  /// `grok-code-fast-1` reasons natively with no controllable selector.
  static const List<GeminiModelConfig> grokModels = [
    GeminiModelConfig(
      id: 'grok-4.3',
      name: 'Grok 4.3',
      modelName: 'grok-4.3',
      thinkingLevel: GeminiThinkingLevel.low,
      supportedThinkingLevels: [
        GeminiThinkingLevel.low,
        GeminiThinkingLevel.medium,
        GeminiThinkingLevel.high,
      ],
      description:
          'xAI Grok model. Polishes text; needs another provider for speech.',
    ),
    GeminiModelConfig(
      id: 'grok-4.5',
      name: 'Grok 4.5',
      modelName: 'grok-4.5',
      thinkingLevel: GeminiThinkingLevel.low,
      supportedThinkingLevels: [
        GeminiThinkingLevel.low,
        GeminiThinkingLevel.medium,
        GeminiThinkingLevel.high,
      ],
      description:
          'xAI Grok model. Polishes text; needs another provider for speech.',
    ),
    GeminiModelConfig(
      id: 'grok-4.6',
      name: 'Grok 4.6',
      modelName: 'grok-4.6',
      thinkingLevel: GeminiThinkingLevel.low,
      supportedThinkingLevels: [
        GeminiThinkingLevel.low,
        GeminiThinkingLevel.medium,
        GeminiThinkingLevel.high,
      ],
      description:
          'xAI Grok model. Polishes text; needs another provider for speech.',
    ),
    GeminiModelConfig(
      id: 'grok-4.7',
      name: 'Grok 4.7',
      modelName: 'grok-4.7',
      thinkingLevel: GeminiThinkingLevel.low,
      supportedThinkingLevels: [
        GeminiThinkingLevel.low,
        GeminiThinkingLevel.medium,
        GeminiThinkingLevel.high,
      ],
      description:
          'xAI Grok model. Polishes text; needs another provider for speech.',
    ),
    GeminiModelConfig(
      id: 'grok-3-mini',
      name: 'Grok 3 Mini',
      modelName: 'grok-3-mini',
      thinkingLevel: GeminiThinkingLevel.low,
      supportedThinkingLevels: [
        GeminiThinkingLevel.low,
        GeminiThinkingLevel.medium,
        GeminiThinkingLevel.high,
      ],
      description:
          'xAI Grok model. Polishes text; needs another provider for speech.',
    ),
    GeminiModelConfig(
      id: 'grok-4.20-multi-agent',
      name: 'Grok 4.20 Multi-Agent',
      modelName: 'grok-4.20-multi-agent',
      thinkingLevel: GeminiThinkingLevel.low,
      supportedThinkingLevels: [
        GeminiThinkingLevel.low,
        GeminiThinkingLevel.medium,
        GeminiThinkingLevel.high,
      ],
      description:
          'xAI Grok model. Polishes text; needs another provider for speech.',
    ),
    GeminiModelConfig(
      id: 'grok-code-fast-1',
      name: 'Grok Code Fast 1',
      modelName: 'grok-code-fast-1',
      description:
          'xAI Grok model. Polishes text; needs another provider for speech.',
    ),
  ];

  /// Models available to the given [provider]. Gemini and Vertex share one
  /// catalog; OpenAI, Codex, and Grok have their own.
  static List<GeminiModelConfig> modelsForProvider(CloudProvider provider) {
    switch (provider) {
      case CloudProvider.geminiApiKey:
      case CloudProvider.vertexAi:
        return availableModels;
      case CloudProvider.openaiApiKey:
        return openAiModels;
      case CloudProvider.codexOAuth:
        return codexModels;
      case CloudProvider.grokOAuth:
        return grokModels;
    }
  }

  /// Providers allowed to receive raw audio for the first transcription pass
  /// (single-pass cloud dictation, or Pass 1 of two-pass). Local Whisper is
  /// the other allowed first pass. ChatGPT uses its dedicated `/transcribe`
  /// endpoint; OpenAI API-key and Grok providers remain polish-only.
  static const Set<CloudProvider> firstPassAudioProviders = {
    CloudProvider.geminiApiKey,
    CloudProvider.vertexAi,
    CloudProvider.codexOAuth,
  };

  /// Whether [provider] may serve the app's raw audio-to-text first pass.
  static bool canTranscribeAudio(CloudProvider provider) =>
      firstPassAudioProviders.contains(provider);

  /// Audio-capable models a provider may actually serve in this app, i.e.
  /// the raw audio-to-text first pass. Restricted to
  /// [firstPassAudioProviders]; refinement-only providers return an empty
  /// list even when their catalog contains speech models.
  static List<GeminiModelConfig> audioModelsForProvider(
    CloudProvider provider,
  ) {
    if (!canTranscribeAudio(provider)) return const [];
    return modelsForProvider(provider)
        .where(
          (m) =>
              m.supportsAudio &&
              !(provider == CloudProvider.vertexAi && m.isTranscriptionOnly),
        )
        .toList();
  }

  /// Strict request-time lookup. Preference resolution is deliberately separate.
  static GeminiModelConfig requireModelForProvider(
    CloudProvider provider,
    String id,
  ) => modelsForProvider(provider).firstWhere(
    (m) => m.id == id,
    orElse: () =>
        throw ArgumentError('Unknown model for ${provider.displayName}: $id'),
  );

  /// Prompt-capable (non-transcription-only) models for [provider].
  static List<GeminiModelConfig> promptCapableModelsForProvider(
    CloudProvider provider,
  ) {
    return modelsForProvider(
      provider,
    ).where((m) => !m.isTranscriptionOnly).toList();
  }

  /// Dedicated speech-to-text models [provider] can serve for the audio
  /// first pass.
  ///
  /// Vertex shares the Gemini catalog but cannot serve the dedicated
  /// Gemini transcription model. OpenAI keeps its speech models catalogued
  /// for future use but is not a first-pass provider in this app.
  static List<GeminiModelConfig> transcriptionModelsForProvider(
    CloudProvider provider,
  ) {
    switch (provider) {
      case CloudProvider.geminiApiKey:
        return transcriptionModels;
      case CloudProvider.vertexAi:
      case CloudProvider.openaiApiKey:
      case CloudProvider.grokOAuth:
        return const [];
      case CloudProvider.codexOAuth:
        return codexModels.where((model) => model.isTranscriptionOnly).toList();
    }
  }

  static String defaultModelIdForProvider(CloudProvider provider) {
    switch (provider) {
      case CloudProvider.geminiApiKey:
      case CloudProvider.vertexAi:
        return defaultModelId;
      case CloudProvider.openaiApiKey:
        return defaultOpenAiModelId;
      case CloudProvider.codexOAuth:
        return defaultCodexModelId;
      case CloudProvider.grokOAuth:
        return defaultGrokModelId;
    }
  }

  /// Resolves [id] inside [provider]'s catalog, falling back to the
  /// catalog's first entry (never a model the provider cannot serve).
  static GeminiModelConfig modelForProvider(CloudProvider provider, String id) {
    final models = modelsForProvider(provider);
    return models.firstWhere(
      (model) => model.id == id,
      orElse: () => models.first,
    );
  }

  static GeminiModelConfig getModelById(String id) {
    for (final models in const [
      availableModels,
      openAiModels,
      codexModels,
      grokModels,
    ]) {
      for (final model in models) {
        if (model.id == id) return model;
      }
    }
    return availableModels.first;
  }

  /// Whether [id] is still offered in ANY provider catalog.
  ///
  /// Pure + testable; used by [SettingsService]'s model migration to detect
  /// stale overrides. Spans every catalog on purpose: a stored id from a
  /// provider that is not currently active is a valid preference and must
  /// survive migration rather than being rewritten to the Gemini default.
  static bool isOfferedModelId(String? id) {
    if (id == null) return false;
    for (final models in const [
      availableModels,
      openAiModels,
      codexModels,
      grokModels,
    ]) {
      if (models.any((model) => model.id == id)) return true;
    }
    return false;
  }

  /// Models that can follow writing-style prompts and perform refinement.
  static List<GeminiModelConfig> get mainModels =>
      availableModels.where((m) => !m.isTranscriptionOnly).toList();

  /// Dedicated speech-to-text models such as `gemini-3.5-transcribe`.
  static List<GeminiModelConfig> get transcriptionModels =>
      availableModels.where((m) => m.isTranscriptionOnly).toList();

  /// OpenAI-compatible models that can follow prompts (refinement step and
  /// the polish half of a chained single pass).
  static List<GeminiModelConfig> get openAiPromptModels =>
      openAiModels.where((m) => !m.isTranscriptionOnly).toList();

  static String resolveModelId(String? savedId) {
    if (savedId != null && isOfferedModelId(savedId)) return savedId;
    return defaultModelId;
  }

  /// Returns a model id that can follow prompts. Transcription-only or
  /// retired ids fall back to [defaultModelId].
  static String resolveRefinementModelId(String? savedId) {
    if (savedId != null && mainModels.any((model) => model.id == savedId)) {
      return savedId;
    }
    return defaultModelId;
  }

  static Future<void> initialize() async {
    // `.env` is a development-only convenience. Do not read dotenv files in
    // release builds so packaged apps cannot accidentally prefer bundled or
    // adjacent plaintext secrets over OS secure storage. In particular,
    // `.env.example` is documentation only and is never treated as config.
    if (kReleaseMode) {
      dotenv.loadFromString(envString: '', isOptional: true);
      return;
    }

    if (await _loadDotEnvFile('.env')) return;

    dotenv.loadFromString(envString: '', isOptional: true);
  }

  static Future<bool> _loadDotEnvFile(String fileName) async {
    try {
      final file = File(fileName);
      if (!await file.exists()) return false;
      final contents = await file.readAsString();
      dotenv.loadFromString(envString: contents, isOptional: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  static const String defaultModelId = 'gemini-3.5-flash-lite';

  /// Cloud model used for the raw transcription step of two-step refinement.
  static const String defaultTranscriptionModelId = 'gemini-3.5-transcribe';

  /// Default prompt-capable OpenAI model (refinement + chained single pass).
  static const String defaultOpenAiModelId = 'gpt-5.4-mini';

  /// OpenAI speech model used by `/audio/transcriptions`. Retained for
  /// client-level endpoint support; OpenAI is not selectable as the app's
  /// audio first pass (see [firstPassAudioProviders]).
  static const String defaultOpenAiTranscriptionModelId = 'gpt-transcribe';

  /// Default Codex model for prompt-capable polish.
  static const String defaultCodexModelId = 'gpt-5.6-terra';

  /// Base URL for the standard OpenAI API; overridable for compatible
  /// endpoints via Settings (`openai_base_url` / `OPENAI_BASE_URL`).
  static const String openAiDefaultBaseUrl = 'https://api.openai.com/v1';

  /// Codex Responses backend root; `/responses` is appended per request.
  static const String codexDefaultBaseUrl =
      'https://chatgpt.com/backend-api/codex';

  /// ChatGPT-account transcription endpoint used by Codex OAuth.
  static const String codexTranscribeUrl =
      'https://chatgpt.com/backend-api/transcribe';

  /// Default Grok model (refinement only — Grok models cannot transcribe).
  static const String defaultGrokModelId = 'grok-4.3';

  /// xAI API root; `/responses` is appended per request.
  static const String xAiDefaultBaseUrl = 'https://api.x.ai/v1';
  static const String defaultHotkey = 'ctrl+shift+v';
  static const String appName = 'Beeamvo';
  static const String audioFormat = 'wav';
}
