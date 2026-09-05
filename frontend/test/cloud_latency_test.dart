import 'dart:async';
import 'dart:typed_data';

import 'package:beeamvo/config.dart';
import 'package:beeamvo/services/cloud_transcription_client.dart';
import 'package:beeamvo/services/gemini_interactions_service.dart';
import 'package:beeamvo/services/secure_credential_store.dart';
import 'package:beeamvo/services/settings_service.dart';
import 'package:beeamvo/services/vertex_ai_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';

class _Settings extends SettingsService {
  _Settings({this.level})
    : super(credentialStore: InMemorySecureCredentialStore());

  final GeminiThinkingLevel? level;

  @override
  Future<String?> readGeminiApiKey() async => 'test-key';

  @override
  String? get vertexProjectId => 'test-project';

  @override
  GeminiThinkingLevel? getThinkingLevelForModel(String modelId) => level;
}

void main() {
  for (final vertex in [false, true]) {
    final provider = vertex ? 'Vertex' : 'Gemini';
    group('$provider transcription latency', () {
      for (final model in AppConfig.mainModels) {
        test('${model.id} defaults to its lowest supported reasoning', () {
          final client = vertex
              ? VertexAiService() as CloudTranscriptionClient
              : GeminiInteractionsService();
          addTearDown(client.dispose);
          client.attachSettings(_Settings());

          final payload = vertex
              ? (client as VertexAiService).buildTranscribeAndImprovePayload(
                  audioData: Uint8List.fromList([1, 2]),
                  mimeType: 'audio/wav',
                  missionInstruction: 'Clean up the dictation.',
                  model: model,
                )
              : (client as GeminiInteractionsService)
                    .buildTranscribeAndImprovePayload(
                      audioData: Uint8List.fromList([1, 2]),
                      mimeType: 'audio/wav',
                      missionInstruction: 'Clean up the dictation.',
                      model: model,
                    );
          final expected = model.resolveThinkingLevel(forceMinimal: true)!;
          final actual = vertex
              ? payload['generationConfig']['thinkingConfig']['thinkingLevel']
              : payload['generation_config']['thinking_level'];
          expect(actual, vertex ? expected.apiValue : expected.name);
        });
      }

      test('does not silently resubmit a timed-out generation', () async {
        var calls = 0;
        final httpClient = MockClient((_) async {
          calls++;
          throw TimeoutException('generation timed out');
        });
        final client = vertex
            ? VertexAiService(adcClientFactory: (_) async => httpClient)
                  as CloudTranscriptionClient
            : GeminiInteractionsService(httpClient: httpClient);
        addTearDown(client.dispose);
        client.attachSettings(_Settings());
        await client.initialize();

        await expectLater(
          client.transcribeAndImprove(Uint8List.fromList([1, 2]), 'audio/wav'),
          throwsA(isA<TimeoutException>()),
        );
        expect(calls, 1);
      });

      test('preserves explicitly selected higher reasoning', () {
        final client = vertex
            ? VertexAiService() as CloudTranscriptionClient
            : GeminiInteractionsService();
        addTearDown(client.dispose);
        client.attachSettings(_Settings(level: GeminiThinkingLevel.high));
        final model = AppConfig.getModelById(AppConfig.defaultModelId);
        final payload = vertex
            ? (client as VertexAiService).buildImprovePayload(
                'dictation',
                missionInstruction: 'Clean up the dictation.',
                model: model,
              )
            : (client as GeminiInteractionsService).buildImprovePayload(
                'dictation',
                missionInstruction: 'Clean up the dictation.',
                model: model,
              );
        expect(
          vertex
              ? payload['generationConfig']['thinkingConfig']['thinkingLevel']
              : payload['generation_config']['thinking_level'],
          vertex ? 'HIGH' : 'high',
        );
      });
    });
  }
}
