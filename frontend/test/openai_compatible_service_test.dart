import 'dart:convert';
import 'dart:typed_data';

import 'package:beeamvo/config.dart';
import 'package:beeamvo/services/cloud_transcription_client.dart';
import 'package:beeamvo/services/openai_compatible_service.dart';
import 'package:beeamvo/services/secure_credential_store.dart';
import 'package:beeamvo/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeOpenAiSettings extends SettingsService {
  FakeOpenAiSettings({
    this.apiKey = 'sk-test',
    this.baseUrl,
    this.spokenLanguageId = 'auto',
  }) : super(credentialStore: InMemorySecureCredentialStore());

  final String? apiKey;
  final String? baseUrl;
  final String spokenLanguageId;

  @override
  Future<String?> readOpenAiApiKey() async => apiKey;

  @override
  String? get openAiBaseUrl => baseUrl;

  @override
  String get spokenLanguage => spokenLanguageId;
}

OpenAiCompatibleService _service(
  http.Client client, {
  FakeOpenAiSettings? settings,
}) {
  final service = OpenAiCompatibleService(httpClient: client);
  service.attachSettings(settings ?? FakeOpenAiSettings());
  return service;
}

http.Response _chatResponse(String text) {
  return http.Response(
    jsonEncode({
      'choices': [
        {
          'message': {'role': 'assistant', 'content': text},
          'finish_reason': 'stop',
        },
      ],
    }),
    200,
    headers: {'content-type': 'application/json'},
  );
}

