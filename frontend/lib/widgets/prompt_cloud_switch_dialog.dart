import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/settings_service.dart';
import 'settings/settings_shared.dart';

/// Outcome of [showPromptCloudSwitchDialog].
enum PromptCloudResult {
  /// User chose to keep local Whisper transcription with a cloud two-pass
  /// refinement so the prompt is applied. The change has already been
  /// persisted to the [SettingsService] before this is returned.
  localTwoPass,

  /// User chose full single-pass cloud transcription. The change has already
  /// been persisted to the [SettingsService] before this is returned.
  cloud,

  /// User dismissed the dialog without changing anything.
  cancelled,

  /// No cloud credentials are configured. The caller should route the user to
  /// the Transcription settings so they can add a key / project.
  openSettings,
}

/// Modes offered when a feature needs a cloud model. Kept private — callers
/// receive the resolved [PromptCloudResult] instead.
enum _SwitchMode { localTwoPass, cloud }

/// Which feature triggered the switch — drives the dialog wording only.
enum PromptCloudFeature { prompt, rephraser }

/// The headline / body copy for a given [PromptCloudFeature].
({String title, String intro, String needsBody}) _copyFor(
  PromptCloudFeature feature,
  String? promptName,
) {
  switch (feature) {
    case PromptCloudFeature.prompt:
      final subject = promptName != null
          ? '\u201c$promptName\u201d'
          : 'prompts';
      final introSubject = promptName != null
          ? '\u201c$promptName\u201d'
          : 'This prompt';
      return (
        title: 'Prompts need a cloud model',
        intro:
            '$introSubject only changes your text when a cloud model is in the '
            'pipeline. For prompt usage we switch to cloud models \u2014 '
            'choose how:',
        needsBody:
            'For prompt usage we switch to cloud models, but no cloud provider '
            'is set up yet. Add a Gemini API key (or configure Vertex AI) in '
            'Settings \u2192 Transcription to use $subject.',
      );
    case PromptCloudFeature.rephraser:
      return (
        title: 'Rephrasing needs a cloud model',
        intro:
            'The rephraser only changes your text when a cloud model is in the '
            'pipeline. For rephraser usage we switch to cloud models \u2014 '
            'choose how:',
        needsBody:
            'For rephraser usage we switch to cloud models, but no cloud '
            'provider is set up yet. Add a Gemini API key (or configure Vertex '
            'AI) in Settings \u2192 Transcription to use the rephraser.',
      );
  }
}

/// Public accessor for the cloud-switch headline / body copy so the inline
/// mode-selection variant (see ModeCloudConfirmPopup) can reuse the exact
/// wording shown by the modal.
({String title, String intro, String needsBody}) promptCloudSwitchCopy(
  PromptCloudFeature feature, [
  String? promptName,
]) => _copyFor(feature, promptName);

/// The two transcription-mode options offered when a feature needs a cloud
/// model, in keyboard-navigation order (conservative "keep local" first).
/// Shared by the modal and the inline popup so both list identical choices.
const List<
  ({
    IconData icon,
    String title,
    String description,
    IconData detailIcon,
    String detail,
  })
>
kPromptCloudModeOptions = [
  (
    icon: Icons.layers_rounded,
    title: 'Local + 2-pass cloud',
    description:
        'Transcribe offline with Whisper, then a cloud model applies your '
        'prompt.',
    detailIcon: Icons.lock_rounded,
    detail: 'Audio stays on device',
  ),
  (
    icon: Icons.cloud_rounded,
    title: 'Cloud transcription',
    description:
        'A cloud model transcribes and applies your prompt in a single pass.',
    detailIcon: Icons.cloud_upload_rounded,
    detail: 'Audio is sent to the cloud',
  ),
];

