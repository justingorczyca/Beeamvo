import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import 'prompt_cloud_switch_dialog.dart';
import 'settings/settings_shared.dart';

/// Inline cloud-switch confirm shown INSIDE the compact 320x360 mode-selection
/// popup (Ctrl+M flow) when the chosen prompt needs a cloud model. It mirrors
/// [ModeSelectionPopup]'s chrome — same panel decoration, tinted header bar and
/// keycap footer — so it reads as a natural drill-in continuation of the mode
/// list rather than a jarring modal/resize.
///
/// The popup window is shown WITHOUT OS focus, so Flutter never receives its
/// key events. Navigation is driven entirely by global hotkeys wired in
/// `main.dart`; tapping a tile confirms that option directly. The option tiles
/// are the shared [PromptCloudModeTile], so this view is pixel-identical to the
/// settings-window modal.
class ModeCloudConfirmPopup extends StatelessWidget {
  final SettingsService settingsService;

  /// Name of the prompt being enabled — drives the headline / no-cloud copy.
  final String promptName;

  /// Keyboard-highlighted option index (0 = local two-pass, 1 = cloud).
  final int selectedIndex;

  /// Confirms the option at [index] (tile tap or Enter on the highlight).
  final ValueChanged<int> onSelect;

  /// Invoked when cloud credentials are missing and the user opts to set them
  /// up (button tap or Enter).
  final VoidCallback onOpenSettings;

  /// Returns to the mode-selection list (Esc).
  final VoidCallback onCancel;

  const ModeCloudConfirmPopup({
    super.key,
    required this.settingsService,
    required this.promptName,
    required this.selectedIndex,
    required this.onSelect,
    required this.onOpenSettings,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final copy = promptCloudSwitchCopy(PromptCloudFeature.prompt, promptName);
    // No provider configured yet — offer to set one up instead of a switch.
    final needsSetup = !settingsService.hasCloudCredentials;

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
              _buildHeader(context, copy.title),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  child: needsSetup
                      ? _buildNeedsSetup(context, copy.needsBody)
                      : _buildOptions(context),
                ),
              ),
              _buildFooter(context, needsSetup),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String title) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
      decoration: BoxDecoration(
        color: beeYellow(context).withValues(alpha: 0.06),
        border: Border(bottom: BorderSide(color: beeDivider(context))),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_rounded, size: 16, color: beeYellow(context)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: beeText(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < kPromptCloudModeOptions.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          PromptCloudModeTile(
            selected: i == selectedIndex,
            icon: kPromptCloudModeOptions[i].icon,
            title: kPromptCloudModeOptions[i].title,
            description: kPromptCloudModeOptions[i].description,
            detailIcon: kPromptCloudModeOptions[i].detailIcon,
            detail: kPromptCloudModeOptions[i].detail,
            onTap: () => onSelect(i),
          ),
        ],
      ],
    );
  }

  Widget _buildNeedsSetup(BuildContext context, String body) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 2),
        Text(
          body,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: beeTextSub(context),
            height: 1.45,
          ),
        ),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton(
            style: beePrimaryButtonStyle(context),
            onPressed: onOpenSettings,
            child: Text(
              'Open Settings',
              style: GoogleFonts.inter(
                color: beeBlack(context),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFooter(BuildContext context, bool needsSetup) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: beeDivider(context))),
      ),
      // Wrap (not Row) so the hints stay on one line when they fit and wrap
      // gracefully on narrower widths instead of overflowing — same as the
      // settings-window modal's hint bar.
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 10,
        runSpacing: 6,
        children: needsSetup
            ? [
                _keyHint(context, 'Enter', 'open settings'),
                _keyHint(context, 'Esc', 'cancel'),
              ]
            : [
                _keyHint(context, 'Up/Down', 'navigate'),
                _keyHint(context, 'Enter', 'switch'),
                _keyHint(context, 'Esc', 'cancel'),
              ],
      ),
    );
  }

  Widget _keyHint(BuildContext context, String key, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...renderKeycaps(key),
        Padding(
          padding: const EdgeInsets.only(left: 3),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 10,
              color: beeTextMuted(context),
            ),
          ),
        ),
      ],
    );
  }
}
