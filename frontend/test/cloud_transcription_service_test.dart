import 'dart:typed_data';

import 'package:beeamvo/config.dart';
import 'package:beeamvo/services/cloud_transcription_client.dart';
import 'package:beeamvo/services/cloud_transcription_service.dart';
import 'package:beeamvo/services/secure_credential_store.dart';
import 'package:beeamvo/services/settings_service.dart';
import 'package:beeamvo/services/transcription_result_guard.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCloudClient implements CloudTranscriptionClient {
  FakeCloudClient({String? response})
    : _response = response ?? 'ok',
      _currentModel = AppConfig.getModelById(AppConfig.defaultModelId);

  final String _response;
  GeminiModelConfig _currentModel;
  bool _isInitialized = false;
  bool settingsAttached = false;
  int initializeCalls = 0;
  int verifyCalls = 0;
  int disposeCalls = 0;
  int improveCalls = 0;
  int transcribeCalls = 0;
  int transcribeAndImproveCalls = 0;
  final List<String> selectedModelIds = [];
  String? lastImproveModelOverrideId;
  GeminiThinkingLevel? lastImproveThinkingLevelOverride;
  String? lastTranscribeAndImproveModelOverrideId;
  GeminiThinkingLevel? lastTranscribeAndImproveThinkingLevelOverride;
  String? lastTranscribeModelOverrideId;
  GeminiThinkingLevel? lastTranscribeThinkingLevelOverride;

  @override
  void attachSettings(SettingsService settings) {
    settingsAttached = true;
  }

  @override
  GeminiModelConfig get currentModel => _currentModel;

  @override
  bool get isInitialized => _isInitialized;

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
    _isInitialized = true;
  }

  @override
  Future<void> verifySetup() async {
    verifyCalls += 1;
  }

  @override
  void setModel(GeminiModelConfig model) {
    _currentModel = model;
  }

  @override
  void setModelById(String modelId) {
    selectedModelIds.add(modelId);
    _currentModel = AppConfig.getModelById(modelId);
  }

  @override
  void dispose() {
    disposeCalls += 1;
  }

  @override
  Future<String> improveTranscription(
    String rawText, {
    String? missionInstruction,
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) async {
    improveCalls += 1;
    lastImproveModelOverrideId = modelOverrideId;
    lastImproveThinkingLevelOverride = thinkingLevelOverride;
    return _response;
  }

  @override
  Future<String> transcribeAndImprove(
    Uint8List audioData,
    String mimeType, {
    String? missionInstruction,
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) async {
    transcribeAndImproveCalls += 1;
    lastTranscribeAndImproveModelOverrideId = modelOverrideId;
    lastTranscribeAndImproveThinkingLevelOverride = thinkingLevelOverride;
    return _response;
  }

  @override
  Future<String> transcribeAudio(
    Uint8List audioData,
    String mimeType, {
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) async {
    transcribeCalls += 1;
    lastTranscribeModelOverrideId = modelOverrideId;
    lastTranscribeThinkingLevelOverride = thinkingLevelOverride;
    return _response;
  }
}

class FakeCloudSettingsService extends SettingsService {
  FakeCloudSettingsService({
    this.provider = CloudProvider.geminiApiKey,
    this.modelId = AppConfig.defaultModelId,
    this.refinement,
  }) : super(credentialStore: InMemorySecureCredentialStore());

  CloudProvider provider;
  String modelId;

  /// Pass-2 provider; `null` keeps the real default (the first-pass
  /// provider).
  CloudProvider? refinement;

  @override
  CloudProvider get cloudProvider => provider;

  @override
  String get selectedModelId => modelId;

  @override
  CloudProvider get refinementProvider =>
      refinement ?? super.refinementProvider;
}

void main() {
  group('CloudTranscriptionService', () {
    test(
      'initialization only touches the currently selected provider',
      () async {
        final geminiClient = FakeCloudClient();
        final vertexClient = FakeCloudClient();
        final settings = FakeCloudSettingsService(
          provider: CloudProvider.geminiApiKey,
          modelId: 'gemini-3-flash',
        );

        final service = CloudTranscriptionService(
          geminiInteractionsService: geminiClient,
          vertexAiService: vertexClient,
        );

        service.attachSettings(settings);
        await service.initialize();

        expect(geminiClient.initializeCalls, equals(1));
        expect(vertexClient.initializeCalls, equals(0));
        expect(geminiClient.selectedModelIds, contains('gemini-3-flash'));
        // Only the active provider's client is touched; dormant providers
        // receive their model lazily when a request targets them.
        expect(vertexClient.selectedModelIds, isEmpty);
      },
    );

    test('verifyProvider lazily initializes the requested provider', () async {
      final geminiClient = FakeCloudClient();
      final vertexClient = FakeCloudClient();
      final settings = FakeCloudSettingsService();

      final service = CloudTranscriptionService(
        geminiInteractionsService: geminiClient,
        vertexAiService: vertexClient,
      );

      service.attachSettings(settings);
      await service.verifyProvider(CloudProvider.vertexAi);

      expect(vertexClient.initializeCalls, equals(1));
      expect(vertexClient.verifyCalls, equals(1));
      expect(geminiClient.verifyCalls, equals(0));
    });

    test('runtime calls follow the active provider setting', () async {
      final geminiClient = FakeCloudClient(response: 'gemini');
      final vertexClient = FakeCloudClient(response: 'vertex');
      final settings = FakeCloudSettingsService(
        provider: CloudProvider.vertexAi,
      );

      final service = CloudTranscriptionService(
        geminiInteractionsService: geminiClient,
        vertexAiService: vertexClient,
      );

      service.attachSettings(settings);

      final vertexResult = await service.transcribeAndImprove(
        Uint8List.fromList([1, 2, 3]),
        'audio/wav',
      );
      expect(vertexResult, equals('vertex'));
      expect(vertexClient.transcribeAndImproveCalls, equals(1));
      expect(geminiClient.transcribeAndImproveCalls, equals(0));

      settings.provider = CloudProvider.geminiApiKey;

      final geminiResult = await service.refineTranscript(
        'raw text',
        settings: settings,
      );
      expect(geminiResult, equals('gemini'));
      expect(geminiClient.improveCalls, equals(1));
      expect(vertexClient.improveCalls, equals(0));
    });

    test('model follows later SettingsService changes', () async {
      final geminiClient = FakeCloudClient();
      final vertexClient = FakeCloudClient();
      final settings = FakeCloudSettingsService(modelId: 'gemini-3-flash');
      final service = CloudTranscriptionService(
        geminiInteractionsService: geminiClient,
        vertexAiService: vertexClient,
      );
      service.attachSettings(settings);
      expect(service.currentModel.id, equals('gemini-3-flash'));

      settings.modelId = 'gemini-3.6-flash';
      settings.notifyListeners();
      expect(service.currentModel.id, equals('gemini-3.6-flash'));
      expect(geminiClient.selectedModelIds.last, equals('gemini-3.6-flash'));
      // The inactive provider is still not synced.
      expect(vertexClient.selectedModelIds, isEmpty);

      service.dispose();
      settings.modelId = 'gemini-3-flash';
      settings.notifyListeners();
      expect(geminiClient.selectedModelIds.last, equals('gemini-3.6-flash'));
    });

    test('two-pass sends audio only to the first-pass provider', () async {
      final geminiClient = FakeCloudClient(response: 'raw transcript');
      final openAiClient = FakeCloudClient(response: 'polished transcript');
      final settings = FakeCloudSettingsService(
        modelId: 'gemini-3.5-transcribe',
        refinement: CloudProvider.openaiApiKey,
      );
      final service = CloudTranscriptionService(
        geminiInteractionsService: geminiClient,
        openAiService: openAiClient,
      );
      service.attachSettings(settings);

      final result = await service.transcribeTwoPass(
        Uint8List.fromList([1, 2, 3]),
        'audio/wav',
        settings: settings,
        missionInstruction: 'clean this up',
      );

      expect(result, equals('polished transcript'));
      expect(geminiClient.transcribeCalls, equals(1));
      expect(
        geminiClient.lastTranscribeModelOverrideId,
        'gemini-3.5-transcribe',
      );
      expect(geminiClient.transcribeAndImproveCalls, equals(0));
      expect(geminiClient.improveCalls, equals(0));
      expect(openAiClient.transcribeCalls, equals(0));
      expect(openAiClient.transcribeAndImproveCalls, equals(0));
      expect(openAiClient.improveCalls, equals(1));
      expect(openAiClient.lastImproveModelOverrideId, 'gpt-5.4-mini');
    });

    test(
      'an audio-capable main provider transcribes pass 1 itself and polishes '
      'with the refinement model',
      () async {
        final geminiClient = FakeCloudClient(response: 'raw transcript');
        final settings = FakeCloudSettingsService(
          provider: CloudProvider.geminiApiKey,
          modelId: 'gemini-3.5-transcribe',
        );
        final service = CloudTranscriptionService(
          geminiInteractionsService: geminiClient,
        );
        service.attachSettings(settings);
        await settings.setTwoPassRefinementModelId('gemini-3.7-flash');

        final result = await service.transcribeTwoPass(
          Uint8List.fromList([1, 2, 3]),
          'audio/wav',
          settings: settings,
          missionInstruction: 'clean this up',
        );

        // The single fake client answers both stages with its response.
        expect(result, equals('raw transcript'));
        // Pass 1 is exactly the single-pass transcription model.
        expect(geminiClient.transcribeCalls, equals(1));
        expect(
          geminiClient.lastTranscribeModelOverrideId,
          'gemini-3.5-transcribe',
        );
        // Pass 2 is the separately chosen refinement model.
        expect(geminiClient.improveCalls, equals(1));
        expect(geminiClient.lastImproveModelOverrideId, 'gemini-3.7-flash');
        expect(geminiClient.transcribeAndImproveCalls, equals(0));
      },
    );

    test('two-pass never refines an invalid first transcript', () async {
      final geminiClient = FakeCloudClient(response: '[NO_TRANSCRIPT]');
      final openAiClient = FakeCloudClient();
      final settings = FakeCloudSettingsService(
        modelId: 'gemini-3.5-transcribe',
        refinement: CloudProvider.openaiApiKey,
      );
      final service = CloudTranscriptionService(
        geminiInteractionsService: geminiClient,
        openAiService: openAiClient,
      );
      service.attachSettings(settings);

      await expectLater(
        service.transcribeTwoPass(
          Uint8List.fromList([1]),
          'audio/wav',
          settings: settings,
        ),
        throwsA(isA<CloudTranscriptionException>()),
      );
      expect(geminiClient.transcribeCalls, equals(1));
      expect(openAiClient.improveCalls, equals(0));
    });

    for (final provider in const [
      CloudProvider.openaiApiKey,
      CloudProvider.codexOAuth,
      CloudProvider.grokOAuth,
    ]) {
      test('${provider.name} polishes pass 2 from text only', () async {
        final geminiClient = FakeCloudClient(response: 'raw transcript');
        final textClient = FakeCloudClient(response: 'polished');
        final settings = FakeCloudSettingsService(refinement: provider);
        final service = CloudTranscriptionService(
          geminiInteractionsService: geminiClient,
          openAiService: provider == CloudProvider.openaiApiKey
              ? textClient
              : null,
          codexService: provider == CloudProvider.codexOAuth
              ? textClient
              : null,
          grokService: provider == CloudProvider.grokOAuth ? textClient : null,
        );
        addTearDown(service.dispose);
        service.attachSettings(settings);

        expect(
          await service.transcribeTwoPass(
            Uint8List.fromList([1]),
            'audio/wav',
            settings: settings,
          ),
          'polished',
        );
        expect(geminiClient.transcribeCalls, 1);
        expect(geminiClient.improveCalls, 0);
        expect(textClient.transcribeCalls, 0);
        expect(textClient.transcribeAndImproveCalls, 0);
        expect(textClient.improveCalls, 1);
        expect(
          textClient.lastImproveModelOverrideId,
          AppConfig.defaultModelIdForProvider(provider),
        );
      });
    }

    test('each pass sends its own thinking level for the same model', () async {
      final geminiClient = FakeCloudClient(response: 'text');
      final settings = FakeCloudSettingsService(modelId: 'gemini-3.7-flash');
      final service = CloudTranscriptionService(
        geminiInteractionsService: geminiClient,
      );
      addTearDown(service.dispose);
      service.attachSettings(settings);
      await settings.setTwoPassRefinementModelId('gemini-3.7-flash');
      await settings.setThinkingLevelForModel(
        'gemini-3.7-flash',
        GeminiThinkingLevel.high,
      );

      await service.transcribeTwoPass(
        Uint8List.fromList([1]),
        'audio/wav',
        settings: settings,
      );
      expect(
        geminiClient.lastTranscribeThinkingLevelOverride,
        GeminiThinkingLevel.high,
      );
      // The polish pass never inherits the first-pass level: unset means
      // the model default, sent explicitly.
      expect(
        geminiClient.lastImproveThinkingLevelOverride,
        GeminiThinkingLevel.low,
      );

      await settings.setRefinementThinkingLevel(
        'gemini-3.7-flash',
        GeminiThinkingLevel.medium,
      );
      await service.transcribeTwoPass(
        Uint8List.fromList([1]),
        'audio/wav',
        settings: settings,
      );
      expect(
        geminiClient.lastTranscribeThinkingLevelOverride,
        GeminiThinkingLevel.high,
      );
      expect(
        geminiClient.lastImproveThinkingLevelOverride,
        GeminiThinkingLevel.medium,
      );
    });

    test(
      'an unset first-pass level leaves pass 1 at the fastest default',
      () async {
        final geminiClient = FakeCloudClient(response: 'text');
        final settings = FakeCloudSettingsService(modelId: 'gemini-3.7-flash');
        final service = CloudTranscriptionService(
          geminiInteractionsService: geminiClient,
        );
        addTearDown(service.dispose);
        service.attachSettings(settings);
        await settings.setRefinementThinkingLevel(
          AppConfig.defaultModelId,
          GeminiThinkingLevel.high,
        );

        await service.transcribeTwoPass(
          Uint8List.fromList([1]),
          'audio/wav',
          settings: settings,
        );
        // Null lets the client force its lowest supported level.
        expect(geminiClient.lastTranscribeThinkingLevelOverride, isNull);
      },
    );

    test(
      'two-pass routes a pass-1 model override and keeps the stored polish',
      () async {
        final geminiClient = FakeCloudClient(response: 'raw transcript');
        final settings = FakeCloudSettingsService(
          modelId: AppConfig.defaultModelId,
        );
        final service = CloudTranscriptionService(
          geminiInteractionsService: geminiClient,
        );
        addTearDown(service.dispose);
        service.attachSettings(settings);
        await settings.setTwoPassRefinementModelId('gemini-3.7-flash');
        await settings.setThinkingLevelForModel(
          'gemini-3.6-flash',
          GeminiThinkingLevel.high,
        );

        final result = await service.transcribeTwoPass(
          Uint8List.fromList([1, 2, 3]),
          'audio/wav',
          settings: settings,
          pass1ModelOverrideId: 'gemini-3.6-flash',
        );

        expect(result, equals('raw transcript'));
        // Pass 1 uses the override id (and its own thinking level) instead of
        // the stored first-pass model.
        expect(geminiClient.transcribeCalls, equals(1));
        expect(geminiClient.lastTranscribeModelOverrideId, 'gemini-3.6-flash');
        expect(
          geminiClient.lastTranscribeThinkingLevelOverride,
          GeminiThinkingLevel.high,
        );
        // Pass 2 is untouched by the pass-1 override.
        expect(geminiClient.improveCalls, equals(1));
        expect(geminiClient.lastImproveModelOverrideId, 'gemini-3.7-flash');
      },
    );

    test(
      'two-pass routes a polish model override with its own thinking level',
      () async {
        final geminiClient = FakeCloudClient(response: 'polished');
        final settings = FakeCloudSettingsService();
        final service = CloudTranscriptionService(
          geminiInteractionsService: geminiClient,
        );
        addTearDown(service.dispose);
        service.attachSettings(settings);
        await settings.setTwoPassRefinementModelId('gemini-3.7-flash');
        await settings.setRefinementThinkingLevel(
          'gemini-3.7-flash',
          GeminiThinkingLevel.medium,
        );
        await settings.setRefinementThinkingLevel(
          'gemini-3.6-flash',
          GeminiThinkingLevel.high,
        );

        final result = await service.transcribeTwoPass(
          Uint8List.fromList([1]),
          'audio/wav',
          settings: settings,
          polishModelOverrideId: 'gemini-3.6-flash',
        );

        expect(result, equals('polished'));
        // Pass 1 is untouched by the polish override.
        expect(geminiClient.transcribeCalls, equals(1));
        expect(
          geminiClient.lastTranscribeModelOverrideId,
          AppConfig.defaultModelId,
        );
        // Pass 2 uses the override id, and the polish thinking level resolves
        // for that override id — never the stored model's level.
        expect(geminiClient.improveCalls, equals(1));
        expect(geminiClient.lastImproveModelOverrideId, 'gemini-3.6-flash');
        expect(
          geminiClient.lastImproveThinkingLevelOverride,
          GeminiThinkingLevel.high,
        );
      },
    );

    test('two-pass composes pass-1 and polish model overrides', () async {
      final geminiClient = FakeCloudClient(response: 'raw transcript');
      final openAiClient = FakeCloudClient(response: 'polished transcript');
      final settings = FakeCloudSettingsService(
        modelId: AppConfig.defaultModelId,
        refinement: CloudProvider.openaiApiKey,
      );
      final service = CloudTranscriptionService(
        geminiInteractionsService: geminiClient,
        openAiService: openAiClient,
      );
      addTearDown(service.dispose);
      service.attachSettings(settings);

      final result = await service.transcribeTwoPass(
        Uint8List.fromList([1, 2, 3]),
        'audio/wav',
        settings: settings,
        missionInstruction: 'clean this up',
        pass1ModelOverrideId: 'gemini-3.5-transcribe',
        polishModelOverrideId: 'gpt-5.6-terra',
      );

      expect(result, equals('polished transcript'));
      // A dedicated speech model is still a legal pass-1 override.
      expect(geminiClient.transcribeCalls, equals(1));
      expect(
        geminiClient.lastTranscribeModelOverrideId,
        'gemini-3.5-transcribe',
      );
      expect(geminiClient.improveCalls, equals(0));
      expect(openAiClient.transcribeCalls, equals(0));
      expect(openAiClient.improveCalls, equals(1));
      expect(openAiClient.lastImproveModelOverrideId, 'gpt-5.6-terra');
    });

    test(
      'a transcription-only polish override is rejected before any request',
      () async {
        final geminiClient = FakeCloudClient();
        final settings = FakeCloudSettingsService();
        final service = CloudTranscriptionService(
          geminiInteractionsService: geminiClient,
        );
        addTearDown(service.dispose);
        service.attachSettings(settings);

        await expectLater(
          () => service.transcribeTwoPass(
            Uint8List.fromList([1]),
            'audio/wav',
            settings: settings,
            polishModelOverrideId: 'gemini-3.5-transcribe',
          ),
          throwsA(
            isA<CloudTranscriptionException>().having(
              (error) => error.message,
              'message',
              contains('only transcribes'),
            ),
          ),
        );
        // Both stages are captured up front, so neither request runs.
        expect(geminiClient.transcribeCalls, equals(0));
        expect(geminiClient.improveCalls, equals(0));
      },
    );

    test('a pass-1 override that cannot receive audio is rejected', () async {
      final vertexClient = FakeCloudClient();
      final settings = FakeCloudSettingsService(
        provider: CloudProvider.vertexAi,
      );
      final service = CloudTranscriptionService(vertexAiService: vertexClient);
      addTearDown(service.dispose);
      service.attachSettings(settings);

      // Vertex shares the Gemini catalog but cannot serve the dedicated
      // transcription-only speech model.
      await expectLater(
        () => service.transcribeTwoPass(
          Uint8List.fromList([1]),
          'audio/wav',
          settings: settings,
          pass1ModelOverrideId: 'gemini-3.5-transcribe',
        ),
        throwsA(
          isA<CloudTranscriptionException>().having(
            (error) => error.message,
            'message',
            contains('cannot receive audio'),
          ),
        ),
      );
      expect(vertexClient.transcribeCalls, equals(0));
    });

    test('refineTranscript routes a polish model override', () async {
      final geminiClient = FakeCloudClient(response: 'polished');
      final settings = FakeCloudSettingsService();
      final service = CloudTranscriptionService(
        geminiInteractionsService: geminiClient,
      );
      addTearDown(service.dispose);
      service.attachSettings(settings);
      await settings.setTwoPassRefinementModelId('gemini-3.7-flash');
      await settings.setRefinementThinkingLevel(
        'gemini-3.6-flash',
        GeminiThinkingLevel.high,
      );

      // Null keeps the stored refinement model.
      await service.refineTranscript('raw', settings: settings);
      expect(geminiClient.lastImproveModelOverrideId, 'gemini-3.7-flash');

      await service.refineTranscript(
        'raw',
        settings: settings,
        polishModelOverrideId: 'gemini-3.6-flash',
      );
      expect(geminiClient.improveCalls, equals(2));
      expect(geminiClient.lastImproveModelOverrideId, 'gemini-3.6-flash');
      expect(
        geminiClient.lastImproveThinkingLevelOverride,
        GeminiThinkingLevel.high,
      );
    });

    test('verifies both stage providers with their own models', () async {
      final geminiClient = FakeCloudClient();
      final codexClient = FakeCloudClient();
      final settings = _ReadySettings();
      final service = CloudTranscriptionService(
        geminiInteractionsService: geminiClient,
        codexService: codexClient,
      );
      addTearDown(service.dispose);
      service.attachSettings(settings);

      await service.verifyTranscriptionSetup(settings);
      expect(geminiClient.verifyCalls, 1);
      expect(codexClient.verifyCalls, 1);
      expect(
        codexClient.selectedModelIds,
        contains(AppConfig.defaultCodexModelId),
      );
    });

    test('verifies Codex first pass using its transcription model', () async {
      final codexClient = FakeCloudClient();
      final settings = _ReadyCodexSettings();
      final service = CloudTranscriptionService(codexService: codexClient);
      addTearDown(service.dispose);
      service.attachSettings(settings);

      await service.verifyTranscriptionSetup(settings);

      expect(codexClient.verifyCalls, 1);
      expect(codexClient.selectedModelIds, contains('chatgpt-transcribe'));
    });

    test(
      'orchestrator refuses to send audio to a non-first-pass provider',
      () async {
        final openAiClient = FakeCloudClient(response: 'audio reply');
        final service = CloudTranscriptionService(openAiService: openAiClient);
        addTearDown(service.dispose);
        // OpenAI keeps speech models in its catalog, but it is not a
        // first-pass provider; no orchestrator path may send audio to it.
        service.attachSettings(
          FakeCloudSettingsService(
            provider: CloudProvider.openaiApiKey,
            modelId: 'gpt-transcribe',
          ),
        );

        await expectLater(
          service.transcribeAudio(Uint8List.fromList([1]), 'audio/wav'),
          throwsA(isA<CloudTranscriptionException>()),
        );
        await expectLater(
          service.transcribeSinglePass(Uint8List.fromList([1]), 'audio/wav'),
          throwsA(isA<CloudTranscriptionException>()),
        );
        await expectLater(
          service.transcribeAndImprove(Uint8List.fromList([1]), 'audio/wav'),
          throwsA(isA<CloudTranscriptionException>()),
        );
        expect(openAiClient.transcribeCalls, equals(0));
        expect(openAiClient.transcribeAndImproveCalls, equals(0));
        expect(openAiClient.improveCalls, equals(0));
      },
    );

    test('audio calls reject the no-transcript marker', () async {
      final geminiClient = FakeCloudClient(response: '[NO_TRANSCRIPT]');
      final vertexClient = FakeCloudClient();
      final settings = FakeCloudSettingsService();

      final service = CloudTranscriptionService(
        geminiInteractionsService: geminiClient,
        vertexAiService: vertexClient,
      );

      service.attachSettings(settings);

      await expectLater(
        () => service.transcribeAndImprove(
          Uint8List.fromList([1, 2, 3]),
          'audio/wav',
        ),
        throwsA(
          isA<CloudTranscriptionException>().having(
            (error) => error.message,
            'message',
            equals('Nothing was transcribed.'),
          ),
        ),
      );
    });

    test(
      'all orchestrator methods guard marker and excessive output',
      () async {
        final markerClient = FakeCloudClient(response: '[NO_TRANSCRIPT]');
        final markerService = CloudTranscriptionService(
          geminiInteractionsService: markerClient,
          vertexAiService: FakeCloudClient(),
        );
        final markerSettings = FakeCloudSettingsService();
        markerService.attachSettings(markerSettings);

        await expectLater(
          () => markerService.refineTranscript('raw', settings: markerSettings),
          throwsA(isA<CloudTranscriptionException>()),
        );
        await expectLater(
          () => markerService.transcribeAndImprove(
            Uint8List.fromList([1]),
            'audio/wav',
          ),
          throwsA(isA<CloudTranscriptionException>()),
        );
        await expectLater(
          () => markerService.transcribeAudio(
            Uint8List.fromList([1]),
            'audio/wav',
          ),
          throwsA(isA<CloudTranscriptionException>()),
        );

        final longClient = FakeCloudClient(
          response: 'x' * (TranscriptionResultGuard.maxTranscriptLength + 10),
        );
        final longService = CloudTranscriptionService(
          geminiInteractionsService: longClient,
          vertexAiService: FakeCloudClient(),
        );
        final longSettings = FakeCloudSettingsService();
        longService.attachSettings(longSettings);

        expect(
          (await longService.refineTranscript(
            'raw',
            settings: longSettings,
          )).length,
          TranscriptionResultGuard.maxTranscriptLength,
        );
        expect(
          (await longService.transcribeAndImprove(
            Uint8List.fromList([1]),
            'audio/wav',
          )).length,
          TranscriptionResultGuard.maxTranscriptLength,
        );
        expect(
          (await longService.transcribeAudio(
            Uint8List.fromList([1]),
            'audio/wav',
          )).length,
          TranscriptionResultGuard.maxTranscriptLength,
        );
      },
    );

    test(
      'rejects transcription-only models for prompt-following paths',
      () async {
        final service = CloudTranscriptionService(
          geminiInteractionsService: FakeCloudClient(),
          vertexAiService: FakeCloudClient(),
        );
        service.attachSettings(FakeCloudSettingsService());

        await expectLater(
          () => service.transcribeAndImprove(
            Uint8List.fromList([1, 2, 3]),
            'audio/wav',
            modelOverrideId: 'gemini-3.5-transcribe',
          ),
          throwsA(
            isA<CloudTranscriptionException>().having(
              (error) => error.message,
              'message',
              contains('only transcribes'),
            ),
          ),
        );
      },
    );

    test(
      'single-pass dispatches Transcribe directly without a style request',
      () async {
        final client = FakeCloudClient(response: 'raw transcript');
        final service = CloudTranscriptionService(
          geminiInteractionsService: client,
        );
        addTearDown(service.dispose);
        service.attachSettings(
          FakeCloudSettingsService(modelId: 'gemini-3.5-transcribe'),
        );
        expect(
          await service.transcribeSinglePass(
            Uint8List.fromList([1, 2, 3]),
            'audio/wav',
            missionInstruction: 'Write a professional email.',
          ),
          'raw transcript',
        );
        expect(client.transcribeCalls, 1);
        expect(client.transcribeAndImproveCalls, 0);
        expect(client.improveCalls, 0);
        expect(client.lastTranscribeModelOverrideId, 'gemini-3.5-transcribe');
      },
    );

    test(
      'Codex single-pass uses ChatGPT Transcribe without a prompt',
      () async {
        final codex = FakeCloudClient(response: 'raw ChatGPT transcript');
        final service = CloudTranscriptionService(codexService: codex);
        addTearDown(service.dispose);
        service.attachSettings(
          FakeCloudSettingsService(
            provider: CloudProvider.codexOAuth,
            modelId: 'chatgpt-transcribe',
          ),
        );

        expect(
          await service.transcribeSinglePass(
            Uint8List.fromList([1, 2, 3]),
            'audio/wav',
            missionInstruction: 'This must not be applied.',
          ),
          'raw ChatGPT transcript',
        );
        expect(codex.transcribeCalls, 1);
        expect(codex.lastTranscribeModelOverrideId, 'chatgpt-transcribe');
        expect(codex.transcribeAndImproveCalls, 0);
        expect(codex.improveCalls, 0);
      },
    );

    test(
      'Codex two-pass transcribes first and polishes with a GPT model',
      () async {
        final codex = FakeCloudClient(response: 'raw transcript');
        final settings = FakeCloudSettingsService(
          provider: CloudProvider.codexOAuth,
          modelId: 'chatgpt-transcribe',
          refinement: CloudProvider.codexOAuth,
        );
        final service = CloudTranscriptionService(codexService: codex);
        addTearDown(service.dispose);
        service.attachSettings(settings);

        expect(
          await service.transcribeTwoPass(
            Uint8List.fromList([1, 2, 3]),
            'audio/wav',
            settings: settings,
            missionInstruction: 'Polish this transcript.',
          ),
          'raw transcript',
        );
        expect(codex.transcribeCalls, 1);
        expect(codex.lastTranscribeModelOverrideId, 'chatgpt-transcribe');
        expect(codex.improveCalls, 1);
        expect(codex.lastImproveModelOverrideId, AppConfig.defaultCodexModelId);
        expect(codex.lastImproveModelOverrideId, isNot('chatgpt-transcribe'));
        expect(codex.transcribeAndImproveCalls, 0);
      },
    );

    for (final model in AppConfig.mainModels) {
      test(
        'single-pass keeps style processing in one request for ${model.id}',
        () async {
          final client = FakeCloudClient();
          final service = CloudTranscriptionService(
            geminiInteractionsService: client,
          );
          addTearDown(service.dispose);
          await service.transcribeSinglePass(
            Uint8List.fromList([1, 2, 3]),
            'audio/wav',
            modelOverrideId: model.id,
            thinkingLevelOverride: GeminiThinkingLevel.high,
          );
          expect(client.transcribeAndImproveCalls, 1);
          expect(client.transcribeCalls, 0);
          expect(client.improveCalls, 0);
          expect(client.lastTranscribeAndImproveModelOverrideId, model.id);
          expect(
            client.lastTranscribeAndImproveThinkingLevelOverride,
            GeminiThinkingLevel.high,
          );
        },
      );
    }

    test(
      'standalone routing preserves the Vertex speech-model restriction',
      () async {
        final vertex = FakeCloudClient();
        final service = CloudTranscriptionService(vertexAiService: vertex);
        addTearDown(service.dispose);
        service.attachSettings(
          FakeCloudSettingsService(provider: CloudProvider.vertexAi),
        );
        await expectLater(
          service.transcribeSinglePass(
            Uint8List.fromList([1, 2, 3]),
            'audio/wav',
            modelOverrideId: 'gemini-3.5-transcribe',
          ),
          throwsA(isA<CloudTranscriptionException>()),
        );
        expect(vertex.transcribeCalls, 0);
      },
    );

    test('allows transcription-only models for raw transcribeAudio', () async {
      final service = CloudTranscriptionService(
        geminiInteractionsService: FakeCloudClient(response: 'raw transcript'),
        vertexAiService: FakeCloudClient(),
      );
      service.attachSettings(FakeCloudSettingsService());

      final result = await service.transcribeAudio(
        Uint8List.fromList([1, 2, 3]),
        'audio/wav',
        modelOverrideId: 'gemini-3.5-transcribe',
      );
      expect(result, equals('raw transcript'));
    });

    test(
      'rejects transcription-only models when Vertex is the active provider',
      () async {
        final service = CloudTranscriptionService(
          geminiInteractionsService: FakeCloudClient(),
          vertexAiService: FakeCloudClient(response: 'vertex'),
        );
        service.attachSettings(
          FakeCloudSettingsService(provider: CloudProvider.vertexAi),
        );

        await expectLater(
          () => service.transcribeAudio(
            Uint8List.fromList([1, 2, 3]),
            'audio/wav',
            modelOverrideId: 'gemini-3.5-transcribe',
          ),
          throwsA(isA<CloudTranscriptionException>()),
        );
      },
    );

    test('runtime calls forward prompt model and thinking overrides', () async {
      final geminiClient = FakeCloudClient();
      final vertexClient = FakeCloudClient();
      final settings = FakeCloudSettingsService();

      final service = CloudTranscriptionService(
        geminiInteractionsService: geminiClient,
        vertexAiService: vertexClient,
      );

      service.attachSettings(settings);

      await service.transcribeAndImprove(
        Uint8List.fromList([1, 2, 3]),
        'audio/wav',
        modelOverrideId: 'gemini-3-flash',
        thinkingLevelOverride: GeminiThinkingLevel.high,
      );
      expect(
        geminiClient.lastTranscribeAndImproveModelOverrideId,
        equals('gemini-3-flash'),
      );
      expect(
        geminiClient.lastTranscribeAndImproveThinkingLevelOverride,
        equals(GeminiThinkingLevel.high),
      );

      await settings.setTwoPassRefinementModelId('gemini-3.7-flash');
      await settings.setRefinementThinkingLevel(
        'gemini-3.7-flash',
        GeminiThinkingLevel.medium,
      );
      await service.refineTranscript('raw', settings: settings);
      expect(
        geminiClient.lastImproveModelOverrideId,
        equals('gemini-3.7-flash'),
      );
      expect(
        geminiClient.lastImproveThinkingLevelOverride,
        equals(GeminiThinkingLevel.medium),
      );

      await service.transcribeAudio(
        Uint8List.fromList([4, 5, 6]),
        'audio/wav',
        modelOverrideId: 'gemini-3-flash',
        thinkingLevelOverride: GeminiThinkingLevel.high,
      );
      expect(
        geminiClient.lastTranscribeModelOverrideId,
        equals('gemini-3-flash'),
      );
      expect(
        geminiClient.lastTranscribeThinkingLevelOverride,
        equals(GeminiThinkingLevel.high),
      );
    });
  });
}

/// Two-step Gemini → ChatGPT setup with both accounts signed in.
class _ReadySettings extends FakeCloudSettingsService {
  _ReadySettings() : super(refinement: CloudProvider.codexOAuth);

  @override
  bool get twoPassTranscriptionEnabled => true;

  @override
  bool hasCredentialsForProvider(CloudProvider provider) => true;
}

class _ReadyCodexSettings extends FakeCloudSettingsService {
  _ReadyCodexSettings()
    : super(provider: CloudProvider.codexOAuth, modelId: 'chatgpt-transcribe');

  @override
  bool get hasCloudCredentials => true;
}
