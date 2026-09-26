import 'package:flutter/foundation.dart';

import '../config.dart';
import 'cloud_transcription_client.dart';
import 'codex_service.dart';
import 'gemini_interactions_service.dart';
import 'grok_service.dart';
import 'openai_compatible_service.dart';
import 'settings_service.dart';
import 'transcription_result_guard.dart';
import 'vertex_ai_service.dart';

class CloudTranscriptionService {
  CloudTranscriptionService({
    CloudTranscriptionClient? geminiInteractionsService,
    CloudTranscriptionClient? vertexAiService,
    CloudTranscriptionClient? openAiService,
    CloudTranscriptionClient? codexService,
    CloudTranscriptionClient? grokService,
  }) : _geminiInteractionsService =
           geminiInteractionsService ?? GeminiInteractionsService(),
       _vertexAiService = vertexAiService ?? VertexAiService(),
       _openAiService = openAiService ?? OpenAiCompatibleService(),
       _codexService = codexService ?? CodexService(),
       _grokService = grokService ?? GrokService();

  final CloudTranscriptionClient _geminiInteractionsService;
  final CloudTranscriptionClient _vertexAiService;
  final CloudTranscriptionClient _openAiService;
  final CloudTranscriptionClient _codexService;
  final CloudTranscriptionClient _grokService;
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
    _openAiService.attachSettings(settings);
    _codexService.attachSettings(settings);
    _grokService.attachSettings(settings);
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

  /// Releases all provider clients, including the Gemini HTTP client and any
  /// cached Vertex ADC client. This is idempotent so app shutdown paths may call
  /// it safely more than once.
  void dispose() {
    if (_isDisposed) return;
    _isDisposed = true;
    _settingsService?.removeListener(_syncModelFromSettings);
    _geminiInteractionsService.dispose();
    _vertexAiService.dispose();
    _openAiService.dispose();
    _codexService.dispose();
    _grokService.dispose();
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
      case CloudProvider.openaiApiKey:
        return _openAiService;
      case CloudProvider.codexOAuth:
        return _codexService;
      case CloudProvider.grokOAuth:
        return _grokService;
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
    AppConfig.requireModelForProvider(currentProvider, modelId);
    _currentClient.setModelById(modelId);
  }

  Future<void> verifyProvider(CloudProvider provider) async {
    _ensureNotDisposed();
    final client = _clientFor(provider);
    await _initializeIfNeeded(client);
    await client.verifySetup();
  }

  GeminiModelConfig _requestModel(
    CloudProvider provider,
    String? id, {
    bool audio = false,
  }) {
    final model = AppConfig.requireModelForProvider(
      provider,
      id ?? _clientFor(provider).currentModel.id,
    );
    if (audio &&
        !AppConfig.audioModelsForProvider(
          provider,
        ).any((m) => m.id == model.id)) {
      throw CloudTranscriptionException(
        'This model cannot receive audio. Enable two-step refinement and choose an audio provider.',
      );
    }
    return model;
  }

  /// Verifies every cloud stage the active pipeline uses: the first-pass
  /// provider (cloud backend) and, with two-step refinement, the pass-2
  /// provider. Each client is verified against the model it will serve.
  Future<void> verifyTranscriptionSetup(SettingsService settings) async {
    _ensureNotDisposed();
    if (!settings.isTranscriptionReady) {
      throw CloudTranscriptionException(
        'Configure both stage models and credentials first.',
      );
    }
    final stages = <(CloudProvider, String)>[
      if (settings.transcriptionBackend == TranscriptionBackend.cloud)
        (settings.cloudProvider, settings.selectedModelId),
      if (settings.twoPassTranscriptionEnabled)
        (settings.refinementProvider, settings.twoPassRefinementModelId),
    ];
    for (final (provider, modelId) in stages) {
      final client = _clientFor(provider);
      final previous = client.currentModel.id;
      client.setModelById(modelId);
      try {
        await verifyProvider(provider);
      } finally {
        client.setModelById(previous);
      }
    }
  }

  GeminiModelConfig _assertPromptCapable(
    String? modelOverrideId, [
    CloudProvider? provider,
  ]) {
    final model = _requestModel(provider ?? currentProvider, modelOverrideId);
    if (model.isTranscriptionOnly) {
      throw CloudTranscriptionException(
        '${model.displayName} only transcribes and cannot apply a writing '
        'style. Choose a different AI model.',
      );
    }
    return model;
  }

  /// Pass-2 role captured from [settings]: provider, model, and the polish
  /// thinking level, resolved explicitly so clients never fall back to the
  /// first-pass level of the same model.
  ({CloudProvider provider, String modelId, GeminiThinkingLevel? thinking})
  _refinementStage(SettingsService settings) {
    final provider = settings.refinementProvider;
    final modelId = settings.twoPassRefinementModelId;
    final model = _assertPromptCapable(modelId, provider);
    return (
      provider: provider,
      modelId: modelId,
      thinking: model.resolveThinkingLevel(
        levelOverride: settings.getRefinementThinkingLevel(modelId),
      ),
    );
  }

