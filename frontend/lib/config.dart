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

  const GeminiModelConfig({
    required this.id,
    required this.name,
    required this.modelName,
    this.vertexLocation = 'global',
    this.isPreview = false,
    this.thinkingBudget,
    this.thinkingLevel,
    this.supportedThinkingLevels = const [],
  });

  bool get hasSelectableThinkingLevel => supportedThinkingLevels.isNotEmpty;

  String get displayName => isPreview ? '$name (Preview)' : name;

  Map<String, dynamic>? thinkingConfigWithLevel([
    GeminiThinkingLevel? levelOverride,
  ]) {
    if (thinkingLevel != null) {
      final effective = levelOverride ?? thinkingLevel!;
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
      id: 'gemini-2.5-flash',
      name: 'Gemini 2.5 Flash',
      modelName: 'gemini-2.5-flash',
      vertexLocation: 'global',
      thinkingBudget: 0,
    ),
    GeminiModelConfig(
      id: 'gemini-2.5-flash-lite',
      name: 'Gemini 2.5 Flash Lite',
      modelName: 'gemini-2.5-flash-lite',
      vertexLocation: 'global',
      thinkingBudget: 0,
    ),
    GeminiModelConfig(
      id: 'gemini-3-flash',
      name: 'Gemini 3 Flash',
      modelName: 'gemini-3-flash-preview',
      vertexLocation: 'global',
      isPreview: true,
      thinkingLevel: GeminiThinkingLevel.minimal,
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
      thinkingLevel: GeminiThinkingLevel.minimal,
      supportedThinkingLevels: [
        GeminiThinkingLevel.minimal,
        GeminiThinkingLevel.low,
        GeminiThinkingLevel.medium,
        GeminiThinkingLevel.high,
      ],
    ),
    GeminiModelConfig(
      id: 'gemini-3.1-flash-lite',
      name: 'Gemini 3.1 Flash Lite',
      modelName: 'gemini-3.1-flash-lite',
      vertexLocation: 'global',
      thinkingLevel: GeminiThinkingLevel.minimal,
      supportedThinkingLevels: [
        GeminiThinkingLevel.minimal,
        GeminiThinkingLevel.low,
        GeminiThinkingLevel.medium,
        GeminiThinkingLevel.high,
      ],
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

  /// Returns the model id that should be persisted on disk for [savedId]:
  /// - `null` (never set) or an id no longer in [availableModels] → [defaultModelId]
  /// - any currently-offered id → [savedId]
  ///
  /// Pure + testable; used by [SettingsService]'s model migration so the
  /// `selected_model_id` key is always explicitly and validly populated.
  static String resolveModelId(String? savedId) {
    if (isOfferedModelId(savedId)) return savedId!;
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

  static const String defaultModelId = 'gemini-3.1-flash-lite';
  static const String defaultHotkey = 'ctrl+shift+v';
  static const String appName = 'Beeamvo';
  static const String audioFormat = 'wav';
}
