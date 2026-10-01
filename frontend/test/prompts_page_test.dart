import 'package:beeamvo/models/system_prompt.dart';
import 'package:beeamvo/providers/settings_provider.dart';
import 'package:beeamvo/services/secure_credential_store.dart';
import 'package:beeamvo/services/settings_service.dart';
import 'package:beeamvo/theme/app_theme.dart';
import 'package:beeamvo/widgets/settings/pages/prompts_page.dart';
import 'package:beeamvo/widgets/settings/settings_shared.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Minimal in-memory settings fake for the Writing Style page, following the
/// repo's `_Settings extends SettingsService` pattern. Only the prompt
/// selection and custom-prompt storage are overridden; everything else stays
/// at the base defaults, where the cloud backend plus the prompt-capable
/// default model keep `promptIsApplied` true (styles active).
class _Settings extends SettingsService {
  _Settings({List<SystemPrompt> seededCustoms = const []})
    : customs = List.of(seededCustoms),
      super(credentialStore: InMemorySecureCredentialStore());

  final List<SystemPrompt> customs;
  String promptId = SystemPrompt.defaultId;

  @override
  List<SystemPrompt> get customPrompts => customs;

  @override
  String get selectedPromptId => promptId;

  @override
  Future<void> setSelectedPromptId(String value) async {
    if (!promptIsApplied && value != SystemPrompt.defaultId) return;
    promptId = value;
    notifyListeners();
  }

  @override
  Future<void> addCustomPrompt(SystemPrompt prompt) async {
    customs.add(prompt);
    notifyListeners();
  }

  @override
  Future<void> updateCustomPrompt(SystemPrompt prompt) async {
    final index = customs.indexWhere((p) => p.id == prompt.id);
    if (index != -1) customs[index] = prompt;
    notifyListeners();
  }
}

