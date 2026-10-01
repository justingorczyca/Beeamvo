import 'package:beeamvo/config.dart';
import 'package:beeamvo/models/system_prompt.dart';
import 'package:beeamvo/services/secure_credential_store.dart';
import 'package:beeamvo/services/settings_service.dart';
import 'package:beeamvo/theme/app_theme.dart';
import 'package:beeamvo/widgets/mode_selection_popup.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Minimal settings fake: the popup and its helpers only read the
/// selectability gate, the active backend, the prompt list, and the saved
/// prompt id. Global pipeline state is modeled with the same knobs the real
/// service resolves from (backend, provider, pass-1 model, two-pass toggle),
/// so the real [SettingsService.promptAppliesFor] — and therefore
/// [promptSelectableInModePopup] — evaluates per-style overrides exactly
/// like production.
class _Settings extends SettingsService {
  _Settings({
    this.twoPass = false,
    this.backend = TranscriptionBackend.cloud,
    this.custom = const [],
    this.modelId = AppConfig.defaultModelId,
  }) : super(credentialStore: InMemorySecureCredentialStore());

  final bool twoPass;
  final TranscriptionBackend backend;
  final List<SystemPrompt> custom;
  final String modelId;

  @override
  bool get twoPassTranscriptionEnabled => twoPass;

  @override
  TranscriptionBackend get transcriptionBackend => backend;

  @override
  CloudProvider get cloudProvider => CloudProvider.geminiApiKey;

  @override
  String get selectedModelId => modelId;

  @override
  List<SystemPrompt> get customPrompts => custom;

  @override
  String get selectedPromptId => SystemPrompt.defaultId;
}

/// Cloud single-pass on a transcription-only model: the global pipeline
/// cannot apply styles.
_Settings _lockedCloud() => _Settings(modelId: 'gemini-3.5-transcribe');

// Pinned lock-notice copy so accidental rewording fails loudly here.
const String _cloudLockNotice =
    'Styles need a prompt-capable model or Two-Step Refinement. '
    'Only Default is available.';
const String _whisperLockNotice =
    'Whisper transcribes only. Turn on Two-Step Refinement to apply styles.';

const SystemPrompt _emailIsh = SystemPrompt(
  id: 'email-ish',
  name: 'Email-ish',
  instruction: 'Shape the transcript like a short email.',
);

/// A custom style that forces the two-step pipeline.
const SystemPrompt _forcedTwoPass = SystemPrompt(
  id: 'forced-two-pass',
  name: 'Forced Two-Step',
  instruction: 'Write it nicely.',
  twoPassOverride: true,
);

/// A custom style that forces single-pass (pass 1 stays the global model).
const SystemPrompt _forcedSinglePass = SystemPrompt(
  id: 'forced-single-pass',
  name: 'Forced One-Step',
  instruction: 'Write it plainly.',
  twoPassOverride: false,
);

/// A custom style that pins a prompt-capable pass-1 model.
const SystemPrompt _pinnedFlash = SystemPrompt(
  id: 'pinned-flash',
  name: 'Pinned Flash',
  instruction: 'Write it fast.',
  modelOverrideId: 'gemini-2.5-flash',
);

