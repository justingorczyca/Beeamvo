import 'dart:typed_data';

import '../config.dart';
import 'cloud_transcription_client.dart';
import 'gemini_interactions_service.dart';
import 'settings_service.dart';
import 'transcription_result_guard.dart';
import 'vertex_ai_service.dart';

class CloudTranscriptionService {
  CloudTranscriptionService({
    CloudTranscriptionClient? geminiInteractionsService,
    CloudTranscriptionClient? vertexAiService,
  }) : _geminiInteractionsService =
           geminiInteractionsService ?? GeminiInteractionsService(),
       _vertexAiService = vertexAiService ?? VertexAiService();

  final CloudTranscriptionClient _geminiInteractionsService;
  final CloudTranscriptionClient _vertexAiService;
  SettingsService? _settingsService;
  bool _isDisposed = false;

  /// Binds to [settings] and keeps the active model in sync with
  /// [SettingsService.selectedModelId] for as long as the service lives.
  void attachSettings(SettingsService settings) {
    _settingsService?.removeListener(_syncModelFromSettings);
    _settingsService = settings;
    settings.addListener(_syncModelFromSettings);
    _geminiInteractionsService.attachSettings(settings);
    _vertexAiService.attachSettings(settings);
    setModelById(settings.selectedModelId);
  }

  void _syncModelFromSettings() {
    final settings = _settingsService;
    if (settings == null || _isDisposed) return;
    final id = settings.selectedModelId;
    if (id != currentModel.id) setModelById(id);
  }

  Future<void> initialize() async {
    _ensureNotDisposed();
    await _initializeIfNeeded(_clientFor(currentProvider));
  }

  /// Releases both provider clients, including the Gemini HTTP client and any
  /// cached Vertex ADC client. This is idempotent so app shutdown paths may call
  /// it safely more than once.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _settingsService?.removeListener(_syncModelFromSettings);
    _geminiInteractionsService.dispose();
    _vertexAiService.dispose();
  }

  void _ensureNotDisposed() {
    if (_isDisposed) {
      throw StateError('CloudTranscriptionService has been disposed.');
    }
  }

  CloudProvider get currentProvider =>
      _settingsService?.cloudProvider ?? CloudProvider.geminiApiKey;

  CloudTranscriptionClient _clientFor(CloudProvider provider) {
    switch (provider) {
      case CloudProvider.geminiApiKey:
        return _geminiInteractionsService;
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
    _geminiInteractionsService.setModelById(modelId);
    _vertexAiService.setModelById(modelId);
  }

  Future<void> verifyProvider(CloudProvider provider) async {
    _ensureNotDisposed();
    final client = _clientFor(provider);
    await _initializeIfNeeded(client);
    await client.verifySetup();
  }

  void _assertPromptCapable(String? modelOverrideId) {
    final model = modelOverrideId != null
        ? AppConfig.getModelById(modelOverrideId)
        : currentModel;
    if (model.isTranscriptionOnly) {
      throw CloudTranscriptionException(
        '${model.displayName} only transcribes and cannot apply a writing '
        'style. Choose a different AI model.',
      );
    }
  }

  Future<String> improveTranscription(
    String rawText, {
    String? missionInstruction,
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) async {
    _ensureNotDisposed();
    _assertPromptCapable(modelOverrideId);
    final client = _currentClient;
    await _initializeIfNeeded(client);
    final result = await client.improveTranscription(
      rawText,
      missionInstruction: missionInstruction,
      modelOverrideId: modelOverrideId,
      thinkingLevelOverride: thinkingLevelOverride,
    );
    return TranscriptionResultGuard.requireTranscript(result);
  }

  Future<String> transcribeAndImprove(
    Uint8List audioData,
    String mimeType, {
    String? missionInstruction,
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) async {
    _ensureNotDisposed();
    _assertPromptCapable(modelOverrideId);
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
    _ensureNotDisposed();
    final client = _currentClient;
    final model = modelOverrideId != null
        ? AppConfig.getModelById(modelOverrideId)
        : currentModel;
    if (model.isTranscriptionOnly &&
        currentProvider != CloudProvider.geminiApiKey) {
      throw CloudTranscriptionException(
        '${model.displayName} is only available with a Gemini API key.',
      );
    }
    await _initializeIfNeeded(client);
    final result = await client.transcribeAudio(
      audioData,
      mimeType,
      modelOverrideId: modelOverrideId,
    );
    return TranscriptionResultGuard.requireTranscript(result);
  }
}
