import 'package:beeamvo/services/secure_credential_store.dart';
import 'package:beeamvo/services/settings_service.dart';
import 'package:beeamvo/theme/app_theme.dart';
import 'package:beeamvo/widgets/mode_cloud_confirm_popup.dart';
import 'package:beeamvo/widgets/prompt_cloud_switch_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Records backend/two-pass writes so the dialog's applied choice can be
/// asserted without touching disk.
class _FakeSettings extends SettingsService {
  _FakeSettings({this.cloudReady = true})
    : super(credentialStore: InMemorySecureCredentialStore());

  final bool cloudReady;
  TranscriptionBackend backend = TranscriptionBackend.whisper;
  bool twoPass = false;

  @override
  bool get hasCloudCredentials => cloudReady;

  @override
  TranscriptionBackend get transcriptionBackend => backend;

  @override
  bool get twoPassTranscriptionEnabled => twoPass;

  @override
  Future<void> setTranscriptionBackend(TranscriptionBackend value) async {
    backend = value;
  }

  @override
  Future<void> setTwoPassTranscriptionEnabled(bool value) async {
    twoPass = value;
  }
}

/// Holds the captured result so keyboard-driven tests can assert the outcome
/// after the dialog closes.
class _ResultBox {
  PromptCloudResult? value;
}