/// Pumps the popup with bounded constraints (its prompt list lives inside an
/// Expanded) and the Bee theme extension registered, mirroring the setup
/// ai_models_page_test.dart uses.
Future<void> _pumpPopup(
  WidgetTester tester,
  SettingsService settings, {
  int selectedIndex = 0,
  void Function(String promptId)? onSelect,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      // AppTheme.lightTheme registers the BeeColors extension that every
      // bee*() helper in the popup reads; a bare MaterialApp would crash
      // on the null-extension bang.
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            // The keycap-hint footer is an unlaid Row, and tests render in
            // Ahem (every glyph is a square), which makes it far wider than
            // production fonts do — so the bounded box is generous.
            width: 560,
            height: 460,
            child: ModeSelectionPopup(
              settingsService: settings,
              selectedIndex: selectedIndex,
              onSelect: onSelect ?? (_) {},
              onCancel: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

int _next(
  SettingsService settings,
  List<SystemPrompt> prompts,
  int current,
  int delta,
) => nextSelectableModeIndex(
  prompts: prompts,
  settings: settings,
  current: current,
  delta: delta,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    // Never reach the network for fonts from inside the test harness.
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('promptSelectableInModePopup', () {
    test('Default stays selectable in every pipeline state', () {
      final defaultPrompt = SystemPrompt.availablePrompts.first;
      expect(defaultPrompt.id, SystemPrompt.defaultId);
      for (final settings in [_Settings(), _lockedCloud()]) {
        expect(
          promptSelectableInModePopup(settings, defaultPrompt),
          isTrue,
          reason: 'promptIsApplied: ${settings.promptIsApplied}',
        );
      }
    });

    test('a built-in style follows promptIsApplied', () {
      final professional = SystemPrompt.availablePrompts.firstWhere(
        (prompt) => prompt.id == SystemPrompt.professionalId,
      );
      expect(promptSelectableInModePopup(_Settings(), professional), isTrue);
      expect(
        promptSelectableInModePopup(_lockedCloud(), professional),
        isFalse,
      );
    });

    test('a custom style follows promptIsApplied', () {
      expect(promptSelectableInModePopup(_Settings(), _emailIsh), isTrue);
      expect(promptSelectableInModePopup(_lockedCloud(), _emailIsh), isFalse);
    });
  });

  group('per-style overrides', () {
    test('twoPassOverride=true applies a style the global setup locks', () {
      final settings = _lockedCloud();
      expect(settings.promptIsApplied, isFalse);
      expect(promptSelectableInModePopup(settings, _forcedTwoPass), isTrue);
      // Built-ins keep following the locked global state.
      expect(
        promptSelectableInModePopup(settings, SystemPrompt.availablePrompts[1]),
        isFalse,
      );
    });

    test('a prompt-capable pass-1 override applies in single-pass', () {
      expect(promptSelectableInModePopup(_lockedCloud(), _pinnedFlash), isTrue);
    });

    test('twoPassOverride=false locks a style under global two-pass on a '
        'transcription-only model', () {
      final settings = _Settings(
        twoPass: true,
        modelId: 'gemini-3.5-transcribe',
      );
      expect(settings.promptIsApplied, isTrue);
      expect(promptSelectableInModePopup(settings, _forcedSinglePass), isFalse);
    });

    test('nextSelectableModeIndex lands on unlocked custom prompts', () {
      final settings = _lockedCloud();
      final prompts = [...SystemPrompt.availablePrompts, _forcedTwoPass];
      // Forward from Default skips every locked built-in onto the custom
      // style; backward from it returns to Default.
      expect(_next(settings, prompts, 0, 1), prompts.length - 1);
      expect(_next(settings, prompts, prompts.length - 1, -1), 0);
      expect(_next(settings, prompts, 3, 1), prompts.length - 1);
    });
  });

  group('nextSelectableModeIndex', () {
    // The built-in list: Default first, then Concise, Smart Mode,
    // Professional.
    final prompts = SystemPrompt.availablePrompts;
    // Default parked behind two locked styles, with one locked after it.
    final parked = [prompts[1], prompts[2], prompts.first, prompts.last];

    test('forward from Default holds when nothing later is selectable', () {
      final locked = _lockedCloud();
      expect(_next(locked, prompts, 0, 1), 0);
      expect(_next(locked, parked, 2, 1), 2);
    });

    test('forward skips locked styles to the next selectable index', () {
      final locked = _lockedCloud();
      // Concise and Smart Mode are locked; Default sits at index 2.
      expect(_next(locked, parked, 0, 1), 2);
      expect(_next(locked, parked, 1, 1), 2);
    });

    test('backward skips locked styles to the previous selectable index', () {
      final locked = _lockedCloud();
      expect(_next(locked, parked, 3, -1), 2);
      expect(_next(locked, parked, 2, -1), 2);
      // On the real built-in list, stepping up from Professional lands on
      // Default, skipping Smart Mode and Concise.
      expect(_next(locked, prompts, 3, -1), 0);
    });

    test('never wraps beyond either end of the list', () {
      final locked = _lockedCloud();
      final unlocked = _Settings();
      expect(_next(locked, parked, 3, 1), 3);
      expect(_next(locked, parked, 0, -1), 0);
      expect(
        _next(unlocked, prompts, prompts.length - 1, 1),
        prompts.length - 1,
      );
      expect(_next(unlocked, prompts, 0, -1), 0);
    });

    test('unlocked behaves like plain +1/-1 clamped to the list', () {
      final unlocked = _Settings();
      expect(_next(unlocked, prompts, 1, 1), 2);
      expect(_next(unlocked, prompts, 2, -1), 1);
      // Only the sign of delta matters, not its magnitude.
      expect(_next(unlocked, prompts, 1, 5), 2);
      expect(_next(unlocked, prompts, 1, -7), 0);
    });

    test('zero delta returns the current index unchanged', () {
      final locked = _lockedCloud();
      final unlocked = _Settings();
      expect(_next(locked, prompts, 3, 0), 3);
      expect(_next(unlocked, prompts, 1, 0), 1);
    });
  });

  group('ModeSelectionPopup', () {
    testWidgets(
      'unlocked pipeline keeps every style tappable with no lock UI',
      (tester) async {
        final selected = <String>[];
        await _pumpPopup(tester, _Settings(), onSelect: selected.add);

        expect(tester.takeException(), isNull);
        expect(find.text('Select Mode'), findsOneWidget);
        expect(find.byIcon(Icons.lock_outline_rounded), findsNothing);
        expect(find.text(_cloudLockNotice), findsNothing);
        expect(find.text(_whisperLockNotice), findsNothing);

        final second = SystemPrompt.availablePrompts[1];
        await tester.tap(find.text(second.name));
        await tester.pump();

        expect(selected, [second.id]);
      },
    );

    testWidgets('locked single-pass cloud locks every non-Default style', (
      tester,
    ) async {
      final selected = <String>[];
      final settings = _Settings(
        modelId: 'gemini-3.5-transcribe',
        custom: const [_emailIsh],
      );
      await _pumpPopup(tester, settings, onSelect: selected.add);

      expect(tester.takeException(), isNull);
      final totalCount =
          SystemPrompt.availablePrompts.length + settings.customPrompts.length;
      // Default never gets a lock; every other tile — including custom
      // styles — does.
      expect(
        find.byIcon(Icons.lock_outline_rounded),
        findsNWidgets(totalCount - 1),
      );
      expect(find.text('Email-ish'), findsOneWidget);
      expect(find.text(_cloudLockNotice), findsOneWidget);
      expect(find.text(_whisperLockNotice), findsNothing);
      // The saved style keeps its DEFAULT badge while locked.
      expect(find.text('DEFAULT'), findsOneWidget);

      await tester.tap(find.text('Concise'));
      await tester.pump();
      await tester.tap(find.text('Email-ish'));
      await tester.pump();
      expect(selected, isEmpty);

      await tester.tap(find.text('Default'));
      await tester.pump();
      expect(selected, [SystemPrompt.defaultId]);
    });

    testWidgets('locked offline Whisper swaps the notice copy', (tester) async {
      final selected = <String>[];
      await _pumpPopup(
        tester,
        _Settings(backend: TranscriptionBackend.whisper),
        onSelect: selected.add,
      );

      expect(tester.takeException(), isNull);
      expect(find.text(_whisperLockNotice), findsOneWidget);
      expect(find.text(_cloudLockNotice), findsNothing);
      expect(
        find.byIcon(Icons.lock_outline_rounded),
        findsNWidgets(SystemPrompt.availablePrompts.length - 1),
      );
    });

    testWidgets(
      'a forced two-step custom style stays selectable while built-ins lock',
      (tester) async {
        final selected = <String>[];
        final settings = _Settings(
          modelId: 'gemini-3.5-transcribe',
          custom: const [_forcedTwoPass],
        );
        await _pumpPopup(tester, settings, onSelect: selected.add);

        expect(tester.takeException(), isNull);
        // The global single-pass transcription-only setup locks every
        // built-in (and keeps the pinned notice copy), but the style that
        // forces two-step renders fully usable: full opacity, no lock icon,
        // tappable.
        expect(
          find.byIcon(Icons.lock_outline_rounded),
          findsNWidgets(SystemPrompt.availablePrompts.length - 1),
        );
        expect(find.text(_cloudLockNotice), findsOneWidget);
        expect(
          tester
              .widget<Opacity>(
                find.ancestor(
                  of: find.text('Forced Two-Step'),
                  matching: find.byType(Opacity),
                ),
              )
              .opacity,
          1.0,
        );

        await tester.tap(find.text('Forced Two-Step'));
        await tester.pump();
        expect(selected, [_forcedTwoPass.id]);
      },
    );

    testWidgets(
      'a forced single-pass custom style renders locked under global two-pass',
      (tester) async {
        final selected = <String>[];
        final settings = _Settings(
          twoPass: true,
          modelId: 'gemini-3.5-transcribe',
          custom: const [_forcedSinglePass],
        );
        await _pumpPopup(tester, settings, onSelect: selected.add);

        expect(tester.takeException(), isNull);
        // Global two-pass leaves every built-in selectable; the style that
        // forces one-step onto the transcription-only pass-1 model is the
        // only locked tile and gives no tap feedback.
        expect(find.byIcon(Icons.lock_outline_rounded), findsOneWidget);
        expect(find.text(_cloudLockNotice), findsNothing);

        await tester.tap(find.text('Forced One-Step'));
        await tester.pump();
        expect(selected, isEmpty);
      },
    );
  });
}
