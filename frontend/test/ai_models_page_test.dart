import 'package:beeamvo/config.dart';
import 'package:beeamvo/providers/settings_provider.dart';
import 'package:beeamvo/services/secure_credential_store.dart';
import 'package:beeamvo/services/settings_service.dart';
import 'package:beeamvo/theme/app_theme.dart';
import 'package:beeamvo/widgets/settings/pages/ai_models_page.dart';
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
    this.twoPassModel = 'legacy-pass-1',
    this.twoPassRefinementModel = 'legacy-pass-2',
    this.whisperLanguageValue = 'legacy-language',
  }) : super(credentialStore: InMemorySecureCredentialStore());

  final TranscriptionBackend backend;
  CloudProvider provider;
  bool geminiKeyPresent;
  String? vertexProjectIdValue;
  final String selectedModel;
  final bool twoPassEnabled;
  final String twoPassModel;
  final String twoPassRefinementModel;
  final String whisperLanguageValue;
  String whisperModelValue = 'ggml-tiny.bin';

  @override
  TranscriptionBackend get transcriptionBackend => backend;

  @override
  CloudProvider get cloudProvider => provider;

  @override
  Future<void> setCloudProvider(CloudProvider provider) async {
    this.provider = provider;
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
  String get selectedModelId => selectedModel;

  @override
  bool get twoPassTranscriptionEnabled => twoPassEnabled;

  @override
  String get twoPassTranscriptionModelId => twoPassModel;

  @override
  String get twoPassRefinementModelId => twoPassRefinementModel;

  @override
  String get whisperLanguage => whisperLanguageValue;

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
  GeminiThinkingLevel? getThinkingLevelForModel(String modelId) => null;
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
    expect(find.text('Primary Cloud Model'), findsOneWidget);
    expect(find.text(AppConfig.availableModels.first.name), findsWidgets);
  });

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
      find.byType(TextField),
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
}
