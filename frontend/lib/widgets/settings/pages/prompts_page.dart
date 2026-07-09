import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../providers/settings_provider.dart';
import '../../../models/system_prompt.dart';
import '../../../models/prompt_settings.dart';
import '../../../services/settings_service.dart';
import '../../prompt_cloud_switch_dialog.dart';
import '../bee_input.dart';
import '../bee_page_header.dart';
import '../settings_shared.dart';
import 'prompt_override_panel.dart';

class PromptsPage extends StatefulWidget {
  final ValueChanged<String>? onPromptChanged;
  const PromptsPage({super.key, this.onPromptChanged});

  @override
  State<PromptsPage> createState() => _PromptsPageState();
}

class _PromptsPageState extends State<PromptsPage> {
  String _selectedPromptId = '';
  List<SystemPrompt> _customPrompts = [];
  RephraseLevel _rephraseLevel = RephraseLevel.off;
  final List<SystemPrompt> _builtInPrompts = SystemPrompt.availablePrompts;
  bool _settingsLoaded = false;
  bool _previewExpanded = false;
  SettingsService? _settingsService;
  // When non-null, the prompt list is replaced by the drill-in detail page
  // for this prompt id (native master → detail navigation).
  String? _detailPromptId;
  // GlobalKey for the segmented control so the local→cloud confirmation
  // popover can anchor itself to the control the user actually tapped.
  final GlobalKey _segmentedKey = GlobalKey();

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
        _rephraseLevel = s.rephraseLevel;
      });
    } else {
      // Light-weight re-sync after the initial load. The prompts page
      // trusts SettingsService to be the source of truth, so any
      // notifyListeners() (e.g. another page changing the rephrase
      // level, the backend being flipped) should be reflected here.
      _syncMutableSettings();
    }
  }

  void _syncMutableSettings() {
    final s = _settingsService;
    if (s == null) return;
    final newLevel = s.rephraseLevel;
    final newPromptId = s.selectedPromptId;
    final newCustomPrompts = s.customPrompts;
    // Skip the setState if nothing actually changed (keeps no-op
    // rebuilds cheap and avoids unnecessary rebuilds of child widgets).
    if (newLevel == _rephraseLevel &&
        newPromptId == _selectedPromptId &&
        identical(newCustomPrompts, _customPrompts)) {
      return;
    }
    setState(() {
      _rephraseLevel = newLevel;
      _selectedPromptId = newPromptId;
      _customPrompts = newCustomPrompts;
    });
  }

  /// Rephraser is "blocked" whenever there is no cloud model in the
  /// pipeline — i.e. pure offline Whisper with two-pass refinement off.
  /// Like prompts, the rephraser is an LLM-level feature that only takes
  /// effect when a cloud model refines the transcript (Cloud backend, or
  /// Whisper + two-pass). Always read this fresh from the [SettingsService]
  /// — the backend can change from another page (AI Models) and we need to
  /// reflect it immediately.
  ///
  /// We surface a "LOCAL ONLY" warning badge in the UI and route any
  /// non-Off pick through the shared switch dialog.
  bool _rephraserBlockedFor(SettingsService s) {
    return !s.isCloudRefinementInPipeline;
  }

  /// Whether a non-default prompt is "blocked" — i.e., it will have no
  /// visible effect because the user is on the Whisper backend without
  /// two-pass refinement enabled, AND the prompt itself doesn't have a
  /// per-prompt override that switches it to Cloud. Delegates to the
  /// shared [SettingsService] check so the prompts page, mode picker and
  /// tray menu all agree on when a prompt is inert.
  ///
  /// The Default prompt is never considered blocked (it's the baseline
  /// that Whisper uses implicitly even though it doesn't send it to an
  /// LLM).
  bool _promptBlockedFor(SettingsService s, SystemPrompt prompt) {
    return s.isPromptInactiveOnLocalBackend(prompt.id);
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

    return Column(
      children: [
        Expanded(
          child: Container(
            color: beeSurface(context),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 220),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (currentChild, previousChildren) => Stack(
                fit: StackFit.expand,
                alignment: Alignment.topLeft,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              ),
              transitionBuilder: (child, animation) {
                // Drill-in feel: the detail page slides in from the right,
                // the list recedes slightly to the left.
                final key = child.key;
                final isDetail =
                    key is ValueKey<String> && key.value.startsWith('detail');
                final begin = isDetail
                    ? const Offset(0.06, 0)
                    : const Offset(-0.04, 0);
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: begin,
                      end: Offset.zero,
                    ).animate(animation),
                    child: child,
                  ),
                );
              },
              child: _detailPromptId != null
                  ? _buildDetail(settings)
                  : _buildPromptList(settings),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildPromptList(SettingsService settings) {
    return SingleChildScrollView(
      key: const ValueKey('list'),
      padding: BeePageHeader.contentPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BeePageHeader(title: 'Prompts'),
          // ── 1. CURRENT PROMPT ────────────────────────────
          // Selected prompt shown prominently at the top with
          // an optional inline preview expander.
          _buildCurrentPromptBlock(settings),

          const SizedBox(height: BeePageHeader.groupGap),

          // ── 2. REPHRASER ─────────────────────────────────
          // Global setting that modifies the resolved prompt.
          //
          // UX: The rephraser is an LLM-prompt-level feature —
          // it only takes effect when there's an LLM in the
          // transcription pipeline. On the Cloud backend that's
          // always true; on Whisper it's only true when two-pass
          // refinement is on (because two-pass sends the transcript
          // through a cloud refinement model).
          //
          // When the user is on Whisper + two-pass OFF, we keep
          // the segmented control tappable (the user can always
          // signal intent) but show a small inline "LOCAL ONLY"
          // warning badge and route any non-Off pick through a
          // native confirmation popover explaining the
          // local → cloud switch.
          const BeeGroupLabel(label: 'Rephraser'),
          Builder(
            builder: (context) {
              // Read backend state fresh on every rebuild so
              // changes from other pages (AI Models) are
              // reflected immediately.
              final s = _settingsService!;
              final blocked = _rephraserBlockedFor(s);
              return BeeSettingsRow(
                icon: Icons.auto_fix_high_rounded,
                label: 'Professional Rephrasing',
                description: _rephraseLevel.description,
                showDivider: false,
                warningBadge: blocked
                    ? _LocalOnlyBadge(hasGeminiKey: s.hasGeminiApiKey)
                    : null,
                // Dim the control when the rephraser can't take
                // effect (local-only), while keeping it tappable so a
                // Medium/High pick opens the switch dialog.
                trailing: Opacity(
                  opacity: blocked ? 0.55 : 1.0,
                  child: BeeSegmented<RephraseLevel>(
                    key: _segmentedKey,
                    value: _rephraseLevel,
                    // Always enabled — the onChanged handler routes
                    // blocked picks through the switch dialog instead
                    // of silently swallowing the tap.
                    enabled: true,
                    options: const [
                      (val: RephraseLevel.off, label: 'Off', icon: null),
                      (val: RephraseLevel.medium, label: 'Medium', icon: null),
                      (val: RephraseLevel.high, label: 'High', icon: null),
                    ],
                    onChanged: (level) async {
                      // Off is always safe — it doesn't need an LLM.
                      if (level == RephraseLevel.off) {
                        await settings.setRephraseLevel(level);
                        setState(() => _rephraseLevel = level);
                        return;
                      }

                      // Re-check the blocked state at click time
                      // so we always act on the CURRENT backend,
                      // not whatever was cached when build() ran.
                      if (_rephraserBlockedFor(settings)) {
                        final result = await showPromptCloudSwitchDialog(
                          context: context,
                          settings: settings,
                          feature: PromptCloudFeature.rephraser,
                        );
                        if (!context.mounted) return;
                        switch (result) {
                          case PromptCloudResult.openSettings:
                            SettingsProviderScope.of(
                              context,
                            ).selectCategory(SettingsCategory.aiModels);
                            return;
                          case PromptCloudResult.cancelled:
                            return;
                          case PromptCloudResult.localTwoPass:
                          case PromptCloudResult.cloud:
                            // Pipeline now has cloud refinement; the
                            // LOCAL ONLY badge clears on rebuild.
                            break;
                        }
                      }

                      await settings.setRephraseLevel(level);
                      setState(() => _rephraseLevel = level);
                    },
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: BeePageHeader.groupGap),

          // ── 3. ALL PROMPTS ───────────────────────────────
          // Single unified list with sub-eyebrows for built-in
          // vs. your prompts. Trailing affordance is a single
          // chevron that opens the prompt inspector.
          Row(
            children: [
              const Expanded(child: BeeGroupLabel(label: 'All Prompts')),
              BeeActionChip(
                label: 'New',
                icon: Icons.add_rounded,
                onTap: () => _showAddDialog(settings),
              ),
            ],
          ),

          // Built-in subhead
          _buildSubEyebrow('Built-in'),
          ..._builtInPrompts.map((p) {
            final isSelected = p.id == _selectedPromptId;
            final overrides = settings.getPromptOverrides(p.id);
            return _buildPromptRow(
              prompt: p,
              isSelected: isSelected,
              overrides: overrides,
              isBuiltIn: true,
              settings: settings,
            );
          }),

          // Your prompts subhead (always rendered so the user
          // sees the place to add custom prompts).
          const SizedBox(height: 14),
          Row(children: [Expanded(child: _buildSubEyebrow('Your prompts'))]),

          if (_customPrompts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              child: BeeEmptyState(
                icon: Icons.edit_note_rounded,
                title: 'No custom prompts yet',
                subtitle:
                    'Create your own prompts tailored to specific use cases',
              ),
            )
          else
            ..._customPrompts.map((p) {
              final isSelected = p.id == _selectedPromptId;
              final overrides = settings.getPromptOverrides(p.id);
              return _buildPromptRow(
                prompt: p,
                isSelected: isSelected,
                overrides: overrides,
                isBuiltIn: false,
                settings: settings,
              );
            }),
        ],
      ),
    );
  }

  // ── Drill-in detail navigation ─────────────────────────────────────

  void _openDetail(String promptId) {
    setState(() => _detailPromptId = promptId);
  }

  Widget _buildDetail(SettingsService settings) {
    final id = _detailPromptId!;
    final all = [..._builtInPrompts, ..._customPrompts];
    final prompt = all.firstWhere(
      (p) => p.id == id,
      orElse: () => _builtInPrompts.first,
    );
    final isBuiltIn = _builtInPrompts.any((p) => p.id == prompt.id);
    final overrides =
        settings.getPromptOverrides(prompt.id) ?? const PromptSettings();

    return PromptDetailPage(
      // Key by id so switching prompts re-initialises the page state, while
      // still starting with "detail" for the slide-direction heuristic.
      key: ValueKey('detail-${prompt.id}'),
      prompt: prompt,
      isBuiltIn: isBuiltIn,
      overrides: overrides,
      settingsService: settings,
      onBack: () => setState(() => _detailPromptId = null),
      onOverridesChanged: (newOverrides) async {
        // Persist immediately (native instant-apply). Selection — not
        // per-prompt overrides — is what drives the tray menu, so we don't
        // fire onPromptChanged here; the mode picker/tray read overrides
        // live from the settings service.
        await settings.setPromptOverrides(prompt.id, newOverrides);
        if (mounted) setState(() {});
      },
      onEdit: isBuiltIn ? null : () => _showEditDialog(settings, prompt),
      onDuplicate: () => _duplicateFromDetail(prompt, settings),
      onDelete: isBuiltIn ? null : () => _deleteFromDetail(settings, prompt.id),
    );
  }

  Future<void> _duplicateFromDetail(
    SystemPrompt prompt,
    SettingsService settings,
  ) async {
    await _duplicatePrompt(prompt, settings);
    // Return to the list so the new copy is visible in context.
    if (mounted) setState(() => _detailPromptId = null);
  }

  Future<void> _deleteFromDetail(SettingsService settings, String id) async {
    await _deletePrompt(settings, id);
    // If the prompt was actually removed, pop back to the list.
    if (mounted && settings.customPrompts.every((p) => p.id != id)) {
      setState(() => _detailPromptId = null);
    }
  }

  // ── Current Prompt block ───────────────────────────────────────────

  Widget _buildCurrentPromptBlock(SettingsService settings) {
    final prompt = _effectiveSelectedPrompt();
    final overrides = settings.getPromptOverrides(prompt.id);
    final effectiveRephraseLevel = overrides?.rephraseLevel ?? _rephraseLevel;
    final rephraserFragment = effectiveRephraseLevel.promptFragment;
    final previewText = rephraserFragment != null
        ? '${prompt.instruction}$rephraserFragment'
        : prompt.instruction;
    final hasOverrides = overrides?.hasAnyOverride == true;
    final isBuiltIn = _builtInPrompts.any((p) => p.id == prompt.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BeeGroupLabel(label: 'Current Prompt'),

        // Header row: radio dot + name + (built-in/custom tag) + expand
        // chevron.
        BeeInteractive(
          onTap: () {
            setState(() => _previewExpanded = !_previewExpanded);
          },
          semanticLabel:
              '${_previewExpanded ? 'Collapse' : 'Expand'} current prompt preview',
          builder: (context, focused) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
            child: Row(
              children: [
                // Filled radio-style indicator — a real selection
                // marker, not just a yellow dot.
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: beeText(context),
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

        // Inline override summary — click to open override panel.
        if (hasOverrides)
          Padding(
            padding: const EdgeInsets.only(left: 24, top: 2),
            child: BeeActionChip(
              label:
                  'Customized · ${_overrideSummary(overrides, compact: true) ?? 'overrides'}',
              icon: Icons.tune_rounded,
              onTap: () => _openDetail(prompt.id),
            ),
          ),

        // Expanded resolved preview — flat indented text, no card.
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
                previewText,
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

  // ── Prompt row (single list, supports both built-in and custom) ────

  Widget _buildPromptRow({
    required SystemPrompt prompt,
    required bool isSelected,
    required PromptSettings? overrides,
    required bool isBuiltIn,
    required SettingsService settings,
  }) {
    final hasOverrides = overrides?.hasAnyOverride == true;
    final subtitle = _truncatePromptText(prompt.instruction, 65);
    final promptBlocked = _promptBlockedFor(settings, prompt);

    return BeeRadioTile(
      isSelected: isSelected,
      label: prompt.name,
      subtitle: subtitle,
      showDivider: false,
      // On the local-only backend a non-default prompt has no effect until a
      // cloud model is in the pipeline, so it reads as grayed-out/inactive.
      dimmed: promptBlocked,
      warningBadge: promptBlocked && !isSelected
          ? _LocalOnlyBadge(hasGeminiKey: settings.hasGeminiApiKey)
          : null,
      badge: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasOverrides)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: Text(
                'Customized',
                style: GoogleFonts.inter(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: beeTextMuted(context),
                ),
              ),
            ),
          BeeInteractive(
            onTap: () => _openDetail(prompt.id),
            semanticLabel:
                'Open ${prompt.name} settings, overrides, and actions',
            tooltip: 'Open settings, overrides, duplicate, or delete',
            builder: (context, focused) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Icon(
                Icons.chevron_right_rounded,
                size: 14,
                color: beeTextMuted(context),
              ),
            ),
          ),
        ],
      ),
      onTap: () async {
        // Non-default prompts require a cloud model to take effect. If the
        // user is on pure Whisper (no two-pass), let them choose how to
        // enable it before selecting — keep local transcription + cloud
        // refinement, or switch fully to cloud.
        if (promptBlocked) {
          final result = await showPromptCloudSwitchDialog(
            context: context,
            settings: settings,
            promptName: prompt.name,
          );
          if (!mounted) return;
          switch (result) {
            case PromptCloudResult.openSettings:
              SettingsProviderScope.of(
                context,
              ).selectCategory(SettingsCategory.aiModels);
              return;
            case PromptCloudResult.cancelled:
              return;
            case PromptCloudResult.localTwoPass:
            case PromptCloudResult.cloud:
              // Backend/two-pass already updated by the dialog — proceed.
              break;
          }
        }
        await settings.setSelectedPromptId(prompt.id);
        setState(() => _selectedPromptId = prompt.id);
        widget.onPromptChanged?.call(prompt.id);
      },
    );
  }

  Widget _buildSubEyebrow(String label) {
    // Smaller than BeeGroupLabel — second-tier hierarchy under
    // "All Prompts".
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
      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      instruction: source.instruction,
      settings: const PromptSettings(),
    );
    await settings.addCustomPrompt(dup);
    setState(() => _customPrompts = settings.customPrompts);
  }

  // ── Helpers ────────────────────────────────────────────────────────

  String _truncatePromptText(String value, int maxLength) {
    final compact = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compact.length <= maxLength) return compact;
    return '${compact.substring(0, maxLength).trimRight()}…';
  }

  String? _overrideSummary(PromptSettings? overrides, {bool compact = false}) {
    if (overrides == null || !overrides.hasAnyOverride) return null;

    final labels = <String>[
      if (overrides.transcriptionBackend != null) 'Engine',
      if (overrides.modelId != null) 'AI model',
      if (overrides.thinkingLevel != null) 'Reasoning',
      if (overrides.whisperModelId != null) 'Offline model',
      if (overrides.whisperLanguage != null) 'Language',
      if (overrides.twoPassTranscriptionEnabled != null) 'Two-pass',
      if (overrides.twoPassTranscriptionModelId != null) 'Pass model',
      if (overrides.twoPassRefinementModelId != null) 'Refine model',
      if (overrides.twoPassRefinementThinkingLevel != null) 'Refine reasoning',
      if (overrides.cloudProvider != null) 'Provider',
      if (overrides.rephraseLevel != null) 'Rephraser',
    ];
    final visibleCount = compact ? 2 : 3;
    final shown = labels.take(visibleCount).join(', ');
    final extraCount = labels.length - visibleCount;
    final extra = extraCount > 0 ? ' +$extraCount' : '';
    final count = overrides.overrideCount;
    final noun = count == 1 ? 'override' : 'overrides';
    if (shown.isEmpty) return '$count $noun';
    return '$count $noun: $shown$extra';
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
    if (duplicate) return 'A prompt with this name already exists';
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

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final availableWidth = MediaQuery.sizeOf(context).width - 96;
          final contentWidth = availableWidth < 420 ? availableWidth : 420.0;

          return AlertDialog(
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 24,
              vertical: 24,
            ),
            backgroundColor: beeSurfaceRaised(context),
            shape: beeDialogShape(),
            title: Text(
              isEdit ? 'Edit Prompt' : 'New Prompt',
              style: GoogleFonts.spaceGrotesk(
                color: beeText(context),
                fontWeight: FontWeight.w700,
                fontSize: 17,
              ),
            ),
            content: SizedBox(
              width: contentWidth,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                    decoration: beeInputDecoration(
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
                ],
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
                      settings: const PromptSettings(),
                    );
                    await settings.updateCustomPrompt(updated);
                    setState(() => _customPrompts = settings.customPrompts);
                    widget.onPromptChanged?.call(existingPrompt.id);
                  } else {
                    final p = SystemPrompt(
                      id: 'custom_${DateTime.now().millisecondsSinceEpoch}',
                      name: promptName,
                      instruction: promptInstruction,
                      settings: const PromptSettings(),
                    );
                    await settings.addCustomPrompt(p);
                    await settings.setSelectedPromptId(p.id);
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
          'Delete Prompt?',
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

// ── Rephraser-blocked UI helpers ────────────────────────────────────

/// Small inline warning badge shown next to the rephraser row label
/// when the user is on Whisper + two-pass off. Tapping it opens a
/// popover anchored to the badge explaining why the rephraser is
/// disabled — this feels native on desktop (macOS info buttons,
/// Windows modern info tips) rather than triggering a full-screen
/// modal AlertDialog.
class _LocalOnlyBadge extends StatefulWidget {
  final bool hasGeminiKey;

  const _LocalOnlyBadge({required this.hasGeminiKey});

  @override
  State<_LocalOnlyBadge> createState() => _LocalOnlyBadgeState();
}

class _LocalOnlyBadgeState extends State<_LocalOnlyBadge> {
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();
  bool _isOpen = false;

  void _togglePopover() {
    if (_isOpen) {
      _closePopover();
    } else {
      _openPopover();
    }
  }

  void _openPopover() {
    final overlay = Overlay.of(context);
    final hasGeminiKey = widget.hasGeminiKey;
    final overlayEntry = OverlayEntry(
      builder: (context) => _LocalOnlyPopover(
        layerLink: _layerLink,
        hasGeminiKey: hasGeminiKey,
        onClose: _closePopover,
      ),
    );
    overlay.insert(overlayEntry);
    setState(() {
      _overlayEntry = overlayEntry;
      _isOpen = true;
    });
  }

  void _closePopover() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    if (mounted) setState(() => _isOpen = false);
  }

  @override
  void dispose() {
    _overlayEntry?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = beeError(context);
    return CompositedTransformTarget(
      link: _layerLink,
      child: Tooltip(
        message:
            'Rephraser has no effect on offline-only Whisper. Tap to learn more.',
        child: BeeInteractive(
          onTap: _togglePopover,
          toggled: _isOpen,
          semanticLabel: 'Rephraser unavailable on local-only Whisper',
          builder: (context, focused) => AnimatedContainer(
            duration: kBeeTransitionDuration,
            curve: kBeeTransitionCurve,
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: error.withValues(alpha: _isOpen || focused ? 0.18 : 0.10),
              borderRadius: BorderRadius.circular(kBeeRadiusPill),
              border: Border.all(
                color: error.withValues(
                  alpha: _isOpen || focused ? 0.42 : 0.22,
                ),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 10,
                  color: error.withValues(alpha: 0.90),
                ),
                const SizedBox(width: 4),
                Text(
                  'LOCAL ONLY',
                  style: GoogleFonts.inter(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: error.withValues(alpha: 0.90),
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Popover anchored to [_LocalOnlyBadge] via a [LayerLink]. Renders
/// as a small elevated card with rounded corners — visually matches
/// our popup menus and dropdowns rather than a Material AlertDialog.
/// Tapping outside dismisses it.
class _LocalOnlyPopover extends StatefulWidget {
  final LayerLink layerLink;
  final bool hasGeminiKey;
  final VoidCallback onClose;

  const _LocalOnlyPopover({
    required this.layerLink,
    required this.hasGeminiKey,
    required this.onClose,
  });

  @override
  State<_LocalOnlyPopover> createState() => _LocalOnlyPopoverState();
}

class _LocalOnlyPopoverState extends State<_LocalOnlyPopover>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    // Popover slides up + fades in — feels like a native info popover.
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Dimiss-on-tap-outside layer. Disables itself from semantics
        // and hover so it doesn't interfere with the rest of the UI.
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onClose,
          child: const SizedBox.expand(),
        ),
        CompositedTransformFollower(
          link: widget.layerLink,
          targetAnchor: Alignment.topLeft,
          followerAnchor: Alignment.bottomLeft,
          // Small gap between badge and popover so it visually floats.
          offset: const Offset(0, -8),
          child: FadeTransition(
            opacity: _fade,
            child: SlideTransition(position: _slide, child: _buildCard()),
          ),
        ),
      ],
    );
  }

  Widget _buildCard() {
    final themeIsDark = Theme.of(context).brightness == Brightness.dark;
    final surface = beeSurfaceHighest(context);
    final border = beeBorder(context);
    final text = beeText(context);
    final textSub = beeTextSub(context);
    final textMuted = beeTextMuted(context);
    final error = beeError(context);

    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: 300,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(kBeeRadiusMd),
          border: Border.all(
            color: border.withValues(alpha: 0.85),
            width: 0.75,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: themeIsDark ? 0.55 : 0.14),
              blurRadius: 22,
              spreadRadius: 1,
              offset: const Offset(0, 8),
            ),
            BoxShadow(
              color: Colors.black.withValues(alpha: themeIsDark ? 0.30 : 0.06),
              blurRadius: 6,
              spreadRadius: 0,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.cloud_off_rounded,
                  size: 13,
                  color: error.withValues(alpha: 0.85),
                ),
                const SizedBox(width: 7),
                Flexible(
                  child: Text(
                    'Cloud feature unavailable',
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: text,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'You\u2019re on offline transcription only. The rephraser '
              'rewrites your transcript with a cloud AI model, so it has '
              'no effect in this mode.',
              style: GoogleFonts.inter(
                fontSize: 11.5,
                color: textSub,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.hasGeminiKey
                  ? 'Pick Medium or High to enable cloud refinement and '
                        'activate the rephraser.'
                  : 'Add a Gemini API key in Settings \u2192 AI Models, '
                        'then pick Medium or High to activate the rephraser.',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: textMuted,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