Future<_ResultBox> _openDialog(
  WidgetTester tester,
  SettingsService settings, {
  PromptCloudFeature feature = PromptCloudFeature.prompt,
  String? promptName = 'Concise',
}) async {
  final box = _ResultBox();
  await tester.binding.setSurfaceSize(const Size(900, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              box.value = await showPromptCloudSwitchDialog(
                context: context,
                settings: settings,
                feature: feature,
                promptName: promptName,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return box;
}

/// Pumps the inline [ModeCloudConfirmPopup] inside a fixed 320x360 box (the
/// size of the Ctrl+M popup window) so its Expanded body has bounded height.
Future<void> _pumpInlinePopup(
  WidgetTester tester,
  SettingsService settings, {
  int selectedIndex = 0,
  ValueChanged<int>? onSelect,
  VoidCallback? onOpenSettings,
  VoidCallback? onCancel,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 700));
  addTearDown(() => tester.binding.setSurfaceSize(null));

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320,
            height: 360,
            child: ModeCloudConfirmPopup(
              settingsService: settings,
              promptName: 'Concise',
              selectedIndex: selectedIndex,
              onSelect: onSelect ?? (_) {},
              onOpenSettings: onOpenSettings ?? () {},
              onCancel: onCancel ?? () {},
            ),
          ),
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

  testWidgets('shows the switch message and both options', (tester) async {
    await _openDialog(tester, _FakeSettings());

    expect(find.textContaining('For prompt usage'), findsOneWidget);
    expect(find.text('Local + 2-pass cloud'), findsOneWidget);
    expect(find.text('Cloud transcription'), findsOneWidget);
    expect(find.text('Switch'), findsOneWidget);
  });

  testWidgets('default choice keeps local transcription with two-pass', (
    tester,
  ) async {
    final settings = _FakeSettings()
      ..backend = TranscriptionBackend.whisper
      ..twoPass = false;

    await _openDialog(tester, settings);
    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();

    // Local transcription preserved, cloud refinement turned on.
    expect(settings.backend, TranscriptionBackend.whisper);
    expect(settings.twoPass, isTrue);
  });

  testWidgets('choosing cloud switches the backend fully to cloud', (
    tester,
  ) async {
    final settings = _FakeSettings()
      ..backend = TranscriptionBackend.whisper
      ..twoPass = false;

    await _openDialog(tester, settings);
    await tester.tap(find.text('Cloud transcription'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();

    expect(settings.backend, TranscriptionBackend.cloud);
    expect(settings.twoPass, isFalse);
  });

  testWidgets('without cloud credentials it offers Open Settings only', (
    tester,
  ) async {
    final settings = _FakeSettings(cloudReady: false);

    await _openDialog(tester, settings);

    expect(find.text('Open Settings'), findsOneWidget);
    expect(find.text('Local + 2-pass cloud'), findsNothing);
    expect(find.text('Cloud transcription'), findsNothing);
    // Backend untouched until the user configures cloud.
    expect(settings.backend, TranscriptionBackend.whisper);
  });

  testWidgets('rephraser feature shows rephraser-specific copy + choices', (
    tester,
  ) async {
    final settings = _FakeSettings()
      ..backend = TranscriptionBackend.whisper
      ..twoPass = false;

    await _openDialog(
      tester,
      settings,
      feature: PromptCloudFeature.rephraser,
      promptName: null,
    );

    expect(find.text('Rephrasing needs a cloud model'), findsOneWidget);
    expect(find.textContaining('For rephraser usage'), findsOneWidget);
    expect(find.text('Local + 2-pass cloud'), findsOneWidget);
    expect(find.text('Cloud transcription'), findsOneWidget);

    await tester.tap(find.text('Switch'));
    await tester.pumpAndSettle();

    // Default (keep local) enables two-pass cloud refinement.
    expect(settings.backend, TranscriptionBackend.whisper);
    expect(settings.twoPass, isTrue);
  });

  testWidgets('renders keyboard navigation hints', (tester) async {
    await _openDialog(tester, _FakeSettings());

    expect(find.text('navigate'), findsOneWidget);
    expect(find.text('switch'), findsOneWidget);
    expect(find.text('cancel'), findsOneWidget);
  });

  testWidgets('arrow keys move selection and Enter confirms (focused window)', (
    tester,
  ) async {
    final settings = _FakeSettings()
      ..backend = TranscriptionBackend.whisper
      ..twoPass = false;

    final box = await _openDialog(tester, settings);

    // Move down to "Cloud transcription", then confirm with Enter.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(settings.backend, TranscriptionBackend.cloud);
    expect(box.value, PromptCloudResult.cloud);
  });

  testWidgets('Escape cancels without changing settings (focused window)', (
    tester,
  ) async {
    final settings = _FakeSettings()
      ..backend = TranscriptionBackend.whisper
      ..twoPass = false;

    final box = await _openDialog(tester, settings);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(settings.backend, TranscriptionBackend.whisper);
    expect(settings.twoPass, isFalse);
    expect(box.value, PromptCloudResult.cancelled);
  });

  // ── Inline cloud-switch popup (Ctrl+M flow) ──────────────────────────────
  // The Ctrl+M popup renders the cloud switch INLINE (no resize, no modal) via
  // [ModeCloudConfirmPopup], reusing the same [PromptCloudModeTile] as the
  // modal so the two contexts stay visually identical.

  testWidgets('inline popup lists both options and the keyboard hints', (
    tester,
  ) async {
    await _pumpInlinePopup(tester, _FakeSettings());

    expect(find.text('Prompts need a cloud model'), findsOneWidget);
    expect(find.text('Local + 2-pass cloud'), findsOneWidget);
    expect(find.text('Cloud transcription'), findsOneWidget);
    expect(find.text('navigate'), findsOneWidget);
    expect(find.text('switch'), findsOneWidget);
    expect(find.text('cancel'), findsOneWidget);
  });

  testWidgets('inline popup confirms the tapped option by index', (
    tester,
  ) async {
    int? confirmed;
    await _pumpInlinePopup(
      tester,
      _FakeSettings(),
      onSelect: (i) => confirmed = i,
    );

    await tester.tap(find.text('Cloud transcription'));
    await tester.pumpAndSettle();

    expect(confirmed, 1);
  });

  testWidgets('inline popup without cloud credentials offers Open Settings', (
    tester,
  ) async {
    var openedSettings = false;
    await _pumpInlinePopup(
      tester,
      _FakeSettings(cloudReady: false),
      onOpenSettings: () => openedSettings = true,
    );

    expect(find.text('Open Settings'), findsOneWidget);
    expect(find.text('Local + 2-pass cloud'), findsNothing);
    expect(find.text('Cloud transcription'), findsNothing);

    await tester.tap(find.text('Open Settings'));
    await tester.pumpAndSettle();
    expect(openedSettings, isTrue);
  });
}
