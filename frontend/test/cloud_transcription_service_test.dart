import 'dart:typed_data';

import 'package:beeamvo/config.dart';
import 'package:beeamvo/services/cloud_transcription_client.dart';
import 'package:beeamvo/services/cloud_transcription_service.dart';
import 'package:beeamvo/services/secure_credential_store.dart';
import 'package:beeamvo/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeCloudClient implements CloudTranscriptionClient {
  FakeCloudClient({String? response})
    : _response = response ?? 'ok',
      _currentModel = AppConfig.getModelById(AppConfig.defaultModelId);

  final String _response;
  GeminiModelConfig _currentModel;
  bool _isInitialized = false;
  int initializeCalls = 0;
  int verifyCalls = 0;
  int improveCalls = 0;
  int transcribeCalls = 0;
  int transcribeAndImproveCalls = 0;
  final List<String> selectedModelIds = [];
  String? lastImproveModelOverrideId;
  GeminiThinkingLevel? lastImproveThinkingLevelOverride;
  String? lastTranscribeAndImproveModelOverrideId;
  GeminiThinkingLevel? lastTranscribeAndImproveThinkingLevelOverride;
  String? lastTranscribeModelOverrideId;

  @override
  void attachSettings(SettingsService settings) {}

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
  void dispose() {}

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
  }) async {
    transcribeCalls += 1;
    lastTranscribeModelOverrideId = modelOverrideId;
    return _response;
  }
}

class FakeCloudSettingsService extends SettingsService {
  FakeCloudSettingsService({
    this.provider = CloudProvider.geminiApiKey,
    this.modelId = AppConfig.defaultModelId,
  }) : super(credentialStore: InMemorySecureCredentialStore());

  CloudProvider provider;
  String modelId;

  @override
  CloudProvider get cloudProvider => provider;

  @override
  String get selectedModelId => modelId;
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
          geminiApiService: geminiClient,
          vertexAiService: vertexClient,
        );

        service.attachSettings(settings);
        await service.initialize();

        expect(geminiClient.initializeCalls, equals(1));
        expect(vertexClient.initializeCalls, equals(0));
        expect(geminiClient.selectedModelIds, contains('gemini-3-flash'));
        expect(vertexClient.selectedModelIds, contains('gemini-3-flash'));
      },
    );

    test('verifyProvider lazily initializes the requested provider', () async {
      final geminiClient = FakeCloudClient();
      final vertexClient = FakeCloudClient();
      final settings = FakeCloudSettingsService();

      final service = CloudTranscriptionService(
        geminiApiService: geminiClient,
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
        geminiApiService: geminiClient,
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

      final geminiResult = await service.improveTranscription('raw text');
      expect(geminiResult, equals('gemini'));
      expect(geminiClient.improveCalls, equals(1));
      expect(vertexClient.improveCalls, equals(0));
    });

    test('audio calls reject the no-transcript marker', () async {
      final geminiClient = FakeCloudClient(response: '[NO_TRANSCRIPT]');
      final vertexClient = FakeCloudClient();
      final settings = FakeCloudSettingsService();

      final service = CloudTranscriptionService(
        geminiApiService: geminiClient,
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

    test('runtime calls forward prompt model and thinking overrides', () async {
      final geminiClient = FakeCloudClient();
      final vertexClient = FakeCloudClient();
      final settings = FakeCloudSettingsService();

      final service = CloudTranscriptionService(
        geminiApiService: geminiClient,
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

      await service.improveTranscription(
        'raw',
        modelOverrideId: 'gemini-3.1-flash-lite',
        thinkingLevelOverride: GeminiThinkingLevel.low,
      );
      expect(
        geminiClient.lastImproveModelOverrideId,
        equals('gemini-3.1-flash-lite'),
      );
      expect(
        geminiClient.lastImproveThinkingLevelOverride,
        equals(GeminiThinkingLevel.low),
      );

      await service.transcribeAudio(
        Uint8List.fromList([4, 5, 6]),
        'audio/wav',
        modelOverrideId: 'gemini-3-flash',
      );
      expect(
        geminiClient.lastTranscribeModelOverrideId,
        equals('gemini-3-flash'),
      );
    });
  });
}
