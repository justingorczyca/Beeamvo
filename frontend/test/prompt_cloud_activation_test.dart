import 'package:beeamvo/models/prompt_settings.dart';
import 'package:beeamvo/services/secure_credential_store.dart';
import 'package:beeamvo/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Overrides the backend-related getters so the prompt-activation logic can be
/// exercised without touching disk (no [SettingsService.initialize]). The
/// switch-action helpers route through [setTranscriptionBackend] /
/// [setTwoPassTranscriptionEnabled], which we override to record writes.
class _FakeSettings extends SettingsService {
  _FakeSettings() : super(credentialStore: InMemorySecureCredentialStore());

  TranscriptionBackend backend = TranscriptionBackend.whisper;
  bool twoPass = false;
  CloudProvider provider = CloudProvider.geminiApiKey;
  bool geminiKey = false;
  String? vertexProject;
  final Map<String, PromptSettings> overrides = {};

  @override
  TranscriptionBackend get transcriptionBackend => backend;

  @override
  bool get twoPassTranscriptionEnabled => twoPass;

  @override
  CloudProvider get cloudProvider => provider;

  @override
  bool get hasGeminiApiKey => geminiKey;

  @override
  String? get vertexProjectId => vertexProject;

  @override
  PromptSettings? getPromptOverrides(String promptId) => overrides[promptId];

  @override
  Future<void> setTranscriptionBackend(TranscriptionBackend value) async {
    backend = value;
  }

  @override
  Future<void> setTwoPassTranscriptionEnabled(bool value) async {
    twoPass = value;
  }
}

void main() {
  group('isPromptInactiveOnLocalBackend', () {
    test('default prompt is never inactive, even on pure local', () {
      final s = _FakeSettings()
        ..backend = TranscriptionBackend.whisper
        ..twoPass = false;

      expect(s.isPromptInactiveOnLocalBackend('standard'), isFalse);
    });

    test('non-default prompt is inactive on whisper without two-pass', () {
      final s = _FakeSettings()
        ..backend = TranscriptionBackend.whisper
        ..twoPass = false;

      expect(s.isPromptInactiveOnLocalBackend('concise'), isTrue);
    });

    test('non-default prompt is active on whisper WITH two-pass', () {
      final s = _FakeSettings()
        ..backend = TranscriptionBackend.whisper
        ..twoPass = true;

      expect(s.isPromptInactiveOnLocalBackend('concise'), isFalse);
    });

    test('non-default prompt is active on the cloud backend', () {
      final s = _FakeSettings()
        ..backend = TranscriptionBackend.cloud
        ..twoPass = false;

      expect(s.isPromptInactiveOnLocalBackend('concise'), isFalse);
    });

    test('per-prompt cloud override keeps the prompt active on local', () {
      final s = _FakeSettings()
        ..backend = TranscriptionBackend.whisper
        ..twoPass = false;
      s.overrides['concise'] = const PromptSettings(
        transcriptionBackend: 'cloud',
      );

      expect(s.isPromptInactiveOnLocalBackend('concise'), isFalse);
    });

    test('per-prompt two-pass override keeps the prompt active on local', () {
      final s = _FakeSettings()
        ..backend = TranscriptionBackend.whisper
        ..twoPass = false;
      s.overrides['concise'] = const PromptSettings(
        twoPassTranscriptionEnabled: true,
      );

      expect(s.isPromptInactiveOnLocalBackend('concise'), isFalse);
    });
  });

  group('isCloudRefinementInPipeline', () {
    test('true on the cloud backend', () {
      final s = _FakeSettings()
        ..backend = TranscriptionBackend.cloud
        ..twoPass = false;
      expect(s.isCloudRefinementInPipeline, isTrue);
    });

    test('true on whisper with two-pass refinement', () {
      final s = _FakeSettings()
        ..backend = TranscriptionBackend.whisper
        ..twoPass = true;
      expect(s.isCloudRefinementInPipeline, isTrue);
    });

    test('false on pure offline whisper', () {
      final s = _FakeSettings()
        ..backend = TranscriptionBackend.whisper
        ..twoPass = false;
      expect(s.isCloudRefinementInPipeline, isFalse);
    });
  });

  group('switch-action helpers', () {
    test('enableLocalTwoPassRefinement keeps whisper and turns two-pass on',
        () async {
      final s = _FakeSettings()
        ..backend = TranscriptionBackend.cloud
        ..twoPass = false;

      await s.enableLocalTwoPassRefinement();

      expect(s.backend, TranscriptionBackend.whisper);
      expect(s.twoPass, isTrue);
    });

    test('switchToCloudTranscription selects cloud and turns two-pass off',
        () async {
      final s = _FakeSettings()
        ..backend = TranscriptionBackend.whisper
        ..twoPass = true;

      await s.switchToCloudTranscription();

      expect(s.backend, TranscriptionBackend.cloud);
      expect(s.twoPass, isFalse);
    });
  });

  group('hasCloudCredentials', () {
    test('gemini provider reflects whether a key is present', () {
      final s = _FakeSettings()..provider = CloudProvider.geminiApiKey;

      s.geminiKey = false;
      expect(s.hasCloudCredentials, isFalse);

      s.geminiKey = true;
      expect(s.hasCloudCredentials, isTrue);
    });

    test('vertex provider reflects whether a project id is set', () {
      final s = _FakeSettings()..provider = CloudProvider.vertexAi;

      s.vertexProject = null;
      expect(s.hasCloudCredentials, isFalse);

      s.vertexProject = 'my-gcp-project';
      expect(s.hasCloudCredentials, isTrue);
    });
  });
}
