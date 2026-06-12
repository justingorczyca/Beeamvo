import 'dart:typed_data';

import '../config.dart';
import 'cloud_transcription_client.dart';
import 'gemini_api_service.dart';
import 'settings_service.dart';
import 'transcription_result_guard.dart';
import 'vertex_ai_service.dart';

class CloudTranscriptionService {
  CloudTranscriptionService({
    CloudTranscriptionClient? geminiApiService,
    CloudTranscriptionClient? vertexAiService,
  }) : _geminiApiService = geminiApiService ?? GeminiApiService(),
       _vertexAiService = vertexAiService ?? VertexAiService();

  final CloudTranscriptionClient _geminiApiService;
  final CloudTranscriptionClient _vertexAiService;
  SettingsService? _settingsService;
  CloudProvider? _providerOverride;

  void attachSettings(SettingsService settings) {
    _settingsService = settings;
    _geminiApiService.attachSettings(settings);
    _vertexAiService.attachSettings(settings);
    setModelById(settings.selectedModelId);
  }

  Future<void> initialize() async {
    await _initializeIfNeeded(_clientFor(currentProvider));
  }

  CloudProvider get currentProvider =>
      _providerOverride ??
      _settingsService?.cloudProvider ??
      CloudProvider.geminiApiKey;

  void setProviderOverride(CloudProvider provider) {
    _providerOverride = provider;
  }

  void clearProviderOverride() {
    _providerOverride = null;
  }

  CloudTranscriptionClient _clientFor(CloudProvider provider) {
    switch (provider) {
      case CloudProvider.geminiApiKey:
        return _geminiApiService;
      case CloudProvider.vertexAi:
        return _vertexAiService;
    }
  }

  CloudTranscriptionClient get _currentClient => _clientFor(currentProvider);

  Future<void> _initializeIfNeeded(CloudTranscriptionClient client) async {
    if (!client.isInitialized) {
      await client.initialize();
    }
  }

  GeminiModelConfig get currentModel => _currentClient.currentModel;

  void setModelById(String modelId) {
    _geminiApiService.setModelById(modelId);
    _vertexAiService.setModelById(modelId);
  }

  Future<void> verifyProvider(CloudProvider provider) async {
    final client = _clientFor(provider);
    await _initializeIfNeeded(client);
    await client.verifySetup();
  }

  Future<String> improveTranscription(
    String rawText, {
    String? missionInstruction,
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) async {
    final client = _currentClient;
    await _initializeIfNeeded(client);
    return client.improveTranscription(
      rawText,
      missionInstruction: missionInstruction,
      modelOverrideId: modelOverrideId,
      thinkingLevelOverride: thinkingLevelOverride,
    );
  }

  Future<String> transcribeAndImprove(
    Uint8List audioData,
    String mimeType, {
    String? missionInstruction,
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) async {
    final client = _currentClient;
    await _initializeIfNeeded(client);
    final result = await client.transcribeAndImprove(
      audioData,
      mimeType,
      missionInstruction: missionInstruction,
      modelOverrideId: modelOverrideId,
      thinkingLevelOverride: thinkingLevelOverride,
    );
    return TranscriptionResultGuard.requireTranscript(result);
  }

  Future<String> transcribeAudio(
    Uint8List audioData,
    String mimeType, {
    String? modelOverrideId,
  }) async {
    final client = _currentClient;
    await _initializeIfNeeded(client);
    final result = await client.transcribeAudio(
      audioData,
      mimeType,
      modelOverrideId: modelOverrideId,
    );
    return TranscriptionResultGuard.requireTranscript(result);
  }
}
