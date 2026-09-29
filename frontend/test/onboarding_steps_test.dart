import 'package:beeamvo/models/hotkey_config.dart';
import 'package:beeamvo/services/settings_service.dart';
import 'package:beeamvo/theme/app_theme.dart';
import 'package:beeamvo/widgets/onboarding/onboarding_shared.dart';
import 'package:beeamvo/widgets/onboarding/onboarding_steps.dart';
import 'package:flutter/material.dart';
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
        const Size(860, 580),
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
      const Size(860, 580),
    );

    final button = tester.widget<OnboardingPrimaryButton>(
      find.byType(OnboardingPrimaryButton),
    );
    expect(button.onTap, isNull);
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
      const Size(860, 580),
    );

    expect(
      find.byType(OnboardingKeycap),
      findsNWidgets(
        HotkeyConfig.defaultHotkey.displayString.split(' + ').length,
      ),
    );
  });

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
