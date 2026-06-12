import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../config.dart';
import '../../../models/prompt_settings.dart';
import '../../../models/system_prompt.dart';
import '../../../services/settings_service.dart';
import '../../../services/whisper_service.dart';
import '../../../services/whisper_model_download_service.dart';
import '../settings_shared.dart';

/// Sentinel used inside [showMenu] dropdowns to represent the
/// "inherit the global default" choice. `showMenu` resolves to `null`
/// when dismissed, so a real `null` selection can't be distinguished
/// from a dismissal — we route the global option through this sentinel
/// instead and translate it back to `null` on the way out.
const String _kGlobalSentinel = '__bee_inherit_global__';

/// Native, drill-in detail page for a single prompt.
///
/// Replaces the former modal `PromptSettingsDialog`. It renders a prompt's
/// per-prompt overrides using the exact same flat vocabulary as the General
/// and AI Models settings pages — [BeeGroupLabel] section headers,
/// [BeeSettingsRow] rows, and [BeeSegmented] / [BeeChip] controls — and
/// applies every change instantly (no Save/Cancel) like the rest of the
/// native settings surface. Every selectable control offers a "Global
/// default" choice so a prompt can inherit or override each setting
/// individually.
class PromptDetailPage extends StatefulWidget {
  final SystemPrompt prompt;
  final bool isBuiltIn;
  final PromptSettings overrides;
  final SettingsService settingsService;

  /// Pop back to the prompt list.
  final VoidCallback onBack;

  /// Fired on every change with the new (possibly empty) overrides. The
  /// parent is responsible for persisting via `setPromptOverrides`.
  final ValueChanged<PromptSettings> onOverridesChanged;

  /// Rename / re-instruction (custom prompts only — null for built-ins).
  final VoidCallback? onEdit;

  /// Create a copy of this prompt.
  final VoidCallback onDuplicate;

  /// Delete this prompt (custom prompts only — null for built-ins).
  final VoidCallback? onDelete;

  const PromptDetailPage({
    super.key,
    required this.prompt,
    required this.isBuiltIn,
    required this.overrides,
    required this.settingsService,
    required this.onBack,
    required this.onOverridesChanged,
    required this.onDuplicate,
    this.onEdit,
    this.onDelete,
  });

  @override
  State<PromptDetailPage> createState() => _PromptDetailPageState();
}

class _PromptDetailPageState extends State<PromptDetailPage> {
  late String? _selectedModel;
  late String? _selectedEngine;
  late String? _selectedProvider;
  late RephraseLevel? _selectedRephrase;
  late bool? _selectedTwoPass;
  late String? _selectedWhisperModel;
  late String? _selectedLanguage;
  late String? _selectedPassModel;
  late String? _selectedRefineModel;
  late GeminiThinkingLevel? _selectedThinkingLevel;
  late GeminiThinkingLevel? _selectedRefineThinkingLevel;

  late List<String> _downloadedWhisperModels;

  @override
  void initState() {
    super.initState();
    final o = widget.overrides;
    _selectedModel = o.modelId;
    _selectedEngine = o.transcriptionBackend;
    _selectedProvider = o.cloudProvider;
    _selectedRephrase = o.rephraseLevel;
    _selectedTwoPass = o.twoPassTranscriptionEnabled;
    _selectedWhisperModel = o.whisperModelId;
    _selectedLanguage = o.whisperLanguage;
    _selectedPassModel = o.twoPassTranscriptionModelId;
    _selectedRefineModel = o.twoPassRefinementModelId;
    _selectedThinkingLevel = o.thinkingLevel;
    _selectedRefineThinkingLevel = o.twoPassRefinementThinkingLevel;
    _downloadedWhisperModels = WhisperService.listDownloadedModels();
  }

  // ── Effective-state getters (mirror the global resolution logic) ─────────

  SettingsService get _s => widget.settingsService;

  bool get _isOfflineMode {
    final effectiveEngine = _selectedEngine ?? _s.transcriptionBackend.name;
    return effectiveEngine == TranscriptionBackend.whisper.name;
  }

