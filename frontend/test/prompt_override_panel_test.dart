import 'package:beeamvo/config.dart';
import 'package:beeamvo/models/prompt_settings.dart';
import 'package:beeamvo/models/system_prompt.dart';
import 'package:beeamvo/services/secure_credential_store.dart';
import 'package:beeamvo/services/settings_service.dart';
import 'package:beeamvo/theme/app_theme.dart';
import 'package:beeamvo/widgets/settings/pages/prompt_override_panel.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _FakePromptOverrideSettings extends SettingsService {
  _FakePromptOverrideSettings({
    this.backend = TranscriptionBackend.whisper,
    this.twoPassEnabled = false,
    this.twoPassRefinementModel = 'gemini-3-flash',
  }) : super(credentialStore: InMemorySecureCredentialStore());

  final TranscriptionBackend backend;
  final bool twoPassEnabled;
  final String twoPassRefinementModel;

  @override
  TranscriptionBackend get transcriptionBackend => backend;

  @override
  bool get twoPassTranscriptionEnabled => twoPassEnabled;

  @override
  String get selectedModelId => 'gemini-3-flash';

  @override
  String get twoPassTranscriptionModelId => 'gemini-2.5-flash';

  @override
  String get twoPassRefinementModelId => twoPassRefinementModel;

  @override
  String get whisperModelId => 'ggml-tiny.bin';

  @override
  String get whisperLanguage => 'en';

  @override
  CloudProvider get cloudProvider => CloudProvider.geminiApiKey;

  @override
  RephraseLevel get rephraseLevel => RephraseLevel.medium;

  @override
  GeminiThinkingLevel? getThinkingLevelForModel(String modelId) => null;
}

Future<void> _pumpDetail(
  WidgetTester tester, {
  required SettingsService settings,
  required PromptSettings overrides,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: PromptDetailPage(
          prompt: const SystemPrompt(
            id: 'standard',
            name: 'Medical Notes',
            instruction: 'Transcribe the dictated medical note verbatim.',
            settings: PromptSettings(),
          ),
          isBuiltIn: true,
          overrides: overrides,
          settingsService: settings,
          onBack: () {},
          onOverridesChanged: (_) {},
          onDuplicate: () {},
        ),
      ),
    ),
  );

  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('detail page treats Global default engine as inherited Whisper', (
    tester,
  ) async {
    await _pumpDetail(
      tester,
      settings: _FakePromptOverrideSettings(
        backend: TranscriptionBackend.whisper,
        twoPassEnabled: false,
      ),
      // Leave the engine at Global default while a single override
      // (rephraser) keeps the prompt customized. This is the exact
      // regression shape: before the effective-engine fix, null was
      // treated as cloud instead of inheriting the global Whisper backend.
      overrides: const PromptSettings(rephraseLevel: RephraseLevel.high),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Processing Engine'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('AI Model'), findsNothing);
    expect(find.text('Cloud Provider'), findsNothing);
    expect(find.text('Reasoning Effort'), findsNothing);
  });

  testWidgets(
    'inherited Whisper plus inherited two-pass exposes cloud refinement controls only',
    (tester) async {
      await _pumpDetail(
        tester,
        settings: _FakePromptOverrideSettings(
          backend: TranscriptionBackend.whisper,
          twoPassEnabled: true,
          twoPassRefinementModel: 'gemini-3-flash',
        ),
        overrides: const PromptSettings(rephraseLevel: RephraseLevel.high),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Cloud Provider'), findsOneWidget);
      expect(find.text('AI Model'), findsNothing);
      expect(find.text('Refinement Reasoning Effort'), findsOneWidget);
      expect(find.text('Reasoning Effort'), findsNothing);
    },
  );
}
