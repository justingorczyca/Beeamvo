import 'dart:convert';
import 'dart:io';

import 'package:beeamvo/config.dart';
import 'package:beeamvo/services/secure_credential_store.dart';
import 'package:beeamvo/services/settings_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<(SettingsService, File)> _initWith(
  Directory root,
  Map<String, dynamic> legacy, {
  InMemorySecureCredentialStore? store,
}) async {
  final folder = Directory('${root.path}/Beeamvo')..createSync(recursive: true);
  final file = File('${folder.path}/settings.json');
  await file.writeAsString(jsonEncode(legacy));
  final settings = SettingsService(
    applicationSupportDirectory: root,
    credentialStore: store ?? InMemorySecureCredentialStore(),
  );
  await settings.initialize();
  return (settings, file);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/package_info'),
        (call) async => {
          'appName': 'Beeamvo',
          'packageName': 'com.beeamvo.app',
          'version': '1.0.0',
          'buildNumber': '1',
          'buildSignature': '',
          'installerStore': '',
        },
      );

  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('beeamvo-providers-');
  });
  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  group('first-pass provider', () {
    test(
      'Codex is a first-pass provider with a transcription-only default',
      () async {
        final (settings, _) = await _initWith(root, {});
        expect(settings.cloudProvider, CloudProvider.geminiApiKey);
        expect(settings.selectedModelId, AppConfig.defaultModelId);
        await settings.setCloudProvider(CloudProvider.vertexAi);
        expect(settings.selectedModelId, AppConfig.defaultModelId);
        await settings.setCloudProvider(CloudProvider.codexOAuth);
        expect(settings.cloudProvider, CloudProvider.codexOAuth);
        expect(settings.selectedModelId, 'chatgpt-transcribe');
        expect(settings.primaryModels.map((model) => model.id), [
          'chatgpt-transcribe',
        ]);
        for (final provider in const [
          CloudProvider.openaiApiKey,
          CloudProvider.grokOAuth,
        ]) {
          expect(
            () => settings.setCloudProvider(provider),
            throwsArgumentError,
            reason: provider.name,
          );
          expect(AppConfig.audioModelsForProvider(provider), isEmpty);
        }
        expect(settings.cloudProvider, CloudProvider.codexOAuth);
      },
    );

    test(
      'Codex cannot resolve a transcription-only model for polish',
      () async {
        final (settings, _) = await _initWith(root, {
          'cloud_provider': 'codexOAuth',
          'legacy_primary_roles_migrated': true,
        });
        await settings.setTwoPassTranscriptionEnabled(true);
        await settings.setRefinementProvider(CloudProvider.codexOAuth);
        expect(settings.selectedModelId, 'chatgpt-transcribe');
        expect(
          settings.twoPassRefinementModelId,
          AppConfig.defaultCodexModelId,
        );
        expect(
          settings.refinementModels.any((model) => model.isTranscriptionOnly),
          isFalse,
        );
      },
    );

    test('the first-pass selection survives provider switches', () async {
      final (settings, file) = await _initWith(root, {
        'selected_model_id': 'gemini-3.5-transcribe',
      });
      await settings.setCloudProvider(CloudProvider.vertexAi);
      // Vertex cannot serve the dedicated speech model.
      expect(settings.selectedModelId, AppConfig.defaultModelId);
      await settings.setCloudProvider(CloudProvider.geminiApiKey);
      expect(settings.selectedModelId, 'gemini-3.5-transcribe');
      expect(
        jsonDecode(await file.readAsString())['selected_model_id'],
        'gemini-3.5-transcribe',
      );
    });

    test('foreign ids in the shared Gemini slot survive migration', () async {
      final (settings, file) = await _initWith(root, {
        'selected_model_id': 'gpt-transcribe',
      });
      // Not servable by Gemini, but still a known catalog id — kept on disk.
      expect(settings.selectedModelId, AppConfig.defaultModelId);
      expect(
        jsonDecode(await file.readAsString())['selected_model_id'],
        'gpt-transcribe',
      );
    });

    test(
      'the first-pass model list is stable across the two-step toggle',
      () async {
        final (settings, _) = await _initWith(root, {
          'selected_model_id': 'gemini-3.5-transcribe',
        });
        final singlePass = settings.primaryModels.map((m) => m.id).toList();
        expect(singlePass, contains('gemini-3.5-transcribe'));
        await settings.setTwoPassTranscriptionEnabled(true);
        expect(settings.primaryModels.map((m) => m.id), singlePass);
        await settings.setRefinementProvider(CloudProvider.grokOAuth);
        expect(settings.primaryModels.map((m) => m.id), singlePass);
        expect(settings.selectedModelId, 'gemini-3.5-transcribe');
      },
    );
  });

  group('polish provider', () {
    test('defaults to the first-pass provider until chosen', () async {
      final (settings, file) = await _initWith(root, {});
      expect(settings.refinementProvider, CloudProvider.geminiApiKey);
      await settings.setCloudProvider(CloudProvider.vertexAi);
      expect(settings.refinementProvider, CloudProvider.vertexAi);
      await settings.setRefinementProvider(CloudProvider.geminiApiKey);
      await settings.setCloudProvider(CloudProvider.vertexAi);
      expect(settings.refinementProvider, CloudProvider.geminiApiKey);
      expect(
        jsonDecode(await file.readAsString())['refinement_provider'],
        'geminiApiKey',
      );
    });

    for (final provider in CloudProvider.values) {
      test('${provider.name} is selectable for pass 2', () async {
        final (settings, _) = await _initWith(root, {});
        await settings.setRefinementProvider(provider);
        expect(settings.refinementProvider, provider);
        expect(
          settings.refinementModels,
          AppConfig.promptCapableModelsForProvider(provider),
        );
        expect(settings.refinementModels, isNotEmpty);
        expect(
          settings.refinementModels.any((m) => m.isTranscriptionOnly),
          isFalse,
        );
        expect(
          settings.twoPassRefinementModelId,
          AppConfig.defaultModelIdForProvider(provider),
        );
        // The first pass is untouched by the pass-2 choice.
        expect(settings.cloudProvider, CloudProvider.geminiApiKey);
      });
    }

    test('refinement models are stored per provider', () async {
      final (settings, file) = await _initWith(root, {});
      await settings.setRefinementProvider(CloudProvider.codexOAuth);
      await settings.setTwoPassRefinementModelId('gpt-5-6-thinking');
      await settings.setRefinementProvider(CloudProvider.grokOAuth);
      await settings.setTwoPassRefinementModelId('grok-4.7');
      await settings.setRefinementProvider(CloudProvider.geminiApiKey);
      await settings.setTwoPassRefinementModelId('gemini-2.5-flash');

      await settings.setRefinementProvider(CloudProvider.codexOAuth);
      expect(settings.twoPassRefinementModelId, 'gpt-5-6-thinking');
      await settings.setRefinementProvider(CloudProvider.grokOAuth);
      expect(settings.twoPassRefinementModelId, 'grok-4.7');
      final persisted = jsonDecode(await file.readAsString()) as Map;
      expect(persisted['two_pass_refinement_model_id'], 'gemini-2.5-flash');
      expect(
        persisted['two_pass_refinement_model_id_codex'],
        'gpt-5-6-thinking',
      );
      expect(persisted['two_pass_refinement_model_id_grok'], 'grok-4.7');
    });

    test('rejects models the polish provider cannot serve', () async {
      final (settings, _) = await _initWith(root, {});
      await settings.setRefinementProvider(CloudProvider.openaiApiKey);
      for (final id in const ['gpt-transcribe', 'gemini-3.7-flash']) {
        expect(
          () => settings.setTwoPassRefinementModelId(id),
          throwsArgumentError,
          reason: id,
        );
      }
    });

    test('a foreign id in a polish slot resolves to the default', () async {
      final (settings, _) = await _initWith(root, {
        'refinement_provider': 'openaiApiKey',
        'two_pass_refinement_model_id_openai': 'gemini-3-flash',
      });
      expect(settings.twoPassRefinementModelId, AppConfig.defaultOpenAiModelId);
    });
  });

  group('two-step readiness', () {
    test('gates recording on both stage credentials', () async {
      final (settings, _) = await _initWith(root, {
        'codex_cli_import_disabled': true,
      });
      expect(settings.isTranscriptionReady, isFalse);
      expect(settings.transcriptionSetupIssue, contains('Gemini API key'));
      await settings.setGeminiApiKey('gk');
      expect(settings.isTranscriptionReady, isTrue);

      await settings.setTwoPassTranscriptionEnabled(true);
      await settings.setRefinementProvider(CloudProvider.codexOAuth);
      expect(settings.isTranscriptionReady, isFalse);
      expect(settings.transcriptionSetupIssue, contains('Sign in to ChatGPT'));
      await settings.setRefinementProvider(CloudProvider.openaiApiKey);
      expect(settings.transcriptionSetupIssue, contains('OpenAI API key'));
      await settings.setOpenAiApiKey('sk');
      expect(settings.isTranscriptionReady, isTrue);
      expect(settings.promptIsApplied, isTrue);
    });

    test('offline two-step only needs the polish credentials', () async {
      final (settings, _) = await _initWith(root, {
        'transcription_backend': 'whisper',
        'two_pass_transcription': true,
        'refinement_provider': 'openaiApiKey',
      });
      expect(settings.isTranscriptionReady, isFalse);
      await settings.setOpenAiApiKey('sk');
      expect(settings.isTranscriptionReady, isTrue);
      await settings.setTwoPassTranscriptionEnabled(false);
      await settings.clearOpenAiApiKey();
      expect(settings.isTranscriptionReady, isTrue);
    });
  });

  group('OpenAI credentials and base URL', () {
    test('API key round-trips through the secure store', () async {
      final (settings, _) = await _initWith(root, {});
      expect(settings.hasOpenAiApiKey, isFalse);
      await settings.setOpenAiApiKey(' sk-test ');
      expect(await settings.readOpenAiApiKey(), 'sk-test');
      expect(settings.hasOpenAiApiKey, isTrue);
      await settings.clearOpenAiApiKey();
      expect(settings.hasOpenAiApiKey, isFalse);
      expect(await settings.readOpenAiApiKey(), isNull);
    });

    test('base URL persists trimmed and clears on empty', () async {
      final (settings, _) = await _initWith(root, {});
      expect(settings.openAiBaseUrl, isNull);
      await settings.setOpenAiBaseUrl(' https://proxy.example.com/v1 ');
      expect(settings.openAiBaseUrl, 'https://proxy.example.com/v1');
      await settings.setOpenAiBaseUrl('');
      expect(settings.openAiBaseUrl, isNull);
    });
  });

  group('hasCloudCredentials', () {
    test('follows the selected provider', () async {
      final store = InMemorySecureCredentialStore();
      await store.writeGeminiApiKey('gk');
      final (settings, _) = await _initWith(root, {
        'codex_cli_import_disabled': true,
      }, store: store);

      expect(settings.hasCloudCredentials, isTrue);

      await settings.setCloudProvider(CloudProvider.vertexAi);
      expect(settings.hasCloudCredentials, isFalse);
      await settings.setVertexProjectId('project-1');
      expect(settings.hasCloudCredentials, isTrue);

      // Polish-provider credentials are tracked separately.
      await settings.setRefinementProvider(CloudProvider.openaiApiKey);
      expect(settings.hasCloudCredentials, isTrue);
      expect(settings.hasRefinementCredentials, isFalse);
      await settings.setOpenAiApiKey('sk');
      expect(settings.hasRefinementCredentials, isTrue);
      await settings.setRefinementProvider(CloudProvider.codexOAuth);
      expect(settings.hasRefinementCredentials, isFalse);
      await settings.setRefinementProvider(CloudProvider.grokOAuth);
      expect(settings.hasRefinementCredentials, isFalse);
    });
  });

  group('Grok auth state', () {
    test('sign-out clears the stored credentials and auth state', () async {
      final store = InMemorySecureCredentialStore();
      final now = DateTime.now().toUtc().toIso8601String();
      await store.writeApiKey(
        'xai_oauth_credentials',
        jsonEncode({
          'accessToken': 'at',
          'refreshToken': 'rt',
          'expiresAt': now,
          'createdAt': now,
          'updatedAt': now,
        }),
      );
      final (settings, _) = await _initWith(root, {
        'cloud_provider': 'grokOAuth',
      }, store: store);
      expect(settings.hasGrokAuth, isTrue);
      expect(settings.refinementProvider, CloudProvider.grokOAuth);
      expect(settings.hasRefinementCredentials, isTrue);

      await settings.signOutGrok();
      expect(settings.hasGrokAuth, isFalse);
      expect(settings.hasRefinementCredentials, isFalse);
    });
  });

  group('Codex auth state', () {
    test(
      'sign-out clears state and persists the import-disabled flag',
      () async {
        final store = InMemorySecureCredentialStore();
        final now = DateTime.now().toUtc().toIso8601String();
        await store.writeApiKey(
          'codex_oauth_credentials',
          jsonEncode({
            'accessToken': 'at',
            'refreshToken': 'rt',
            'expiresAt': now,
            'createdAt': now,
            'updatedAt': now,
          }),
        );
        final (settings, file) = await _initWith(root, {
          'cloud_provider': 'codexOAuth',
          // Keep the test deterministic on machines that have a real
          // ~/.codex/auth.json: only the stored credential set may load.
          'codex_cli_import_disabled': true,
        }, store: store);
        expect(settings.hasCodexAuth, isTrue);
        expect(settings.hasRefinementCredentials, isTrue);

        await settings.signOutCodex();
        expect(settings.hasCodexAuth, isFalse);
        expect(settings.hasRefinementCredentials, isFalse);
        expect(
          jsonDecode(await file.readAsString())['codex_cli_import_disabled'],
          isTrue,
        );
      },
    );
  });
}