  bool get _hasDownloadedModels => _downloadedWhisperModels.isNotEmpty;
  bool get _isTwoPassEnabled =>
      _selectedTwoPass ?? _s.twoPassTranscriptionEnabled;
  bool get _usesCloudForAnyStep => !_isOfflineMode || _isTwoPassEnabled;
  String get _effectiveCloudModelId => _selectedModel ?? _s.selectedModelId;
  String get _effectiveRefineModelId =>
      _selectedRefineModel ?? _selectedModel ?? _s.twoPassRefinementModelId;

  PromptSettings _buildOverrides() => PromptSettings(
    modelId: _selectedModel,
    transcriptionBackend: _selectedEngine,
    cloudProvider: _selectedProvider,
    rephraseLevel: _selectedRephrase,
    twoPassTranscriptionEnabled: _selectedTwoPass,
    twoPassTranscriptionModelId: _selectedPassModel,
    twoPassRefinementModelId: _selectedRefineModel,
    whisperModelId: _selectedWhisperModel,
    whisperLanguage: _selectedLanguage,
    thinkingLevel: _selectedThinkingLevel,
    twoPassRefinementThinkingLevel: _selectedRefineThinkingLevel,
  );

  /// Persist the current selections through the parent. Called after every
  /// change so the page behaves like the instant-apply native settings pages.
  void _apply() => widget.onOverridesChanged(_buildOverrides());

