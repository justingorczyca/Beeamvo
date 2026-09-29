import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';
import '../settings/settings_shared.dart';

// ─── Re-export shared design tokens for convenience ─────────────────────
// These onboarding widgets resolve colours at runtime via the `bee*()`
// accessors (see settings_shared.dart) so they honour the user's light / dark
// theme instead of the legacy compile-time AppTheme colour constants.
// Radius tokens below are layout-only and intentionally left compile-time.

const double _kRadiusSm = AppTheme.radiusSm;
const double _kRadiusMd = AppTheme.radiusMd;
const double _kRadiusLg = AppTheme.radiusLg;
const double _kRadiusPill = AppTheme.radiusPill;

// ─── Step Navigation ────────────────────────────────────────────────────

class OnboardingNav extends InheritedWidget {
  final int stepNumber;
  final int totalSteps;
  final VoidCallback onBack;

  const OnboardingNav({
    super.key,
    required this.stepNumber,
    required this.totalSteps,
    required this.onBack,
    required super.child,
  });

  static OnboardingNav? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<OnboardingNav>();

  @override
  bool updateShouldNotify(OnboardingNav oldWidget) =>
      stepNumber != oldWidget.stepNumber ||
      totalSteps != oldWidget.totalSteps ||
      onBack != oldWidget.onBack;
}

class OnboardingStepScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget body;
  final String primaryLabel;
  final VoidCallback? onPrimary;
  final bool primaryLoading;
  final IconData? primaryIcon;
  final List<Widget> secondaryActions;

  const OnboardingStepScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.body,
    required this.primaryLabel,
    required this.onPrimary,
    this.primaryLoading = false,
    this.primaryIcon = Icons.arrow_forward_rounded,
    this.secondaryActions = const [],
  });

  @override
  Widget build(BuildContext context) {
    final nav = OnboardingNav.maybeOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(40, 32, 40, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (nav != null) ...[
                Text(
                  'STEP ${nav.stepNumber} OF ${nav.totalSteps}',
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: beeTextMuted(context),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Text(
                title,
                style: GoogleFonts.spaceGrotesk(
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.8,
                  color: beeText(context),
                ),
              ),
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Text(
                  subtitle,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: beeTextSub(context),
                    height: 1.4,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: SingleChildScrollView(
              child: Align(alignment: Alignment.topLeft, child: body),
            ),
          ),
        ),
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 40),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: beeDivider(context))),
          ),
          child: Row(
            children: [
              if (nav != null)
                OnboardingSecondaryButton(label: 'Back', onTap: nav.onBack),
              if (nav != null) const Spacer(),
              Flexible(
                child: FittedBox(
                  alignment: Alignment.centerRight,
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final (index, action)
                          in secondaryActions.indexed) ...[
                        if (index > 0) const SizedBox(width: 8),
                        action,
                      ],
                      if (secondaryActions.isNotEmpty) const SizedBox(width: 8),
                      OnboardingPrimaryButton(
                        label: primaryLabel,
                        icon: primaryIcon,
                        onTap: onPrimary,
                        isLoading: primaryLoading,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ─── Primary Button ─────────────────────────────────────────────────────

class OnboardingPrimaryButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool isLoading;
  final bool small;

  const OnboardingPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.isLoading = false,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null && !isLoading;
    return BeeInteractive(
      onTap: enabled ? onTap : null,
      semanticLabel: isLoading ? '$label (loading)' : label,
      builder: (context, focused) => Opacity(
        opacity: enabled || isLoading ? 1 : 0.4,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.all(focused ? 2 : 0),
          decoration: BoxDecoration(
            border: focused
                ? Border.all(
                    color: beeYellow(context).withValues(alpha: 0.35),
                    width: 2,
                  )
                : null,
            borderRadius: BorderRadius.circular(_kRadiusMd + 2),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            height: small ? 32 : 40,
            padding: EdgeInsets.symmetric(horizontal: small ? 12 : 20),
            decoration: BoxDecoration(
              color: focused
                  ? beeYellow(context).withValues(alpha: 0.86)
                  : beeYellow(context),
              borderRadius: BorderRadius.circular(_kRadiusMd),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: small ? 12 : 13,
                    fontWeight: FontWeight.w600,
                    color: beeBlack(context),
                  ),
                ),
                if (isLoading) ...[
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(beeBlack(context)),
                    ),
                  ),
                ] else if (icon != null) ...[
                  const SizedBox(width: 8),
                  Icon(icon, size: 16, color: beeBlack(context)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Secondary Button ───────────────────────────────────────────────────

class OnboardingSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final bool small;

  const OnboardingSecondaryButton({
    super.key,
    required this.label,
    this.onTap,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return BeeInteractive(
      onTap: onTap,
      semanticLabel: label,
      builder: (context, focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: small ? 32 : 40,
        padding: EdgeInsets.symmetric(horizontal: small ? 10 : 14),
        decoration: BoxDecoration(
          color: enabled && focused
              ? beeText(context).withValues(alpha: 0.05)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(_kRadiusMd),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: small ? 12 : 13,
            fontWeight: FontWeight.w500,
            color: enabled ? beeTextSub(context) : beeTextMuted(context),
          ),
        ),
      ),
    );
  }
}

// ─── Selection Tile ─────────────────────────────────────────────────────

class OnboardingOptionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String? badge;
  final bool selected;
  final bool vertical;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Widget? footer;

  const OnboardingOptionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.badge,
    this.selected = false,
    this.vertical = false,
    this.onTap,
    this.trailing,
    this.footer,
  });

  Widget _iconWell(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: selected ? beeYellow(context) : beeSurfaceHighest(context),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(
        icon,
        size: 18,
        color: selected ? beeBlack(context) : beeTextSub(context),
      ),
    );
  }

  Widget _title(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.inter(
              fontSize: vertical ? 14 : 14,
              fontWeight: FontWeight.w600,
              color: beeText(context),
            ),
          ),
        ),
        if (badge != null && !vertical) ...[
          const SizedBox(width: 8),
          _badge(context),
        ],
      ],
    );
  }

  Widget _badge(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: beeSurfaceHighest(context),
        borderRadius: BorderRadius.circular(_kRadiusPill),
      ),
      child: Text(
        badge!,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: beeTextSub(context),
        ),
      ),
    );
  }

  Widget _textContent(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _title(context),
        const SizedBox(height: 4),
        Text(
          description,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: beeTextMuted(context),
            height: 1.4,
          ),
        ),
        if (vertical && badge != null) ...[
          const SizedBox(height: 6),
          _badge(context),
        ],
        if (footer != null) ...[const SizedBox(height: 8), footer!],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final selection = trailing ?? BeeRadioIndicator(selected: selected);
    return Semantics(
      selected: selected,
      button: true,
      child: BeeInteractive(
        onTap: onTap,
        semanticLabel: title,
        selected: selected,
        toggled: selected,
        builder: (context, focused) {
          final borderColor = selected
              ? beeYellow(context)
              : focused
              ? beeTextMuted(context).withValues(alpha: 0.5)
              : beeBorder(context).withValues(alpha: 0.6);
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: selected
                  ? beeYellow(context).withValues(alpha: 0.035)
                  : beeSurfaceRaised(context),
              borderRadius: BorderRadius.circular(_kRadiusLg),
              border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
            ),
            child: vertical
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _iconWell(context),
                          const Spacer(),
                          selection,
                        ],
                      ),
                      const SizedBox(height: 12),
                      _textContent(context),
                    ],
                  )
                : Row(
                    children: [
                      _iconWell(context),
                      const SizedBox(width: 14),
                      Expanded(child: _textContent(context)),
                      const SizedBox(width: 14),
                      selection,
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class OnboardingKeycap extends StatelessWidget {
  final String label;
  final bool small;

  const OnboardingKeycap({super.key, required this.label, this.small = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minWidth: small ? 24 : 40),
      height: small ? 24 : 40,
      padding: EdgeInsets.symmetric(horizontal: small ? 6 : 12),
      decoration: BoxDecoration(
        color: beeSurface(context),
        borderRadius: BorderRadius.circular(_kRadiusSm),
        border: Border(
          top: BorderSide(color: beeBorder(context)),
          left: BorderSide(color: beeBorder(context)),
          right: BorderSide(color: beeBorder(context)),
          bottom: BorderSide(color: beeBorder(context), width: 2),
        ),
      ),
      child: Align(
        alignment: Alignment.center,
        widthFactor: 1,
        child: Text(
          label,
          style: GoogleFonts.spaceGrotesk(
            fontSize: small ? 11 : 16,
            fontWeight: FontWeight.w600,
            color: beeText(context),
          ),
        ),
      ),
    );
  }
}

// ─── Text Field ─────────────────────────────────────────────────────────

class OnboardingTextField extends StatefulWidget {
  final String hintText;
  final bool obscureText;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final Widget? suffixIcon;

  const OnboardingTextField({
    super.key,
    required this.hintText,
    this.obscureText = false,
    required this.controller,
    this.onChanged,
    this.suffixIcon,
  });

  @override
  State<OnboardingTextField> createState() => _OnboardingTextFieldState();
}

class _OnboardingTextFieldState extends State<OnboardingTextField> {
  late final FocusNode _focusNode = FocusNode()..addListener(_onFocusChange);

  void _onFocusChange() => setState(() {});

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocusChange)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      height: 44,
      decoration: BoxDecoration(
        color: beeSurfaceRaised(context),
        borderRadius: BorderRadius.circular(_kRadiusMd),
        border: Border.all(
          color: _focusNode.hasFocus ? beeYellow(context) : beeBorder(context),
          width: _focusNode.hasFocus ? 1.5 : 1,
        ),
      ),
      child: TextField(
        focusNode: _focusNode,
        controller: widget.controller,
        obscureText: widget.obscureText,
        onChanged: widget.onChanged,
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: beeText(context),
        ),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: GoogleFonts.inter(color: beeTextMuted(context)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 11,
          ),
          suffixIcon: widget.suffixIcon,
        ),
      ),
    );
  }
}

// ─── Status Badge ───────────────────────────────────────────────────────

class OnboardingStatusBadge extends StatelessWidget {
  final String label;
  final bool isError;
  final bool isSuccess;

  const OnboardingStatusBadge({
    super.key,
    required this.label,
    this.isError = false,
    this.isSuccess = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? beeError(context)
        : isSuccess
        ? beeSuccess(context)
        : beeTextMuted(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(_kRadiusSm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            isError
                ? Icons.error_outline_rounded
                : isSuccess
                ? Icons.check_circle_outline_rounded
                : Icons.info_outline_rounded,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