  Future<String> _refine(
    String rawText,
    ({CloudProvider provider, String modelId, GeminiThinkingLevel? thinking})
    stage, {
    String? missionInstruction,
  }) {
    rawText = TranscriptionResultGuard.requireTranscript(rawText);
    final client = _clientFor(stage.provider);
    return _runTranscription(
      'refine',
      client,
      () => client.improveTranscription(
        rawText,
        missionInstruction: missionInstruction,
        modelOverrideId: stage.modelId,
        thinkingLevelOverride: stage.thinking,
      ),
      modelOverrideId: stage.modelId,
      thinkingLevelOverride: stage.thinking,
      providerOverride: stage.provider,
    );
  }

  /// Pass 2 alone, for transcripts produced locally (offline Whisper): the
  /// refinement provider, model and thinking level from [settings].
  Future<String> refineTranscript(
    String rawText, {
    required SettingsService settings,
    String? missionInstruction,
  }) async {
    _ensureNotDisposed();
    return _refine(
      rawText,
      _refinementStage(settings),
      missionInstruction: missionInstruction,
    );
  }

  Future<String> transcribeSinglePass(
    Uint8List audioData,
    String mimeType, {
    String? missionInstruction,
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) async {
    _ensureNotDisposed();
    final model = _requestModel(currentProvider, modelOverrideId, audio: true);
    if (model.isTranscriptionOnly) {
      return transcribeAudio(audioData, mimeType, modelOverrideId: model.id);
    }
    return transcribeAndImprove(
      audioData,
      mimeType,
      missionInstruction: missionInstruction,
      modelOverrideId: model.id,
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
    _ensureNotDisposed();
    _assertPromptCapable(modelOverrideId);
    _requestModel(currentProvider, modelOverrideId, audio: true);
    final client = _currentClient;
    return _runTranscription(
      'transcribe-and-refine',
      client,
      () => client.transcribeAndImprove(
        audioData,
        mimeType,
        missionInstruction: missionInstruction,
        modelOverrideId: modelOverrideId,
        thinkingLevelOverride: thinkingLevelOverride,
      ),
      modelOverrideId: modelOverrideId,
      thinkingLevelOverride: thinkingLevelOverride,
      audioBytes: audioData.length,
    );
  }

  Future<String> transcribeAudio(
    Uint8List audioData,
    String mimeType, {
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
    CloudProvider? providerOverride,
  }) async {
    _ensureNotDisposed();
    final provider = providerOverride ?? currentProvider;
    final client = _clientFor(provider);
    _requestModel(provider, modelOverrideId, audio: true);
    return _runTranscription(
      'transcribe',
      client,
      () => client.transcribeAudio(
        audioData,
        mimeType,
        modelOverrideId: modelOverrideId,
        thinkingLevelOverride: thinkingLevelOverride,
      ),
      modelOverrideId: modelOverrideId,
      thinkingLevelOverride: thinkingLevelOverride,
      audioBytes: audioData.length,
      providerOverride: provider,
    );
  }

  /// Shared desktop/mobile pipeline. Both roles are captured before any await;
  /// an invalid/empty first transcript never reaches the refinement provider.
  /// Pass 1 is always the Gemini-family [SettingsService.cloudProvider]; pass
  /// 2 may be any provider and only ever receives transcript text.
  Future<String> transcribeTwoPass(
    Uint8List audioData,
    String mimeType, {
    required SettingsService settings,
    String? missionInstruction,
  }) async {
    _ensureNotDisposed();
    final firstProvider = settings.cloudProvider;
    final firstModel = settings.selectedModelId;
    final firstThinking = settings.getThinkingLevelForModel(firstModel);
    _requestModel(firstProvider, firstModel, audio: true);
    final refinement = _refinementStage(settings);
    final raw = await transcribeAudio(
      audioData,
      mimeType,
      modelOverrideId: firstModel,
      thinkingLevelOverride: firstThinking,
      providerOverride: firstProvider,
    );
    return _refine(raw, refinement, missionInstruction: missionInstruction);
  }

  Future<String> _runTranscription(
    String stage,
    CloudTranscriptionClient client,
    Future<String> Function() generate, {
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
    int? audioBytes,
    CloudProvider? providerOverride,
  }) async {
    final watch = Stopwatch()..start();
    final providerValue = providerOverride ?? currentProvider;
    final provider = providerValue.name;
    final model = modelOverrideId == null
        ? client.currentModel
        : AppConfig.getModelById(modelOverrideId);
    if (kDebugMode) {
      final level =
          model.resolveThinkingLevel(
            levelOverride:
                thinkingLevelOverride ??
                _settingsService?.getThinkingLevelForModel(model.id),
            forceMinimal:
                stage == 'transcribe' && thinkingLevelOverride == null,
          ) ??
          (providerValue == CloudProvider.geminiApiKey
              ? model.interactionsThinkingLevel
              : null);
      debugPrint(
        '[CloudTranscription] stage=$stage provider=$provider '
        'model=${model.id} thinking=${level?.name ?? 'none'} '
        'audioBytes=${audioBytes ?? 0}',
      );
    }
    var completed = false;
    try {
      await _initializeIfNeeded(client);
      final result = TranscriptionResultGuard.requireTranscript(
        await generate(),
      );
      completed = true;
      return result;
    } finally {
      if (kDebugMode) {
        debugPrint(
          '[CloudTranscription] stage=$stage provider=$provider '
          'completed=$completed elapsed=${watch.elapsedMilliseconds}ms',
        );
      }
    }
  }
}
