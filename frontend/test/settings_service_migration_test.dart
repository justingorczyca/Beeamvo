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
      'two_pass_refinement_model_id': 'gemini-3-flash',
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
      'two_pass_refinement_model_id',
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

  test('primary model must be prompt-capable, step-1 model optional', () async {
    final (settings, file) = await _initWith(root, {
      'selected_model_id': 'gemini-3.5-transcribe',
      'two_pass_transcription_model_id': 'retired-model',
    });
    expect(settings.selectedModelId, AppConfig.defaultModelId);
    expect(
      settings.twoPassTranscriptionModelId,
      AppConfig.defaultTranscriptionModelId,
    );
    final persisted = jsonDecode(await file.readAsString());
    expect(persisted['selected_model_id'], AppConfig.defaultModelId);
    expect(persisted.containsKey('two_pass_transcription_model_id'), isFalse);
  });

  test('valid primary and step-1 models are preserved', () async {
    final (settings, _) = await _initWith(root, {
      'selected_model_id': 'gemini-3.6-flash',
      'two_pass_transcription_model_id': 'gemini-3.5-transcribe',
    });
    expect(settings.selectedModelId, 'gemini-3.6-flash');
    expect(settings.twoPassTranscriptionModelId, 'gemini-3.5-transcribe');
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
