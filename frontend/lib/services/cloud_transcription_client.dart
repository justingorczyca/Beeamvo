import 'dart:typed_data';

import '../config.dart';
import 'settings_service.dart';

class CloudTranscriptionException implements Exception {
  final String message;

  CloudTranscriptionException(this.message);

  @override
  String toString() => message;
}

abstract class CloudTranscriptionClient {
  void attachSettings(SettingsService settings);
  Future<void> initialize();
  Future<void> verifySetup();
  void setModel(GeminiModelConfig model);
  void setModelById(String modelId);
  void dispose();
  GeminiModelConfig get currentModel;
  bool get isInitialized;

  Future<String> improveTranscription(
    String rawText, {
    String? missionInstruction,
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
  });

  Future<String> transcribeAndImprove(
    Uint8List audioData,
    String mimeType, {
    String? missionInstruction,
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
  });

  Future<String> transcribeAudio(
    Uint8List audioData,
    String mimeType, {
    String? modelOverrideId,
  });
}
