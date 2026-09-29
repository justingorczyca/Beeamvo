import 'package:beeamvo/services/secure_credential_store.dart';
import 'package:beeamvo/services/settings_service.dart';
import 'package:beeamvo/theme/app_theme.dart';
import 'package:beeamvo/widgets/onboarding/onboarding_shared.dart';
import 'package:beeamvo/widgets/onboarding/onboarding_steps.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

class _ProviderStepSettings extends SettingsService {
  _ProviderStepSettings()
    : super(credentialStore: InMemorySecureCredentialStore());

  @override
  TranscriptionBackend get transcriptionBackend => TranscriptionBackend.cloud;

  @override
  CloudProvider get cloudProvider => CloudProvider.geminiApiKey;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('cloud provider cards have equal heights', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: ProviderStep(
            onNext: () {},
            settingsService: _ProviderStepSettings(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final heights = [
      for (final provider in ['Gemini', 'Vertex AI', 'ChatGPT'])
        tester
            .getSize(
              find.ancestor(
                of: find.text(provider),
                matching: find.byType(OnboardingGlowCard),
              ),
            )
            .height,
    ];

    expect(heights, [heights.first, heights.first, heights.first]);
    expect(tester.takeException(), isNull);
  });
}
