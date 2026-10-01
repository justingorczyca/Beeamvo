import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../config.dart';
import '../../../providers/settings_provider.dart';
import '../../../models/system_prompt.dart';
import '../../../services/settings_service.dart';
import '../../../services/whisper_model_download_service.dart';
import '../bee_input.dart';
import '../bee_page_header.dart';
import '../settings_shared.dart';

class PromptsPage extends StatefulWidget {
  final ValueChanged<String>? onPromptChanged;
  const PromptsPage({super.key, this.onPromptChanged});

  @override
  State<PromptsPage> createState() => _PromptsPageState();
}

class _PromptsPageState extends State<PromptsPage> {
  /// Monotonic counter to guarantee unique prompt IDs even when two prompts
  /// are created within the same microsecond.
  static int _promptIdCounter = 0;

  String _selectedPromptId = '';
  List<SystemPrompt> _customPrompts = [];
  final List<SystemPrompt> _builtInPrompts = SystemPrompt.availablePrompts;
  bool _settingsLoaded = false;
  bool _previewExpanded = false;
  SettingsService? _settingsService;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_settingsLoaded) {
      _settingsLoaded = true;
      final s = SettingsProviderScope.of(context).settingsService;
      _settingsService = s;
      setState(() {
        _selectedPromptId = s.selectedPromptId;
        _customPrompts = s.customPrompts;
      });
    } else {
      _syncMutableSettings();
    }
  }

  void _syncMutableSettings() {
    final s = _settingsService;
    if (s == null) return;
    final newPromptId = s.selectedPromptId;
    final newCustomPrompts = s.customPrompts;
    if (newPromptId == _selectedPromptId &&
        identical(newCustomPrompts, _customPrompts)) {
      return;
    }
    setState(() {
      _selectedPromptId = newPromptId;
      _customPrompts = newCustomPrompts;
    });
  }

  SystemPrompt _effectiveSelectedPrompt() {
    final all = [..._builtInPrompts, ..._customPrompts];
    return all.firstWhere(
      (p) => p.id == _selectedPromptId,
      orElse: () => _builtInPrompts.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settingsService!;
    final stylesActive = settings.promptIsApplied;

    return Container(
      color: beeSurface(context),
      child: SingleChildScrollView(
        padding: BeePageHeader.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BeePageHeader(title: 'Writing Style'),
            if (!stylesActive) ...[
              _buildOfflineNotice(),
              const SizedBox(height: BeePageHeader.groupGap),
            ],
            _buildCurrentPromptBlock(stylesActive),
            const SizedBox(height: BeePageHeader.groupGap),
            const BeeGroupLabel(label: 'Tone'),
            BeeSettingsRow(
              icon: Icons.tune_rounded,
              label: 'Tone refinement',
              description: settings.toneRefinement.description,
              showDivider: false,
              trailing: BeeSegmented<ToneRefinement>(
                value: settings.toneRefinement,
                enabled: stylesActive,
                onChanged: (tone) async {
                  await settings.setToneRefinement(tone);
                  setState(() {});
                },
                options: [
                  for (final tone in ToneRefinement.values)
                    (val: tone, label: tone.displayName, icon: null),
                ],
              ),
            ),
            const SizedBox(height: BeePageHeader.groupGap),
            Row(
              children: [
                const Expanded(child: BeeGroupLabel(label: 'All Styles')),
                BeeActionChip(
                  label: 'New',
                  icon: Icons.add_rounded,
                  onTap: () => _showAddDialog(settings),
                ),
              ],
            ),
            _buildSubEyebrow('Built-in'),
            ..._builtInPrompts.map(
              (p) => _buildPromptRow(
                prompt: p,
                isBuiltIn: true,
                settings: settings,
                stylesActive: stylesActive,
              ),
            ),
            const SizedBox(height: 14),
            _buildSubEyebrow('Your styles'),
            if (_customPrompts.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                child: BeeEmptyState(
                  icon: Icons.edit_note_rounded,
                  title: 'No custom styles yet',
                  subtitle:
                      'Write your own instructions for meeting notes, code comments, or anything else.',
                ),
              )
            else
              ..._customPrompts.map(
                (p) => _buildPromptRow(
                  prompt: p,
                  isBuiltIn: false,
                  settings: settings,
                  stylesActive: stylesActive,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Shown when the pipeline cannot apply writing-style prompts: the
  /// selected style is remembered until a prompt-capable model runs.
  Widget _buildOfflineNotice() {
    return BeeSettingsRow(
      icon: Icons.cloud_off_outlined,
      label: 'Writing style is set to Default',
      description:
          'Speech-to-text-only models and offline Whisper paste the plain transcript, so the style stays on Default and tone on Off. To use a style, choose a prompt-capable cloud model or turn on Two-Step Refinement.',
      showDivider: false,
      trailing: BeeActionChip(
        label: 'Open Transcription',
        onTap: () => SettingsProviderScope.of(
          context,
        ).selectCategory(SettingsCategory.aiModels),
      ),
    );
  }

  Widget _buildCurrentPromptBlock(bool stylesActive) {
    final prompt = _effectiveSelectedPrompt();
    final isBuiltIn = _builtInPrompts.any((p) => p.id == prompt.id);
    final pipelineSummary = _currentPipelineSummary(prompt);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BeeGroupLabel(label: 'Current Style'),
        BeeInteractive(
          onTap: () => setState(() => _previewExpanded = !_previewExpanded),
          semanticLabel:
              '${_previewExpanded ? 'Collapse' : 'Expand'} current style instructions',
          builder: (context, focused) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: stylesActive
                        ? beeText(context)
                        : beeTextMuted(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              prompt.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: beeText(context),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          beeBadge(
                            context,
                            isBuiltIn ? 'BUILT-IN' : 'CUSTOM',
                            BeeBadgeTone.neutral,
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      if (pipelineSummary != null) ...[
                        Text(
                          pipelineSummary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 10.5,
                            color: beeTextMuted(context),
                          ),
                        ),
                        const SizedBox(height: 3),
                      ],
                      Text(
                        _truncatePromptText(prompt.instruction, 110),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 11.5,
                          color: beeTextSub(context),
                          height: 1.45,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                AnimatedRotation(
                  duration: kBeeTransitionDuration,
                  turns: _previewExpanded ? 0.25 : 0,
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: beeTextMuted(context),
                  ),
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          duration: kBeeTransitionDuration,
          crossFadeState: _previewExpanded
              ? CrossFadeState.showFirst
              : CrossFadeState.showSecond,
          firstChild: Padding(
            padding: const EdgeInsets.only(left: 24, top: 10),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: beeText(context).withValues(alpha: 0.025),
                borderRadius: BorderRadius.circular(kBeeRadiusXs),
              ),
              child: Text(
                prompt.instruction,
                style: GoogleFonts.inter(
                  fontSize: 11.5,
                  color: beeTextSub(context),
                  height: 1.55,
                ),
              ),
            ),
          ),
          secondChild: const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  /// Whether [prompt] carries any per-style pipeline override. Built-ins
  /// never do; a custom style does as soon as one of the three override
  /// fields is set.
  bool _promptHasPipelineOverrides(SystemPrompt prompt) =>
      prompt.twoPassOverride != null ||
      prompt.modelOverrideId != null ||
      prompt.polishModelOverrideId != null;

  /// One-line summary of the pipeline [prompt] runs on, shown in the Current
  /// Style block — or null when the style simply follows the global setup.
  ///
  /// Model names come from the effective pipeline
  /// ([SettingsService.resolvePipelineForPrompt], which already falls back
  /// safely for stale overrides); on the Whisper backend the audio stage is
  /// local, so the whisper model name is shown instead of the unused cloud
  /// id.
  String? _currentPipelineSummary(SystemPrompt prompt) {
    if (!_promptHasPipelineOverrides(prompt)) return null;
    final settings = _settingsService;
    if (settings == null) return null;
    final pipeline = settings.resolvePipelineForPrompt(prompt);
    final String pass1Name;
    if (settings.transcriptionBackend == TranscriptionBackend.whisper) {
      pass1Name =
          WhisperModelDownloadService.getModelInfo(
            settings.whisperModelId,
          )?.name ??
          settings.whisperModelId;
    } else {
      pass1Name = AppConfig.getModelById(pipeline.pass1ModelId).displayName;
    }
    if (!pipeline.twoPass) {
      return 'Own pipeline · One-pass · $pass1Name';
    }
    final polishName = AppConfig.getModelById(
      pipeline.polishModelId,
    ).displayName;
    return 'Own pipeline · Two-pass · $pass1Name → $polishName';
  }

  Widget _buildPromptRow({
    required SystemPrompt prompt,
    required bool isBuiltIn,
    required SettingsService settings,
    required bool stylesActive,
  }) {
    final isSelected = prompt.id == _selectedPromptId;
    return BeeRadioTile(
      isSelected: isSelected,
      label: prompt.name,
      subtitle: _truncatePromptText(prompt.instruction, 65),
      showDivider: false,
      dimmed: !stylesActive && prompt.id != SystemPrompt.defaultId,
      badge: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Custom styles that override the pipeline get a tune affordance
          // before the generic actions; tapping it opens the edit dialog.
          if (!isBuiltIn && _promptHasPipelineOverrides(prompt))
            _rowAction(
              icon: Icons.tune_rounded,
              size: 13,
              label: 'Uses its own pipeline settings',
              onTap: () => _showEditDialog(settings, prompt),
            ),
          _rowAction(
            icon: Icons.copy_rounded,
            label: 'Duplicate ${prompt.name}',
            onTap: () => _duplicatePrompt(prompt, settings),
          ),
          if (!isBuiltIn) ...[
            _rowAction(
              icon: Icons.edit_outlined,
              label: 'Edit ${prompt.name}',
              onTap: () => _showEditDialog(settings, prompt),
            ),
            _rowAction(
              icon: Icons.delete_outline_rounded,
              label: 'Delete ${prompt.name}',
              color: beeError(context).withValues(alpha: 0.8),
              onTap: () => _deletePrompt(settings, prompt.id),
            ),
          ],
        ],
      ),
      onTap: !stylesActive && prompt.id != SystemPrompt.defaultId
          ? () {}
          : () async {
              await settings.setSelectedPromptId(prompt.id);
              setState(() => _selectedPromptId = prompt.id);
              widget.onPromptChanged?.call(prompt.id);
            },
    );
  }

  Widget _rowAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
    double size = 14,
  }) {
    return BeeInteractive(
      onTap: onTap,
      semanticLabel: label,
      tooltip: label,
      builder: (context, focused) => Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: size, color: color ?? beeTextMuted(context)),
      ),
    );
  }

  Widget _buildSubEyebrow(String label) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 2),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
          color: beeTextMuted(context),
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  /// Generates a collision-resistant unique ID for a custom prompt using a
  /// high-resolution microsecond timestamp plus a monotonic counter, so two
  /// prompts created within the same microsecond can never collide.
  String _generatePromptId() {
    final ts = DateTime.now().microsecondsSinceEpoch;
    final seq = _promptIdCounter++;
    return 'custom_${ts}_$seq';
  }

  Future<void> _duplicatePrompt(
    SystemPrompt source,
    SettingsService settings,
  ) async {
    final baseName = '${source.name} Copy';
    // Generate a unique name like macOS does ("X", "X 2", "X 3"...).
    final allNames = [
      ..._builtInPrompts.map((p) => p.name.toLowerCase()),
      ..._customPrompts.map((p) => p.name.toLowerCase()),
    ];
    String name = baseName;
    int n = 2;
    while (allNames.contains(name.toLowerCase())) {
      name = '$baseName $n';
      n++;
    }

    final dup = SystemPrompt(
      id: _generatePromptId(),
      name: name,
      instruction: source.instruction,
    );
    await settings.addCustomPrompt(dup);
    setState(() => _customPrompts = settings.customPrompts);
  }

  String _truncatePromptText(String value, int maxLength) {
    final compact = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compact.length <= maxLength) return compact;
    return '${compact.substring(0, maxLength).trimRight()}…';
  }

  String? _validatePromptName(String value, {SystemPrompt? existingPrompt}) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Name is required';
    if (trimmed.length < 2) return 'Name must be at least 2 characters';
    if (trimmed.length > 60) return 'Name must be 60 characters or fewer';
    if (RegExp(r'[\r\n\t]').hasMatch(trimmed)) {
      return 'Name cannot include line breaks or tabs';
    }

    final normalized = trimmed.toLowerCase();
    final duplicate = [..._builtInPrompts, ..._customPrompts].any(
      (prompt) =>
          prompt.id != existingPrompt?.id &&
          prompt.name.trim().toLowerCase() == normalized,
    );
    if (duplicate) return 'A style with this name already exists';
    return null;
  }

  String? _validatePromptInstruction(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return 'Instruction is required';
    if (trimmed.length < 12) {
      return 'Instruction needs a little more detail';
    }
    if (trimmed.length > 6000) {
      return 'Instruction must be 6000 characters or fewer';
    }
    return null;
  }

  // ── Prompt Dialog (shared for Add & Edit) ──────────────────────────

  void _showAddDialog(SettingsService settings) {
    _showPromptDialog(settings, existingPrompt: null);
  }

  void _showEditDialog(SettingsService settings, SystemPrompt existing) {
    _showPromptDialog(settings, existingPrompt: existing);
  }

  // ── Pipeline override helpers (style dialog) ────────────────────────

  /// Dialog value for the transcription-mode selector:
  /// `''` = Follow global, `'one'` = One-pass, `'two'` = Two-pass.
  static String _modeValueFor(bool? twoPassOverride) =>
      switch (twoPassOverride) {
        true => 'two',
        false => 'one',
        null => '',
      };

  /// Inverse of [_modeValueFor]: the `twoPassOverride` to persist.
  static bool? _modeOverrideFor(String value) => switch (value) {
    'one' => false,
    'two' => true,
    _ => null,
  };

  /// The dialog value for a stored model override: the id when it still
  /// resolves in [models] (display-only check), otherwise `''` so a stale
  /// override reads as 'Follow global' until it is re-saved.
  static String _validOverrideId(String? id, List<GeminiModelConfig> models) =>
      id != null && models.any((model) => model.id == id) ? id : '';

  /// Small muted label above a pipeline control inside the style dialog.
  Widget _dialogFieldLabel(String label) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: beeTextMuted(context),
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }

  /// Dropdown for a pipeline model override, styled like the dialog's
  /// 'Start from' selector: 'Follow global' plus one entry per [models].
  Widget _pipelineModelDropdown({
    required String label,
    required String value,
    required List<GeminiModelConfig> models,
    required ValueChanged<String> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      style: GoogleFonts.inter(color: beeText(context), fontSize: 14),
      iconEnabledColor: beeTextMuted(context),
      dropdownColor: beeSurfaceRaised(context),
      decoration: beeInputDecoration(context, label: label),
      items: [
        DropdownMenuItem(
          value: '',
          child: Text(
            'Follow global',
            style: GoogleFonts.inter(color: beeText(context), fontSize: 14),
          ),
        ),
        for (final model in models)
          DropdownMenuItem(
            value: model.id,
            child: Text(
              model.displayName,
              style: GoogleFonts.inter(color: beeText(context), fontSize: 14),
            ),
          ),
      ],
      onChanged: (value) {
        if (value == null) return;
        onChanged(value);
      },
    );
  }

  /// Muted notice shown while the dialog's current pipeline state would not
  /// apply writing styles, with the readiness reason as a second line when
  /// the pipeline cannot run.
  Widget _pipelineWarning(BuildContext context, {required String? issue}) {
    final muted = beeTextMuted(context);
    final textStyle = GoogleFonts.inter(
      fontSize: 11,
      color: muted,
      height: 1.35,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 13, color: muted),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "This style won't shape the transcript while a "
                  'transcription-only model runs it. Choose Two-pass or a '
                  'prompt-capable model.',
                  style: textStyle,
                ),
                if (issue != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(issue, style: textStyle),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showPromptDialog(
    SettingsService settings, {
    SystemPrompt? existingPrompt,
  }) {
    final isEdit = existingPrompt != null;
    final nameCtrl = TextEditingController(text: existingPrompt?.name ?? '');
    final instrCtrl = TextEditingController(
      text: existingPrompt?.instruction ?? '',
    );
    String? nameError;
    String? instrError;
    // 'Start from' base for the create dialog: '' = Blank, otherwise the id
    // of a built-in prompt whose instruction seeds the new style.
    var baseId = '';
    // The last name auto-suggested from a base pick, so a later pick may
    // replace its own suggestion but never a name the user typed.
    var autoName = '';
    // ── Per-style pipeline overrides (dialog state) ──
    // modeValue: '' = Follow global, 'one' = One-pass, 'two' = Two-pass.
    var modeValue = _modeValueFor(existingPrompt?.twoPassOverride);
    // A stored model override that no longer resolves in the current global
    // catalogs displays as 'Follow global' without erasing the stored id
    // while the dialog is merely open; saving then writes null.
    var modelValue = _validOverrideId(
      existingPrompt?.modelOverrideId,
      settings.primaryModels,
    );
    // The polish override keeps its value while its picker is hidden (for
    // example while the effective mode is one-pass), so temporarily
    // switching never silently drops it.
    var polishValue = _validOverrideId(
      existingPrompt?.polishModelOverrideId,
      settings.refinementModels,
    );

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final availableWidth = MediaQuery.sizeOf(context).width - 96;
          final contentWidth = availableWidth < 420 ? availableWidth : 420.0;
          // The Model picker is meaningful only on the cloud backend; local
          // Whisper always serves the audio stage.
          final showModelPicker =
              settings.transcriptionBackend == TranscriptionBackend.cloud;
          final effectiveTwoPass =
              _modeOverrideFor(modeValue) ??
              settings.twoPassTranscriptionEnabled;
          // Draft carrying the dialog's current override state, evaluated
          // against the same service logic the recording pipeline uses.
          final pipelineDraft = SystemPrompt(
            id: existingPrompt?.id ?? 'draft',
            name: existingPrompt?.name ?? '',
            instruction: '',
            modelOverrideId: modelValue.isEmpty ? null : modelValue,
            polishModelOverrideId: polishValue.isEmpty ? null : polishValue,
            twoPassOverride: _modeOverrideFor(modeValue),
          );
          final styleApplies = settings.promptAppliesFor(pipelineDraft);
          final pipelineIssue = styleApplies
              ? null
              : settings.pipelineIssueForPrompt(pipelineDraft);

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            backgroundColor: beeSurfaceRaised(context),
            shape: beeDialogShape(),
            title: Text(
              isEdit ? 'Edit Style' : 'New Style',
              style: GoogleFonts.spaceGrotesk(
                color: beeText(context),
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
            content: SizedBox(
              width: contentWidth,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isEdit) ...[
                      DropdownButtonFormField<String>(
                        initialValue: baseId,
                        isExpanded: true,
                        style: GoogleFonts.inter(
                          color: beeText(context),
                          fontSize: 14,
                        ),
                        iconEnabledColor: beeTextMuted(context),
                        dropdownColor: beeSurfaceRaised(context),
                        decoration: beeInputDecoration(
                          context,
                          label: 'Start from',
                        ),
                        items: [
                          DropdownMenuItem(
                            value: '',
                            child: Text(
                              'Blank',
                              style: GoogleFonts.inter(
                                color: beeText(context),
                                fontSize: 14,
                              ),
                            ),
                          ),
                          for (final prompt in _builtInPrompts)
                            DropdownMenuItem(
                              value: prompt.id,
                              child: Text(
                                prompt.name,
                                style: GoogleFonts.inter(
                                  color: beeText(context),
                                  fontSize: 14,
                                ),
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setDialogState(() {
                            baseId = value;
                            if (value.isEmpty) {
                              // Back to Blank: undo what the base pick added,
                              // but never a name the user typed themselves.
                              instrCtrl.text = '';
                              if (nameCtrl.text == autoName) {
                                nameCtrl.text = '';
                              }
                              autoName = '';
                            } else {
                              final base = _builtInPrompts.firstWhere(
                                (p) => p.id == value,
                              );
                              // The base is only a starting point: the text
                              // lands in the field for the user to rework.
                              instrCtrl.text = base.instruction;
                              if (nameCtrl.text.isEmpty ||
                                  nameCtrl.text == autoName) {
                                autoName = '${base.name} (custom)';
                                nameCtrl.text = autoName;
                              }
                            }
                            if (instrError != null) {
                              instrError = _validatePromptInstruction(
                                instrCtrl.text,
                              );
                            }
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextField(
                      controller: nameCtrl,
                      style: GoogleFonts.inter(
                        color: beeText(context),
                        fontSize: 14,
                      ),
                      onChanged: (_) {
                        if (nameError != null) {
                          setDialogState(() {
                            nameError = _validatePromptName(
                              nameCtrl.text,
                              existingPrompt: existingPrompt,
                            );
                          });
                        }
                      },
                      decoration: beeInputDecoration(context, label: 'Name')
                          .copyWith(
                            errorText: nameError,
                            errorStyle: GoogleFonts.inter(
                              color: beeError(context),
                              fontSize: 11,
                            ),
                          ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: instrCtrl,
                      maxLines: 6,
                      style: GoogleFonts.inter(
                        color: beeText(context),
                        fontSize: 13,
                        height: 1.5,
                      ),
                      onChanged: (_) {
                        setDialogState(() {
                          if (instrError != null) {
                            instrError = _validatePromptInstruction(
                              instrCtrl.text,
                            );
                          }
                        });
                      },
                      decoration:
                          beeInputDecoration(
                            context,
                            label: 'Instruction',
                          ).copyWith(
                            errorText: instrError,
                            errorStyle: GoogleFonts.inter(
                              color: beeError(context),
                              fontSize: 11,
                            ),
                            alignLabelWithHint: true,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        '${instrCtrl.text.length} characters',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: instrCtrl.text.length > 6000
                              ? beeError(context)
                              : beeTextMuted(context),
                        ),
                      ),
                    ),
                    // ── Per-style pipeline ───────────────────────────────
                    const BeeGroupLabel(label: 'Pipeline'),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'This style may run on its own setup. Anything left '
                        'on Follow global keeps using the global '
                        'Transcription settings.',
                        style: GoogleFonts.inter(
                          fontSize: 10.5,
                          color: beeTextMuted(context),
                          height: 1.4,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    _dialogFieldLabel('Transcription mode'),
                    BeeSegmented<String>(
                      value: modeValue,
                      options: const [
                        (val: '', label: 'Follow global', icon: null),
                        (val: 'one', label: 'One-pass', icon: null),
                        (val: 'two', label: 'Two-pass', icon: null),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => modeValue = value),
                    ),
                    if (showModelPicker) ...[
                      const SizedBox(height: 12),
                      _pipelineModelDropdown(
                        label: 'Model',
                        value: modelValue,
                        models: settings.primaryModels,
                        onChanged: (value) =>
                            setDialogState(() => modelValue = value),
                      ),
                    ],
                    if (effectiveTwoPass) ...[
                      const SizedBox(height: 12),
                      _pipelineModelDropdown(
                        label: 'Polish model',
                        value: polishValue,
                        models: settings.refinementModels,
                        onChanged: (value) =>
                            setDialogState(() => polishValue = value),
                      ),
                    ],
                    if (!styleApplies)
                      _pipelineWarning(context, issue: pipelineIssue),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                style: beeSecondaryButtonStyle(context),
                onPressed: () => Navigator.pop(context),
                child: Text(
                  'Cancel',
                  style: GoogleFonts.inter(
                    color: beeTextSub(context),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              ElevatedButton(
                style: beePrimaryButtonStyle(context),
                onPressed: () async {
                  final navigator = Navigator.of(context);
                  final promptName = nameCtrl.text.trim();
                  final promptInstruction = instrCtrl.text.trim();
                  final nErr = _validatePromptName(
                    promptName,
                    existingPrompt: existingPrompt,
                  );
                  final iErr = _validatePromptInstruction(promptInstruction);
                  if (nErr != null || iErr != null) {
                    setDialogState(() {
                      nameError = nErr;
                      instrError = iErr;
                    });
                    return;
                  }
                  if (isEdit) {
                    final updated = SystemPrompt(
                      id: existingPrompt.id,
                      name: promptName,
                      instruction: promptInstruction,
                      modelOverrideId: modelValue.isEmpty ? null : modelValue,
                      polishModelOverrideId: polishValue.isEmpty
                          ? null
                          : polishValue,
                      twoPassOverride: _modeOverrideFor(modeValue),
                    );
                    await settings.updateCustomPrompt(updated);
                    if (!mounted) return;
                    setState(() => _customPrompts = settings.customPrompts);
                    widget.onPromptChanged?.call(existingPrompt.id);
                  } else {
                    final p = SystemPrompt(
                      id: _generatePromptId(),
                      name: promptName,
                      instruction: promptInstruction,
                      modelOverrideId: modelValue.isEmpty ? null : modelValue,
                      polishModelOverrideId: polishValue.isEmpty
                          ? null
                          : polishValue,
                      twoPassOverride: _modeOverrideFor(modeValue),
                    );
                    await settings.addCustomPrompt(p);
                    await settings.setSelectedPromptId(p.id);
                    if (!mounted) return;
                    setState(() {
                      _customPrompts = settings.customPrompts;
                      _selectedPromptId = p.id;
                    });
                    widget.onPromptChanged?.call(p.id);
                  }
                  if (mounted) navigator.pop();
                },
                child: Text(
                  isEdit ? 'Save' : 'Create',
                  style: GoogleFonts.inter(
                    color: beeBlack(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _deletePrompt(SettingsService settings, String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: beeSurfaceRaised(context),
        shape: beeDialogShape(),
        title: Text(
          'Delete Style?',
          style: GoogleFonts.spaceGrotesk(
            color: beeText(context),
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        content: Text(
          'This cannot be undone.',
          style: GoogleFonts.inter(color: beeTextSub(context), fontSize: 14),
        ),
        actions: [
          TextButton(
            style: beeSecondaryButtonStyle(context),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: beePrimaryButtonStyle(
              context,
              backgroundColor: beeError(context),
              foregroundColor: beeText(context),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await settings.removeCustomPrompt(id);
      setState(() => _customPrompts = settings.customPrompts);
    }
  }
}