  void _resetToGlobal() {
    setState(() {
      _selectedModel = null;
      _selectedEngine = null;
      _selectedProvider = null;
      _selectedRephrase = null;
      _selectedTwoPass = null;
      _selectedWhisperModel = null;
      _selectedLanguage = null;
      _selectedPassModel = null;
      _selectedRefineModel = null;
      _selectedThinkingLevel = null;
      _selectedRefineThinkingLevel = null;
    });
    _apply();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildNavBar(context),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 4, 24, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildPromptHeader(context),
                ..._buildSettingsGroups(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Navigation bar (drill-in header) ─────────────────────────────────────

  Widget _buildNavBar(BuildContext context) {
    final hasOverride = _buildOverrides().hasAnyOverride;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 20, 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: beeDivider(context).withValues(alpha: 0.55),
          ),
        ),
      ),
      child: Row(
        children: [
          BeeInteractive(
            onTap: widget.onBack,
            semanticLabel: 'Back to all prompts',
            tooltip: 'All prompts',
            builder: (context, focused) => AnimatedContainer(
              duration: kBeeTransitionDuration,
              curve: kBeeTransitionCurve,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              decoration: BoxDecoration(
                color: focused
                    ? beeText(context).withValues(alpha: 0.06)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(kBeeRadiusXs),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.chevron_left_rounded,
                    size: 18,
                    color: beeTextSub(context),
                  ),
                  const SizedBox(width: 2),
                  Text(
                    'All Prompts',
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: beeTextSub(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          _kindTag(context, widget.isBuiltIn),
          if (hasOverride) ...[
            const SizedBox(width: 8),
            _customizedPill(context),
          ],
        ],
      ),
    );
  }

  Widget _buildPromptHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.prompt.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 19,
              fontWeight: FontWeight.w700,
              color: beeText(context),
              letterSpacing: -0.2,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: beeText(context).withValues(alpha: 0.025),
              borderRadius: BorderRadius.circular(kBeeRadiusXs),
            ),
            child: Text(
              widget.prompt.instruction.trim(),
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                color: beeTextSub(context),
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _kindTag(BuildContext context, bool isBuiltIn) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: beeText(context).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(kBeeRadiusXs),
      ),
      child: Text(
        isBuiltIn ? 'BUILT-IN' : 'CUSTOM',
        style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: beeTextMuted(context),
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _customizedPill(BuildContext context) {
    final accent = beeYellow(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(kBeeRadiusPill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tune_rounded, size: 10, color: accent),
          const SizedBox(width: 4),
          Text(
            'CUSTOMIZED',
            style: GoogleFonts.inter(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: accent,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Settings groups ──────────────────────────────────────────────────────

  /// Build a labelled group, wiring dividers so only inner rows draw one.
  List<Widget> _group(
    String label,
    List<Widget Function(bool showDivider)> rowBuilders,
  ) {
    final out = <Widget>[BeeGroupLabel(label: label)];
    for (var i = 0; i < rowBuilders.length; i++) {
      out.add(rowBuilders[i](i < rowBuilders.length - 1));
    }
    return out;
  }

  List<Widget> _buildSettingsGroups(BuildContext context) {
    final widgets = <Widget>[];

    void gap() => widgets.add(const SizedBox(height: 22));

    // ── PROCESSING ──────────────────────────────────────────────
    widgets.addAll(_group('Processing', [(d) => _engineRow(context, d)]));

    // ── CLOUD ───────────────────────────────────────────────────
    if (_usesCloudForAnyStep) {
      gap();
      final cloudModel = AppConfig.getModelById(_effectiveCloudModelId);
      widgets.addAll(
        _group('Cloud', [
          (d) => _providerRow(context, d),
          if (!_isOfflineMode) (d) => _modelRow(context, d),
          if (!_isOfflineMode && cloudModel.hasSelectableThinkingLevel)
            (d) => _reasoningRow(context, d),
        ]),
      );
    }

    // ── LOCAL ───────────────────────────────────────────────────
    if (_isOfflineMode) {
      gap();
      widgets.addAll(
        _group('Local', [
          (d) => _offlineModelRow(context, d),
          (d) => _languageRow(context, d),
        ]),
      );
    }

    // ── TRANSCRIPTION PIPELINE ──────────────────────────────────
    gap();
    final refineModel = AppConfig.getModelById(_effectiveRefineModelId);
    widgets.addAll(
      _group('Transcription Pipeline', [
        (d) => _twoPassRow(context, d),
        if (_isTwoPassEnabled) ...[
          (d) => _passOneRow(context, d),
          (d) => _refineModelRow(context, d),
          if (refineModel.hasSelectableThinkingLevel)
            (d) => _refineReasoningRow(context, d),
        ],
      ]),
    );

    // ── FORMATTING ──────────────────────────────────────────────
    gap();
    widgets.addAll(_group('Formatting', [(d) => _rephraserRow(context, d)]));

    // ── OVERRIDES (reset) ───────────────────────────────────────
    if (_buildOverrides().hasAnyOverride) {
      gap();
      widgets.addAll(_group('Overrides', [(d) => _resetRow(context, d)]));
    }

    // ── MANAGE PROMPT ───────────────────────────────────────────
    gap();
    widgets.addAll(_buildManageRows(context));

    return widgets;
  }

  // ── Individual rows ────────────────────────────────────────────────────

  Widget _engineRow(BuildContext context, bool showDivider) {
    final backend = _s.transcriptionBackend;
    final desc = _selectedEngine == null
        ? 'Inherits the app default — ${backend.displayName}'
        : _selectedEngine == TranscriptionBackend.cloud.value
        ? 'Always uses Cloud AI for this prompt'
        : 'Always runs offline (Whisper) for this prompt';
    return BeeSettingsRow(
      icon: Icons.memory_rounded,
      label: 'Processing Engine',
      description: desc,
      showDivider: showDivider,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: BeeSegmented<String?>(
          value: _selectedEngine,
          options: [
            (val: null, label: 'Global', icon: null),
            (val: TranscriptionBackend.cloud.value, label: 'Cloud', icon: null),
            (
              val: TranscriptionBackend.whisper.value,
              label: 'Local',
              icon: null,
            ),
          ],
          onChanged: (v) => setState(() {
            _selectedEngine = v;
            if (!AppConfig.getModelById(
              _effectiveCloudModelId,
            ).hasSelectableThinkingLevel) {
              _selectedThinkingLevel = null;
            }
            _apply();
          }),
        ),
      ),
    );
  }

  Widget _providerRow(BuildContext context, bool showDivider) {
    final global = _s.cloudProvider;
    return BeeSettingsRow(
      icon: Icons.cloud_rounded,
      label: 'Cloud Provider',
      description: _selectedProvider == null
          ? 'Inherits the app default — ${global.displayName}'
          : 'Custom override for this prompt',
      showDivider: showDivider,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 280),
        child: BeeSegmented<String?>(
          value: _selectedProvider,
          options: [
            (val: null, label: 'Global', icon: null),
            (
              val: CloudProvider.geminiApiKey.value,
              label: 'Gemini',
              icon: null,
            ),
            (val: CloudProvider.vertexAi.value, label: 'Vertex', icon: null),
          ],
          onChanged: (v) => setState(() {
            _selectedProvider = v;
            _apply();
          }),
        ),
      ),
    );
  }

  Widget _modelRow(BuildContext context, bool showDivider) {
    final items = <({String? value, String label})>[
      (value: null, label: 'Global default'),
      ...AppConfig.availableModels.map((m) => (value: m.id, label: m.name)),
    ];
    return BeeSettingsRow(
      icon: Icons.psychology_rounded,
      label: 'AI Model',
      description: _selectedModel == null
          ? 'Inherits the app default — ${_modelDisplayName(_s.selectedModelId)}'
          : 'Custom override for this prompt',
      showDivider: showDivider,
      trailing: _OverrideDropdown(
        items: items,
        value: _selectedModel,
        onChanged: (v) => setState(() {
          _selectedModel = v;
          if (!AppConfig.getModelById(
            _effectiveCloudModelId,
          ).hasSelectableThinkingLevel) {
            _selectedThinkingLevel = null;
          }
          _apply();
        }),
      ),
    );
  }

  Widget _reasoningRow(BuildContext context, bool showDivider) {
    final model = AppConfig.getModelById(_effectiveCloudModelId);
    final levels = model.supportedThinkingLevels;
    final globalLevel =
        _s.getThinkingLevelForModel(_effectiveCloudModelId) ??
        model.thinkingLevel ??
        levels.first;
    return BeeSettingsRow(
      icon: Icons.psychology_alt_rounded,
      label: 'Reasoning Effort',
      description: _selectedThinkingLevel == null
          ? 'Inherits the app default — ${globalLevel.displayLabel}'
          : 'Custom override for this prompt',
      showDivider: showDivider,
      trailing: _OverrideDropdown(
        items: [
          (value: null, label: 'Global default'),
          ...levels.map((l) => (value: l.apiValue, label: l.displayLabel)),
        ],
        value: _selectedThinkingLevel?.apiValue,
        onChanged: (v) => setState(() {
          _selectedThinkingLevel = GeminiThinkingLevelExtension.fromString(v);
          _apply();
        }),
      ),
    );
  }

  Widget _offlineModelRow(BuildContext context, bool showDivider) {
    if (!_hasDownloadedModels) {
      return BeeSettingsRow(
        icon: Icons.cloud_off_rounded,
        label: 'Offline Model',
        description: 'No offline models downloaded. Add one in AI Models.',
        showDivider: showDivider,
        trailing: Text(
          'None',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: beeTextMuted(context),
          ),
        ),
      );
    }
    return BeeSettingsRow(
      icon: Icons.offline_pin_rounded,
      label: 'Offline Model',
      description: _selectedWhisperModel == null
          ? 'Inherits the app default — ${_whisperModelDisplayName(_s.whisperModelId)}'
          : 'Custom override for this prompt',
      showDivider: showDivider,
      trailing: _OverrideDropdown(
        items: [
          (value: null, label: 'Global default'),
          ..._getDownloadedModelItems(),
        ],
        value: _selectedWhisperModel,
        onChanged: (v) => setState(() {
          _selectedWhisperModel = v;
          _apply();
        }),
      ),
    );
  }

  Widget _languageRow(BuildContext context, bool showDivider) {
    return BeeSettingsRow(
      icon: Icons.translate_rounded,
      label: 'Language',
      description: _selectedLanguage == null
          ? 'Inherits the app default — ${_languageDisplayName(_s.whisperLanguage)}'
          : 'Custom override for this prompt',
      showDivider: showDivider,
      trailing: _OverrideDropdown(
        items: const [
          (value: null, label: 'Global default'),
          (value: 'auto', label: 'Auto-Detect'),
          (value: 'en', label: 'English'),
          (value: 'de', label: 'German'),
          (value: 'fr', label: 'French'),
          (value: 'es', label: 'Spanish'),
        ],
        value: _selectedLanguage,
        onChanged: (v) => setState(() {
          _selectedLanguage = v;
          _apply();
        }),
      ),
    );
  }

  Widget _twoPassRow(BuildContext context, bool showDivider) {
    final global = _s.twoPassTranscriptionEnabled;
    return BeeSettingsRow(
      icon: Icons.linear_scale_rounded,
      label: 'Two-Pass Refinement',
      description: _selectedTwoPass == null
          ? 'Inherits the app default — ${global ? 'On' : 'Off'}'
          : 'Custom override for this prompt',
      showDivider: showDivider,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: BeeSegmented<bool?>(
          value: _selectedTwoPass,
          options: const [
            (val: null, label: 'Global', icon: null),
            (val: false, label: 'Off', icon: null),
            (val: true, label: 'On', icon: null),
          ],
          onChanged: (v) => setState(() {
            _selectedTwoPass = v;
            _apply();
          }),
        ),
      ),
    );
  }

  Widget _passOneRow(BuildContext context, bool showDivider) {
    if (_isOfflineMode) {
      return BeeSettingsRow(
        icon: Icons.looks_one_rounded,
        label: 'Pass 1 · Raw Transcription',
        description: 'Runs on your selected offline Whisper model.',
        showDivider: showDivider,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_rounded, size: 11, color: beeTextMuted(context)),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 160),
              child: Text(
                _getOfflineModelName() ?? 'Whisper (Offline)',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: beeTextSub(context),
                ),
              ),
            ),
          ],
        ),
      );
    }
    // Cloud first pass can override the transcription-only model.
    final items = <({String? value, String label})>[
      (value: null, label: 'Global default'),
      ...AppConfig.availableModels.map((m) => (value: m.id, label: m.name)),
    ];
    return BeeSettingsRow(
      icon: Icons.looks_one_rounded,
      label: 'Pass 1 · Transcription',
      description: _selectedPassModel == null
          ? 'Inherits the app default — ${_modelDisplayName(_s.twoPassTranscriptionModelId)}'
          : 'Custom override for this prompt',
      showDivider: showDivider,
      trailing: _OverrideDropdown(
        items: items,
        value: _selectedPassModel,
        onChanged: (v) => setState(() {
          _selectedPassModel = v;
          _apply();
        }),
      ),
    );
  }

  Widget _refineModelRow(BuildContext context, bool showDivider) {
    final items = <({String? value, String label})>[
      (value: null, label: 'Global default'),
      ...AppConfig.availableModels.map((m) => (value: m.id, label: m.name)),
    ];
    return BeeSettingsRow(
      icon: Icons.looks_two_rounded,
      label: 'Pass 2 · AI Refinement',
      description: _selectedRefineModel == null
          ? 'Inherits the app default — ${_modelDisplayName(_s.twoPassRefinementModelId)}'
          : 'Custom override for this prompt',
      showDivider: showDivider,
      trailing: _OverrideDropdown(
        items: items,
        value: _selectedRefineModel,
        onChanged: (v) => setState(() {
          _selectedRefineModel = v;
          if (!AppConfig.getModelById(
            _effectiveRefineModelId,
          ).hasSelectableThinkingLevel) {
            _selectedRefineThinkingLevel = null;
          }
          _apply();
        }),
      ),
    );
  }

  Widget _refineReasoningRow(BuildContext context, bool showDivider) {
    final model = AppConfig.getModelById(_effectiveRefineModelId);
    final levels = model.supportedThinkingLevels;
    final globalLevel =
        _s.getThinkingLevelForModel(_effectiveRefineModelId) ??
        model.thinkingLevel ??
        levels.first;
    return BeeSettingsRow(
      icon: Icons.psychology_rounded,
      label: 'Refinement Reasoning Effort',
      description: _selectedRefineThinkingLevel == null
          ? 'Inherits the app default — ${globalLevel.displayLabel}'
          : 'Custom override for this prompt',
      showDivider: showDivider,
      trailing: _OverrideDropdown(
        items: [
          (value: null, label: 'Global default'),
          ...levels.map((l) => (value: l.apiValue, label: l.displayLabel)),
        ],
        value: _selectedRefineThinkingLevel?.apiValue,
        onChanged: (v) => setState(() {
          _selectedRefineThinkingLevel =
              GeminiThinkingLevelExtension.fromString(v);
          _apply();
        }),
      ),
    );
  }

  Widget _rephraserRow(BuildContext context, bool showDivider) {
    final global = _s.rephraseLevel;
    return BeeSettingsRow(
      icon: Icons.auto_fix_high_rounded,
      label: 'Rephraser',
      description: _selectedRephrase == null
          ? 'Inherits the app default — ${global.displayName}'
          : 'Custom override for this prompt',
      showDivider: showDivider,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: BeeSegmented<RephraseLevel?>(
          value: _selectedRephrase,
          options: const [
            (val: null, label: 'Global', icon: null),
            (val: RephraseLevel.off, label: 'Off', icon: null),
            (val: RephraseLevel.medium, label: 'Medium', icon: null),
            (val: RephraseLevel.high, label: 'High', icon: null),
          ],
          onChanged: (v) => setState(() {
            _selectedRephrase = v;
            _apply();
          }),
        ),
      ),
    );
  }

  Widget _resetRow(BuildContext context, bool showDivider) {
    return BeeSettingsRow(
      icon: Icons.restart_alt_rounded,
      label: 'Reset to App Defaults',
      description:
          'Clear every custom setting and inherit the global defaults.',
      showDivider: showDivider,
      trailing: BeeActionChip(
        label: 'Reset',
        icon: Icons.restore_rounded,
        color: beeError(context),
        onTap: _resetToGlobal,
      ),
    );
  }

  List<Widget> _buildManageRows(BuildContext context) {
    final rows = <Widget Function(bool)>[];
    if (!widget.isBuiltIn && widget.onEdit != null) {
      rows.add(
        (d) => BeeSettingsRow(
          icon: Icons.edit_outlined,
          label: 'Edit Name & Instruction',
          description: 'Rename this prompt or change its wording.',
          showDivider: d,
          onTap: widget.onEdit,
          trailing: _chevron(context),
        ),
      );
    }
    rows.add(
      (d) => BeeSettingsRow(
        icon: Icons.copy_all_rounded,
        label: 'Duplicate',
        description: widget.isBuiltIn
            ? 'Create an editable custom copy of this built-in prompt.'
            : 'Create a copy of this prompt.',
        showDivider: d,
        onTap: widget.onDuplicate,
        trailing: _chevron(context),
      ),
    );
    if (!widget.isBuiltIn && widget.onDelete != null) {
      rows.add(
        (d) => BeeSettingsRow(
          icon: Icons.delete_outline_rounded,
          label: 'Delete Prompt',
          description: 'Permanently remove this custom prompt.',
          showDivider: d,
          trailing: BeeActionChip(
            label: 'Delete',
            icon: Icons.delete_outline_rounded,
            color: beeError(context),
            onTap: widget.onDelete,
          ),
        ),
      );
    }
    return _group('Manage Prompt', rows);
  }

  Widget _chevron(BuildContext context) =>
      Icon(Icons.chevron_right_rounded, size: 14, color: beeTextMuted(context));

  // ── Display-name helpers ─────────────────────────────────────────────────

  List<({String? value, String label})> _getDownloadedModelItems() {
    return _downloadedWhisperModels.map((id) {
      final info = WhisperModelDownloadService.availableModels.firstWhere(
        (m) => m.id == id,
        orElse: () => WhisperModelDownloadService.availableModels.first,
      );
      return (value: id, label: '${info.name} (${info.sizeDisplay})');
    }).toList();
  }

  String _modelDisplayName(String modelId) =>
      AppConfig.getModelById(modelId).displayName;

  String _whisperModelDisplayName(String modelId) {
    try {
      final info = WhisperModelDownloadService.availableModels.firstWhere(
        (m) => m.id == modelId,
      );
      return info.name;
    } catch (_) {
      return modelId;
    }
  }

  String _languageDisplayName(String language) {
    switch (language) {
      case 'auto':
        return 'Auto-detect';
      case 'en':
        return 'English';
      case 'de':
        return 'German';
      case 'fr':
        return 'French';
      case 'es':
        return 'Spanish';
      default:
        return language;
    }
  }

  String? _getOfflineModelName() {
    final modelId = _selectedWhisperModel ?? _s.whisperModelId;
    return _whisperModelDisplayName(modelId);
  }
}

