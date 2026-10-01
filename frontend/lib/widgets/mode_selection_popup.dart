import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/system_prompt.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import 'settings/settings_shared.dart';

/// Whether [prompt] may be chosen in the mode popup right now. Default is
/// always selectable; every other style requires a pipeline that applies
/// prompts (cloud prompt-capable model, or two-step refinement) — resolved
/// for THAT style, so a style carrying overrides (forced two-step, or a
/// prompt-capable pass-1 model) stays usable even when the global setup
/// cannot apply styles, and vice versa.
bool promptSelectableInModePopup(
  SettingsService settings,
  SystemPrompt prompt,
) => prompt.id == SystemPrompt.defaultId || settings.promptAppliesFor(prompt);

/// Next index from [current] (stepping in the direction of [delta].sign)
/// whose prompt is selectable. Returns [current] when no selectable index
/// exists in that direction. Never wraps. Pure, no side effects.
int nextSelectableModeIndex({
  required List<SystemPrompt> prompts,
  required SettingsService settings,
  required int current,
  required int delta,
}) {
  final step = delta.sign;
  if (step == 0) return current;
  for (var i = current + step; i >= 0 && i < prompts.length; i += step) {
    if (promptSelectableInModePopup(settings, prompts[i])) return i;
  }
  return current;
}

/// Copy for the notice strip shown while styles are locked, phrased for the
/// active backend so the way out is actionable. Kept as a pure top-level
/// function so tests can pin the exact strings.
String modePopupLockNotice(SettingsService settings) {
  if (settings.transcriptionBackend == TranscriptionBackend.whisper) {
    return 'Whisper transcribes only. Turn on Two-Step Refinement to apply styles.';
  }
  // Cloud engine with a transcription-only model in single-pass mode.
  return 'Styles need a prompt-capable model or Two-Step Refinement. Only Default is available.';
}

/// Compact popup that lists all available transcription prompts for quick
/// one-off mode selection. Keyboard-navigable (arrows, Enter, Escape).
class ModeSelectionPopup extends StatefulWidget {
  final SettingsService settingsService;
  final int selectedIndex;
  final ValueChanged<String> onSelect;
  final VoidCallback onCancel;

  const ModeSelectionPopup({
    super.key,
    required this.settingsService,
    required this.selectedIndex,
    required this.onSelect,
    required this.onCancel,
  });

  @override
  State<ModeSelectionPopup> createState() => _ModeSelectionPopupState();
}

class _ModeSelectionPopupState extends State<ModeSelectionPopup> {
  /// Attached only to the currently selected tile so we can scroll it into
  /// view whenever the keyboard-driven [widget.selectedIndex] changes.
  final GlobalKey _selectedTileKey = GlobalKey();
  int _lastKnownIndex = 0;

