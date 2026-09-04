/// App configuration for Beeamvo.
library;

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Thinking level for Gemini 3+ models.
enum GeminiThinkingLevel { minimal, low, medium, high }

extension GeminiThinkingLevelExtension on GeminiThinkingLevel {
  String get apiValue {
    switch (this) {
      case GeminiThinkingLevel.minimal:
        return 'MINIMAL';
      case GeminiThinkingLevel.low:
        return 'LOW';
      case GeminiThinkingLevel.medium:
        return 'MEDIUM';
      case GeminiThinkingLevel.high:
        return 'HIGH';
    }
  }

  String get displayLabel {
    switch (this) {
      case GeminiThinkingLevel.minimal:
        return 'Minimal';
      case GeminiThinkingLevel.low:
        return 'Low';
      case GeminiThinkingLevel.medium:
        return 'Medium';
      case GeminiThinkingLevel.high:
        return 'High';
    }
  }

  String get description {
    switch (this) {
      case GeminiThinkingLevel.minimal:
        return 'Fastest, lowest cost, best for simple tasks';
      case GeminiThinkingLevel.low:
        return 'Balanced, light reasoning, great default';
      case GeminiThinkingLevel.medium:
        return 'Deeper reasoning, better accuracy, slightly slower';
      case GeminiThinkingLevel.high:
        return 'Highest quality, strongest reasoning, highest token cost';
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

/// Represents a Gemini model shared across the direct API and Vertex flows.
class GeminiModelConfig {
  final String id;
  final String name;
  final String modelName;

  /// Vertex AI location. Preview models use `global`.
  final String vertexLocation;

  final bool isPreview;

  /// For Gemini 2.x models.
  final int? thinkingBudget;

  /// For Gemini 3+ models.
  final GeminiThinkingLevel? thinkingLevel;

  final List<GeminiThinkingLevel> supportedThinkingLevels;

  /// True when this model is a dedicated speech-to-text model. It can be used
  /// for any raw audio-to-text pass (single-pass or Pass 1 of two-pass), but
  /// it cannot follow mission prompts, so it is excluded from refinement and
  /// transcribe-and-improve paths.
  final bool isTranscriptionOnly;

  const GeminiModelConfig({
    required this.id,
    required this.name,
    required this.modelName,
    this.vertexLocation = 'global',
    this.isPreview = false,
    this.thinkingBudget,
    this.thinkingLevel,
    this.supportedThinkingLevels = const [],
    this.isTranscriptionOnly = false,
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
      vertexLocation: 'global',
      thinkingLevel: GeminiThinkingLevel.medium,
      supportedThinkingLevels: [
        GeminiThinkingLevel.low,
        GeminiThinkingLevel.medium,
        GeminiThinkingLevel.high,
      ],
    ),
    GeminiModelConfig(
      id: 'gemini-3.6-flash',
      name: 'Gemini 3.6 Flash',
      modelName: 'gemini-3.6-flash',
      vertexLocation: 'global',
      thinkingLevel: GeminiThinkingLevel.medium,
      supportedThinkingLevels: [
        GeminiThinkingLevel.minimal,
        GeminiThinkingLevel.low,
        GeminiThinkingLevel.medium,
        GeminiThinkingLevel.high,
      ],
    ),
    GeminiModelConfig(
      id: 'gemini-3.5-flash',
      name: 'Gemini 3.5 Flash',
      modelName: 'gemini-3.5-flash',
      vertexLocation: 'global',
      thinkingLevel: GeminiThinkingLevel.medium,
      supportedThinkingLevels: [
        GeminiThinkingLevel.minimal,
        GeminiThinkingLevel.low,
        GeminiThinkingLevel.medium,
        GeminiThinkingLevel.high,
      ],
    ),
    GeminiModelConfig(
      id: 'gemini-3.5-flash-lite',
      name: 'Gemini 3.5 Flash Lite',
      modelName: 'gemini-3.5-flash-lite',
      vertexLocation: 'global',
      thinkingLevel: GeminiThinkingLevel.minimal,
      supportedThinkingLevels: [
        GeminiThinkingLevel.minimal,
        GeminiThinkingLevel.low,
        GeminiThinkingLevel.medium,
        GeminiThinkingLevel.high,
      ],
    ),
    GeminiModelConfig(
      id: 'gemini-3-flash',
      name: 'Gemini 3 Flash',
      modelName: 'gemini-3-flash-preview',
      vertexLocation: 'global',
      isPreview: true,
      thinkingLevel: GeminiThinkingLevel.high,
      supportedThinkingLevels: [
        GeminiThinkingLevel.minimal,
        GeminiThinkingLevel.low,
        GeminiThinkingLevel.medium,
        GeminiThinkingLevel.high,
      ],
    ),
    GeminiModelConfig(
      id: 'gemini-3.5-transcribe',
      name: 'Gemini 3.5 Transcribe',
      modelName: 'gemini-3.5-transcribe',
      vertexLocation: 'global',
      isPreview: true,
      isTranscriptionOnly: true,
    ),
  ];

  static GeminiModelConfig getModelById(String id) {
    return availableModels.firstWhere(
      (model) => model.id == id,
      orElse: () => availableModels.first,
    );
  }

  /// Whether [id] is still offered in [availableModels].
  ///
  /// Pure + testable; used by [SettingsService]'s model migration to detect
  /// stale overrides (e.g. a two-pass model id left over from a retired model).
  static bool isOfferedModelId(String? id) {
    if (id == null) return false;
    return availableModels.any((model) => model.id == id);
  }

  /// Models that can follow prompts: the only choices for the primary model.
  static List<GeminiModelConfig> get mainModels =>
      availableModels.where((m) => !m.isTranscriptionOnly).toList();

  /// Dedicated speech-to-text models such as `gemini-3.5-transcribe`.
  static List<GeminiModelConfig> get transcriptionModels =>
      availableModels.where((m) => m.isTranscriptionOnly).toList();

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
  static const String defaultHotkey = 'ctrl+shift+v';
  static const String appName = 'Beeamvo';
  static const String audioFormat = 'wav';
}