// ── Override dropdown (flat trailing chip + native popup menu) ──────────────

/// A trailing control for [BeeSettingsRow] that mirrors the AI Models page's
/// flat dropdown: a [BeeChip] showing the current selection that opens a
/// native [showMenu] popup. The first item is expected to be the
/// "Global default" sentinel; a `null` [value] means the row is inheriting.
class _OverrideDropdown extends StatelessWidget {
  final List<({String? value, String label})> items;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _OverrideDropdown({
    required this.items,
    required this.value,
    required this.onChanged,
  });

  String _labelForValue(String? v) {
    for (final item in items) {
      if (item.value == v) return item.label;
    }
    return v ?? 'Global default';
  }

  @override
  Widget build(BuildContext context) {
    final isOverride = value != null;
    final currentLabel = _labelForValue(value);

    return Builder(
      builder: (context) => ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 240),
        child: BeeChip(
          displayValue: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isOverride) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: beeYellow(context),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: Text(
                  currentLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: isOverride
                        ? beeText(context)
                        : beeTextMuted(context),
                  ),
                ),
              ),
            ],
          ),
          onTap: () async {
            final selected = await showMenu<String>(
              context: context,
              position: _menuPosition(context),
              color: beeSurfaceRaised(context),
              elevation: 8,
              constraints: const BoxConstraints(minWidth: 210),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kBeeRadiusSm),
                side: BorderSide(
                  color: beeDivider(context).withValues(alpha: 0.6),
                ),
              ),
              initialValue: value ?? _kGlobalSentinel,
              items: items.map((item) {
                final menuValue = item.value ?? _kGlobalSentinel;
                final isGlobal = item.value == null;
                final isSel = item.value == value;
                return PopupMenuItem<String>(
                  value: menuValue,
                  height: 40,
                  child: Row(
                    children: [
                      if (isGlobal) ...[
                        Icon(
                          Icons.public_rounded,
                          size: 13,
                          color: beeTextMuted(context),
                        ),
                        const SizedBox(width: 8),
                      ],
                      Expanded(
                        child: Text(
                          item.label,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: isSel
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: isSel
                                ? beeYellow(context)
                                : beeText(context),
                          ),
                        ),
                      ),
                      if (isSel) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: beeYellow(context),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            );
            if (selected == null) return; // dismissed
            final newValue = selected == _kGlobalSentinel ? null : selected;
            if (newValue != value) onChanged(newValue);
          },
        ),
      ),
    );
  }
}

/// Position a popup menu just below and roughly centered under the chip.
RelativeRect _menuPosition(BuildContext context) {
  final box = context.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
  if (box == null) {
    return RelativeRect.fill;
  }
  final size = box.size;
  final offset = box.localToGlobal(Offset.zero, ancestor: overlay);
  final overlaySize = overlay.size;
  return RelativeRect.fromLTRB(
    offset.dx + (size.width / 2).clamp(80.0, overlaySize.width / 2),
    offset.dy + size.height + 4,
    overlaySize.width - (offset.dx + size.width - 8),
    overlaySize.height - (offset.dy + size.height + 100),
  );
}
