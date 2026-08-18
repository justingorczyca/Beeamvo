import 'dart:convert';
import 'dart:typed_data';

import 'package:beeamvo/config.dart';
import 'package:beeamvo/models/openai_compatible_provider.dart';
import 'package:beeamvo/services/cloud_transcription_client.dart';
import 'package:beeamvo/services/openai_compatible_service.dart';
import 'package:beeamvo/services/secure_credential_store.dart';
import 'package:beeamvo/services/settings_service.dart';
import 'package:beeamvo/services/transcription_result_guard.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

OpenAiCompatibleModel _textModel() => const OpenAiCompatibleModel(
  id: 'text-model',
  displayName: 'Text model',
  maxOutputTokens: 256,
  supportsReasoningEffort: true,
  defaultReasoningEffort: OpenAiReasoningEffort.low,
  supportedReasoningEfforts: [
    OpenAiReasoningEffort.minimal,
    OpenAiReasoningEffort.low,
  ],
);

OpenAiCompatibleModel _audioModel() => const OpenAiCompatibleModel(
  id: 'audio-model',
  displayName: 'Audio model',
  supportsAudioInput: true,
  maxOutputTokens: 512,
);

OpenAiCompatibleProvider _provider({
  bool transcriptions = false,
  bool supportsTemperature = true,
  OpenAiTokenLimitParam tokenLimitParam =
      OpenAiTokenLimitParam.maxCompletionTokens,
}) => OpenAiCompatibleProvider(
  id: 'test-provider',
  displayName: 'Test Provider',
  defaultBaseUrl: 'https://example.test/api/v1',
  models: [_textModel(), _audioModel()],
  tokenLimitParam: tokenLimitParam,
  supportsReasoningEffort: true,
  supportsTemperature: supportsTemperature,
  supportsTranscriptionsEndpoint: transcriptions,
  transcriptionModelId: transcriptions ? 'stt-model' : null,
  extraHeaders: const {'X-Test': 'value'},
);

OpenAiCompatibleService _service({
  http.Client? client,
  bool transcriptions = false,
  bool supportsTemperature = true,
  OpenAiCompatibleModel? model,
  Future<String?> Function()? apiKeySupplier,
}) {
  final provider = _provider(
    transcriptions: transcriptions,
    supportsTemperature: supportsTemperature,
  );
  return OpenAiCompatibleService(
    config: OpenAiCompatibleServiceConfig(
      provider: provider,
      model: model ?? _textModel(),
      baseUrl: provider.defaultBaseUrl,
      apiKeySupplier: apiKeySupplier ?? (() async => 'secret-key'),
    ),
    httpClient: client,
  );
}