/// A single transcription-mode option tile. Shared by the inline cloud-switch
/// popup (Ctrl+M flow) and the [showPromptCloudSwitchDialog] modal (settings
/// window) so both read identically. Uses the app's amber accent for the
/// selected state (tint + border + radio + detail caps) to match the
/// mode-selection popup tiles instead of a monochrome choice group.
class PromptCloudModeTile extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String description;
  final IconData detailIcon;
  final String detail;
  final VoidCallback onTap;
  final bool enabled;

  const PromptCloudModeTile({
    super.key,
    required this.selected,
    required this.icon,
    required this.title,
    required this.description,
    required this.detailIcon,
    required this.detail,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final accent = beeYellow(context);
    return BeeInteractive(
      onTap: enabled ? onTap : null,
      semanticLabel: title,
      selected: selected,
      toggled: selected,
      builder: (context, focused) => AnimatedContainer(
        duration: kBeeTransitionDuration,
        curve: kBeeTransitionCurve,
        padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.10)
              : beeText(context).withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(kBeeRadiusMd),
          border: Border.all(
            color: selected
                ? accent.withValues(alpha: 0.75)
                : focused
                ? accent.withValues(alpha: 0.45)
                : beeDivider(context),
            width: selected ? 1.4 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: selected
                    ? accent.withValues(alpha: 0.18)
                    : beeText(context).withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(kBeeRadiusSm),
              ),
              child: Icon(
                icon,
                size: 16,
                color: selected ? accent : beeTextMuted(context),
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                      color: selected ? beeText(context) : beeTextSub(context),
                      letterSpacing: -0.1,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: GoogleFonts.inter(
                      fontSize: 11.5,
                      color: beeTextSub(context),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Icon(
                        detailIcon,
                        size: 11,
                        color: selected ? accent : beeTextMuted(context),
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          detail.toUpperCase(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            color: selected ? accent : beeTextMuted(context),
                            letterSpacing: 0.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: _radio(context, selected, accent),
            ),
          ],
        ),
      ),
    );
  }

  Widget _radio(BuildContext context, bool selected, Color accent) {
    return AnimatedContainer(
      duration: kBeeTransitionDuration,
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? accent : Colors.transparent,
        border: Border.all(
          color: selected ? accent : beeBorder(context),
          width: selected ? 1 : 1.4,
        ),
      ),
      child: selected
          ? Icon(Icons.check_rounded, size: 12, color: beeBlack(context))
          : null,
    );
  }
}

/// Explains that a feature (a prompt, or the rephraser) only takes effect with
/// a cloud model in the pipeline, and lets the user choose HOW to enable it:
///
///  * **Keep local transcription** — Whisper still transcribes the audio
///    offline, but a cloud model refines the transcript (two-pass).
///  * **Use cloud transcription** — a cloud model transcribes and refines in a
///    single pass.
///
/// The chosen change is applied to [settings] before the future completes, so
/// callers only need to react to the returned [PromptCloudResult].
///
/// When no cloud credentials are configured, a simpler "set up cloud" variant
/// is shown and [PromptCloudResult.openSettings] is returned if the user opts
/// to configure it.
Future<PromptCloudResult> showPromptCloudSwitchDialog({
  required BuildContext context,
  required SettingsService settings,
  PromptCloudFeature feature = PromptCloudFeature.prompt,
  String? promptName,
}) async {
  final copy = _copyFor(feature, promptName);

  if (!settings.hasCloudCredentials) {
    final openSettings = await _showNeedsCloudDialog(
      context,
      title: copy.title,
      body: copy.needsBody,
    );
    return openSettings == true
        ? PromptCloudResult.openSettings
        : PromptCloudResult.cancelled;
  }

  final result = await showDialog<PromptCloudResult>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => _PromptCloudSwitchDialog(
      settings: settings,
      title: copy.title,
      intro: copy.intro,
    ),
  );
  return result ?? PromptCloudResult.cancelled;
}

/// Compact dialog shown when the feature needs cloud but no provider is
/// configured. Returns `true` when the user asks to open settings.
Future<bool?> _showNeedsCloudDialog(
  BuildContext context, {
  required String title,
  required String body,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (context) {
      return AlertDialog(
        backgroundColor: beeSurfaceRaised(context),
        surfaceTintColor: Colors.transparent,
        shape: beeDialogShape(),
        title: Text(
          title,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: beeText(context),
            height: 1.25,
          ),
        ),
        content: Text(
          body,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: beeTextSub(context),
            height: 1.45,
          ),
        ),
        actions: [
          TextButton(
            style: beeSecondaryButtonStyle(context),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: beePrimaryButtonStyle(context),
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              'Open Settings',
              style: GoogleFonts.inter(
                color: beeBlack(context),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
        ],
      );
    },
  );
}

class _PromptCloudSwitchDialog extends StatefulWidget {
  final SettingsService settings;
  final String title;
  final String intro;

  const _PromptCloudSwitchDialog({
    required this.settings,
    required this.title,
    required this.intro,
  });

  @override
  State<_PromptCloudSwitchDialog> createState() =>
      _PromptCloudSwitchDialogState();
}

class _PromptCloudSwitchDialogState extends State<_PromptCloudSwitchDialog> {
  // Selection order for keyboard navigation. Conservative option first: keep
  // transcribing locally and only send the transcript to the cloud.
  static const _order = [_SwitchMode.localTwoPass, _SwitchMode.cloud];

  _SwitchMode _mode = _SwitchMode.localTwoPass;
  bool _isWorking = false;

  void _moveSelection(int delta) {
    if (_isWorking) return;
    final current = _order.indexOf(_mode);
    final next = (current + delta).clamp(0, _order.length - 1);
    if (next != current) setState(() => _mode = _order[next]);
  }

