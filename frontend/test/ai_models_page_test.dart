import 'package:beeamvo/config.dart';
import 'package:beeamvo/providers/settings_provider.dart';
import 'package:beeamvo/services/secure_credential_store.dart';
import 'package:beeamvo/services/settings_service.dart';
import 'package:beeamvo/theme/app_theme.dart';
import 'package:beeamvo/widgets/settings/pages/ai_models_page.dart';
import 'package:beeamvo/widgets/settings/bee_dropdown.dart';
import 'package:beeamvo/widgets/settings/settings_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class FakeAiModelsSettingsService extends SettingsService {
  FakeAiModelsSettingsService({
    this.backend = TranscriptionBackend.cloud,
    this.provider = CloudProvider.geminiApiKey,
    this.geminiKeyPresent = false,
    this.vertexProjectIdValue,
    this.selectedModel = 'legacy-model',
    this.twoPassEnabled = true,
    this.spokenLanguageValue = 'legacy-language',
  }) : super(credentialStore: InMemorySecureCredentialStore());

  final TranscriptionBackend backend;
  CloudProvider provider;
  bool geminiKeyPresent;
  String? vertexProjectIdValue;
  String selectedModel;
  bool twoPassEnabled;
  final firstPassThinkingWrites = <String, GeminiThinkingLevel>{};
  final String spokenLanguageValue;
  String whisperModelValue = 'ggml-tiny.bin';

  @override
  TranscriptionBackend get transcriptionBackend => backend;

  @override
  CloudProvider get cloudProvider => provider;

  @override
  Future<void> setCloudProvider(CloudProvider provider) async {
    this.provider = provider;
    notifyListeners();
  }

  @override
  bool get hasGeminiApiKey => geminiKeyPresent;

  @override
  Future<void> setGeminiApiKey(String value) async {
    geminiKeyPresent = value.trim().isNotEmpty;
  }

  @override
  Future<void> clearGeminiApiKey() async {
    geminiKeyPresent = false;
  }

  @override
  String get selectedModelId => resolvePrimaryModelId(selectedModel);

  @override
  Future<void> setSelectedModelId(String value) async {
    selectedModel = value;
    notifyListeners();
  }

  @override
  bool get twoPassTranscriptionEnabled => twoPassEnabled;

  @override
  Future<void> setTwoPassTranscriptionEnabled(bool value) async {
    twoPassEnabled = value;
    notifyListeners();
  }

  @override
  String get spokenLanguage => spokenLanguageValue;

  @override
  String get whisperModelId => whisperModelValue;

  @override
  Future<void> setWhisperModelId(String value) async {
    whisperModelValue = value;
  }

  @override
  String? get vertexProjectId => vertexProjectIdValue;

  @override
  Future<void> setVertexProjectId(String value) async {
    final trimmed = value.trim();
    vertexProjectIdValue = trimmed.isEmpty ? null : trimmed;
  }

  @override
  Future<void> clearVertexProjectId() async {
    vertexProjectIdValue = null;
  }

  @override
  GeminiThinkingLevel? getThinkingLevelForModel(String modelId) =>
      firstPassThinkingWrites[modelId];

  @override
  Future<void> setThinkingLevelForModel(
    String modelId,
    GeminiThinkingLevel level,
  ) async {
    firstPassThinkingWrites[modelId] = level;
    notifyListeners();
  }
}