void main() {
  group('provider data', () {
    test('wire names and reasoning mappings are provider-neutral', () {
      expect(OpenAiTokenLimitParam.maxTokens.wireName, 'max_tokens');
      expect(
        OpenAiTokenLimitParam.maxCompletionTokens.wireName,
        'max_completion_tokens',
      );
      expect(OpenAiReasoningEffort.high.apiValue, 'high');
      expect(
        GeminiThinkingLevel.medium.openAiReasoningEffort,
        OpenAiReasoningEffort.medium,
      );
      expect(OpenAiCompatibleProviderRegistry.builtIn, isEmpty);
    });

    test('model capability fields and lookup are preserved', () {
      final provider = _provider();
      expect(provider.models.last.supportsAudioInput, isTrue);
      expect(
        OpenAiCompatibleProviderRegistry.modelById(provider, 'audio-model'),
        isNotNull,
      );
      expect(
        OpenAiCompatibleProviderRegistry.modelById(provider, 'missing'),
        isNull,
      );
    });
  });

  group('base URLs', () {
    test('normalizes paths and preserves provider prefixes', () {
      expect(
        normalizeBaseUrl(' https://openrouter.ai/api/v1/// '),
        'https://openrouter.ai/api/v1',
      );
      expect(
        normalizeBaseUrl('http://localhost:8080///'),
        'http://localhost:8080',
      );
      expect(
        normalizeBaseUrl('http://127.0.0.1:1234/v1/'),
        'http://127.0.0.1:1234/v1',
      );
    });

    test('rejects insecure remote and relative URLs', () {
      expect(
        () => normalizeBaseUrl('http://remote.example/v1'),
        throwsA(isA<CloudTranscriptionException>()),
      );
      expect(
        () => normalizeBaseUrl('/api/v1'),
        throwsA(isA<CloudTranscriptionException>()),
      );
    });

    test('rejects URLs containing a completions endpoint', () {
      for (final value in [
        'https://example.test/v1/chat/completions',
        'https://example.test/v1/completions/',
      ]) {
        expect(
          () => normalizeBaseUrl(value),
          throwsA(
            predicate<CloudTranscriptionException>(
              (error) => error.message.contains('base URL'),
            ),
          ),
        );
      }
    });

    test('rejects an invalid override when resolving service config', () {
      final provider = _provider();
      expect(
        () => OpenAiCompatibleService(
          config: OpenAiCompatibleServiceConfig(
            provider: provider,
            model: _textModel(),
            baseUrlOverride: 'http://remote.example/v1',
            apiKeySupplier: () async => 'key',
          ),
        ),
        throwsA(isA<CloudTranscriptionException>()),
      );
    });
  });

  group('chat payloads', () {
    test('builds refine payload with auth only in headers', () {
      final service = _service();
      final payload = service.buildImprovePayload(
        'quoted draft',
        missionInstruction: 'Make it concise.',
        model: _textModel(),
      );
      final encoded = jsonEncode(payload);
      expect(payload['stream'], isFalse);
      expect((payload['messages'] as List).first['role'], 'system');
      expect(encoded, isNot(contains('secret-key')));
      expect(payload['max_completion_tokens'], 256);
      expect(payload['reasoning_effort'], 'low');
      expect(
        service.buildHeaders('secret-key')['Authorization'],
        contains('secret-key'),
      );
      expect(service.buildHeaders('secret-key')['X-Test'], 'value');
      service.dispose();
    });

    test('gates temperature, token and reasoning fields', () {
      final service = _service(supportsTemperature: false);
      final payload = service.buildImprovePayload(
        'draft',
        missionInstruction: 'mission',
        model: _textModel(),
        reasoningEffortOverride: OpenAiReasoningEffort.minimal,
      );
      expect(payload.containsKey('temperature'), isFalse);
      expect(payload['max_completion_tokens'], 256);
      expect(payload['reasoning_effort'], 'minimal');
      service.dispose();
    });

    test('uses the provider-selected legacy token parameter', () {
      final provider = _provider(
        tokenLimitParam: OpenAiTokenLimitParam.maxTokens,
      );
      final service = OpenAiCompatibleService(
        config: OpenAiCompatibleServiceConfig(
          provider: provider,
          model: _textModel(),
          baseUrl: provider.defaultBaseUrl,
          apiKeySupplier: () async => 'key',
        ),
      );
      final payload = service.buildImprovePayload(
        'draft',
        missionInstruction: 'mission',
        model: _textModel(),
      );
      expect(payload['max_tokens'], 256);
      expect(payload.containsKey('max_completion_tokens'), isFalse);
      service.dispose();
    });

    test('builds audio content parts and uses the no-speech guard', () {
      final service = _service();
      final payload = service.buildTranscribeAndImprovePayload(
        audioData: Uint8List.fromList([1, 2, 3]),
        mimeType: 'audio/wav',
        missionInstruction: 'mission',
        model: _audioModel(),
      );
      final user = (payload['messages'] as List)[1] as Map;
      final content = user['content'] as List;
      expect(content[0]['type'], 'text');
      expect(content[1]['type'], 'input_audio');
      expect(content[1]['input_audio']['format'], 'wav');
      expect(
        content[0]['text'],
        contains(TranscriptionResultGuard.noTranscriptPromptInstruction),
      );
      service.dispose();
    });

    test('maps audio MIME types and rejects unsupported formats', () {
      final service = _service();
      expect(service.audioFormatForMimeType('audio/x-wav'), 'wav');
      expect(service.audioFormatForMimeType('audio/mp3'), 'mp3');
      expect(
        () => service.audioFormatForMimeType('audio/ogg'),
        throwsA(isA<CloudTranscriptionException>()),
      );
      service.dispose();
    });

    test('rejects a non-audio model without degrading silently', () {
      final service = _service();
      expect(
        () => service.buildTranscribePayload(
          audioData: Uint8List.fromList([1]),
          mimeType: 'audio/wav',
          model: _textModel(),
        ),
        throwsA(
          predicate<CloudTranscriptionException>(
            (error) =>
                error.message.contains('audio-capable') &&
                error.message.contains('offline Whisper'),
          ),
        ),
      );
      service.dispose();
    });

    test('rejects an inline payload over the provider cap', () async {
      final provider = _provider();
      final service = OpenAiCompatibleService(
        config: OpenAiCompatibleServiceConfig(
          provider: OpenAiCompatibleProvider(
            id: provider.id,
            displayName: provider.displayName,
            defaultBaseUrl: provider.defaultBaseUrl,
            models: provider.models,
            tokenLimitParam: provider.tokenLimitParam,
            supportsReasoningEffort: provider.supportsReasoningEffort,
            maxInlineRequestBytes: 1,
          ),
          model: _audioModel(),
          baseUrl: provider.defaultBaseUrl,
          apiKeySupplier: () async => 'key',
        ),
      );
      await expectLater(
        service.transcribeAudio(Uint8List.fromList([1]), 'audio/wav'),
        throwsA(isA<CloudTranscriptionException>()),
      );
      service.dispose();
    });
  });

  group('response parsing and transport', () {
    test('parses string and multipart text content', () {
      final service = _service();
      expect(
        service.parseChatResponse(
          http.Response(
            '{"choices":[{"message":{"content":"hello"},"finish_reason":"stop"}]}',
            200,
          ),
        ),
        'hello',
      );
      expect(
        service.parseChatResponse(
          http.Response(
            '{"choices":[{"message":{"content":[{"type":"text","text":"a"},{"type":"text","text":"b"}],"reasoning":"ignored","reasoning_content":"ignored"},"finish_reason":"stop"}]}',
            200,
          ),
        ),
        'ab',
      );
      service.dispose();
    });

    test('handles empty, malformed and non-stop responses', () {
      final service = _service();
      expect(
        () => service.parseChatResponse(
          http.Response(
            '{"choices":[{"message":{"content":""},"finish_reason":"stop"}]}',
            200,
          ),
        ),
        throwsA(isA<CloudTranscriptionException>()),
      );
      expect(
        () => service.parseChatResponse(http.Response('{bad', 200)),
        throwsA(isA<CloudTranscriptionException>()),
      );
      expect(
        service.parseChatResponse(
          http.Response(
            '{"choices":[{"message":{"content":"partial"},"finish_reason":"length"}]}',
            200,
          ),
        ),
        'partial',
      );
      for (final finishReason in ['end_turn', 'STOP', null]) {
        final encodedReason = finishReason == null
            ? 'null'
            : jsonEncode(finishReason);
        expect(
          service.parseChatResponse(
            http.Response(
              '{"choices":[{"message":{"content":"complete"},"finish_reason":$encodedReason}]}',
              200,
            ),
          ),
          'complete',
        );
      }
      expect(
        () => service.parseChatResponse(
          http.Response(
            '{"choices":[{"message":{"content":""},"finish_reason":"length"}]}',
            200,
          ),
        ),
        throwsA(
          predicate<CloudTranscriptionException>(
            (error) => error.message.contains('length'),
          ),
        ),
      );
      service.dispose();
    });

    test('maps non-success status without exposing the body', () {
      final service = _service();
      expect(
        () => service.parseChatResponse(
          http.Response('DO NOT SHOW THIS SECRET BODY', 401),
        ),
        throwsA(
          predicate<CloudTranscriptionException>(
            (error) =>
                error.message.contains('Invalid API key') &&
                !error.message.contains('DO NOT SHOW'),
          ),
        ),
      );
      service.dispose();
    });

    test('builds chat URI and sends request with key in header', () async {
      late http.BaseRequest request;
      final service = _service(
        client: MockClient((incoming) async {
          request = incoming;
          return http.Response(
            '{"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}',
            200,
          );
        }),
      );
      expect(await service.improveTranscription('draft'), 'ok');
      expect(request.url.toString(), endsWith('/api/v1/chat/completions'));
      expect(request.headers['authorization'], 'Bearer secret-key');
      final body = (request as http.Request).body;
      expect(body, isNot(contains('secret-key')));
      service.dispose();
    });

    test('honors Retry-After and retries a transient response', () async {
      var attempts = 0;
      final service = _service(
        client: MockClient((_) async {
          attempts++;
          if (attempts == 1) {
            return http.Response(
              'rate limited',
              429,
              headers: {'retry-after': '0'},
            );
          }
          return http.Response(
            '{"choices":[{"message":{"content":"ok"},"finish_reason":"stop"}]}',
            200,
          );
        }),
      );
      expect(await service.improveTranscription('draft'), 'ok');
      expect(attempts, 2);
      service.dispose();
    });

    test('rebuilds multipart transcription requests for retries', () async {
      var attempts = 0;
      final requests = <http.Request>[];
      final service = _service(
        transcriptions: true,
        client: MockClient((request) async {
          attempts++;
          requests.add(request);
          if (attempts == 1) {
            return http.Response('busy', 503, headers: {'retry-after': '0'});
          }
          return http.Response('{"text":"transcribed"}', 200);
        }),
      );
      expect(
        await service.transcribeAudio(
          Uint8List.fromList([1, 2]),
          'audio/wav',
          modelOverrideId: 'audio-model',
        ),
        'transcribed',
      );
      expect(attempts, 2);
      expect(
        requests[0].headers['content-type'],
        startsWith('multipart/form-data'),
      );
      expect(requests[0].body, contains('response_format'));
      expect(requests[0].body, contains('stt-model'));
      expect(requests[0].body, isNot(contains('audio-model')));
      expect(requests[0].body, contains('audio.wav'));
      expect(requests[1].body, contains('audio.wav'));
      service.dispose();
    });
  });

  group('credentials and settings', () {
    test('isolates keyed credentials and preserves Gemini account', () async {
      final store = InMemorySecureCredentialStore();
      await store.writeGeminiApiKey('gemini');
      await store.writeApiKey(
        openAiCompatibleApiKeyAccount('open-router'),
        'openrouter',
      );
      expect(await store.readGeminiApiKey(), 'gemini');
      expect(
        await store.readApiKey(openAiCompatibleApiKeyAccount('open-router')),
        'openrouter',
      );
      expect(
        () => openAiCompatibleApiKeyAccount('Gemini'),
        throwsArgumentError,
      );
      expect(
        () => openAiCompatibleApiKeyAccount('gemini_api_key'),
        returnsNormally,
      );
    });

    test('round trips provider settings and keyed API keys', () async {
      final settings = SettingsService(
        credentialStore: InMemorySecureCredentialStore(),
      );
      await settings.setSelectedOpenAiCompatibleProviderId('open-router');
      await settings.setSelectedOpenAiCompatibleModelId('model');
      await settings.setOpenAiCompatibleBaseUrlOverride(
        'open-router',
        'https://openrouter.ai/api/v1',
      );
      await settings.setOpenAiCompatibleApiKey('open-router', 'key');
      expect(settings.selectedOpenAiCompatibleProviderId, 'open-router');
      expect(settings.selectedOpenAiCompatibleModelId, 'model');
      expect(
        settings.getOpenAiCompatibleBaseUrlOverride('open-router'),
        'https://openrouter.ai/api/v1',
      );
      expect(await settings.readOpenAiCompatibleApiKey('open-router'), 'key');
      expect(settings.hasOpenAiCompatibleApiKey('open-router'), isTrue);
      await settings.clearOpenAiCompatibleApiKey('open-router');
      expect(settings.hasOpenAiCompatibleApiKey('open-router'), isFalse);
      await settings.setOpenAiCompatibleBaseUrlOverride('open-router', null);
      expect(
        settings.getOpenAiCompatibleBaseUrlOverride('open-router'),
        isNull,
      );
      settings.dispose();
    });
  });
}
