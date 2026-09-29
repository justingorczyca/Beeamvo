import 'package:beeamvo/theme/app_theme.dart';
import 'package:beeamvo/widgets/onboarding/onboarding_shared.dart';
import 'package:beeamvo/widgets/onboarding/onboarding_wizard.dart';
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
    'welcome opens the six-step rail and navigation returns to welcome',
    (tester) async {
      await _pumpWizard(tester);

      await _tapAndAdvance(tester, find.text('Get started'));

      for (final label in [
        'Engine',
        'Account',
        'Model',
        'Recording',
        'Hotkey',
        'Finish',
      ]) {
        expect(find.text(label), findsOneWidget);
      }
      expect(find.text('STEP 1 OF 6'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await _tapAndAdvance(tester, find.text('Continue'));
      expect(find.text('Cloud · Gemini'), findsOneWidget);
      expect(find.text('STEP 2 OF 6'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(find.text('API Key'), findsOneWidget);

      await _tapAndAdvance(tester, find.text('Engine').first);
      expect(find.text('STEP 1 OF 6'), findsOneWidget);

      await _tapAndAdvance(tester, find.text('Back'));
      expect(find.text('Get started'), findsOneWidget);
      expect(find.text('Engine'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('every wizard step fits the 860 by 640 window', (tester) async {
    await _pumpWizard(tester);

    await _tapAndAdvance(tester, find.text('Get started'));
    expect(tester.takeException(), isNull, reason: 'Engine');
    expect(
      tester.getRect(find.text('ChatGPT')).bottom,
      lessThan(
        tester
            .getRect(find.byType(OnboardingPrimaryButton).hitTestable().first)
            .top,
      ),
      reason: 'Engine provider rows fit above the footer',
    );

    await _tapAndAdvance(tester, find.text('Continue'));
    expect(tester.takeException(), isNull, reason: 'Account');
    expect(find.text('STEP 2 OF 6'), findsOneWidget);
    expect(find.text('Set up later'), findsOneWidget);

    await _tapAndAdvance(tester, find.text('Set up later'));
    expect(find.text('STEP 3 OF 6'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'Model');

    await _tapAndAdvance(tester, find.text('Continue'));
    expect(find.text('STEP 4 OF 6'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'Recording');

    await _tapAndAdvance(tester, find.text('Continue'));
    expect(find.text('STEP 5 OF 6'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'Hotkey');

    await _tapAndAdvance(tester, find.text('Continue'));
    expect(find.text('STEP 6 OF 6'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'Finish');
  });
}

Future<void> _pumpWizard(WidgetTester tester) async {
  await tester.binding.setSurfaceSize(const Size(860, 640));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: OnboardingWizard(
        settingsService: OnboardingTestSettingsService(),
        onComplete: () {},
      ),
    ),
  );
  await tester.pump();
}

Future<void> _tapAndAdvance(WidgetTester tester, Finder target) async {
  await tester.tap(target.hitTestable().first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
}
