import 'package:beeamvo/models/enums.dart';
import 'package:beeamvo/models/hotkey_config.dart';
import 'package:beeamvo/models/system_prompt.dart';
import 'package:beeamvo/services/settings_service.dart';
import 'package:beeamvo/theme/app_theme.dart';
import 'package:beeamvo/widgets/onboarding/onboarding_shared.dart';
import 'package:beeamvo/widgets/onboarding/onboarding_steps.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'onboarding_test_helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets(
    'engine tiles have equal heights and provider rows are cloud-only',
    (tester) async {
      await _pumpStep(
        tester,
        ProviderStep(
          onNext: () {},
          settingsService: OnboardingTestSettingsService(),
        ),
        const Size(860, 640),
      );

      final cloudTile = find.ancestor(
        of: find.text('Cloud AI'),
        matching: find.byType(OnboardingOptionTile),
      );
      final offlineTile = find.ancestor(
        of: find.text('Offline'),
        matching: find.byType(OnboardingOptionTile),
      );
      expect(
        tester.getSize(cloudTile).height,
        tester.getSize(offlineTile).height,
      );
      expect(find.text('Gemini'), findsOneWidget);
      expect(find.text('Vertex AI'), findsOneWidget);
      expect(find.text('ChatGPT'), findsOneWidget);

      await tester.tap(offlineTile);
      await tester.pumpAndSettle();

      expect(find.text('Gemini'), findsNothing);
      expect(find.text('Vertex AI'), findsNothing);
      expect(find.text('ChatGPT'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Continue is disabled without an account credential', (
    tester,
  ) async {
    await _pumpStep(
      tester,
      ApiKeyStep(
        onNext: () {},
        onSkip: () {},
        settingsService: OnboardingTestSettingsService(),
      ),
      const Size(860, 640),
    );

    final button = tester.widget<OnboardingPrimaryButton>(
      find.byType(OnboardingPrimaryButton),
    );
    expect(button.onTap, isNull);
  });

  testWidgets('footer buttons stay full-size and align to the content edge', (
    tester,
  ) async {
    await _pumpStep(
      tester,
      ProviderStep(
        onNext: () {},
        settingsService: OnboardingTestSettingsService(),
      ),
      const Size(860, 640),
    );

    final primary = find.byType(OnboardingPrimaryButton);
    final back = find.ancestor(
      of: find.text('Back'),
      matching: find.byType(OnboardingSecondaryButton),
    );
    expect(tester.getSize(primary).height, 40);
    expect(tester.getRect(primary).right, closeTo(820, 0.5));
    expect(tester.getCenter(back).dy, tester.getCenter(primary).dy);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer();
    await mouse.moveTo(tester.getCenter(primary));
    await tester.pump();
    expect(tester.getSize(primary).height, 40);
    await mouse.removePointer();
  });

  testWidgets('hotkey renders one keycap for each default shortcut key', (
    tester,
  ) async {
    await _pumpStep(
      tester,
      HotkeyStep(
        onNext: () {},
        settingsService: OnboardingTestSettingsService(),
      ),
      const Size(860, 640),
    );

    expect(
      find.byType(OnboardingKeycap),
      findsNWidgets(
        HotkeyConfig.defaultHotkey.displayString.split(' + ').length,
      ),
    );
  });

  testWidgets('recording illustrations show the configured main hotkey', (
    tester,
  ) async {
    final settings = OnboardingTestSettingsService();
    await settings.setHotkey(
      HotkeyConfig(key: LogicalKeyboardKey.keyR, modifiers: {}),
    );
    await _pumpStep(
      tester,
      RecordingModeStep(onNext: () {}, settingsService: settings),
      const Size(860, 640),
    );

    expect(find.text('R'), findsNWidgets(3));
    expect(find.text('⌘'), findsNothing);
  });

  testWidgets('transcription-only Finish style is Not applied without Edit', (
    tester,
  ) async {
    final settings = OnboardingTestSettingsService(
      provider: CloudProvider.codexOAuth,
    );
    await settings.setSelectedModelId('chatgpt-transcribe');
    await _pumpStep(
      tester,
      ReadyStep(
        onFinish: () {},
        onGoToModelStep: () {},
        settingsService: settings,
      ),
      const Size(860, 640),
    );

    final styleRow = find
        .ancestor(of: find.text('Style'), matching: find.byType(Row))
        .first;
    expect(tester.getSize(styleRow).height, 44);
    expect(
      find.descendant(of: styleRow, matching: find.text('Not applied')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: styleRow, matching: find.text('Edit')),
      findsNothing,
    );
  });

  testWidgets(
    'two-step transcription-only Finish style shows the selected prompt',
    (tester) async {
      final settings = OnboardingTestSettingsService(
        provider: CloudProvider.geminiApiKey,
        hasGeminiKey: true,
      );
      await settings.setSelectedModelId('gemini-3.5-transcribe');
      await settings.setTwoPassTranscriptionEnabled(true);
      await _pumpStep(
        tester,
        ReadyStep(
          onFinish: () {},
          onGoToModelStep: () {},
          settingsService: settings,
        ),
        const Size(860, 640),
      );

      final styleRow = find
          .ancestor(of: find.text('Style'), matching: find.byType(Row))
          .first;
      expect(
        find.descendant(
          of: styleRow,
          matching: find.text(
            SystemPrompt.getById(settings.selectedPromptId).name,
          ),
        ),
        findsOneWidget,
      );
      expect(find.text('Not applied'), findsNothing);
    },
  );

  testWidgets('onboarding steps do not overflow at 390px width', (
    tester,
  ) async {
    final settings = OnboardingTestSettingsService();
    final steps = <Widget>[
      WelcomeStep(onNext: () {}, onSkip: () {}),
      ProviderStep(onNext: () {}, settingsService: settings),
      ApiKeyStep(onNext: () {}, onSkip: () {}, settingsService: settings),
      ModelStep(onNext: () {}, settingsService: settings),
      RecordingModeStep(onNext: () {}, settingsService: settings),
      HotkeyStep(onNext: () {}, settingsService: settings),
      ReadyStep(onFinish: () {}, settingsService: settings),
    ];

    for (final step in steps) {
      await _pumpStep(tester, step, const Size(390, 844));
      expect(
        tester.takeException(),
        isNull,
        reason: step.runtimeType.toString(),
      );
    }

    await _pumpStep(
      tester,
      ModelStep(
        onNext: () {},
        settingsService: OnboardingTestSettingsService(
          backend: TranscriptionBackend.whisper,
        ),
      ),
      const Size(390, 844),
    );
    expect(tester.takeException(), isNull, reason: 'Whisper model step');
  });
}

Future<void> _pumpStep(WidgetTester tester, Widget step, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: child!,
      ),
      home: Scaffold(
        body: OnboardingNav(
          stepNumber: 1,
          totalSteps: 6,
          onBack: () {},
          child: step,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