  @override
  void initState() {
    super.initState();
    _lastKnownIndex = widget.selectedIndex;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _ensureSelectedVisible(),
    );
  }

  @override
  void didUpdateWidget(covariant ModeSelectionPopup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != _lastKnownIndex) {
      _lastKnownIndex = widget.selectedIndex;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ensureSelectedVisible(),
      );
    }
  }

  /// Scrolls the currently selected tile into view so arrow-key navigation
  /// always reveals the highlighted prompt, even when it sits below the fold.
  void _ensureSelectedVisible() {
    final ctx = _selectedTileKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final allPrompts = [
      ...SystemPrompt.availablePrompts,
      ...widget.settingsService.customPrompts,
    ];
    final savedId = widget.settingsService.selectedPromptId;

    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: AppTheme.panelDecoration(
          color: beeBlack(context),
          radius: kBeeRadiusLg,
          outlineColor: beeBorder(context),
          outlineOpacity: 0.8,
          shadows: AppTheme.windowShadow,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(kBeeRadiusLg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(context),
              if (!widget.settingsService.promptIsApplied)
                _buildLockNotice(context),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  itemCount: allPrompts.length,
                  itemBuilder: (_, i) {
                    final prompt = allPrompts[i];
                    // Selectability lives in one place so the tray menu,
                    // keyboard stepping, and the tiles can never drift.
                    final isBlocked = !promptSelectableInModePopup(
                      widget.settingsService,
                      prompt,
                    );
                    return _PromptTile(
                      key: i == widget.selectedIndex ? _selectedTileKey : null,
                      prompt: prompt,
                      isSelected: i == widget.selectedIndex,
                      isDefault: prompt.id == savedId,
                      isBlocked: isBlocked,
                      onTap: isBlocked
                          ? null
                          : () => widget.onSelect(prompt.id),
                    );
                  },
                ),
              ),
              _buildFooter(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: beeYellow(context).withValues(alpha: 0.06),
        border: Border(bottom: BorderSide(color: beeDivider(context))),
      ),
      child: Row(
        children: [
          Icon(Icons.tune_rounded, size: 16, color: beeYellow(context)),
          const SizedBox(width: 8),
          Text(
            'Select Mode',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: beeText(context),
            ),
          ),
        ],
      ),
    );
  }

  /// Quiet notice between header and list, shown only while the active
  /// pipeline cannot apply writing styles. Explains the dimmed, locked
  /// tiles so the state is self-explanatory instead of silently ignored.
  Widget _buildLockNotice(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: beeYellow(context).withValues(alpha: 0.06),
        border: Border(bottom: BorderSide(color: beeDivider(context))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 13, color: beeYellow(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              modePopupLockNotice(widget.settingsService),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 11,
                color: beeTextMuted(context),
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: beeDivider(context))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ..._keycapHints(context, 'Up/Down', 'navigate'),
          const SizedBox(width: 10),
          ..._keycapHints(context, 'Enter', 'select'),
          const SizedBox(width: 10),
          ..._keycapHints(context, 'Esc', 'cancel'),
        ],
      ),
    );
  }

  List<Widget> _keycapHints(BuildContext context, String key, String label) {
    return [
      ...renderKeycaps(key),
      Padding(
        padding: const EdgeInsets.only(left: 3),
        child: Text(
          label,
          style: GoogleFonts.inter(fontSize: 10, color: beeTextMuted(context)),
        ),
      ),
    ];
  }
}

class _PromptTile extends StatefulWidget {
  final SystemPrompt prompt;
  final bool isSelected;

  /// Marks the saved style with the trailing DEFAULT badge.
  final bool isDefault;

  /// A blocked style cannot affect the pipeline's output: the tile is
  /// dimmed, untappable, never highlighted, and not a semantic button.
  final bool isBlocked;

  /// Null while blocked so the tile gives no tap feedback at all.
  final VoidCallback? onTap;

  const _PromptTile({
    super.key,
    required this.prompt,
    required this.isSelected,
    required this.isDefault,
    required this.isBlocked,
    required this.onTap,
  });

  @override
  State<_PromptTile> createState() => _PromptTileState();
}

class _PromptTileState extends State<_PromptTile>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context); // Required for AutomaticKeepAliveClientMixin
    // Styles other than Default only shape the output when the pipeline
    // applies prompts. A blocked tile stays visible but inert: no tap
    // target, no selection highlight, and no button semantics.
    final showSelected = widget.isSelected && !widget.isBlocked;

    return Semantics(
      label: widget.prompt.name,
      button: !widget.isBlocked,
      enabled: !widget.isBlocked,
      selected: showSelected,
      onTap: widget.isBlocked ? null : widget.onTap,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            color: showSelected
                ? beeYellow(context).withValues(alpha: 0.10)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(kBeeRadiusSm),
            border: showSelected
                ? Border.all(color: beeYellow(context).withValues(alpha: 0.70))
                : null,
          ),
          child: Opacity(
            opacity: widget.isBlocked ? 0.5 : 1.0,
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: showSelected
                        ? beeYellow(context)
                        : Colors.transparent,
                    border: Border.all(
                      color: showSelected
                          ? beeYellow(context)
                          : beeBorder(context),
                      width: 1.5,
                    ),
                  ),
                  child: showSelected
                      ? Center(
                          child: Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: beeBlack(context),
                            ),
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.prompt.name,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: showSelected
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: showSelected
                          ? beeText(context)
                          : beeTextSub(context),
                    ),
                  ),
                ),
                // The trailing slot holds the DEFAULT badge, or — only on a
                // blocked tile, which is never the default — the lock icon.
                if (widget.isDefault)
                  _buildDefaultBadge(context)
                else if (widget.isBlocked)
                  Icon(
                    Icons.lock_outline_rounded,
                    size: 13,
                    color: beeTextMuted(context),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Trailing pill that marks the saved style.
  Widget _buildDefaultBadge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: beeYellow(context).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(kBeeRadiusXs),
      ),
      child: Text(
        'DEFAULT',
        style: GoogleFonts.inter(
          fontSize: 8,
          fontWeight: FontWeight.w800,
          color: beeYellow(context),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
