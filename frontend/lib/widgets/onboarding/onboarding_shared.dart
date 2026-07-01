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

// ─── Step Shell ──────────────────────────────────────────────────────────

/// Consistent layout wrapper for every onboarding step.
class OnboardingStepShell extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Widget child;
  final double iconSize;

  const OnboardingStepShell({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.child,
    this.iconSize = 32,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          // Icon container — compact
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: beeYellow(context).withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(_kRadiusMd),
              border: Border.all(color: beeYellow(context).withValues(alpha: 0.22)),
            ),
            child: Center(
              child: Icon(icon, size: iconSize * 0.72, color: beeYellow(context)),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: beeText(context),
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: beeTextSub(context),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Flexible(child: child),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

// ─── Animated Background ────────────────────────────────────────────────

/// Subtle animated amber-glow background used behind the onboarding wizard.
class OnboardingBackground extends StatefulWidget {
  final Widget child;
  const OnboardingBackground({super.key, required this.child});

  @override
  State<OnboardingBackground> createState() => _OnboardingBackgroundState();
}

class _OnboardingBackgroundState extends State<OnboardingBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 8),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        return Container(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.0 + 0.3 * (t - 0.5), -0.6 + 0.2 * (t - 0.5)),
              radius: 1.2,
              colors: [
                beeYellow(context).withValues(alpha: 0.04 + 0.02 * t),
                beeSurface(context).withValues(alpha: 0.0),
              ],
              stops: const [0.0, 0.7],
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

// ─── Primary Button ─────────────────────────────────────────────────────

class OnboardingPrimaryButton extends StatefulWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool isLoading;

  const OnboardingPrimaryButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.isLoading = false,
  });

  @override
  State<OnboardingPrimaryButton> createState() =>
      _OnboardingPrimaryButtonState();
}

class _OnboardingPrimaryButtonState extends State<OnboardingPrimaryButton> {
  @override
  Widget build(BuildContext context) {
    final accent = beeYellow(context);
    return GestureDetector(
      onTap: widget.isLoading ? null : widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [accent, beeYellowDim(context)],
          ),
          borderRadius: BorderRadius.circular(_kRadiusMd),
          boxShadow: [
            BoxShadow(
              color: accent.withValues(alpha: 0.15),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.icon != null) ...[
              Icon(widget.icon, size: 18, color: Colors.white),
              const SizedBox(width: 8),
            ],
            if (widget.isLoading)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: const AlwaysStoppedAnimation(Colors.white),
                ),
              )
            else
              Text(
                widget.label,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

      // ─── Secondary Button ───────────────────────────────────────────────────

class OnboardingSecondaryButton extends StatefulWidget {
  final String label;
  final VoidCallback? onTap;

  const OnboardingSecondaryButton({super.key, required this.label, this.onTap});

  @override
  State<OnboardingSecondaryButton> createState() =>
      _OnboardingSecondaryButtonState();
}

class _OnboardingSecondaryButtonState extends State<OnboardingSecondaryButton> {
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(_kRadiusMd),
        ),
        child: Text(
          widget.label,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: beeTextMuted(context),
          ),
        ),
      ),
    );
  }
}

// ─── Progress Bar ───────────────────────────────────────────────────────

class OnboardingProgress extends StatelessWidget {
  final int currentStep;
  final int totalSteps;

  const OnboardingProgress({
    super.key,
    required this.currentStep,
    required this.totalSteps,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Row(
        children: List.generate(totalSteps, (i) {
          final isActive = i == currentStep;
          final isCompleted = i < currentStep;
          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: 3,
                decoration: BoxDecoration(
                  color: isCompleted
                      ? beeYellow(context)
                      : isActive
                      ? beeYellow(context).withValues(alpha: 0.75)
                      : beeSurfaceHighest(context),
                  borderRadius: BorderRadius.circular(_kRadiusPill),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

// ─── Glow Card ──────────────────────────────────────────────────────────

class OnboardingGlowCard extends StatelessWidget {
  final Widget child;
  final Color? accentColor;
  final bool isSelected;
  final VoidCallback? onTap;

  const OnboardingGlowCard({
    super.key,
    required this.child,
    this.accentColor,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? beeYellow(context);
    return MouseRegion(
      cursor: onTap != null
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected
                ? accent.withValues(alpha: 0.08)
                : beeSurfaceRaised(context),
            borderRadius: BorderRadius.circular(_kRadiusLg),
            border: Border.all(
              color: isSelected
                  ? accent.withValues(alpha: 0.50)
                  : beeBorder(context).withValues(alpha: 0.6),
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: accent.withValues(alpha: 0.08),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ]
                : [],
          ),
          child: child,
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
  @override
  Widget build(BuildContext context) {
    return Focus(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: beeSurfaceHighest(context),
          borderRadius: BorderRadius.circular(_kRadiusMd),
          border: Border.all(color: beeBorder(context)),
          boxShadow: null,
        ),
        child: TextField(
          controller: widget.controller,
          obscureText: widget.obscureText,
          onChanged: widget.onChanged,
          style: GoogleFonts.inter(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: beeText(context),
          ),
          decoration: InputDecoration(
            hintText: widget.hintText,
            hintStyle: GoogleFonts.inter(color: beeTextMuted(context)),
            border: InputBorder.none,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 14,
            ),
            suffixIcon: widget.suffixIcon,
          ),
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
        border: Border.all(color: color.withValues(alpha: 0.25)),
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
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
