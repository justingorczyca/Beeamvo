import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../models/system_prompt.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import 'settings/settings_shared.dart';

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
    WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSelectedVisible());
  }

  @override
  void didUpdateWidget(covariant ModeSelectionPopup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selectedIndex != _lastKnownIndex) {
      _lastKnownIndex = widget.selectedIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) => _ensureSelectedVisible());
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
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  itemCount: allPrompts.length,
                  itemBuilder: (_, i) => _PromptTile(
                    key: i == widget.selectedIndex ? _selectedTileKey : null,
                    prompt: allPrompts[i],
                    isSelected: i == widget.selectedIndex,
                    isDefault: allPrompts[i].id == savedId,
                    settingsService: widget.settingsService,
                    onTap: () => widget.onSelect(allPrompts[i].id),
                  ),
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
  final bool isDefault;
  final SettingsService settingsService;
  final VoidCallback onTap;

  const _PromptTile({
    super.key,
    required this.prompt,
    required this.isSelected,
    required this.isDefault,
    required this.settingsService,
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
    final overrides = widget.settingsService.getPromptOverrides(
      widget.prompt.id,
    );
    final hasOverrides = overrides != null && overrides.hasAnyOverride;
    // On the local-only backend a non-default prompt has no effect until a
    // cloud model is in the pipeline. It stays tappable (selecting it opens
    // the switch-to-cloud prompt) but reads as grayed-out/inactive.
    final isBlocked = widget.settingsService.isPromptInactiveOnLocalBackend(
      widget.prompt.id,
    );

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        margin: const EdgeInsets.symmetric(vertical: 2),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: widget.isSelected
              ? beeYellow(context).withValues(alpha: 0.10)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(kBeeRadiusSm),
          border: widget.isSelected
              ? Border.all(color: beeYellow(context).withValues(alpha: 0.70))
              : null,
        ),
        child: Opacity(
          opacity: isBlocked ? 0.5 : 1.0,
          child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.isSelected ? beeYellow(context) : Colors.transparent,
                border: Border.all(
                  color: widget.isSelected ? beeYellow(context) : beeBorder(context),
                  width: 1.5,
                ),
              ),
              child: widget.isSelected
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
                  fontWeight: widget.isSelected
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: widget.isSelected ? beeText(context) : beeTextSub(context),
                ),
              ),
            ),
            if (widget.isDefault)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
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
              ),
            if (hasOverrides) ...[
              if (widget.isDefault) const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 5,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: beeSuccess(context).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(kBeeRadiusXs),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.tune_rounded, size: 10, color: beeSuccess(context)),
                    const SizedBox(width: 2),
                    Text(
                      '${overrides.overrideCount}',
                      style: GoogleFonts.inter(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: beeSuccess(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        ),
      ),
    );
  }
}
