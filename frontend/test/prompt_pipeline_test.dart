import 'dart:convert';
import 'dart:io';

import 'package:beeamvo/config.dart';
import 'package:beeamvo/models/system_prompt.dart';
import 'package:beeamvo/services/secure_credential_store.dart';
import 'package:beeamvo/services/settings_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The repo's fake-settings pattern (`cloud_latency_test.dart`): a real
/// [SettingsService] over an [InMemorySecureCredentialStore] and a temp
/// support directory, so migrations, setters, and credential state behave
/// exactly as in the app.
class _Settings extends SettingsService {
  _Settings(Directory dir)
    : super(
        applicationSupportDirectory: dir,
        credentialStore: InMemorySecureCredentialStore(),
      );
}

Future<_Settings> _init(Directory root, Map<String, dynamic> seed) async {
  final folder = Directory('${root.path}/Beeamvo')..createSync(recursive: true);
  await File('${folder.path}/settings.json').writeAsString(jsonEncode(seed));
  final settings = _Settings(root);
  await settings.initialize();
  return settings;
}

Future<_Settings> _reload(Directory root) async {
  final settings = _Settings(root);
  await settings.initialize();
  return settings;
}

SystemPrompt _style({
  String? modelOverrideId,
  String? polishModelOverrideId,
  bool? twoPassOverride,
}) {
  return SystemPrompt(
    id: 'style-1',
    name: 'Style',
    instruction: 'Write with flair.',
    modelOverrideId: modelOverrideId,
    polishModelOverrideId: polishModelOverrideId,
    twoPassOverride: twoPassOverride,
  );
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
    root = await Directory.systemTemp.createTemp('beeamvo-prompt-pipeline-');
  });
  tearDown(() async {
    if (root.existsSync()) await root.delete(recursive: true);
  });

  group('SystemPrompt pipeline overrides', () {
    test(
      'toMap stays byte-identical without overrides and round-trips with them',
      () {
        final plain = _style();
        expect(
          jsonEncode(plain.toMap()),
          jsonEncode({
            'id': 'style-1',
            'name': 'Style',
            'instruction': 'Write with flair.',
          }),
        );

        final styled = _style(
          modelOverrideId: 'gemini-2.5-flash',
          polishModelOverrideId: 'gemini-3.7-flash',
          twoPassOverride: true,
        );
        final map = styled.toMap();
        expect(map['model_override_id'], 'gemini-2.5-flash');
        expect(map['polish_model_override_id'], 'gemini-3.7-flash');
        expect(map['two_pass_override'], isTrue);

        final restored = SystemPrompt.fromMap(map);
        expect(restored.id, styled.id);
        expect(restored.name, styled.name);
        expect(restored.instruction, styled.instruction);
        expect(restored.modelOverrideId, 'gemini-2.5-flash');
        expect(restored.polishModelOverrideId, 'gemini-3.7-flash');
        expect(restored.twoPassOverride, isTrue);
      },
    );

    test('cleared overrides drop their persisted keys again', () {
      final cleared =
          _style(
            modelOverrideId: 'gemini-2.5-flash',
            polishModelOverrideId: 'gemini-3.7-flash',
            twoPassOverride: false,
          ).copyWith(
            clearModelOverride: true,
            clearPolishModelOverride: true,
            clearTwoPassOverride: true,
          );
      expect(
        jsonEncode(cleared.toMap()),
        jsonEncode({
          'id': 'style-1',
          'name': 'Style',
          'instruction': 'Write with flair.',
        }),
      );
    });

    test('old maps without override keys load as all-null', () {
      final restored = SystemPrompt.fromMap({
        'id': 'legacy',
        'name': 'Legacy',
        'instruction': 'Old style.',
      });
      expect(restored.modelOverrideId, isNull);
      expect(restored.polishModelOverrideId, isNull);
      expect(restored.twoPassOverride, isNull);
    });

    test('mistyped override values load as null', () {
      final restored = SystemPrompt.fromMap({
        'id': 'x',
        'name': 'X',
        'instruction': 'i',
        'model_override_id': 42,
        'polish_model_override_id': true,
        'two_pass_override': 'yes',
      });
      expect(restored.modelOverrideId, isNull);
      expect(restored.polishModelOverrideId, isNull);
      expect(restored.twoPassOverride, isNull);
    });

    test('copyWith sets and clears each override independently', () {
      final base = _style();
      expect(base.modelOverrideId, isNull);
      expect(base.polishModelOverrideId, isNull);
      expect(base.twoPassOverride, isNull);

      final withModel = base.copyWith(modelOverrideId: 'gemini-2.5-flash');
      expect(withModel.modelOverrideId, 'gemini-2.5-flash');
      expect(withModel.polishModelOverrideId, isNull);
      expect(withModel.twoPassOverride, isNull);

      final withPolish = base.copyWith(polishModelOverrideId: 'gemini-3.7');
      expect(withPolish.polishModelOverrideId, 'gemini-3.7');
      expect(withPolish.modelOverrideId, isNull);

      final withMode = base.copyWith(twoPassOverride: false);
      expect(withMode.twoPassOverride, isFalse);
      expect(withMode.modelOverrideId, isNull);

      // Clearing one override leaves the others intact.
      final all = _style(
        modelOverrideId: 'gemini-2.5-flash',
        polishModelOverrideId: 'gemini-3.7-flash',
        twoPassOverride: true,
      );
      final modelCleared = all.copyWith(clearModelOverride: true);
      expect(modelCleared.modelOverrideId, isNull);
      expect(modelCleared.polishModelOverrideId, 'gemini-3.7-flash');
      expect(modelCleared.twoPassOverride, isTrue);

      final polishCleared = all.copyWith(clearPolishModelOverride: true);
      expect(polishCleared.polishModelOverrideId, isNull);
      expect(polishCleared.modelOverrideId, 'gemini-2.5-flash');
      expect(polishCleared.twoPassOverride, isTrue);

      final modeCleared = all.copyWith(clearTwoPassOverride: true);
      expect(modeCleared.twoPassOverride, isNull);
      expect(modeCleared.modelOverrideId, 'gemini-2.5-flash');
      expect(modeCleared.polishModelOverrideId, 'gemini-3.7-flash');

      // A clear flag wins over a value passed in the same call.
      expect(
        all
            .copyWith(
              modelOverrideId: 'gemini-3-flash',
              clearModelOverride: true,
            )
            .modelOverrideId,
        isNull,
      );

      // Core fields still copy through.
      final renamed = base.copyWith(name: 'Renamed', instruction: 'New words.');
      expect(renamed.name, 'Renamed');
      expect(renamed.instruction, 'New words.');
      expect(renamed.id, base.id);
    });

    test("built-in styles never carry overrides", () {
      for (final prompt in SystemPrompt.availablePrompts) {
        expect(prompt.modelOverrideId, isNull, reason: prompt.id);
        expect(prompt.polishModelOverrideId, isNull, reason: prompt.id);
        expect(prompt.twoPassOverride, isNull, reason: prompt.id);
        expect(
          jsonEncode(prompt.toMap()),
          jsonEncode({
            'id': prompt.id,
            'name': prompt.name,
            'instruction': prompt.instruction,
          }),
          reason: prompt.id,
        );
      }
    });

    test('per-style overrides persist through the settings file', () async {
      final settings = await _init(root, {});
      await settings.addCustomPrompt(
        _style(
          modelOverrideId: 'gemini-2.5-flash',
          polishModelOverrideId: 'gemini-3.7-flash',
          twoPassOverride: true,
        ),
      );

      final reloaded = await _reload(root);
      final stored = reloaded.customPrompts.single;
      expect(stored.modelOverrideId, 'gemini-2.5-flash');
      expect(stored.polishModelOverrideId, 'gemini-3.7-flash');
      expect(stored.twoPassOverride, isTrue);
    });
  });

  group('resolvePipelineForPrompt', () {
    test('a style without overrides follows the global setup', () async {
      final settings = await _init(root, {});
      final plain = _style();
      expect(
        settings.resolvePipelineForPrompt(plain),
        PromptPipeline(
          twoPass: false,
          pass1ModelId: settings.selectedModelId,
          polishModelId: settings.twoPassRefinementModelId,
        ),
      );

      await settings.setTwoPassTranscriptionEnabled(true);
      await settings.setTwoPassRefinementModelId('gemini-3.7-flash');
      expect(
        settings.resolvePipelineForPrompt(plain),
        PromptPipeline(
          twoPass: true,
          pass1ModelId: settings.selectedModelId,
          polishModelId: 'gemini-3.7-flash',
        ),
      );
    });

    test(
      'twoPassOverride forces each way regardless of the global mode',
      () async {
        final settings = await _init(root, {});
        expect(settings.twoPassTranscriptionEnabled, isFalse);
        expect(
          settings
              .resolvePipelineForPrompt(_style(twoPassOverride: true))
              .twoPass,
          isTrue,
        );

        await settings.setTwoPassTranscriptionEnabled(true);
        expect(
          settings
              .resolvePipelineForPrompt(_style(twoPassOverride: false))
              .twoPass,
          isFalse,
        );
        expect(settings.resolvePipelineForPrompt(_style()).twoPass, isTrue);
      },
    );

    test(
      'a valid model override serves pass 1; a foreign id falls back',
      () async {
        final settings = await _init(root, {
          'selected_model_id': 'gemini-3.5-flash-lite',
        });
        expect(
          settings
              .resolvePipelineForPrompt(
                _style(modelOverrideId: 'gemini-2.5-flash'),
              )
              .pass1ModelId,
          'gemini-2.5-flash',
        );
        // Real catalog ids that Gemini's audio list does not offer, plus an
        // unknown id: the safety net falls back to the global selection.
        for (final id in const ['grok-4.3', 'gpt-5.4', 'not-a-model']) {
          expect(
            settings
                .resolvePipelineForPrompt(_style(modelOverrideId: id))
                .pass1ModelId,
            settings.selectedModelId,
            reason: id,
          );
        }
      },
    );

    test(
      'a valid polish override serves pass 2; a foreign id falls back',
      () async {
        final settings = await _init(root, {});
        await settings.setTwoPassTranscriptionEnabled(true);
        await settings.setTwoPassRefinementModelId('gemini-3.7-flash');
        expect(
          settings
              .resolvePipelineForPrompt(
                _style(polishModelOverrideId: 'gemini-2.5-flash'),
              )
              .polishModelId,
          'gemini-2.5-flash',
        );
        // Transcription-only models cannot polish.
        expect(
          settings
              .resolvePipelineForPrompt(
                _style(polishModelOverrideId: 'chatgpt-transcribe'),
              )
              .polishModelId,
          'gemini-3.7-flash',
        );

        await settings.setRefinementProvider(CloudProvider.openaiApiKey);
        expect(
          settings
              .resolvePipelineForPrompt(
                _style(polishModelOverrideId: 'gpt-5.4-mini'),
              )
              .polishModelId,
          'gpt-5.4-mini',
        );
        expect(
          settings
              .resolvePipelineForPrompt(
                _style(polishModelOverrideId: 'gemini-2.5-flash'),
              )
              .polishModelId,
          AppConfig.defaultOpenAiModelId,
        );
      },
    );

    test(
      'on the whisper backend the pass-1 id is resolved but unused',
      () async {
        final settings = await _init(root, {
          'transcription_backend': 'whisper',
          'selected_model_id': 'gemini-3.5-flash-lite',
        });
        expect(settings.transcriptionBackend, TranscriptionBackend.whisper);
        expect(
          settings
              .resolvePipelineForPrompt(
                _style(modelOverrideId: 'gemini-2.5-flash'),
              )
              .pass1ModelId,
          'gemini-2.5-flash',
        );
        expect(
          settings.resolvePipelineForPrompt(_style()).pass1ModelId,
          'gemini-3.5-flash-lite',
        );
      },
    );
  });

  group('promptAppliesFor', () {
    final states = <(String, Map<String, dynamic>, bool)>[
      ('whisper single-pass', {'transcription_backend': 'whisper'}, false),
      (
        'whisper two-pass',
        {'transcription_backend': 'whisper', 'two_pass_transcription': true},
        true,
      ),
      (
        'cloud prompt-capable model',
        {'selected_model_id': 'gemini-3.5-flash-lite'},
        true,
      ),
      (
        'cloud transcription-only model',
        {'selected_model_id': 'gemini-3.5-transcribe'},
        false,
      ),
      (
        'cloud Codex transcription-only model',
        {'cloud_provider': 'codexOAuth', 'legacy_primary_roles_migrated': true},
        false,
      ),
      (
        'cloud transcription-only model with global two-pass',
        {
          'selected_model_id': 'gemini-3.5-transcribe',
          'two_pass_transcription': true,
        },
        true,
      ),
    ];

    for (final (name, seed, expected) in states) {
      test('a null-override style matches promptIsApplied ($name)', () async {
        final settings = await _init(root, seed);
        final plain = _style();
        expect(settings.promptIsApplied, expected, reason: name);
        expect(settings.promptAppliesFor(plain), expected, reason: name);
        expect(
          settings.pipelineIssueForPrompt(plain),
          settings.transcriptionSetupIssue,
          reason: name,
        );
      });
    }

    test(
      'twoPassOverride=true makes a transcription-only setup apply',
      () async {
        final settings = await _init(root, {
          'selected_model_id': 'gemini-3.5-transcribe',
        });
        expect(settings.promptIsApplied, isFalse);
        expect(
          settings.promptAppliesFor(_style(twoPassOverride: true)),
          isTrue,
        );
      },
    );

    test(
      'twoPassOverride=false keeps a global two-pass transcription-only setup from applying',
      () async {
        final settings = await _init(root, {
          'selected_model_id': 'gemini-3.5-transcribe',
          'two_pass_transcription': true,
        });
        expect(settings.promptIsApplied, isTrue);
        expect(
          settings.promptAppliesFor(_style(twoPassOverride: false)),
          isFalse,
        );
      },
    );

    test('a prompt-capable model override applies even in one-pass', () async {
      final settings = await _init(root, {
        'selected_model_id': 'gemini-3.5-transcribe',
      });
      expect(
        settings.promptAppliesFor(_style(modelOverrideId: 'gemini-2.5-flash')),
        isTrue,
      );
    });
  });

  group('pipelineReadyForPrompt / pipelineIssueForPrompt', () {
    test('ready with credentials for both effective stages', () async {
      final settings = await _init(root, {});
      await settings.setGeminiApiKey('gk');
      await settings.setRefinementProvider(CloudProvider.geminiApiKey);

      final forced = _style(twoPassOverride: true);
      expect(settings.pipelineReadyForPrompt(forced), isTrue);
      expect(settings.pipelineIssueForPrompt(forced), isNull);
      expect(settings.pipelineReadyForPrompt(_style()), isTrue);
    });

    test('missing polish credentials surface under forced two-pass', () async {
      final settings = await _init(root, {});
      await settings.setGeminiApiKey('gk');
      await settings.setRefinementProvider(CloudProvider.openaiApiKey);
      expect(settings.twoPassTranscriptionEnabled, isFalse);

      // Global single-pass: the plain style stays ready.
      expect(settings.pipelineReadyForPrompt(_style()), isTrue);
      expect(settings.pipelineIssueForPrompt(_style()), isNull);

      final forced = _style(twoPassOverride: true);
      expect(settings.pipelineReadyForPrompt(forced), isFalse);
      expect(
        settings.pipelineIssueForPrompt(forced),
        contains('OpenAI API key'),
      );

      await settings.setOpenAiApiKey('sk');
      expect(settings.pipelineReadyForPrompt(forced), isTrue);
      expect(settings.pipelineIssueForPrompt(forced), isNull);
    });

    test('missing transcription credentials are reported first', () async {
      final settings = await _init(root, {});
      expect(settings.hasCloudCredentials, isFalse);
      final forced = _style(twoPassOverride: true);
      expect(settings.pipelineReadyForPrompt(forced), isFalse);
      expect(
        settings.pipelineIssueForPrompt(forced),
        contains('Add your Gemini API key'),
      );
      expect(
        settings.pipelineIssueForPrompt(forced),
        contains('start dictating'),
      );
    });

    test(
      'whisper with forced two-pass needs only polish credentials',
      () async {
        final settings = await _init(root, {
          'transcription_backend': 'whisper',
          'two_pass_transcription': false,
          'refinement_provider': 'openaiApiKey',
        });
        final forced = _style(twoPassOverride: true);
        expect(settings.pipelineReadyForPrompt(forced), isFalse);
        expect(
          settings.pipelineIssueForPrompt(forced),
          contains('OpenAI API key'),
        );

        await settings.setOpenAiApiKey('sk');
        expect(settings.pipelineReadyForPrompt(forced), isTrue);
        expect(settings.pipelineIssueForPrompt(forced), isNull);
      },
    );
  });
}