  void _cancel() {
    if (_isWorking || !mounted) return;
    Navigator.pop(context, PromptCloudResult.cancelled);
  }

  /// Handles key events while the dialog lives in a focused window (the
  /// settings window). The Ctrl+M popup flow uses the inline
  /// ModeCloudConfirmPopup instead, so the modal only needs focused-window
  /// keyboard handling.
  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveSelection(-1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveSelection(1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _confirm();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _cancel();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Future<void> _confirm() async {
    if (_isWorking) return;
    setState(() => _isWorking = true);
    try {
      if (_mode == _SwitchMode.localTwoPass) {
        await widget.settings.enableLocalTwoPassRefinement();
      } else {
        await widget.settings.switchToCloudTranscription();
      }
      if (mounted) {
        Navigator.pop(
          context,
          _mode == _SwitchMode.localTwoPass
              ? PromptCloudResult.localTwoPass
              : PromptCloudResult.cloud,
        );
      }
    } catch (_) {
      if (mounted) setState(() => _isWorking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    // A plain Dialog (unlike AlertDialog) never probes intrinsic sizes, so
    // the native BeeChoiceGroup — which uses a LayoutBuilder — is safe to
    // embed here. Match the chrome of the app's other dialogs.
    final maxWidth = screenWidth - 24;
    final dialogWidth = maxWidth < 360 ? maxWidth : 360.0;

    return Focus(
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Dialog(
        backgroundColor: beeSurfaceRaised(context),
        surfaceTintColor: Colors.transparent,
        shape: beeDialogShape(),
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
        child: SizedBox(
          width: dialogWidth,
          // Mirror the app's native panel chrome (see ModeSelectionPopup):
          // a tinted, bottom-bordered header bar; a flat body whose option
          // tiles ([PromptCloudModeTile]) are the same widget the inline
          // popup uses; and a top-bordered keyboard hint footer.
          child: ClipRRect(
            borderRadius: BorderRadius.circular(kBeeRadiusLg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(context),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.intro,
                          style: GoogleFonts.inter(
                            fontSize: 12.5,
                            color: beeTextSub(context),
                            height: 1.45,
                          ),
                        ),
                        const BeeGroupLabel(label: 'Transcription Mode'),
                        for (
                          var i = 0;
                          i < kPromptCloudModeOptions.length;
                          i++
                        ) ...[
                          if (i > 0) const SizedBox(height: 8),
                          PromptCloudModeTile(
                            selected: _mode == _order[i],
                            icon: kPromptCloudModeOptions[i].icon,
                            title: kPromptCloudModeOptions[i].title,
                            description: kPromptCloudModeOptions[i].description,
                            detailIcon: kPromptCloudModeOptions[i].detailIcon,
                            detail: kPromptCloudModeOptions[i].detail,
                            enabled: !_isWorking,
                            onTap: () => setState(() => _mode = _order[i]),
                          ),
                        ],
                        const SizedBox(height: 18),
                        _buildActions(context),
                      ],
                    ),
                  ),
                ),
                _buildKeyHintBar(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Tinted, bottom-bordered header bar — the same chrome the mode-selection
  /// popup uses, so the dialog reads as a natural continuation of that flow.
  Widget _buildHeader(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 15, 18, 13),
      decoration: BoxDecoration(
        color: beeYellow(context).withValues(alpha: 0.05),
        border: Border(bottom: BorderSide(color: beeDivider(context))),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_rounded, size: 17, color: beeYellow(context)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              widget.title,
              style: GoogleFonts.spaceGrotesk(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: beeText(context),
                height: 1.2,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        TextButton(
          style: beeSecondaryButtonStyle(context),
          onPressed: _isWorking
              ? null
              : () => Navigator.pop(context, PromptCloudResult.cancelled),
          child: Text(
            'Cancel',
            style: GoogleFonts.inter(
              color: beeTextSub(context),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          style: beePrimaryButtonStyle(context),
          onPressed: _isWorking ? null : _confirm,
          child: Text(
            _isWorking ? 'Switching\u2026' : 'Switch',
            style: GoogleFonts.inter(
              color: beeBlack(context),
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ),
      ],
    );
  }

  /// Keyboard affordance bar — matches the mode-selection popup footer so the
  /// arrow-key flow reads as native and discoverable.
  Widget _buildKeyHintBar(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 9, 14, 11),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: beeDivider(context))),
      ),
      // Wrap (not Row) so the hints stay on one line when they fit and wrap
      // gracefully on narrower widths instead of overflowing.
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        runSpacing: 6,
        children: [
          _keyHint(context, 'Up/Down', 'navigate'),
          _keyHint(context, 'Enter', 'switch'),
          _keyHint(context, 'Esc', 'cancel'),
        ],
      ),
    );
  }

  Widget _keyHint(BuildContext context, String keys, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...renderKeycaps(keys),
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