Future<void> _pumpAiModelsPage(
  WidgetTester tester,
  SettingsService settingsService,
) async {
  await tester.binding.setSurfaceSize(const Size(1400, 1000));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final provider = SettingsProvider(settingsService: settingsService);

  await tester.pumpWidget(
    MaterialApp(
      // AppTheme.lightTheme registers the BeeColors theme extension
      // that the page reads via beeColors(context). Pumping a bare
      // MaterialApp crashes on the null-extension bang otherwise.
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: SettingsProviderScope(
          provider: provider,
          child: const AiModelsPage(),
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

  testWidgets('renders cloud controls when stored model ids are stale', (
    WidgetTester tester,
  ) async {
    await _pumpAiModelsPage(tester, FakeAiModelsSettingsService());

    expect(tester.takeException(), isNull);
    expect(find.text('Model'), findsOneWidget);
    expect(
      find.text(AppConfig.getModelById(AppConfig.defaultModelId).displayName),
      findsWidgets,
    );
    expect(find.text('Step 1 · Transcribe'), findsOneWidget);
    expect(find.text('Step 2 · Polish'), findsOneWidget);
    // The transcription-only first-pass model is never rendered: pass 1 is
    // the primary selection and pass 2 resolves to a prompt-capable default.
    expect(
      find.text(
        AppConfig.getModelById(
          AppConfig.defaultTranscriptionModelId,
        ).displayName,
      ),
      findsNothing,
    );
  });

  testWidgets(
    'single-pass Gemini selector offers standalone Transcribe and restored models',
    (tester) async {
      await _pumpAiModelsPage(
        tester,
        FakeAiModelsSettingsService(
          twoPassEnabled: false,
          selectedModel: 'gemini-3.5-transcribe',
        ),
      );
      final picker = tester
          .widgetList<BeeDropdown<String>>(find.byType(BeeDropdown<String>))
          .singleWhere(
            (dropdown) => dropdown.options.any(
              (option) => option.value == 'gemini-3.7-flash',
            ),
          );
      expect(picker.value, 'gemini-3.5-transcribe');
      expect(
        picker.options.map((option) => option.value),
        containsAll([
          'gemini-3.5-transcribe',
          'gemini-3.1-flash-lite',
          'gemini-2.5-flash',
          'gemini-2.5-flash-lite',
        ]),
      );
      expect(
        find.text('Speech-to-text only. Writing styles are not applied.'),
        findsOneWidget,
      );
      expect(find.text('Step 2 · Polish'), findsNothing);
    },
  );

  testWidgets(
    'model selection survives two-step toggles and provider switches',
    (tester) async {
      final settings = FakeAiModelsSettingsService(
        selectedModel: 'gemini-3.5-transcribe',
        twoPassEnabled: false,
      );
      await _pumpAiModelsPage(tester, settings);
      BeeDropdown<String> primary() => tester
          .widgetList<BeeDropdown<String>>(find.byType(BeeDropdown<String>))
          .firstWhere(
            (dropdown) => dropdown.options.any(
              (option) => option.value == 'gemini-3.7-flash',
            ),
          );
      expect(primary().value, 'gemini-3.5-transcribe');
      // Enabling two-step keeps the transcription model as the primary
      // selection; it only adds the separate polish dropdown.
      await settings.setTwoPassTranscriptionEnabled(true);
      await tester.pumpAndSettle();
      expect(primary().value, 'gemini-3.5-transcribe');
      expect(find.text('Step 1 · Transcribe'), findsOneWidget);
      expect(find.text('Step 2 · Polish'), findsOneWidget);
      await settings.setTwoPassTranscriptionEnabled(false);
      await tester.pumpAndSettle();
      expect(primary().value, 'gemini-3.5-transcribe');
      expect(find.text('Step 2 · Polish'), findsNothing);
      await settings.setCloudProvider(CloudProvider.vertexAi);
      await tester.pumpAndSettle();
      expect(primary().value, AppConfig.defaultModelId);
      expect(
        primary().options.map((option) => option.value),
        isNot(contains('gemini-3.5-transcribe')),
      );
      await settings.setCloudProvider(CloudProvider.geminiApiKey);
      await tester.pumpAndSettle();
      expect(primary().value, 'gemini-3.5-transcribe');
      expect(tester.takeException(), isNull);
    },
  );

  for (final provider in CloudProvider.values) {
    testWidgets(
      'polish selector excludes speech-only models on ${provider.name}',
      (tester) async {
        final settings = FakeAiModelsSettingsService();
        await settings.setRefinementProvider(provider);
        await _pumpAiModelsPage(tester, settings);
        final picker = tester.widget<BeeDropdown<String>>(
          find.byKey(const ValueKey('two-pass-refinement-model')),
        );
        expect(
          picker.options.map((option) => option.value),
          contains(AppConfig.defaultModelIdForProvider(provider)),
        );
        for (final speechId in const [
          'gemini-3.5-transcribe',
          'gpt-transcribe',
          'gpt-4o-transcribe',
          'gpt-4o-mini-transcribe',
          'whisper-1',
        ]) {
          expect(
            picker.options.map((option) => option.value),
            isNot(contains(speechId)),
          );
        }
      },
    );
  }

  testWidgets('renders whisper controls when stored language is stale', (
    WidgetTester tester,
  ) async {
    await _pumpAiModelsPage(
      tester,
      FakeAiModelsSettingsService(
        backend: TranscriptionBackend.whisper,
        twoPassEnabled: false,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Spoken Language'), findsOneWidget);
    expect(find.text('Auto-Detect'), findsOneWidget);
    expect(find.text('Model'), findsNothing);
    expect(find.text('Step 1 · Transcribe'), findsNothing);
  });

  testWidgets('api key save is updated, not verified', (
    WidgetTester tester,
  ) async {
    final settings = FakeAiModelsSettingsService();
    await _pumpAiModelsPage(tester, settings);

    await tester.tap(find.text('Add API Key'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Show key'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(
      find.text('Enter an API key or use Remove to clear the saved key.'),
      findsOneWidget,
    );

    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      'AIza${'SyValidLookingLocalTestKey'}123',
    );
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(settings.geminiKeyPresent, isTrue);
    expect(find.text('Ready'), findsOneWidget);
    expect(find.text('Verified'), findsNothing);

    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();

    expect(settings.geminiKeyPresent, isFalse);
    expect(find.text('Add API Key'), findsOneWidget);
    expect(find.text('Verified'), findsNothing);
  });

  testWidgets('offline two-step shows the cloud model inline', (
    WidgetTester tester,
  ) async {
    await _pumpAiModelsPage(
      tester,
      FakeAiModelsSettingsService(backend: TranscriptionBackend.whisper),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Step 1 · Transcribe'), findsOneWidget);
    expect(find.text('Step 2 · Polish'), findsOneWidget);
    expect(find.text('Offline'), findsWidgets);
    // The polish dropdown replaces the old inline AI Model section.
    expect(
      find.byKey(const ValueKey('two-pass-refinement-model')),
      findsOneWidget,
    );
    expect(find.text('Model'), findsNothing);
    // Offline has no cloud transcription account; only the polish account.
    expect(find.byKey(const ValueKey('transcription-provider')), findsNothing);
    expect(
      find.byKey(const ValueKey('two-pass-refinement-provider')),
      findsOneWidget,
    );
  });

  testWidgets('the transcription account offers all audio providers', (
    WidgetTester tester,
  ) async {
    final settings = FakeAiModelsSettingsService();
    await _pumpAiModelsPage(tester, settings);
    BeeSegmented<CloudProvider> picker() =>
        tester.widget(find.byKey(const ValueKey('transcription-provider')));
    expect(picker().options.map((o) => o.val), [
      CloudProvider.geminiApiKey,
      CloudProvider.vertexAi,
      CloudProvider.codexOAuth,
    ]);

    await tester.tap(find.text('Vertex AI'));
    await tester.pumpAndSettle();
    expect(settings.provider, CloudProvider.vertexAi);
    expect(picker().value, CloudProvider.vertexAi);
    expect(find.text('Project ID'), findsOneWidget);
  });

  testWidgets('ChatGPT is a first-pass option without a segmented overflow', (
    WidgetTester tester,
  ) async {
    final settings = FakeAiModelsSettingsService(twoPassEnabled: false);
    await _pumpAiModelsPage(tester, settings);
    BeeSegmented<CloudProvider> picker() =>
        tester.widget(find.byKey(const ValueKey('transcription-provider')));
    expect(picker().options.map((o) => o.val), [
      CloudProvider.geminiApiKey,
      CloudProvider.vertexAi,
      CloudProvider.codexOAuth,
    ]);

    await tester.tap(find.text('ChatGPT'));
    await tester.pumpAndSettle();

    expect(settings.provider, CloudProvider.codexOAuth);
    expect(picker().value, CloudProvider.codexOAuth);
    expect(find.text('ChatGPT Sign-In'), findsOneWidget);
    expect(find.text('ChatGPT Transcribe'), findsOneWidget);
    expect(
      find.text(
        'ChatGPT transcribes your audio in the cloud. '
        'Turn on two-step refinement to apply your writing style.',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('first-pass-thinking')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ChatGPT engine description reflects the enabled polish step', (
    WidgetTester tester,
  ) async {
    await _pumpAiModelsPage(
      tester,
      FakeAiModelsSettingsService(
        provider: CloudProvider.codexOAuth,
        selectedModel: 'chatgpt-transcribe',
        twoPassEnabled: true,
      ),
    );

    expect(
      find.text(
        'ChatGPT transcribes your audio in the cloud; '
        'the polish step applies your writing style.',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('every provider is offered for the polish step', (
    WidgetTester tester,
  ) async {
    final settings = FakeAiModelsSettingsService();
    await _pumpAiModelsPage(tester, settings);
    BeeDropdown<CloudProvider> picker() => tester.widget(
      find.byKey(const ValueKey('two-pass-refinement-provider')),
    );
    expect(picker().options.map((o) => o.value), CloudProvider.values);
    // Sharing the first-pass account needs no second credential row.
    expect(find.text('ChatGPT Sign-In'), findsNothing);

    picker().onChanged(CloudProvider.codexOAuth);
    await tester.pumpAndSettle();

    expect(settings.refinementProvider, CloudProvider.codexOAuth);
    expect(settings.provider, CloudProvider.geminiApiKey);
    expect(picker().value, CloudProvider.codexOAuth);
    expect(find.text('ChatGPT Sign-In'), findsOneWidget);
    final model = tester.widget<BeeDropdown<String>>(
      find.byKey(const ValueKey('two-pass-refinement-model')),
    );
    expect(model.value, AppConfig.defaultCodexModelId);
    expect(tester.takeException(), isNull);
  });

  testWidgets('first-pass and polish thinking levels are independent', (
    WidgetTester tester,
  ) async {
    final settings = FakeAiModelsSettingsService(
      selectedModel: 'gemini-3.7-flash',
    );
    await settings.setTwoPassRefinementModelId('gemini-3.7-flash');
    await _pumpAiModelsPage(tester, settings);

    BeeSegmented<GeminiThinkingLevel> row(String key) => tester.widget(
      find.descendant(
        of: find.byKey(ValueKey(key)),
        matching: find.byType(BeeSegmented<GeminiThinkingLevel>),
      ),
    );

    // Unset step 1 defaults to the fastest level; the polish row shows the
    // model default.
    expect(row('first-pass-thinking').value, GeminiThinkingLevel.low);
    expect(row('two-pass-refinement-thinking').value, GeminiThinkingLevel.low);

    row('two-pass-refinement-thinking').onChanged(GeminiThinkingLevel.high);
    await tester.pumpAndSettle();
    expect(
      settings.getRefinementThinkingLevel('gemini-3.7-flash'),
      GeminiThinkingLevel.high,
    );
    expect(settings.firstPassThinkingWrites, isEmpty);
    expect(row('first-pass-thinking').value, GeminiThinkingLevel.low);

    row('first-pass-thinking').onChanged(GeminiThinkingLevel.medium);
    await tester.pumpAndSettle();
    expect(
      settings.firstPassThinkingWrites['gemini-3.7-flash'],
      GeminiThinkingLevel.medium,
    );
    expect(
      settings.getRefinementThinkingLevel('gemini-3.7-flash'),
      GeminiThinkingLevel.high,
    );
    expect(row('two-pass-refinement-thinking').value, GeminiThinkingLevel.high);
  });
}
