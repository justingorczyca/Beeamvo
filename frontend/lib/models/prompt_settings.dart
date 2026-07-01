import '../config.dart' show GeminiThinkingLevel, GeminiThinkingLevelExtension;
import 'system_prompt.dart' show RephraseLevel;

/// Per-prompt setting overrides. Every field is nullable — `null` means
/// "use the global default". Non-null values override the corresponding
/// setting for the duration of a single transcription session.
class PromptSettings {
  final String? modelId;
  final String? transcriptionBackend; // TranscriptionBackend.*.name
  final String? cloudProvider; // CloudProvider.*.name
  final String? whisperModelId;
  final String? whisperLanguage;
  final bool? twoPassTranscriptionEnabled;
  final String? twoPassTranscriptionModelId;
  final String? twoPassRefinementModelId;
  final RephraseLevel? rephraseLevel;
  final GeminiThinkingLevel? thinkingLevel;
  final GeminiThinkingLevel? twoPassRefinementThinkingLevel;

  const PromptSettings({
    this.modelId,
    this.transcriptionBackend,
    this.cloudProvider,
    this.whisperModelId,
    this.whisperLanguage,
    this.twoPassTranscriptionEnabled,
    this.twoPassTranscriptionModelId,
    this.twoPassRefinementModelId,
    this.rephraseLevel,
    this.thinkingLevel,
    this.twoPassRefinementThinkingLevel,
  });

  bool get hasAnyOverride =>
      modelId != null ||
      transcriptionBackend != null ||
      cloudProvider != null ||
      whisperModelId != null ||
      whisperLanguage != null ||
      twoPassTranscriptionEnabled != null ||
      twoPassTranscriptionModelId != null ||
      twoPassRefinementModelId != null ||
      rephraseLevel != null ||
      thinkingLevel != null ||
      twoPassRefinementThinkingLevel != null;

  int get overrideCount {
    var count = 0;
    if (modelId != null) count++;
    if (transcriptionBackend != null) count++;
    if (cloudProvider != null) count++;
    if (whisperModelId != null) count++;
    if (whisperLanguage != null) count++;
    if (twoPassTranscriptionEnabled != null) count++;
    if (twoPassTranscriptionModelId != null) count++;
    if (twoPassRefinementModelId != null) count++;
    if (rephraseLevel != null) count++;
    if (thinkingLevel != null) count++;
    if (twoPassRefinementThinkingLevel != null) count++;
    return count;
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{};
    if (modelId != null) map['modelId'] = modelId;
    if (transcriptionBackend != null) {
      map['transcriptionBackend'] = transcriptionBackend;
    }
    if (cloudProvider != null) map['cloudProvider'] = cloudProvider;
    if (whisperModelId != null) map['whisperModelId'] = whisperModelId;
    if (whisperLanguage != null) map['whisperLanguage'] = whisperLanguage;
    if (twoPassTranscriptionEnabled != null) {
      map['twoPassTranscriptionEnabled'] = twoPassTranscriptionEnabled;
    }
    if (twoPassTranscriptionModelId != null) {
      map['twoPassTranscriptionModelId'] = twoPassTranscriptionModelId;
    }
    if (twoPassRefinementModelId != null) {
      map['twoPassRefinementModelId'] = twoPassRefinementModelId;
    }
    if (rephraseLevel != null) map['rephraseLevel'] = rephraseLevel!.name;
    if (thinkingLevel != null) map['thinkingLevel'] = thinkingLevel!.apiValue;
    if (twoPassRefinementThinkingLevel != null) {
      map['twoPassRefinementThinkingLevel'] =
          twoPassRefinementThinkingLevel!.apiValue;
    }
    return map;
  }

  factory PromptSettings.fromMap(Map<String, dynamic>? map) {
    if (map == null) return const PromptSettings();
    return PromptSettings(
      modelId: _asString(map, 'modelId'),
      transcriptionBackend: _asString(map, 'transcriptionBackend'),
      cloudProvider: _asString(map, 'cloudProvider'),
      whisperModelId: _asString(map, 'whisperModelId'),
      whisperLanguage: _asString(map, 'whisperLanguage'),
      twoPassTranscriptionEnabled: _asBool(map, 'twoPassTranscriptionEnabled'),
      twoPassTranscriptionModelId:
          _asString(map, 'twoPassTranscriptionModelId'),
      twoPassRefinementModelId: _asString(map, 'twoPassRefinementModelId'),
      rephraseLevel: _rephraseLevelFromString(_asString(map, 'rephraseLevel')),
      thinkingLevel: GeminiThinkingLevelExtension.fromString(
        _asString(map, 'thinkingLevel'),
      ),
      twoPassRefinementThinkingLevel: GeminiThinkingLevelExtension.fromString(
        _asString(map, 'twoPassRefinementThinkingLevel'),
      ),
    );
  }

  PromptSettings copyWith({
    String? Function()? modelId,
    String? Function()? transcriptionBackend,
    String? Function()? cloudProvider,
    String? Function()? whisperModelId,
    String? Function()? whisperLanguage,
    bool? Function()? twoPassTranscriptionEnabled,
    String? Function()? twoPassTranscriptionModelId,
    String? Function()? twoPassRefinementModelId,
    RephraseLevel? Function()? rephraseLevel,
    GeminiThinkingLevel? Function()? thinkingLevel,
    GeminiThinkingLevel? Function()? twoPassRefinementThinkingLevel,
  }) {
    return PromptSettings(
      modelId: modelId != null ? modelId() : this.modelId,
      transcriptionBackend: transcriptionBackend != null
          ? transcriptionBackend()
          : this.transcriptionBackend,
      cloudProvider: cloudProvider != null
          ? cloudProvider()
          : this.cloudProvider,
      whisperModelId: whisperModelId != null
          ? whisperModelId()
          : this.whisperModelId,
      whisperLanguage: whisperLanguage != null
          ? whisperLanguage()
          : this.whisperLanguage,
      twoPassTranscriptionEnabled: twoPassTranscriptionEnabled != null
          ? twoPassTranscriptionEnabled()
          : this.twoPassTranscriptionEnabled,
      twoPassTranscriptionModelId: twoPassTranscriptionModelId != null
          ? twoPassTranscriptionModelId()
          : this.twoPassTranscriptionModelId,
      twoPassRefinementModelId: twoPassRefinementModelId != null
          ? twoPassRefinementModelId()
          : this.twoPassRefinementModelId,
      rephraseLevel: rephraseLevel != null
          ? rephraseLevel()
          : this.rephraseLevel,
      thinkingLevel: thinkingLevel != null
          ? thinkingLevel()
          : this.thinkingLevel,
      twoPassRefinementThinkingLevel: twoPassRefinementThinkingLevel != null
          ? twoPassRefinementThinkingLevel()
          : this.twoPassRefinementThinkingLevel,
    );
  }
}

/// Best-effort string accessor that tolerates mistyped JSON values
/// (returns null instead of throwing _TypeError).
String? _asString(Map<String, dynamic> map, String key) {
  final v = map[key];
  return v is String ? v : null;
}

/// Best-effort bool accessor that tolerates mistyped JSON values.
bool? _asBool(Map<String, dynamic> map, String key) {
  final v = map[key];
  return v is bool ? v : null;
}

RephraseLevel? _rephraseLevelFromString(String? value) {
  if (value == null) return null;
  for (final level in RephraseLevel.values) {
    if (level.name == value) return level;
  }
  return null;
}
