import 'dart:convert';
import 'dart:typed_data';

import 'package:beeamvo/config.dart';
import 'package:beeamvo/services/cloud_transcription_client.dart';
import 'package:beeamvo/services/grok_service.dart';
import 'package:beeamvo/services/secure_credential_store.dart';
import 'package:beeamvo/services/xai_oauth_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

http.StreamedResponse _sse(String body, {int status = 200}) {
  return http.StreamedResponse(
    Stream<List<int>>.fromIterable([utf8.encode(body)]),
    status,
    headers: {'content-type': 'text/event-stream'},
  );
}

String _delta(String text) =>
    'data: ${jsonEncode({'type': 'response.output_text.delta', 'delta': text})}\n\n';

String _completed(String text) =>
    'data: ${jsonEncode({
      'type': 'response.completed',
      'response': {
        'output': [
          {
            'type': 'message',
            'content': [
              {'type': 'output_text', 'text': text},
            ],
          },
        ],
      },
    })}\n\n';

XAiCredentials _credentials({
  String accessToken = 'at-valid',
  DateTime? expiresAt,
  String? accountId = 'acct-1',
}) {
  final now = DateTime.now().toUtc();
  return XAiCredentials(
    accessToken: accessToken,
    refreshToken: 'rt',
    expiresAt: expiresAt ?? now.add(const Duration(hours: 1)),
    accountId: accountId,
    tokenEndpoint: 'https://auth.x.ai/oauth2/token',
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late InMemorySecureCredentialStore store;
  late List<Map<String, String>> tokenBodies;

  setUp(() {
    store = InMemorySecureCredentialStore();
    tokenBodies = <Map<String, String>>[];
  });

  XAiOAuthManager oauth({http.Client? tokenClient}) {
    return XAiOAuthManager(
      credentialStore: store,
      client:
          tokenClient ??
          MockClient((request) async {
            tokenBodies.add(request.bodyFields);
            return http.Response(
              jsonEncode({
                'access_token': 'at-refreshed',
                'refresh_token': 'rt-new',
                'expires_in': 3600,
              }),
              200,
            );
          }),
    );
  }

  Future<XAiOAuthManager> signedIn() async {
    final manager = oauth();
    await manager.saveCredentials(_credentials());
    return manager;
  }

  group('payloads', () {
    test('improve payload is stream-only Responses wire format', () {
      final service = GrokService(
        httpClient: MockClient.streaming((_, _) async => _sse('')),
      );
      final payload = service.buildImprovePayload(
        'raw text',
        missionInstruction: 'Be concise.',
        model: AppConfig.getModelById('grok-4.3'),
        thinkingLevelOverride: GeminiThinkingLevel.high,
      );

      expect(payload['model'], 'grok-4.3');
      expect(payload['stream'], isTrue);
      expect(payload['store'], isFalse);
      expect(payload['reasoning'], {'effort': 'high'});
      expect(payload['instructions'], isA<String>());
      final input = payload['input'] as List<dynamic>;
      final message = input.single as Map<String, dynamic>;
      expect(message['role'], 'user');
      final content = message['content'] as List<dynamic>;
      expect(content.single['type'], 'input_text');
      expect(content.single['text'], contains('raw text'));
    });

    test('reasoning clamps to low — xAI rejects disabling reasoning', () {
      final service = GrokService(
        httpClient: MockClient.streaming((_, _) async => _sse('')),
      );
      final model = AppConfig.getModelById('grok-4.3');
      // grok-4.3 does not offer 'minimal'; the resolved level is its default.
      final payload = service.buildImprovePayload(
        'raw',
        missionInstruction: 'x',
        model: model,
        thinkingLevelOverride: GeminiThinkingLevel.minimal,
      );
      expect(payload['reasoning'], {'effort': 'low'});
    });

    test('natively-reasoning models omit the reasoning key entirely', () {
      final service = GrokService(
        httpClient: MockClient.streaming((_, _) async => _sse('')),
      );
      final payload = service.buildImprovePayload(
        'raw',
        missionInstruction: 'x',
        model: AppConfig.getModelById('grok-code-fast-1'),
        thinkingLevelOverride: GeminiThinkingLevel.high,
      );
      expect(payload.containsKey('reasoning'), isFalse);
    });

    test('foreign model overrides resolve to the Grok catalog', () {
      final service = GrokService(
        httpClient: MockClient.streaming((_, _) async => _sse('')),
      );
      // setModelById must not let a foreign id replace the Grok model.
      service.setModelById('gpt-5.4-mini');
      expect(service.currentModel.id, AppConfig.defaultGrokModelId);
      service.setModelById('grok-4.7');
      expect(service.currentModel.id, 'grok-4.7');
    });
  });

  group('audio surface', () {
    test(
      'audio entry points fail with a clear Grok limitation error',
      () async {
        final service = GrokService(
          httpClient: MockClient.streaming((_, _) async => _sse('')),
        );
        for (final call in [
          () => service.transcribeAudio(Uint8List(0), 'audio/wav'),
          () => service.transcribeAndImprove(Uint8List(0), 'audio/wav'),
        ]) {
          await expectLater(
            call(),
            throwsA(
              isA<CloudTranscriptionException>().having(
                (e) => e.message,
                'message',
                contains('cannot transcribe audio'),
              ),
            ),
          );
        }
      },
    );
  });

  group('SSE streaming', () {
    test('concatenates output_text deltas', () async {
      final service = GrokService(
        oauthManager: await signedIn(),
        httpClient: MockClient.streaming(
          (_, _) async => _sse('${_delta('Hel')}${_delta('lo')}'),
        ),
      );
      expect(await service.improveTranscription('raw'), 'Hello');
    });

    test('falls back to response.completed when no deltas arrive', () async {
      final service = GrokService(
        oauthManager: await signedIn(),
        httpClient: MockClient.streaming(
          (_, _) async => _sse(_completed('completed text')),
        ),
      );
      expect(await service.improveTranscription('raw'), 'completed text');
    });

    test('error events surface their message', () async {
      final service = GrokService(
        oauthManager: await signedIn(),
        httpClient: MockClient.streaming(
          (_, _) async => _sse(
            'data: ${jsonEncode({
              'type': 'error',
              'error': {'message': 'boom'},
            })}\n\n',
          ),
        ),
      );
      await expectLater(
        service.improveTranscription('raw'),
        throwsA(
          isA<CloudTranscriptionException>().having(
            (e) => e.message,
            'message',
            contains('boom'),
          ),
        ),
      );
    });

    test('requests hit api.x.ai/v1/responses with the Grok headers', () async {
      http.BaseRequest? captured;
      String? body;
      final service = GrokService(
        oauthManager: await signedIn(),
        httpClient: MockClient.streaming((request, requestBody) async {
          captured = request;
          body = await requestBody.bytesToString();
          return _sse(_delta('ok'));
        }),
      );
      await service.improveTranscription('raw');

      expect(captured!.url.host, 'api.x.ai');
      expect(captured!.url.path, '/v1/responses');
      expect(captured!.headers['authorization'], 'Bearer at-valid');
      expect(captured!.headers['accept'], 'text/event-stream');
      expect(captured!.headers['x-grok-conv-id'], isNotEmpty);
      expect(jsonDecode(body!)['stream'], isTrue);
    });
  });

  group('authentication and retries', () {
    test('missing credentials require sign-in before any request', () async {
      var calls = 0;
      final service = GrokService(
        oauthManager: oauth(),
        httpClient: MockClient.streaming((_, _) async {
          calls++;
          return _sse(_delta('ok'));
        }),
      );
      await expectLater(
        service.improveTranscription('raw'),
        throwsA(
          isA<CloudTranscriptionException>().having(
            (e) => e.message,
            'message',
            contains('sign-in required'),
          ),
        ),
      );
      expect(calls, 0);
    });

    test('verifySetup propagates the sign-in requirement unwrapped', () async {
      final service = GrokService(
        oauthManager: oauth(),
        httpClient: MockClient.streaming((_, _) async => _sse('')),
      );
      await expectLater(
        service.verifySetup(),
        throwsA(isA<XAiSignInRequiredException>()),
      );
    });

    test('a 401 forces one refresh and retries with the new token', () async {
      final manager = oauth();
      await manager.saveCredentials(_credentials(accessToken: 'at-stale'));

      final authorizations = <String?>[];
      final service = GrokService(
        oauthManager: manager,
        httpClient: MockClient.streaming((request, _) async {
          authorizations.add(request.headers['authorization']);
          if (authorizations.length == 1) return _sse('', status: 401);
          return _sse(_delta('fresh'));
        }),
      );

      expect(await service.improveTranscription('raw'), 'fresh');
      expect(authorizations, ['Bearer at-stale', 'Bearer at-refreshed']);
      expect(tokenBodies.single['grant_type'], 'refresh_token');
      expect(tokenBodies.single['refresh_token'], 'rt');
    });

    test('expired credentials refresh before the first request', () async {
      final manager = oauth();
      await manager.saveCredentials(
        _credentials(
          accessToken: 'at-expired',
          expiresAt: DateTime.now().toUtc().subtract(
            const Duration(minutes: 10),
          ),
        ),
      );

      String? authorization;
      final service = GrokService(
        oauthManager: manager,
        httpClient: MockClient.streaming((request, _) async {
          authorization = request.headers['authorization'];
          return _sse(_delta('ok'));
        }),
      );
      await service.improveTranscription('raw');
      expect(authorization, 'Bearer at-refreshed');
    });

    test('429 responses retry with bounded delays', () async {
      var calls = 0;
      final service = GrokService(
        oauthManager: await signedIn(),
        httpClient: MockClient.streaming((_, _) async {
          calls++;
          if (calls <= 2) return _sse('', status: 429);
          return _sse(_delta('ok'));
        }),
      );
      expect(await service.improveTranscription('raw'), 'ok');
      expect(calls, 3);
    });

    test('persistent 429 eventually surfaces the rate-limit error', () async {
      var calls = 0;
      final service = GrokService(
        oauthManager: await signedIn(),
        httpClient: MockClient.streaming((_, _) async {
          calls++;
          return _sse('', status: 429);
        }),
      );
      await expectLater(
        service.improveTranscription('raw'),
        throwsA(
          isA<CloudTranscriptionException>().having(
            (e) => e.message,
            'message',
            contains('rate-limiting'),
          ),
        ),
      );
      expect(calls, 4);
    });

    test('400 surfaces a safe processing error', () async {
      final service = GrokService(
        oauthManager: await signedIn(),
        httpClient: MockClient.streaming((_, _) async => _sse('', status: 400)),
      );
      await expectLater(
        service.improveTranscription('raw'),
        throwsA(
          isA<CloudTranscriptionException>().having(
            (e) => e.message,
            'message',
            contains('could not process'),
          ),
        ),
      );
    });
  });
}
