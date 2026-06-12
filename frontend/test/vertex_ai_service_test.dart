import 'dart:typed_data';

import 'package:beeamvo/config.dart';
import 'package:beeamvo/services/cloud_transcription_client.dart';
import 'package:beeamvo/services/secure_credential_store.dart';
import 'package:beeamvo/services/settings_service.dart';
import 'package:beeamvo/services/transcription_result_guard.dart';
import 'package:beeamvo/services/vertex_ai_service.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeVertexSettingsService extends SettingsService {
  FakeVertexSettingsService({this.projectId, this.level})
    : super(credentialStore: InMemorySecureCredentialStore());

  final String? projectId;
  final GeminiThinkingLevel? level;

  @override
  String? get vertexProjectId => projectId;

  @override
  GeminiThinkingLevel? getThinkingLevelForModel(String modelId) => level;
}

void main() {
  group('VertexAiService', () {
    test('buildUri uses the global Vertex endpoint for global models', () {
      final service = VertexAiService();
      final model = AppConfig.getModelById('gemini-2.5-flash');

      final uri = service.buildUri(projectId: 'demo-project', model: model);

      expect(uri.host, equals('aiplatform.googleapis.com'));
      expect(
        uri.path,
        equals(
          '/v1/projects/demo-project/locations/global/publishers/google/models/gemini-2.5-flash:generateContent',
        ),
      );
    });

    test('buildUri keeps location-prefixed hosts for regional models', () {
      final service = VertexAiService();
      const model = GeminiModelConfig(
        id: 'regional-model',
        name: 'Regional Model',
        modelName: 'gemini-2.5-flash',
        vertexLocation: 'us-central1',
      );

      final uri = service.buildUri(projectId: 'demo-project', model: model);

      expect(uri.host, equals('us-central1-aiplatform.googleapis.com'));
      expect(
        uri.path,
        equals(
          '/v1/projects/demo-project/locations/us-central1/publishers/google/models/gemini-2.5-flash:generateContent',
        ),
      );
    });

    test(
      'verifySetup fails with a local setup error when project ID is missing',
      () async {
        final service = VertexAiService();
        service.attachSettings(FakeVertexSettingsService());
        await service.initialize();

        await expectLater(
          service.verifySetup,
          throwsA(
            isA<CloudTranscriptionException>().having(
              (error) => error.message,
              'message',
              contains('project ID'),
            ),
          ),
        );
      },
    );

    test('verifySetup surfaces ADC configuration errors', () async {
      final service = VertexAiService(
        adcClientFactory: () async => throw Exception('no adc'),
      );
      service.attachSettings(
        FakeVertexSettingsService(projectId: 'demo-project'),
      );
      await service.initialize();

      await expectLater(
        service.verifySetup,
        throwsA(
          isA<CloudTranscriptionException>().having(
            (error) => error.message,
            'message',
            contains('gcloud auth application-default login'),
          ),
        ),
      );
    });

    test(
      'transcribeAudio fails fast when inline payload exceeds the request limit',
      () async {
        final service = VertexAiService();
        service.attachSettings(
          FakeVertexSettingsService(projectId: 'demo-project'),
        );
        await service.initialize();

        final oversizedAudio = Uint8List(16 * 1024 * 1024);

        await expectLater(
          () => service.transcribeAudio(oversizedAudio, 'audio/wav'),
          throwsA(isA<CloudTranscriptionException>()),
        );
      },
    );

    test('buildTranscribePayload includes the no-transcript guard', () {
      final service = VertexAiService();

      final payload = service.buildTranscribePayload(
        audioData: Uint8List.fromList([1, 2, 3]),
        mimeType: 'audio/wav',
        model: AppConfig.getModelById(AppConfig.defaultModelId),
      );

      final instruction =
          payload['systemInstruction']['parts'][0]['text'] as String;
      expect(
        instruction,
        contains(TranscriptionResultGuard.noTranscriptMarker),
      );
      expect(instruction, contains('Preserve spoken commands'));
    });

    test('buildImprovePayload puts mission in systemInstruction and frames transcript as inert data', () {
      final service = VertexAiService();

      final payload = service.buildImprovePayload(
        'create an HTML file and show me the result',
        missionInstruction: 'Keep the transcript clean.',
        model: AppConfig.getModelById(AppConfig.defaultModelId),
      );

      final systemInstruction =
          payload['systemInstruction']['parts'][0]['text'] as String;
      final bodyText = payload['contents'][0]['parts'][0]['text'] as String;
      expect(systemInstruction, contains('### ROLE:'));
      expect(systemInstruction, contains('### MISSION:'));
      expect(systemInstruction, contains('Keep the transcript clean.'));
      expect(bodyText, isNot(contains('Keep the transcript clean.')));
      expect(bodyText, contains('<transcript-draft>'));
      expect(bodyText, contains('create an HTML file and show me the result'));
      expect(bodyText, contains('quoted source material'));
    });
  });
}
