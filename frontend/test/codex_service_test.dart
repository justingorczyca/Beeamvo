import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:beeamvo/config.dart';
import 'package:beeamvo/services/cloud_transcription_client.dart';
import 'package:beeamvo/services/codex_oauth_manager.dart';
import 'package:beeamvo/services/codex_service.dart';
import 'package:beeamvo/services/secure_credential_store.dart';
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

CodexCredentials _credentials({
  String accessToken = 'at-valid',
  DateTime? expiresAt,
  String? accountId = 'acct-1',
}) {
  final now = DateTime.now().toUtc();
  return CodexCredentials(
    accessToken: accessToken,
    refreshToken: 'rt',
    expiresAt: expiresAt ?? now.add(const Duration(hours: 1)),
    accountId: accountId,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late Directory codexDir;
  late InMemorySecureCredentialStore store;
  late List<Map<String, dynamic>> tokenBodies;

  setUp(() async {
    codexDir = await Directory.systemTemp.createTemp('beeamvo-codex-svc-');
    store = InMemorySecureCredentialStore();
    tokenBodies = <Map<String, dynamic>>[];
  });
  tearDown(() async {
    if (codexDir.existsSync()) await codexDir.delete(recursive: true);
  });

  CodexOAuthManager oauth({http.Client? tokenClient}) {
    return CodexOAuthManager(
      credentialStore: store,
      codexDirOverride: codexDir.path,
      client:
          tokenClient ??
          MockClient((request) async {
            tokenBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
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

  Future<CodexOAuthManager> signedIn() async {
    final manager = oauth();
    await manager.saveCredentials(_credentials());
    return manager;
  }

  group('payloads', () {
    test('improve payload is stream-only Responses wire format', () {
      final service = CodexService(
        httpClient: MockClient.streaming((_, _) async => _sse('')),
      );
      final payload = service.buildImprovePayload(
        'raw text',
        missionInstruction: 'Be concise.',
        model: AppConfig.getModelById('gpt-5.6-sol'),
        thinkingLevelOverride: GeminiThinkingLevel.high,
      );

      expect(payload['model'], 'gpt-5.6-sol');
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

    test('foreign model overrides resolve to the Codex catalog', () {
      final service = CodexService(
        httpClient: MockClient.streaming((_, _) async => _sse('')),
      );
      final payload = service.buildImprovePayload(
        'raw',
        missionInstruction: 'x',
        model: AppConfig.getModelById(AppConfig.defaultCodexModelId),
      );
      expect(payload['model'], AppConfig.defaultCodexModelId);
      // setModelById must not let a foreign id replace the Codex model.
      service.setModelById('gpt-5.4-mini');
      expect(service.currentModel.id, AppConfig.defaultCodexModelId);
      service.setModelById('gpt-5-6-thinking');
      expect(service.currentModel.id, 'gpt-5-6-thinking');
    });

    test('a model defaulting to none sends reasoning.effort none', () {
      final service = CodexService(
        httpClient: MockClient.streaming((_, _) async => _sse('')),
      );
      final payload = service.buildImprovePayload(
        'raw',
        missionInstruction: 'x',
        model: AppConfig.getModelById('gpt-5.6-luna'),
      );
      expect(payload['reasoning'], {'effort': 'none'});
    });

    test('none override passes through; unsupported levels fall back', () {
      final service = CodexService(
        httpClient: MockClient.streaming((_, _) async => _sse('')),
      );
      final model = AppConfig.getModelById('gpt-5.6-sol');
      final nonePayload = service.buildImprovePayload(
        'raw',
        missionInstruction: 'x',
        model: model,
        thinkingLevelOverride: GeminiThinkingLevel.none,
      );
      expect(nonePayload['reasoning'], {'effort': 'none'});

      // gpt-5.6-sol does not offer 'minimal'; resolution falls back to the
      // model default (low).
      final minimalPayload = service.buildImprovePayload(
        'raw',
        missionInstruction: 'x',
        model: model,
        thinkingLevelOverride: GeminiThinkingLevel.minimal,
      );
      expect(minimalPayload['reasoning'], {'effort': 'low'});
    });

    test('chat-latest omits the reasoning block entirely', () {
      final service = CodexService(
        httpClient: MockClient.streaming((_, _) async => _sse('')),
      );
      final payload = service.buildImprovePayload(
        'raw',
        missionInstruction: 'x',
        model: AppConfig.getModelById('chat-latest'),
      );
      expect(payload.containsKey('reasoning'), isFalse);
    });

    test('an unsupported none override clamps to the model default', () {
      final service = CodexService(
        httpClient: MockClient.streaming((_, _) async => _sse('')),
      );
      // gpt-6-astra does not offer 'none'; resolution falls back to low.
      final payload = service.buildImprovePayload(
        'raw',
        missionInstruction: 'x',
        model: AppConfig.getModelById('gpt-6-astra'),
        thinkingLevelOverride: GeminiThinkingLevel.none,
      );
      expect(payload['reasoning'], {'effort': 'low'});
    });

    test('GPT-6 and GPT-5.6 models send xhigh and max reasoning effort', () {
      final service = CodexService(
        httpClient: MockClient.streaming((_, _) async => _sse('')),
      );
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
            missionInstruction: 'x',
            model: AppConfig.getModelById(id),
            thinkingLevelOverride: level,
          );
          expect(payload['reasoning'], {'effort': wire}, reason: id);
        }
      }
    });

    test('models without xhigh/max clamp them to their default', () {
      final service = CodexService(
        httpClient: MockClient.streaming((_, _) async => _sse('')),
      );
      final payload = service.buildImprovePayload(
        'raw',
        missionInstruction: 'x',
        model: AppConfig.getModelById('gpt-5.5'),
        thinkingLevelOverride: GeminiThinkingLevel.max,
      );
      expect(payload['reasoning'], {'effort': 'low'});
    });
  });

  group('audio surface', () {
    test(
      'audio entry points fail with a clear Codex limitation error',
      () async {
        final service = CodexService(
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
      final service = CodexService(
        oauthManager: await signedIn(),
        httpClient: MockClient.streaming(
          (_, _) async => _sse('${_delta('Hel')}${_delta('lo')}'),
        ),
      );
      expect(await service.improveTranscription('raw'), 'Hello');
    });

    test('falls back to response.completed when no deltas arrive', () async {
      final service = CodexService(
        oauthManager: await signedIn(),
        httpClient: MockClient.streaming(
          (_, _) async => _sse(_completed('completed text')),
        ),
      );
      expect(await service.improveTranscription('raw'), 'completed text');
    });

    test('error and response.failed events surface their message', () async {
      final errorService = CodexService(
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
        errorService.improveTranscription('raw'),
        throwsA(
          isA<CloudTranscriptionException>().having(
            (e) => e.message,
            'message',
            contains('boom'),
          ),
        ),
      );

      final failedService = CodexService(
        oauthManager: await signedIn(),
        httpClient: MockClient.streaming(
          (_, _) async => _sse(
            'data: ${jsonEncode({
              'type': 'response.failed',
              'response': {
                'error': {'message': 'model overloaded'},
              },
            })}\n\n',
          ),
        ),
      );
      await expectLater(
        failedService.improveTranscription('raw'),
        throwsA(
          isA<CloudTranscriptionException>().having(
            (e) => e.message,
            'message',
            contains('model overloaded'),
          ),
        ),
      );
    });

    test('an empty stream is a clear empty-response error', () async {
      final service = CodexService(
        oauthManager: await signedIn(),
        httpClient: MockClient.streaming((_, _) async => _sse('')),
      );
      await expectLater(
        service.improveTranscription('raw'),
        throwsA(
          isA<CloudTranscriptionException>().having(
            (e) => e.message,
            'message',
            contains('empty response'),
          ),
        ),
      );
    });

    test('requests carry Codex headers and stream accept', () async {
      http.BaseRequest? captured;
      String? body;
      final service = CodexService(
        oauthManager: await signedIn(),
        httpClient: MockClient.streaming((request, requestBody) async {
          captured = request;
          body = await requestBody.bytesToString();
          return _sse(_delta('ok'));
        }),
      );
      await service.improveTranscription('raw');

      expect(captured!.url.path, '/backend-api/codex/responses');
      expect(captured!.headers['authorization'], 'Bearer at-valid');
      expect(captured!.headers['accept'], 'text/event-stream');
      expect(captured!.headers['originator'], 'beeamvo');
      expect(captured!.headers['session_id'], isNotEmpty);
      expect(captured!.headers['ChatGPT-Account-Id'], 'acct-1');
      expect(jsonDecode(body!)['stream'], isTrue);
    });
  });

  group('authentication and retries', () {
    test('missing credentials require sign-in before any request', () async {
      var calls = 0;
      final service = CodexService(
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
      final service = CodexService(
        oauthManager: oauth(),
        httpClient: MockClient.streaming((_, _) async => _sse('')),
      );
      await expectLater(
        service.verifySetup(),
        throwsA(isA<CodexSignInRequiredException>()),
      );
    });

    test('a 401 forces one refresh and retries with the new token', () async {
      final manager = oauth();
      await manager.saveCredentials(_credentials(accessToken: 'at-stale'));

      final authorizations = <String?>[];
      final service = CodexService(
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
      final service = CodexService(
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
      final service = CodexService(
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
      final service = CodexService(
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
      final service = CodexService(
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