Future<void> _pumpPromptsPage(WidgetTester tester, _Settings settings) async {
  final provider = SettingsProvider(settingsService: settings);
  await tester.pumpWidget(
    MaterialApp(
      // AppTheme.lightTheme registers the BeeColors theme extension that
      // the page reads; a bare MaterialApp crashes on the null bang.
      theme: AppTheme.lightTheme,
      home: Scaffold(
        body: SettingsProviderScope(
          provider: provider,
          child: const PromptsPage(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The dialog's TextField carrying [label] ('Name' / 'Instruction').
Finder _dialogTextField(String label) => find.descendant(
  of: find.byType(AlertDialog),
  matching: find.widgetWithText(TextField, label),
);

String _fieldText(WidgetTester tester, String label) =>
    tester.widget<TextField>(_dialogTextField(label)).controller!.text;

/// The 'Start from' dropdown of the style dialog (the Model / Polish model
/// pickers below it are separate dropdowns, so the finder must be scoped).
Finder _dialogDropdown() => find.descendant(
  of: find.widgetWithText(DropdownButtonFormField<String>, 'Start from'),
  matching: find.byType(DropdownButton<String>),
);

/// The pipeline dropdown labelled [label] ('Model' / 'Polish model').
Finder _pipelineDropdown(String label) => find.descendant(
  of: find.widgetWithText(DropdownButtonFormField<String>, label),
  matching: find.byType(DropdownButton<String>),
);

/// Opens the pipeline dropdown labelled [label] and picks the menu item
/// showing [itemText].
Future<void> _pickFromPipelineDropdown(
  WidgetTester tester, {
  required String label,
  required String itemText,
}) async {
  await tester.ensureVisible(_pipelineDropdown(label));
  await tester.tap(_pipelineDropdown(label));
  await tester.pumpAndSettle();
  final item = find.text(itemText).last;
  await tester.ensureVisible(item);
  await tester.tap(item);
  await tester.pumpAndSettle();
}

/// Taps the [label] option of the dialog's transcription-mode segmented
/// control ('Follow global' / 'One-pass' / 'Two-pass').
Future<void> _pickTranscriptionMode(WidgetTester tester, String label) async {
  final option = find.descendant(
    of: find.byType(BeeSegmented<String>),
    matching: find.text(label),
  );
  await tester.ensureVisible(option);
  await tester.tap(option);
  await tester.pumpAndSettle();
}

Future<void> _openNewStyleDialog(WidgetTester tester) async {
  await tester.ensureVisible(find.text('New'));
  await tester.tap(find.text('New'));
  await tester.pumpAndSettle();
}

/// Opens the 'Start from' dropdown and picks the menu item showing
/// [itemText] (the last match: the open menu overlays the page rows).
Future<void> _pickStartFrom(WidgetTester tester, String itemText) async {
  await tester.tap(_dialogDropdown());
  await tester.pumpAndSettle();
  await tester.tap(find.text(itemText).last);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  final professional = SystemPrompt.availablePrompts.firstWhere(
    (p) => p.id == SystemPrompt.professionalId,
  );

  testWidgets('lists built-in styles and the empty state without customs', (
    tester,
  ) async {
    final settings = _Settings();
    await _pumpPromptsPage(tester, settings);

    expect(tester.takeException(), isNull);
    // Sanity per the settings contract: a plain fake (cloud backend +
    // prompt-capable default model) keeps styles active.
    expect(settings.promptIsApplied, isTrue);
    expect(find.text('Open Transcription'), findsNothing);
    expect(find.text('Built-in'), findsOneWidget);
    expect(find.text('Your styles'), findsOneWidget);
    for (final prompt in SystemPrompt.availablePrompts) {
      expect(find.text(prompt.name), findsWidgets);
    }
    expect(find.text('No custom styles yet'), findsOneWidget);
    expect(settings.customPrompts, isEmpty);
  });

  testWidgets(
    'the New Style dialog offers Blank plus every built-in as a base',
    (tester) async {
      await _pumpPromptsPage(tester, _Settings());
      await _openNewStyleDialog(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('New Style'), findsOneWidget);
      expect(find.text('Start from'), findsOneWidget);
      // 'Blank' is the initially selected option, shown by the closed field.
      expect(find.text('Blank'), findsOneWidget);
      expect(_fieldText(tester, 'Name'), isEmpty);
      expect(_fieldText(tester, 'Instruction'), isEmpty);
      expect(find.text('0 characters'), findsOneWidget);

      final dropdown = tester.widget<DropdownButton<String>>(_dialogDropdown());
      expect(dropdown.items, isNotNull);
      expect(dropdown.items!.map((item) => item.value), [
        '',
        for (final prompt in SystemPrompt.availablePrompts) prompt.id,
      ]);
      expect(dropdown.items!.map((item) => (item.child as Text).data), [
        'Blank',
        for (final prompt in SystemPrompt.availablePrompts) prompt.name,
      ]);

      // Opening the menu really renders the items: 'Blank' is then shown by
      // both the closed field and the menu, and each built-in gains its menu
      // copy on top of its page row.
      await tester.tap(_dialogDropdown());
      await tester.pumpAndSettle();
      expect(find.text('Blank'), findsNWidgets(2));
      expect(find.text(professional.name), findsNWidgets(2));

      // Back to Blank keeps the dialog pristine.
      await tester.tap(find.text('Blank').last);
      await tester.pumpAndSettle();
      expect(_fieldText(tester, 'Instruction'), isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'picking a base prefills the instruction, auto-suggests a name, and '
    'refreshes the counter',
    (tester) async {
      await _pumpPromptsPage(tester, _Settings());
      await _openNewStyleDialog(tester);

      await _pickStartFrom(tester, professional.name);

      expect(tester.takeException(), isNull);
      expect(_fieldText(tester, 'Instruction'), professional.instruction);
      expect(_fieldText(tester, 'Name'), '${professional.name} (custom)');
      expect(
        find.text('${professional.instruction.length} characters'),
        findsOneWidget,
      );
      // The closed dropdown now displays the chosen base next to the page's
      // own built-in row for it.
      expect(find.text(professional.name), findsNWidgets(2));
    },
  );

  testWidgets('a user-typed name survives a later base pick', (tester) async {
    await _pumpPromptsPage(tester, _Settings());
    await _openNewStyleDialog(tester);

    await tester.enterText(_dialogTextField('Name'), 'Meeting Recap');
    await _pickStartFrom(tester, professional.name);

    expect(tester.takeException(), isNull);
    expect(_fieldText(tester, 'Name'), 'Meeting Recap');
    expect(_fieldText(tester, 'Instruction'), professional.instruction);
    expect(
      find.text('${professional.instruction.length} characters'),
      findsOneWidget,
    );
  });

  testWidgets('re-picking Blank clears the instruction and the auto name', (
    tester,
  ) async {
    await _pumpPromptsPage(tester, _Settings());
    await _openNewStyleDialog(tester);

    await _pickStartFrom(tester, professional.name);
    expect(_fieldText(tester, 'Instruction'), professional.instruction);
    expect(_fieldText(tester, 'Name'), '${professional.name} (custom)');

    await _pickStartFrom(tester, 'Blank');

    expect(tester.takeException(), isNull);
    expect(_fieldText(tester, 'Instruction'), isEmpty);
    // The auto-suggested name was still untouched, so Blank removes it.
    expect(_fieldText(tester, 'Name'), isEmpty);
    expect(find.text('0 characters'), findsOneWidget);
    expect(find.text('Blank'), findsOneWidget);
  });

  testWidgets(
    'creating from a base persists the edited instruction and selects the '
    'new style',
    (tester) async {
      final settings = _Settings();
      await _pumpPromptsPage(tester, settings);
      await _openNewStyleDialog(tester);

      await _pickStartFrom(tester, professional.name);
      const marker = 'MARKER: quarterly recap';
      await tester.enterText(
        _dialogTextField('Instruction'),
        '${professional.instruction}\n\n$marker',
      );
      await tester.enterText(_dialogTextField('Name'), 'Quarterly Digest');

      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      expect(settings.customPrompts, hasLength(1));
      final created = settings.customPrompts.last;
      expect(created.name, 'Quarterly Digest');
      // The persisted instruction is the edited text, not the raw base.
      expect(created.instruction, contains(marker));
      expect(created.instruction, isNot(professional.instruction));
      expect(settings.selectedPromptId, created.id);
      // The new row appears and the Current Style block names it with a
      // CUSTOM badge (two text occurrences: current block + row).
      expect(find.text('Quarterly Digest'), findsNWidgets(2));
      expect(find.text('CUSTOM'), findsOneWidget);
      expect(find.text('No custom styles yet'), findsNothing);
    },
  );

  testWidgets(
    'Create still validates: required, duplicate, and missing instruction '
    'keep the dialog open',
    (tester) async {
      final settings = _Settings();
      await _pumpPromptsPage(tester, settings);
      await _openNewStyleDialog(tester);

      // Base picked but name cleared: the required-name error fires.
      await _pickStartFrom(tester, professional.name);
      await tester.enterText(_dialogTextField('Name'), '');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Name is required'), findsOneWidget);
      expect(find.text('New Style'), findsOneWidget);

      // A built-in's name is still a duplicate.
      await tester.enterText(_dialogTextField('Name'), professional.name);
      await tester.pumpAndSettle();
      expect(
        find.text('A style with this name already exists'),
        findsOneWidget,
      );
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      // Valid name but emptied instruction: the instruction error fires.
      await tester.enterText(_dialogTextField('Name'), 'Workshop Notes');
      await tester.enterText(_dialogTextField('Instruction'), '');
      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();
      expect(find.text('Instruction is required'), findsOneWidget);
      expect(find.text('New Style'), findsOneWidget);
      expect(settings.customPrompts, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'the edit dialog has no start-from selector and saves updates in place',
    (tester) async {
      const seededInstruction =
          'Take terse field notes with owners and due '
          'dates.';
      final settings = _Settings(
        seededCustoms: const [
          SystemPrompt(
            id: 'custom_field_notes',
            name: 'Field Notes',
            instruction: seededInstruction,
          ),
        ],
      );
      await _pumpPromptsPage(tester, settings);
      expect(find.text('Field Notes'), findsOneWidget);

      await tester.ensureVisible(find.byTooltip('Edit Field Notes'));
      await tester.tap(find.byTooltip('Edit Field Notes'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Edit Style'), findsOneWidget);
      expect(find.text('Start from'), findsNothing);
      // The edit dialog keeps the pipeline group: the Model picker (cloud
      // backend fake) is its only dropdown while one-pass hides Polish.
      expect(_pipelineDropdown('Model'), findsOneWidget);
      expect(find.text('Polish model'), findsNothing);
      expect(_fieldText(tester, 'Name'), 'Field Notes');
      expect(_fieldText(tester, 'Instruction'), seededInstruction);

      const marker = 'MARKER: edited in place';
      await tester.enterText(_dialogTextField('Name'), 'Field Notes Pro');
      await tester.enterText(
        _dialogTextField('Instruction'),
        '$seededInstruction\n\n$marker',
      );
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      final updated = settings.customPrompts.single;
      expect(updated.id, 'custom_field_notes');
      expect(updated.name, 'Field Notes Pro');
      expect(updated.instruction, contains(marker));
      expect(find.text('Field Notes Pro'), findsOneWidget);
    },
  );

  testWidgets('duplicating a built-in adds a named copy under Your styles', (
    tester,
  ) async {
    final settings = _Settings();
    await _pumpPromptsPage(tester, settings);

    await tester.ensureVisible(find.byTooltip('Duplicate Default'));
    await tester.tap(find.byTooltip('Duplicate Default'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final dup = settings.customPrompts.single;
    expect(dup.name, 'Default Copy');
    expect(
      dup.instruction,
      SystemPrompt.getById(SystemPrompt.defaultId).instruction,
    );
    // Duplicates start without pipeline overrides (follow global).
    expect(dup.twoPassOverride, isNull);
    expect(dup.modelOverrideId, isNull);
    expect(dup.polishModelOverrideId, isNull);
    expect(find.byTooltip('Uses its own pipeline settings'), findsNothing);
    expect(find.text('Default Copy'), findsOneWidget);
    expect(find.text('No custom styles yet'), findsNothing);
  });

  testWidgets(
    'the new-style dialog offers a pipeline group with Follow global defaults',
    (tester) async {
      final settings = _Settings();
      await _pumpPromptsPage(tester, settings);
      await _openNewStyleDialog(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('PIPELINE'), findsOneWidget);
      expect(find.text('Transcription mode'), findsOneWidget);
      // Defaults: the segmented mode control and the Model picker both sit
      // on 'Follow global'; the Polish picker stays hidden while the
      // effective mode is one-pass (the fake keeps global two-pass off).
      expect(find.text('Follow global'), findsNWidgets(2));
      expect(find.text('Polish model'), findsNothing);

      final modelItems = tester
          .widget<DropdownButton<String>>(_pipelineDropdown('Model'))
          .items!;
      expect(modelItems.map((item) => item.value), [
        '',
        for (final model in settings.primaryModels) model.id,
      ]);
      expect(modelItems.map((item) => (item.child as Text).data), [
        'Follow global',
        for (final model in settings.primaryModels) model.displayName,
      ]);

      // Two-pass reveals the Polish picker with the refinement catalog.
      await _pickTranscriptionMode(tester, 'Two-pass');
      expect(find.text('Polish model'), findsOneWidget);
      final polishItems = tester
          .widget<DropdownButton<String>>(_pipelineDropdown('Polish model'))
          .items!;
      expect(polishItems.map((item) => item.value), [
        '',
        for (final model in settings.refinementModels) model.id,
      ]);
      expect(polishItems.map((item) => (item.child as Text).data), [
        'Follow global',
        for (final model in settings.refinementModels) model.displayName,
      ]);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'saving a Two-pass style with both models persists the overrides and '
    'surfaces them on the page',
    (tester) async {
      final settings = _Settings();
      await _pumpPromptsPage(tester, settings);
      await _openNewStyleDialog(tester);

      await tester.enterText(_dialogTextField('Name'), 'Slow And Careful');
      await tester.enterText(
        _dialogTextField('Instruction'),
        'Take your time and write it well.',
      );
      await _pickTranscriptionMode(tester, 'Two-pass');
      await _pickFromPipelineDropdown(
        tester,
        label: 'Model',
        itemText: 'Gemini 3.7 Flash',
      );
      await _pickFromPipelineDropdown(
        tester,
        label: 'Polish model',
        itemText: 'Gemini 3.5 Flash',
      );

      await tester.tap(find.text('Create'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      final created = settings.customPrompts.single;
      expect(created.twoPassOverride, isTrue);
      expect(created.modelOverrideId, 'gemini-3.7-flash');
      expect(created.polishModelOverrideId, 'gemini-3.5-flash');
      // Round-trip through the service's own resolver.
      final pipeline = settings.resolvePipelineForPrompt(created);
      expect(pipeline.twoPass, isTrue);
      expect(pipeline.pass1ModelId, 'gemini-3.7-flash');
      expect(pipeline.polishModelId, 'gemini-3.5-flash');
      // The row carries the tune affordance, and the (auto-selected) Current
      // Style block summarizes the pipeline.
      expect(find.byTooltip('Uses its own pipeline settings'), findsOneWidget);
      expect(
        find.text(
          'Own pipeline · Two-pass · Gemini 3.7 Flash → Gemini 3.5 Flash',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('leaving every picker on Follow global saves null overrides', (
    tester,
  ) async {
    final settings = _Settings();
    await _pumpPromptsPage(tester, settings);
    await _openNewStyleDialog(tester);

    await tester.enterText(_dialogTextField('Name'), 'Plain Vanilla');
    await tester.enterText(
      _dialogTextField('Instruction'),
      'Just clean up the words.',
    );
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final created = settings.customPrompts.single;
    expect(created.modelOverrideId, isNull);
    expect(created.polishModelOverrideId, isNull);
    expect(created.twoPassOverride, isNull);
    expect(find.byTooltip('Uses its own pipeline settings'), findsNothing);
    expect(find.textContaining('Own pipeline ·'), findsNothing);
  });

  testWidgets(
    'the edit dialog seeds the pipeline group and clears back to Follow global',
    (tester) async {
      final settings = _Settings(
        seededCustoms: const [
          SystemPrompt(
            id: 'custom_pipelined',
            name: 'Pipelined',
            instruction: 'Take crisp notes with clear owners.',
            modelOverrideId: 'gemini-2.5-flash',
            polishModelOverrideId: 'gemini-3.7-flash',
            twoPassOverride: true,
          ),
        ],
      );
      await _pumpPromptsPage(tester, settings);

      // Not selected yet: the row still flags its own pipeline, and no
      // summary shows while Default is the current style.
      expect(find.byTooltip('Uses its own pipeline settings'), findsOneWidget);
      expect(find.textContaining('Own pipeline ·'), findsNothing);

      // Selecting it surfaces the summary in the Current Style block.
      await tester.ensureVisible(find.text('Pipelined'));
      await tester.tap(find.text('Pipelined'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Own pipeline · Two-pass · Gemini 2.5 Flash → Gemini 3.7 Flash',
        ),
        findsOneWidget,
      );

      await tester.ensureVisible(find.byTooltip('Edit Pipelined'));
      await tester.tap(find.byTooltip('Edit Pipelined'));
      await tester.pumpAndSettle();

      // 'Transcription mode' defaults to the stored override: Two-pass, with
      // both pickers prefilled from the stored model ids.
      expect(find.text('Transcription mode'), findsOneWidget);
      expect(
        tester.widget<DropdownButton<String>>(_pipelineDropdown('Model')).value,
        'gemini-2.5-flash',
      );
      expect(
        tester
            .widget<DropdownButton<String>>(_pipelineDropdown('Polish model'))
            .value,
        'gemini-3.7-flash',
      );

      // Editing every override back to Follow global clears all three.
      await _pickFromPipelineDropdown(
        tester,
        label: 'Model',
        itemText: 'Follow global',
      );
      await _pickFromPipelineDropdown(
        tester,
        label: 'Polish model',
        itemText: 'Follow global',
      );
      await _pickTranscriptionMode(tester, 'Follow global');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(AlertDialog), findsNothing);
      final updated = settings.customPrompts.single;
      expect(updated.id, 'custom_pipelined');
      expect(updated.modelOverrideId, isNull);
      expect(updated.polishModelOverrideId, isNull);
      expect(updated.twoPassOverride, isNull);
      expect(find.byTooltip('Uses its own pipeline settings'), findsNothing);
      expect(find.textContaining('Own pipeline ·'), findsNothing);
    },
  );

  testWidgets('a hidden Polish override survives an edit of a one-pass style', (
    tester,
  ) async {
    final settings = _Settings(
      seededCustoms: const [
        SystemPrompt(
          id: 'custom_onepass',
          name: 'One Pass Notes',
          instruction: 'Keep it lean and tidy, please.',
          modelOverrideId: 'gemini-2.5-flash',
          polishModelOverrideId: 'gemini-3.7-flash',
          twoPassOverride: false,
        ),
      ],
    );
    await _pumpPromptsPage(tester, settings);

    // One-pass: the summary names the pass-1 model only.
    await tester.ensureVisible(find.text('One Pass Notes'));
    await tester.tap(find.text('One Pass Notes'));
    await tester.pumpAndSettle();
    expect(
      find.text('Own pipeline · One-pass · Gemini 2.5 Flash'),
      findsOneWidget,
    );

    await tester.ensureVisible(find.byTooltip('Edit One Pass Notes'));
    await tester.tap(find.byTooltip('Edit One Pass Notes'));
    await tester.pumpAndSettle();

    // The Polish picker is hidden by the forced one-pass mode…
    expect(find.text('Polish model'), findsNothing);
    // …and saving without touching it keeps the stored override.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    final updated = settings.customPrompts.single;
    expect(updated.twoPassOverride, isFalse);
    expect(updated.modelOverrideId, 'gemini-2.5-flash');
    expect(updated.polishModelOverrideId, 'gemini-3.7-flash');
  });

  testWidgets(
    'the dialog warns about a transcription-only one-pass draft and clears '
    'the warning on Two-pass',
    (tester) async {
      final settings = _Settings();
      await _pumpPromptsPage(tester, settings);
      await _openNewStyleDialog(tester);

      // One-pass on the prompt-capable default model still applies styles.
      await _pickTranscriptionMode(tester, 'One-pass');
      expect(find.textContaining("won't shape the transcript"), findsNothing);

      // A transcription-only pass-1 model breaks single-pass styling…
      await _pickFromPipelineDropdown(
        tester,
        label: 'Model',
        itemText: 'Gemini 3.5 Transcribe (Preview)',
      );
      expect(find.textContaining("won't shape the transcript"), findsOneWidget);
      // …and the readiness reason rides along as the second line (the fake
      // has no cloud credentials).
      expect(find.textContaining('Add your Gemini API key'), findsOneWidget);

      // Two-pass moves the style onto the polish pass again.
      await _pickTranscriptionMode(tester, 'Two-pass');
      expect(find.textContaining("won't shape the transcript"), findsNothing);
      expect(find.textContaining('Add your Gemini API key'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
