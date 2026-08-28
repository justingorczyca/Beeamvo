import 'dart:convert';
import 'dart:typed_data';

import 'package:beeamvo/config.dart';
import 'package:beeamvo/services/cloud_transcription_client.dart';
import 'package:beeamvo/services/gemini_interactions_service.dart';
import 'package:beeamvo/services/secure_credential_store.dart';
import 'package:beeamvo/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeInteractionsSettingsService extends SettingsService {
  FakeInteractionsSettingsService({this.apiKey = 'test-key', this.level})
    : super(credentialStore: InMemorySecureCredentialStore());

  final String? apiKey;
  final GeminiThinkingLevel? level;

  @override
  Future<String?> readGeminiApiKey() async => apiKey;

  @override
  GeminiThinkingLevel? getThinkingLevelForModel(String modelId) => level;
}

http.Response _completedResponse(String text) {
  return http.Response(
    jsonEncode({
      'id': 'interaction-1',
      'status': 'completed',
      'steps': [
        {
          'type': 'model_output',
          'status': 'done',
          'content': [
            {'type': 'text', 'text': text},
          ],
        },
      ],
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}

GeminiInteractionsService _service(http.Client client) {
  final service = GeminiInteractionsService(httpClient: client);
  service.attachSettings(FakeInteractionsSettingsService());
  return service;
}

void main() {
  group('GeminiInteractionsService payloads', () {
    test('improve payload uses the Interactions wire format', () {
      final service = _service(
        MockClient((_) async => _completedResponse('ok')),
      );
      service.attachSettings(
        FakeInteractionsSettingsService(level: GeminiThinkingLevel.high),
      );
      final payload = service.buildImprovePayload(
        'raw text',
        missionInstruction: 'Be concise.',
        model: AppConfig.getModelById('gemini-3-flash'),
      );

      expect(payload['model'], equals('gemini-3-flash-preview'));
      expect(payload['store'], isFalse);
      expect(payload['system_instruction'], isA<String>());
      expect(payload.containsKey('systemInstruction'), isFalse);
      expect(payload['input'], isA<List<dynamic>>());
      expect(payload['input'][0]['type'], equals('text'));
      expect(payload['generation_config']['thinking_level'], equals('high'));
      expect(payload['generation_config']['max_output_tokens'], equals(32768));
      expect(
        payload['generation_config'].containsKey('temperature'),
        isFalse,
        reason:
            'The Interactions API rejects unknown generation_config fields.',
      );
    });

    test('audio payloads use text and inline audio content items', () {
      final service = _service(
        MockClient((_) async => _completedResponse('ok')),
      );
      final payload = service.buildTranscribeAndImprovePayload(
        audioData: Uint8List.fromList([1, 2, 3]),
        mimeType: 'audio/wav',
        missionInstruction: 'Format it.',
        model: AppConfig.getModelById('gemini-3-flash'),
      );
      final input = payload['input'] as List<dynamic>;
      expect(input[0]['type'], equals('text'));
      expect(input[1], {
        'type': 'audio',
        'data': base64Encode([1, 2, 3]),
        'mime_type': 'audio/wav',
      });
      expect(payload['system_instruction'], isA<String>());
    });

    test('thinking budget models omit Interactions thinking config', () {
      final service = _service(
        MockClient((_) async => _completedResponse('ok')),
      );
      final payload = service.buildTranscribePayload(
        audioData: Uint8List.fromList([1]),
        mimeType: 'audio/wav',
        model: AppConfig.getModelById('gemini-2.5-flash'),
      );

      final generationConfig =
          payload['generation_config'] as Map<String, dynamic>;
      expect(generationConfig.containsKey('thinking_level'), isFalse);
      expect(generationConfig.containsKey('thinking_budget'), isFalse);
    });

    test(
      'transcription-only payload uses generation_config.transcription_config',
      () {
        final service = _service(
          MockClient((_) async => _completedResponse('ok')),
        );
        final payload = service.buildTranscribePayload(
          audioData: Uint8List.fromList([1, 2, 3]),
          mimeType: 'audio/wav',
          model: AppConfig.getModelById('gemini-3.5-transcribe'),
        );

        expect(payload['model'], equals('gemini-3.5-transcribe'));
        final input = payload['input'] as List<dynamic>;
        expect(input, [
          {
            'type': 'audio',
            'data': base64Encode([1, 2, 3]),
            'mime_type': 'audio/wav',
          },
        ]);
        expect(payload.containsKey('system_instruction'), isFalse);
        final generationConfig =
            payload['generation_config'] as Map<String, dynamic>;
        final transcriptionConfig =
            generationConfig['transcription_config'] as Map<String, dynamic>;
        expect(transcriptionConfig['language_codes'], equals(['auto']));
        expect(transcriptionConfig['mode'], {'type': 'verbatim'});
        expect(generationConfig.containsKey('thinking_level'), isFalse);
      },
    );

    test('verifySetup uses the key header and robust verify payload', () async {
      http.Request? capturedRequest;
      final service = _service(
        MockClient((request) async {
          capturedRequest = request;
          return _completedResponse('OK');
        }),
      );

      await service.verifySetup();

      expect(capturedRequest, isNotNull);
      final request = capturedRequest!;
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['store'], isFalse);
      expect(body.containsKey('system_instruction'), isFalse);
      // The Interactions API rejects unknown generation_config fields (HTTP
      // 400), so no `temperature` may be sent.
      expect(body['generation_config']!.containsKey('temperature'), isFalse);
      expect(body['generation_config'], {
        'max_output_tokens': 64,
        'thinking_level': 'minimal',
      });
      expect(request.headers['x-goog-api-key'], equals('test-key'));
      expect(
        request.headers['Api-Revision'],
        equals(GeminiInteractionsService.apiRevision),
      );
      expect(request.url.path, equals('/v1beta/interactions'));
      expect(request.headers.containsKey('Authorization'), isFalse);
      expect(request.headers.containsKey('authorization'), isFalse);
    });
  });

  group('GeminiInteractionsService responses', () {
    test('extracts text from completed model output steps', () async {
      final service = _service(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'status': 'completed',
              'steps': [
                {
                  'type': 'model_output',
                  'content': [
                    {'type': 'text', 'text': 'Hello '},
                    {'type': 'other', 'text': 'ignored'},
                    {'type': 'text', 'text': 'world'},
                  ],
                },
              ],
            }),
            200,
          ),
        ),
      );

      expect(await service.improveTranscription('raw'), equals('Hello world'));
    });

    test(
      'extracts text from transcription-only steps without a step type',
      () async {
        final service = _service(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'status': 'completed',
                'steps': [
                  {
                    'content': [
                      {'type': 'text', 'text': 'Transcribed'},
                    ],
                  },
                ],
              }),
              200,
            ),
          ),
        );

        expect(
          await service.transcribeAudio(Uint8List(0), 'audio/wav'),
          equals('Transcribed'),
        );
      },
    );

    test('reports non-completed interactions and empty text safely', () async {
      final pendingService = _service(
        MockClient(
          (_) async => http.Response(
            jsonEncode({'status': 'in_progress', 'steps': []}),
            200,
          ),
        ),
      );
      await expectLater(
        pendingService.improveTranscription('raw'),
        throwsA(
          isA<CloudTranscriptionException>().having(
            (error) => error.message,
            'message',
            contains('did not complete'),
          ),
        ),
      );

      final emptyService = _service(
        MockClient(
          (_) async => http.Response(
            jsonEncode({'status': 'completed', 'steps': []}),
            200,
          ),
        ),
      );
      await expectLater(
        emptyService.improveTranscription('raw'),
        throwsA(
          isA<CloudTranscriptionException>().having(
            (error) => error.message,
            'message',
            contains('empty response'),
          ),
        ),
      );
    });

    test('malformed JSON produces a safe error', () async {
      final service = _service(
        MockClient((_) async => http.Response('<html>bad</html>', 200)),
      );

      await expectLater(
        service.improveTranscription('raw'),
        throwsA(
          isA<CloudTranscriptionException>().having(
            (error) => error.message,
            'message',
            contains('invalid response'),
          ),
        ),
      );
    });

    test('Retry-After seconds are converted to a real delay', () async {
      var calls = 0;
      final service = _service(
        MockClient((_) async {
          calls++;
          if (calls == 1) {
            return http.Response('{}', 429, headers: {'retry-after': '1'});
          }
          return _completedResponse('ok');
        }),
      );
      final stopwatch = Stopwatch()..start();

      expect(await service.improveTranscription('raw'), equals('ok'));
      stopwatch.stop();

      expect(calls, equals(2));
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(800));
    });

    test('non-numeric Retry-After falls back to exponential backoff', () async {
      var calls = 0;
      final service = _service(
        MockClient((_) async {
          calls++;
          if (calls == 1) {
            return http.Response(
              '{}',
              429,
              headers: {'retry-after': 'Wed, 21 Oct 2015 07:28:00 GMT'},
            );
          }
          return _completedResponse('ok');
        }),
      );
      final stopwatch = Stopwatch()..start();

      expect(await service.improveTranscription('raw'), equals('ok'));
      stopwatch.stop();

      expect(calls, equals(2));
      expect(stopwatch.elapsedMilliseconds, greaterThanOrEqualTo(400));
    });

    test('requests always target the v1beta Interactions endpoint', () async {
      final paths = <String>[];
      final service = _service(
        MockClient((request) async {
          paths.add(request.url.path);
          return _completedResponse('ok');
        }),
      );

      expect(await service.improveTranscription('raw'), equals('ok'));
      expect(await service.improveTranscription('raw'), equals('ok'));
      expect(paths, equals(['/v1beta/interactions', '/v1beta/interactions']));
    });

    test('errors surface a safe message without upstream details', () async {
      final paths = <String>[];
      final service = _service(
        MockClient((request) async {
          paths.add(request.url.path);
          return http.Response(
            jsonEncode({
              'error': {'message': 'secret upstream details'},
            }),
            400,
          );
        }),
      );

      await expectLater(
        service.improveTranscription('raw'),
        throwsA(
          isA<CloudTranscriptionException>().having(
            (error) => error.message,
            'message',
            allOf(
              contains('could not process'),
              isNot(contains('secret upstream details')),
            ),
          ),
        ),
      );
      expect(paths, equals(['/v1beta/interactions']));
    });
  });
}
