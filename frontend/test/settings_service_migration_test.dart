import 'dart:convert';
import 'dart:io';

import 'package:beeamvo/config.dart';
import 'package:beeamvo/models/system_prompt.dart';
import 'package:beeamvo/services/secure_credential_store.dart';
import 'package:beeamvo/services/settings_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

Future<(SettingsService, File)> _initWith(
  Directory root,
  Map<String, dynamic> legacy,
) async {
  final folder = Directory('${root.path}/Beeamvo')..createSync(recursive: true);
  final file = File('${folder.path}/settings.json');
  await file.writeAsString(jsonEncode(legacy));
  final settings = SettingsService(
    applicationSupportDirectory: root,
    credentialStore: InMemorySecureCredentialStore(),
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
    root = await Directory.systemTemp.createTemp('beeamvo-migration-');
  });
  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  test('legacy rephraser maps the default prompt to Professional', () async {
    final (settings, file) = await _initWith(root, {
      'rephrase_level': 'medium',
      'active_system_prompt_id': SystemPrompt.defaultId,
    });
    expect(settings.selectedPromptId, SystemPrompt.professionalId);
    final persisted = jsonDecode(await file.readAsString());
    expect(persisted.containsKey('rephrase_level'), isFalse);
  });

  test('legacy rephraser never overrides an explicit prompt choice', () async {
    final (settings, _) = await _initWith(root, {
      'rephrase_level': 'medium',
      'active_system_prompt_id': 'concise',
    });
    expect(settings.selectedPromptId, 'concise');
  });

  test('cloud and whisper languages merge into spoken_language', () async {
    final (settings, file) = await _initWith(root, {
      'transcription_language': 'de',
      'whisper_language': 'fr',
    });
    expect(settings.spokenLanguage, 'de');
    final persisted = jsonDecode(await file.readAsString());
    expect(persisted['spoken_language'], 'de');
    expect(persisted.containsKey('transcription_language'), isFalse);
    expect(persisted.containsKey('whisper_language'), isFalse);
  });

  test('whisper language is used when no cloud language existed', () async {
    final (settings, _) = await _initWith(root, {'whisper_language': 'fr'});
    expect(settings.spokenLanguage, 'fr');
  });

  test('retired expert settings are removed from disk', () async {
    final (_, file) = await _initWith(root, {
      'transcription_mode': 'verbatim',
      'transcription_diarization': true,
      'transcription_word_timestamps': true,
      'gemini_api_surface': 'interactions',
      'openai_compatible_provider_id': 'x',
      'openai_compatible_model_id': 'y',
      'openai_compatible_base_url_x': 'https://example.invalid',
      'prompt_overrides': '{}',
      'transcription_custom_vocabulary': 'Beeamvo',
    });
    final persisted = jsonDecode(await file.readAsString()) as Map;
    for (final key in [
      'transcription_mode',
      'transcription_diarization',
      'transcription_word_timestamps',
      'gemini_api_surface',
      'openai_compatible_provider_id',
      'openai_compatible_model_id',
      'openai_compatible_base_url_x',
      'prompt_overrides',
      'transcription_custom_vocabulary',
    ]) {
      expect(persisted.containsKey(key), isFalse, reason: key);
    }
  });

  test('a stored step-2 refinement preference survives migration', () async {
    final (settings, _) = await _initWith(root, {
      'selected_model_id': 'gemini-3.5-transcribe',
      'two_pass_refinement_model_id': 'gemini-3.7-flash',
    });
    expect(settings.twoPassTranscriptionEnabled, isFalse);
    expect(settings.selectedModelId, 'gemini-3.5-transcribe');
    expect(settings.twoPassRefinementModelId, 'gemini-3.7-flash');

    // A transcription-only id cannot polish, so the prompt-capable default
    // applies instead of the stale refinement choice.
    final (fallback, _) = await _initWith(root, {
      'two_pass_refinement_model_id': 'gemini-3.5-transcribe',
    });
    expect(fallback.twoPassRefinementModelId, AppConfig.defaultModelId);
  });

  test(
    'standalone Transcribe selection survives migration without refinement',
    () async {
      final (settings, file) = await _initWith(root, {
        'selected_model_id': 'gemini-3.5-transcribe',
        'two_pass_transcription_model_id': 'retired-model',
      });
      expect(settings.selectedModelId, 'gemini-3.5-transcribe');
      expect(settings.twoPassTranscriptionEnabled, isFalse);
      expect(settings.promptIsApplied, isFalse);
      final persisted = jsonDecode(await file.readAsString());
      expect(persisted['selected_model_id'], 'gemini-3.5-transcribe');
      expect(persisted.containsKey('two_pass_transcription_model_id'), isFalse);
    },
  );

  for (final id in [
    'gemini-2.5-flash',
    'gemini-2.5-flash-lite',
    'gemini-3.1-flash-lite',
  ]) {
    test('migration preserves restored model $id', () async {
      final (settings, file) = await _initWith(root, {'selected_model_id': id});
      expect(settings.selectedModelId, id);
      expect(jsonDecode(await file.readAsString())['selected_model_id'], id);
    });
  }

  test(
    'Transcribe selection survives enabling and disabling two-step',
    () async {
      final (settings, file) = await _initWith(root, {
        'selected_model_id': 'gemini-3.5-transcribe',
      });
      await settings.setTwoPassTranscriptionEnabled(true);
      // The transcription model stays the primary selection; two-step only
      // adds the separate polish model on top of it.
      expect(settings.selectedModelId, 'gemini-3.5-transcribe');
      expect(settings.promptIsApplied, isTrue);
      expect(settings.cloudProvider, CloudProvider.geminiApiKey);
      expect(settings.refinementProvider, CloudProvider.geminiApiKey);
      // The transcription-only id cannot polish, so the prompt-capable
      // default serves as the initial refinement model.
      expect(settings.twoPassRefinementModelId, AppConfig.defaultModelId);
      await settings.setTwoPassRefinementModelId('gemini-3.7-flash');
      expect(settings.twoPassRefinementModelId, 'gemini-3.7-flash');
      await settings.setTwoPassTranscriptionEnabled(false);
      expect(settings.selectedModelId, 'gemini-3.5-transcribe');
      await settings.setCloudProvider(CloudProvider.vertexAi);
      expect(settings.selectedModelId, AppConfig.defaultModelId);
      await settings.setCloudProvider(CloudProvider.geminiApiKey);
      expect(settings.selectedModelId, 'gemini-3.5-transcribe');
      expect(
        jsonDecode(await file.readAsString())['selected_model_id'],
        'gemini-3.5-transcribe',
      );
    },
  );

  test(
    'a gemini primary keeps its model and drops the legacy step-1 slot',
    () async {
      final (settings, file) = await _initWith(root, {
        'selected_model_id': 'gemini-3.6-flash',
        'two_pass_transcription_model_id': 'gemini-3.5-transcribe',
      });
      expect(settings.selectedModelId, 'gemini-3.6-flash');
      expect(settings.refinementProvider, CloudProvider.geminiApiKey);
      final persisted = jsonDecode(await file.readAsString()) as Map;
      expect(persisted.containsKey('two_pass_transcription_model_id'), isFalse);
      expect(persisted.containsKey('refinement_provider'), isFalse);
    },
  );

  for (final legacy in const ['openaiApiKey', 'codexOAuth', 'grokOAuth']) {
    test('a text-only $legacy primary moves into the polish role', () async {
      final (settings, file) = await _initWith(root, {
        'cloud_provider': legacy,
        'two_pass_cloud_provider': 'vertexAi',
        'two_pass_transcription_model_id': 'gemini-3.6-flash',
        'two_pass_transcription_model_id_openai': 'gpt-transcribe',
      });
      expect(settings.cloudProvider, CloudProvider.vertexAi);
      expect(settings.selectedModelId, 'gemini-3.6-flash');
      expect(settings.refinementProvider.name, legacy);
      expect(settings.twoPassTranscriptionEnabled, isTrue);
      final persisted = jsonDecode(await file.readAsString()) as Map;
      expect(persisted['cloud_provider'], 'vertexAi');
      expect(persisted['refinement_provider'], legacy);
      for (final key in const [
        'two_pass_cloud_provider',
        'two_pass_transcription_model_id',
        'two_pass_transcription_model_id_openai',
      ]) {
        expect(persisted.containsKey(key), isFalse, reason: key);
      }
    });
  }

  test('a migrated Codex first pass survives a later launch', () async {
    final (settings, file) = await _initWith(root, {
      'cloud_provider': 'codexOAuth',
      'legacy_primary_roles_migrated': true,
    });
    await settings.setSelectedModelId('chatgpt-transcribe');

    final reloaded = SettingsService(
      applicationSupportDirectory: root,
      credentialStore: InMemorySecureCredentialStore(),
    );
    await reloaded.initialize();

    expect(reloaded.cloudProvider, CloudProvider.codexOAuth);
    expect(reloaded.selectedModelId, 'chatgpt-transcribe');
    expect(
      jsonDecode(await file.readAsString())['legacy_primary_roles_migrated'],
      isTrue,
    );
  });

  test('a fresh install records the legacy primary migration flag', () async {
    final (_, file) = await _initWith(root, {});
    final persisted = jsonDecode(await file.readAsString()) as Map;
    expect(persisted['legacy_primary_roles_migrated'], isTrue);
  });

  test(
    'a text-only primary without a usable first pass falls back to Gemini',
    () async {
      final (settings, _) = await _initWith(root, {
        'cloud_provider': 'codexOAuth',
        'two_pass_cloud_provider': 'openaiApiKey',
        'two_pass_transcription_model_id': 'gpt-transcribe',
        'selected_model_id_codex': 'gpt-5-6-thinking',
      });
      expect(settings.cloudProvider, CloudProvider.geminiApiKey);
      expect(settings.selectedModelId, AppConfig.defaultModelId);
      expect(settings.refinementProvider, CloudProvider.codexOAuth);
      // The old primary slot seeds the polish model on upgrade.
      expect(settings.twoPassRefinementModelId, 'gpt-5-6-thinking');
    },
  );

  test('thinking levels are split once, then diverge per pass', () async {
    final (settings, file) = await _initWith(root, {
      'thinking_level_gemini-3.7-flash': 'high',
    });
    expect(
      settings.getThinkingLevelForModel('gemini-3.7-flash'),
      GeminiThinkingLevel.high,
    );
    expect(
      settings.getRefinementThinkingLevel('gemini-3.7-flash'),
      GeminiThinkingLevel.high,
    );
    await settings.setRefinementThinkingLevel(
      'gemini-3.7-flash',
      GeminiThinkingLevel.low,
    );
    await settings.setThinkingLevelForModel(
      'gemini-3.6-flash',
      GeminiThinkingLevel.medium,
    );
    expect(
      settings.getThinkingLevelForModel('gemini-3.7-flash'),
      GeminiThinkingLevel.high,
    );

    // A relaunch never re-couples: new first-pass levels stay first-pass.
    final reloaded = SettingsService(
      applicationSupportDirectory: root,
      credentialStore: InMemorySecureCredentialStore(),
    );
    await reloaded.initialize();
    expect(
      reloaded.getRefinementThinkingLevel('gemini-3.7-flash'),
      GeminiThinkingLevel.low,
    );
    expect(reloaded.getRefinementThinkingLevel('gemini-3.6-flash'), isNull);
    expect(
      jsonDecode(await file.readAsString())['refinement_thinking_split'],
      isTrue,
    );
  });

  test('prompt is applied for cloud or explicit two-step only', () async {
    final (settings, _) = await _initWith(root, {
      'transcription_backend': 'whisper',
    });
    expect(settings.promptIsApplied, isFalse);
    await settings.setTwoPassTranscriptionEnabled(true);
    expect(settings.promptIsApplied, isTrue);
    await settings.setTwoPassTranscriptionEnabled(false);
    await settings.setTranscriptionBackend(TranscriptionBackend.cloud);
    expect(settings.promptIsApplied, isTrue);
  });
}