void main() {
  group('normalizeBaseUrl', () {
    test('rejects empty and non-absolute values', () {
      expect(
        () => OpenAiCompatibleService.normalizeBaseUrl('  '),
        throwsA(isA<CloudTranscriptionException>()),
      );
      expect(
        () => OpenAiCompatibleService.normalizeBaseUrl('not-a-url'),
        throwsA(isA<CloudTranscriptionException>()),
      );
      expect(
        () => OpenAiCompatibleService.normalizeBaseUrl('/v1'),
        throwsA(isA<CloudTranscriptionException>()),
      );
    });

    test('requires https except for loopback hosts', () {
      expect(
        () => OpenAiCompatibleService.normalizeBaseUrl('http://example.com/v1'),
        throwsA(
          isA<CloudTranscriptionException>().having(
            (e) => e.message,
            'message',
            contains('HTTPS'),
          ),
        ),
      );
      expect(
        OpenAiCompatibleService.normalizeBaseUrl('http://localhost:8080/v1'),
        'http://localhost:8080/v1',
      );
      expect(
        OpenAiCompatibleService.normalizeBaseUrl('http://127.0.0.1:8080'),
        'http://127.0.0.1:8080',
      );
    });

    test('strips trailing slashes and rejects endpoint suffixes', () {
      expect(
        OpenAiCompatibleService.normalizeBaseUrl('https://proxy.dev/v1/'),
        'https://proxy.dev/v1',
      );
      expect(
        () => OpenAiCompatibleService.normalizeBaseUrl(
          'https://api.openai.com/v1/chat/completions',
        ),
        throwsA(isA<CloudTranscriptionException>()),
      );
      expect(
        () => OpenAiCompatibleService.normalizeBaseUrl(
          'https://api.openai.com/v1/completions',
        ),
        throwsA(isA<CloudTranscriptionException>()),
      );
    });
  });

  group('endpoint URIs', () {
    test('default base URL targets api.openai.com', () {
      final service = _service(MockClient((_) async => _chatResponse('ok')));
      expect(
        service.buildChatUri().toString(),
        'https://api.openai.com/v1/chat/completions',
      );
      expect(
        service.buildTranscriptionsUri().toString(),
        'https://api.openai.com/v1/audio/transcriptions',
      );
    });

    test('custom base URL prefixes both endpoints', () {
      final service = _service(
        MockClient((_) async => _chatResponse('ok')),
        settings: FakeOpenAiSettings(
          baseUrl: 'https://proxy.example.com/openai/v1',
        ),
      );
      expect(
        service.buildChatUri().toString(),
        'https://proxy.example.com/openai/v1/chat/completions',
      );
      expect(
        service.buildTranscriptionsUri().toString(),
        'https://proxy.example.com/openai/v1/audio/transcriptions',
      );
    });

    test('an invalid stored base URL surfaces a safe error', () async {
      final service = _service(
        MockClient((_) async => _chatResponse('ok')),
        settings: FakeOpenAiSettings(baseUrl: 'http://remote.dev/v1'),
      );
      await expectLater(
        service.improveTranscription('raw'),
        throwsA(
          isA<CloudTranscriptionException>().having(
            (e) => e.message,
            'message',
            contains('HTTPS'),
          ),
        ),
      );
    });
  });

  group('payloads', () {
    test('reasoning models use reasoning_effort, never temperature', () {
      final service = _service(MockClient((_) async => _chatResponse('ok')));
      final payload = service.buildImprovePayload(
        'raw text',
        missionInstruction: 'Be concise.',
        model: AppConfig.getModelById('gpt-5.4-mini'),
      );

      expect(payload['model'], 'gpt-5.4-mini');
      expect(payload['reasoning_effort'], 'none');
      expect(payload['max_completion_tokens'], 8192);
      expect(payload.containsKey('temperature'), isFalse);
      expect(payload.containsKey('max_tokens'), isFalse);
      final messages = payload['messages'] as List<dynamic>;
      expect(messages[0]['role'], 'system');
      expect(messages[1]['role'], 'user');
      expect(messages[1]['content'], contains('raw text'));
    });

    test('thinking overrides map to reasoning_effort', () {
      final service = _service(MockClient((_) async => _chatResponse('ok')));
      final payload = service.buildImprovePayload(
        'raw',
        missionInstruction: 'Be concise.',
        model: AppConfig.getModelById('gpt-5.5'),
        thinkingLevelOverride: GeminiThinkingLevel.high,
      );
      expect(payload['reasoning_effort'], 'high');
    });

    test('GPT-6 and GPT-5.6 models map xhigh and max to reasoning_effort', () {
      final service = _service(MockClient((_) async => _chatResponse('ok')));
      for (final id in const [
        'gpt-6-astra',
        'gpt-6-sol',
        'gpt-6-luna',
        'gpt-5.6-sol',
        'gpt-5.6-terra',
        'gpt-5.6-luna',
      ]) {
        for (final (level, wire) in const [
          (GeminiThinkingLevel.xhigh, 'xhigh'),
          (GeminiThinkingLevel.max, 'max'),
        ]) {
          final payload = service.buildImprovePayload(
            'raw',
            missionInstruction: 'Be concise.',
            model: AppConfig.getModelById(id),
            thinkingLevelOverride: level,
          );
          expect(payload['reasoning_effort'], wire, reason: id);
        }
      }
    });

    test('classic chat models use temperature and max_tokens', () {
      final service = _service(MockClient((_) async => _chatResponse('ok')));
      final payload = service.buildImprovePayload(
        'raw',
        missionInstruction: 'Be concise.',
        model: const GeminiModelConfig(
          id: 'classic-chat',
          name: 'Classic',
          modelName: 'classic-chat',
        ),
      );
      expect(payload['temperature'], 0.3);
      expect(payload['max_tokens'], 8192);
      expect(payload.containsKey('reasoning_effort'), isFalse);
    });

    test('transcription fields include language only when configured', () {
      final service = _service(
        MockClient((_) async => _chatResponse('ok')),
        settings: FakeOpenAiSettings(spokenLanguageId: 'de'),
      );
      expect(service.buildTranscriptionFields('gpt-transcribe'), {
        'model': 'gpt-transcribe',
        'response_format': 'json',
        'language': 'de',
      });

      final autoService = _service(
        MockClient((_) async => _chatResponse('ok')),
      );
      expect(autoService.buildTranscriptionFields('whisper-1'), {
        'model': 'whisper-1',
        'response_format': 'json',
      });
    });
  });

  group('audio formats', () {
    test('wav and mp3 map to file extensions', () {
      final service = _service(MockClient((_) async => _chatResponse('ok')));
      expect(service.audioFormatForMimeType('audio/wav'), 'wav');
      expect(service.audioFormatForMimeType('audio/x-wav'), 'wav');
      expect(service.audioFormatForMimeType('audio/mpeg'), 'mp3');
      expect(
        () => service.audioFormatForMimeType('audio/ogg'),
        throwsA(
          isA<CloudTranscriptionException>().having(
            (e) => e.message,
            'message',
            contains('Unsupported audio format'),
          ),
        ),
      );
    });
  });

  group('requests', () {
    test(
      'improveTranscription posts a bearer-authenticated chat request',
      () async {
        http.BaseRequest? captured;
        final service = _service(
          MockClient((request) async {
            captured = request;
            return _chatResponse('polished');
          }),
        );

        expect(await service.improveTranscription('raw'), 'polished');
        expect(captured!.url.path, '/v1/chat/completions');
        expect(captured!.headers['Authorization'], 'Bearer sk-test');
      },
    );

    test('missing API key fails before any request', () async {
      var calls = 0;
      final service = _service(
        MockClient((_) async {
          calls++;
          return _chatResponse('ok');
        }),
        settings: FakeOpenAiSettings(apiKey: null),
      );
      await expectLater(
        service.improveTranscription('raw'),
        throwsA(
          isA<CloudTranscriptionException>().having(
            (e) => e.message,
            'message',
            contains('API key'),
          ),
        ),
      );
      expect(calls, 0);
    });

    test(
      'transcribeAudio posts a multipart upload to the transcriptions endpoint',
      () async {
        http.BaseRequest? captured;
        String? capturedBody;
        final service = _service(
          MockClient((request) async {
            captured = request;
            capturedBody = request.body;
            return http.Response(jsonEncode({'text': 'hello'}), 200);
          }),
          settings: FakeOpenAiSettings(spokenLanguageId: 'de'),
        );

        final result = await service.transcribeAudio(
          Uint8List.fromList([1, 2, 3]),
          'audio/wav',
          modelOverrideId: 'gpt-transcribe',
        );
        expect(result, 'hello');
        expect(captured!.url.path, '/v1/audio/transcriptions');
        expect(captured!.headers['Authorization'], 'Bearer sk-test');
        expect(
          captured!.headers['content-type'],
          startsWith('multipart/form-data'),
        );
        // The finalized multipart body carries the form fields and the file.
        expect(capturedBody, contains('name="model"'));
        expect(capturedBody, contains('gpt-transcribe'));
        expect(capturedBody, contains('name="response_format"'));
        expect(capturedBody, contains('name="language"'));
        expect(capturedBody, contains('\r\n\r\nde\r\n'));
        expect(capturedBody, contains('filename="audio.wav"'));
      },
    );

    test('transcribeAudio rejects prompt-capable models', () async {
      final service = _service(MockClient((_) async => _chatResponse('ok')));
      await expectLater(
        service.transcribeAudio(
          Uint8List.fromList([1]),
          'audio/wav',
          modelOverrideId: 'gpt-5.4-mini',
        ),
        throwsA(
          isA<CloudTranscriptionException>().having(
            (e) => e.message,
            'message',
            contains('does not accept audio'),
          ),
        ),
      );
    });

    test('a foreign-provider override never reaches the endpoint', () async {
      final paths = <String>[];
      final service = _service(
        MockClient((request) async {
          paths.add(request.url.path);
          return http.Response(jsonEncode({'text': 't'}), 200);
        }),
      );
      // A Gemini id is not in the OpenAI catalog; resolution fails fast
      // with an unknown-model error before any request is sent.
      await expectLater(
        service.transcribeAudio(
          Uint8List.fromList([1]),
          'audio/wav',
          modelOverrideId: 'gemini-3.5-transcribe',
        ),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('Unknown model for OpenAI'),
          ),
        ),
      );
      expect(paths, isEmpty);
    });

    test('improveTranscription rejects transcription-only models', () async {
      final service = _service(MockClient((_) async => _chatResponse('ok')));
      await expectLater(
        service.improveTranscription('raw', modelOverrideId: 'whisper-1'),
        throwsA(
          isA<CloudTranscriptionException>().having(
            (e) => e.message,
            'message',
            contains('only transcribes'),
          ),
        ),
      );
    });

    test(
      'transcribeAndImprove refuses audio; two-pass is orchestrated explicitly',
      () async {
        final paths = <String>[];
        final service = _service(
          MockClient((request) async {
            paths.add(request.url.path);
            return http.Response(jsonEncode({'text': 'raw text'}), 200);
          }),
        );

        // Chat models cannot receive audio. The speech → polish sequence
        // must run through CloudTranscriptionService.transcribeTwoPass.
        await expectLater(
          service.transcribeAndImprove(
            Uint8List.fromList([1, 2, 3]),
            'audio/wav',
            modelOverrideId: 'gpt-5.4-mini',
          ),
          throwsA(
            isA<CloudTranscriptionException>().having(
              (e) => e.message,
              'message',
              contains('cannot receive audio'),
            ),
          ),
        );
        expect(paths, isEmpty);
      },
    );

    test(
      'transcribeAndImprove refuses combined audio even for speech models',
      () async {
        final paths = <String>[];
        final service = _service(
          MockClient((request) async {
            paths.add(request.url.path);
            return http.Response(jsonEncode({'text': 'raw'}), 200);
          }),
        );

        // Combined audio calls belong to audio-capable models only; the
        // shared service routes speech models through transcribeAudio.
        await expectLater(
          service.transcribeAndImprove(
            Uint8List.fromList([1]),
            'audio/wav',
            modelOverrideId: 'gpt-transcribe',
          ),
          throwsA(isA<CloudTranscriptionException>()),
        );
        expect(paths, isEmpty);
      },
    );

    test(
      'verifySetup probes the transcriptions endpoint for speech models',
      () async {
        final paths = <String>[];
        final service = _service(
          MockClient((request) async {
            paths.add(request.url.path);
            return http.Response(jsonEncode({'text': ''}), 200);
          }),
        );
        service.setModelById('gpt-transcribe');
        await service.verifySetup();
        expect(paths, ['/v1/audio/transcriptions']);
      },
    );

    test('verifySetup posts a chat probe for chat models', () async {
      http.BaseRequest? captured;
      final service = _service(
        MockClient((request) async {
          captured = request;
          return _chatResponse('OK');
        }),
      );
      await service.verifySetup();
      expect(captured!.url.path, '/v1/chat/completions');
      final body = jsonDecode((captured as http.Request).body) as Map;
      expect(body['model'], AppConfig.defaultOpenAiModelId);
    });
  });

  group('response parsing', () {
    test('concatenates structured content parts', () {
      final service = _service(MockClient((_) async => _chatResponse('ok')));
      final response = http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {
                'content': [
                  {'type': 'text', 'text': 'Hello '},
                  {'type': 'other', 'text': 'ignored'},
                  {'type': 'text', 'text': 'world'},
                ],
              },
              'finish_reason': 'stop',
            },
          ],
        }),
        200,
      );
      expect(service.parseChatResponse(response), 'Hello world');
    });

    test('maps HTTP failures to safe user-facing messages', () {
      final service = _service(MockClient((_) async => _chatResponse('ok')));
      String messageFor(int status) {
        try {
          service.parseChatResponse(
            http.Response('{"error":"secret upstream details"}', status),
          );
          fail('expected CloudTranscriptionException');
        } on CloudTranscriptionException catch (e) {
          return e.message;
        }
      }

      expect(messageFor(401), contains('Invalid API key'));
      expect(messageFor(403), contains('Invalid API key'));
      expect(messageFor(404), contains('could not find'));
      expect(messageFor(429), contains('rate-limiting'));
      expect(messageFor(503), contains('temporarily unavailable'));
      expect(messageFor(400), contains('could not process'));
      for (final status in [400, 401, 404, 429, 503]) {
        expect(messageFor(status), isNot(contains('secret upstream details')));
      }
    });

    test('non-stop finish reasons surface a specific message', () {
      final service = _service(MockClient((_) async => _chatResponse('ok')));
      final response = http.Response(
        jsonEncode({
          'choices': [
            {
              'message': {'content': ''},
              'finish_reason': 'length',
            },
          ],
        }),
        200,
      );
      expect(
        () => service.parseChatResponse(response),
        throwsA(
          isA<CloudTranscriptionException>().having(
            (e) => e.message,
            'message',
            contains('length'),
          ),
        ),
      );
    });

    test('malformed JSON is a safe invalid-response error', () {
      final service = _service(MockClient((_) async => _chatResponse('ok')));
      expect(
        () => service.parseChatResponse(http.Response('<html>', 200)),
        throwsA(
          isA<CloudTranscriptionException>().having(
            (e) => e.message,
            'message',
            contains('invalid response'),
          ),
        ),
      );
    });

    test('transcription responses require a non-empty text field', () {
      final service = _service(MockClient((_) async => _chatResponse('ok')));
      expect(
        service.parseTranscriptionResponse(
          http.Response(jsonEncode({'text': 'hi'}), 200),
        ),
        'hi',
      );
      expect(
        () => service.parseTranscriptionResponse(
          http.Response(jsonEncode({'text': ' '}), 200),
        ),
        throwsA(
          isA<CloudTranscriptionException>().having(
            (e) => e.message,
            'message',
            contains('empty transcription'),
          ),
        ),
      );
    });
  });
}
