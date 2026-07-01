import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/macos_permission_service.dart';
import '../settings/settings_shared.dart';

/// A guided, auto-detecting dialog for granting macOS Accessibility permission
/// — the single permission needed to auto-paste transcriptions.
///
/// Flow: intro → (tap "Enable Paste") → waiting (native prompt + live polling)
///       → granted (animated success).
///
/// Use [PermissionOnboardingDialog.show] which no-ops silently if the
/// permission is already granted (safe to call from any entry point).
class PermissionOnboardingDialog extends StatefulWidget {
  const PermissionOnboardingDialog({super.key});

  /// Pops up the dialog only when Accessibility is NOT yet granted.
  /// On non-macOS, or when already granted, this returns immediately.
  static Future<void> show(BuildContext context) async {
    if (!Platform.isMacOS) return;
    final granted = await MacOsPermissionService.isGranted();
    if (granted) return;
    if (!context.mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (_) => const PermissionOnboardingDialog(),
    );
  }

  @override
  State<PermissionOnboardingDialog> createState() =>
      _PermissionOnboardingDialogState();
}

enum _Step { intro, waiting, granted }

class _PermissionOnboardingDialogState extends State<PermissionOnboardingDialog>
    with SingleTickerProviderStateMixin {
  _Step _step = _Step.intro;
  Timer? _poll;

  late final AnimationController _checkController;

  @override
  void initState() {
    super.initState();
    _checkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );

    // In case the permission was actually granted between the isGranted() gate
    // in show() and the dialog building, verify immediately.
    WidgetsBinding.instance.addPostFrameCallback((_) => _verifyAndMaybePoll());
  }

  @override
  void dispose() {
    _poll?.cancel();
    _checkController.dispose();
    super.dispose();
  }

  Future<void> _verifyAndMaybePoll() async {
    final granted = await MacOsPermissionService.isGranted();
    if (!mounted) return;
    if (granted) {
      _onGranted();
    } else if (_step == _Step.waiting && _poll == null) {
      _startPolling();
    }
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(milliseconds: 1000), (_) async {
      final granted = await MacOsPermissionService.isGranted();
      if (!mounted) return;
      if (granted) _onGranted();
    });
  }

  void _onGranted() {
    _poll?.cancel();
    _poll = null;
    setState(() => _step = _Step.granted);
    _checkController.forward(from: 0);
  }

  Future<void> _onEnablePressed() async {
    // Fires the native one-click dialog that deep-links to Accessibility.
    await MacOsPermissionService.request();
    if (!mounted) return;
    setState(() => _step = _Step.waiting);
    _startPolling();
  }

  /// Clear a stale/"stuck" Accessibility toggle (e.g. left over from a prior
  /// ad-hoc build) and re-fire the native prompt. Used as the "auto-repair"
  /// fallback when granting normally doesn't take.
  Future<void> _onAutoRepair() async {
    setState(() => _step = _Step.waiting);
    _startPolling();
    await MacOsPermissionService.autoRepair();
    if (!mounted) return;
    final granted = await MacOsPermissionService.isGranted();
    if (mounted && granted) _onGranted();
  }

  Future<void> _openSystemSettings() async {
    await MacOsPermissionService.openSettings();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: beeSurfaceRaised(context),
      surfaceTintColor: Colors.transparent,
      shape: beeDialogShape(),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      contentPadding: EdgeInsets.zero,
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                child: _buildBody(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() {
    final bool success = _step == _Step.granted;
    final Color accent = success ? beeSuccess(context) : beeError(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 6),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  success
                      ? Icons.check_rounded
                      : Icons.content_paste_rounded,
                  size: 32,
                  color: accent,
                ),
                if (success)
                  ScaleTransition(
                    scale: Tween<double>(begin: 0.4, end: 1.0).animate(
                      CurvedAnimation(
                        parent: _checkController,
                        curve: Curves.elasticOut,
                      ),
                    ),
                    child: Icon(
                      Icons.check_rounded,
                      size: 32,
                      color: accent,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            success ? 'Paste is ready!' : 'Enable Automatic Pasting',
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: beeText(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            success
                ? 'Beeamvo can now paste transcriptions for you automatically.'
                : 'One quick permission and you’re done — no digging through Settings.',
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 13,
              height: 1.45,
              color: beeTextSub(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (_step) {
      case _Step.intro:
        return _IntroBody(
          onEnable: _onEnablePressed,
          onOpenSettings: _openSystemSettings,
          onAutoRepair: _onAutoRepair,
          onClose: () => Navigator.of(context).maybePop(),
        );
      case _Step.waiting:
        return _WaitingBody(
          onOpenSettings: _openSystemSettings,
          onAutoRepair: _onAutoRepair,
          onClose: () => Navigator.of(context).maybePop(),
        );
      case _Step.granted:
        return _GrantedBody(onClose: () => Navigator.of(context).pop());
    }
  }
}

// ── Intro ───────────────────────────────────────────────────────────────

class _IntroBody extends StatelessWidget {
  final Future<void> Function() onEnable;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onAutoRepair;
  final VoidCallback onClose;

  const _IntroBody({
    required this.onEnable,
    required this.onOpenSettings,
    required this.onAutoRepair,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StepTile(
          number: 1,
          text: 'Tap “Enable Paste” — macOS opens the right Settings screen.',
        ),
        _StepTile(
          number: 2,
          text: 'Find Beeamvo in the list and switch it ON.',
        ),
        _StepTile(
          number: 3,
          text: 'Come back here — it’s detected automatically.',
          isLast: true,
        ),
        const SizedBox(height: 18),
        ElevatedButton.icon(
          style: beePrimaryButtonStyle(context),
          onPressed: () => onEnable(),
          icon: const Icon(Icons.rocket_launch_rounded, size: 18),
          label: const Text('Enable Paste'),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              style: beeSecondaryButtonStyle(context),
              onPressed: () => onOpenSettings(),
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: const Text('Open Settings'),
            ),
            TextButton(
              style: beeSecondaryButtonStyle(context),
              onPressed: onClose,
              child: Text(
                'Not now',
                style: GoogleFonts.inter(color: beeTextMuted(context)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Stale-toggle escape hatch for developers: after a flutter clean /
        // rebuild the ad-hoc toggle can become "stuck". A scoped reset +
        // re-prompt repairs it without leaving the app.
        Center(
          child: TextButton.icon(
            style: beeSecondaryButtonStyle(context),
            onPressed: () => onAutoRepair(),
            icon: const Icon(Icons.auto_fix_high_rounded, size: 15),
            label: Text(
              'Toggle already ON but not working? Auto-repair',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: beeTextMuted(context),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ── Waiting ─────────────────────────────────────────────────────────────

class _WaitingBody extends StatelessWidget {
  final Future<void> Function() onOpenSettings;
  final Future<void> Function() onAutoRepair;
  final VoidCallback onClose;

  const _WaitingBody({
    required this.onOpenSettings,
    required this.onAutoRepair,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: beeYellow(context).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(kBeeRadiusSm),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: beeYellow(context),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Waiting… switch ON “Beeamvo” in System Settings, then this '
                  'closes by itself.',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.4,
                    color: beeText(context),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // If the toggle is already ON (stale from a rebuild) but still not
        // detected, this clears just this app's entry and re-prompts.
        Center(
          child: TextButton.icon(
            style: beeSecondaryButtonStyle(context),
            onPressed: () => onAutoRepair(),
            icon: const Icon(Icons.auto_fix_high_rounded, size: 15),
            label: Text(
              'Toggle already ON? Auto-repair',
              style: GoogleFonts.inter(
                fontSize: 12,
                color: beeTextMuted(context),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            TextButton.icon(
              style: beeSecondaryButtonStyle(context),
              onPressed: () => onOpenSettings(),
              icon: const Icon(Icons.open_in_new_rounded, size: 15),
              label: const Text('Open Settings'),
            ),
            TextButton(
              style: beeSecondaryButtonStyle(context),
              onPressed: onClose,
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(color: beeTextMuted(context)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Granted ─────────────────────────────────────────────────────────────

class _GrantedBody extends StatelessWidget {
  final VoidCallback onClose;
  const _GrantedBody({required this.onClose});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: beeSuccess(context).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(kBeeRadiusSm),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle_rounded,
                  size: 18, color: beeSuccess(context)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'All set — auto-paste is now enabled.',
                  style: GoogleFonts.inter(
                    fontSize: 12.5,
                    height: 1.4,
                    color: beeText(context),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          style: beePrimaryButtonStyle(context),
          onPressed: onClose,
          child: const Text('Done'),
        ),
      ],
    );
  }
}

// ── Shared step tile ────────────────────────────────────────────────────

class _StepTile extends StatelessWidget {
  final int number;
  final String text;
  final bool isLast;

  const _StepTile({required this.number, required this.text, this.isLast = false});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 20,
            height: 20,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(
              color: beeYellow(context).withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '$number',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: beeYellow(context),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                height: 1.4,
                color: beeText(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
