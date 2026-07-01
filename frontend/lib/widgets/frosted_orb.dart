import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:math' as math;
import '../main.dart';
import 'settings/settings_shared.dart';

class FrostedOrb extends StatefulWidget {
  final RecordingState state;
  final String? errorMessage;
  final bool canRetry;
  final VoidCallback? onRetry;
  final VoidCallback? onAdjustSettings;
  final Animation<double> glowAnimation; // Used for breathing/scaling
  final AnimationController rotationController; // Used for rotation time base

  const FrostedOrb({
    super.key,
    required this.state,
    this.errorMessage,
    this.canRetry = false,
    this.onRetry,
    this.onAdjustSettings,
    required this.glowAnimation,
    required this.rotationController,
  });

  @override
  State<FrostedOrb> createState() => _FrostedOrbState();
}

class _FrostedOrbState extends State<FrostedOrb> with TickerProviderStateMixin {
  late AnimationController _transitionController;
  late AnimationController _entranceController;

  @override
  void initState() {
    super.initState();
    _transitionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );
    // Play entrance animation on first appear
    _entranceController.forward();
  }

  @override
  void didUpdateWidget(covariant FrostedOrb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.state == RecordingState.success &&
        oldWidget.state != RecordingState.success) {
      _transitionController.forward(from: 0.0);
    } else if (widget.state != RecordingState.success &&
        _transitionController.value > 0) {
      _transitionController.reset();
    }
  }

  @override
  void dispose() {
    _transitionController.dispose();
    _entranceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Resolve theme-aware colors once per build, then thread them into
    // the CustomPainter. The orb floats on a transparent desktop window,
    // so it needs a real background tint in dark mode (otherwise the
    // old hardcoded `AppTheme.surfaceContainer` produced a glaring white
    // disk on a dark OS desktop).
    final Color orbSurface = beeSurfaceHighest(context);
    final Color orbBorder = beeBorder(context);
    final Color inkAccent = beeYellow(context);
    final Color iconColor = beeText(context);
    final Color errorColor = beeError(context);
    final Color shadowColor = beeText(context);

    // Determine size and immersion level based on state
    final bool isThinking = widget.state == RecordingState.processing;
    final bool isRecording = widget.state == RecordingState.recording;
    final double orbSize = isThinking ? 42 : 36;

    return AnimatedBuilder(
      animation: Listenable.merge([
        widget.glowAnimation,
        widget.rotationController,
        _transitionController,
        _entranceController,
      ]),
      builder: (context, child) {
        // Entrance: subtle fade + scale from 0.6 → 1.0
        final entranceCurve = Curves.easeOutCubic.transform(
          _entranceController.value,
        );
        return Opacity(
          opacity: entranceCurve,
          child: Transform.scale(
            scale: 0.6 + (0.4 * entranceCurve),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    // Outer Nebula Aura for Recording
                    if (isRecording)
                      CustomPaint(
                        size: const Size(120, 120),
                        painter: _UnifiedNebulaPainter(
                          animationValue: widget.rotationController.value,
                          pulseValue: widget.glowAnimation.value,
                          state: widget.state,
                          isAura: true,
                          transitionValue: 0.0,
                          inkAccent: inkAccent,
                          errorColor: errorColor,
                        ),
                      ),

                    // The Frosted Orb
                    // On macOS, skip BackdropFilter as it shows black on transparent windows
                    _buildOrb(
                      orbSize,
                      isThinking,
                      orbSurface: orbSurface,
                      orbBorder: orbBorder,
                      inkAccent: inkAccent,
                      iconColor: iconColor,
                      errorColor: errorColor,
                      shadowColor: shadowColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildOrb(
    double orbSize,
    bool isThinking, {
    required Color orbSurface,
    required Color orbBorder,
    required Color inkAccent,
    required Color iconColor,
    required Color errorColor,
    required Color shadowColor,
  }) {
    final orbContent = AnimatedContainer(
      duration: const Duration(milliseconds: 100),
      curve: Curves.easeOut,
      width: orbSize,
      height: orbSize,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        // Theme-aware frosted chrome. In light mode this is warm-white;
        // in dark mode the surface-highest graphite (`#2D2D2D`) so the
        // orb reads as a raised disk against any OS desktop background.
        color: orbSurface.withValues(
          alpha: Platform.isMacOS ? 0.92 : 0.82,
        ),
        border: Border.all(
          color: orbBorder.withValues(alpha: 0.80),
          width: 0.5,
        ),
        // Neutral graphite shadow for monochrome depth without a colored aura.
        // Uses the resolved text color so it darkens naturally in dark mode
        // rather than always being a black drop on a white disk.
        boxShadow: [
          BoxShadow(
            color: shadowColor.withValues(alpha: 0.18),
            blurRadius: 20,
            spreadRadius: 3,
          ),
        ],
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Internal Nebula Graphics
          CustomPaint(
            size: Size(orbSize, orbSize),
            painter: _UnifiedNebulaPainter(
              animationValue: widget.rotationController.value,
              pulseValue: widget.glowAnimation.value,
              state: widget.state,
              isAura: false,
              transitionValue: _transitionController.value,
              inkAccent: inkAccent,
              errorColor: errorColor,
            ),
          ),

          // Show icon only if not "deep thinking"
          if (!isThinking)
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 100),
              child: Icon(
                _getIcon(),
                key: ValueKey(widget.state),
                color: _getIconColor(
                  iconColor: iconColor,
                  inkAccent: inkAccent,
                  errorColor: errorColor,
                ),
                size: 16,
              ),
            ),
        ],
      ),
    );

    // On macOS, skip the BackdropFilter (causes black background on transparent windows)
    if (Platform.isMacOS) {
      return ClipOval(child: orbContent);
    }

    // On other platforms, use BackdropFilter for frosted glass effect
    return ClipOval(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: orbContent,
      ),
    );
  }

  IconData _getIcon() {
    switch (widget.state) {
      case RecordingState.recording:
        return Icons.mic_rounded;
      case RecordingState.success:
        return Icons.check_circle_outline_rounded;
      case RecordingState.error:
        return Icons.error_outline_rounded;
      default:
        return Icons.mic_none_rounded;
    }
  }

  Color _getIconColor({
    required Color iconColor,
    required Color inkAccent,
    required Color errorColor,
  }) {
    // Success uses the monochrome signal; error remains semantic red.
    if (widget.state == RecordingState.success) return inkAccent;
    if (widget.state == RecordingState.error) return errorColor;
    return iconColor;
  }
}

class _UnifiedNebulaPainter extends CustomPainter {
  final double animationValue; // 0.0 to 1.0 (rotation/time)
  final double pulseValue; // 0.0 to 1.0 (breathing)
  final double transitionValue; // 0.0 to 1.0 (for state transitions)
  final RecordingState state;
  final bool isAura;
  // Theme-aware colors passed in from the widget (CustomPainter has no
  // BuildContext of its own).
  final Color inkAccent;
  final Color errorColor;

  _UnifiedNebulaPainter({
    required this.animationValue,
    required this.pulseValue,
    required this.state,
    required this.isAura,
    required this.inkAccent,
    required this.errorColor,
    this.transitionValue = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;

    switch (state) {
      case RecordingState.recording:
        _paintNebulaFlow(canvas, center, maxRadius);
        break;
      case RecordingState.processing:
        _paintNebulaVortex(canvas, center, maxRadius);
        break;
      case RecordingState.success:
      case RecordingState.error:
        _paintNebulaCoalesce(canvas, center, maxRadius);
        break;
      default:
        break;
    }
  }

  void _paintNebulaFlow(Canvas canvas, Offset center, double radius) {
    // Slow, airy whisps
    final count = isAura ? 3 : 2;
    for (int i = 0; i < count; i++) {
      final whispPaint = Paint()
        ..shader = SweepGradient(
          colors: [
            inkAccent.withValues(alpha: 0.0),
            inkAccent.withValues(alpha: isAura ? 0.08 : 0.24),
            inkAccent.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
          // Perfect loop: multiplier must be integer
          transform: GradientRotation(animationValue * math.pi * 2 * (i + 1)),
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = isAura ? (10.0 + i * 5) : (2.0 + i)
        ..strokeCap = StrokeCap.round;

      final whispRadius = isAura
          ? (radius - 10 - i * 15)
          : (radius - 5 - i * 4);
      if (whispRadius > 0) {
        canvas.drawCircle(center, whispRadius, whispPaint);
      }
    }

    // Drifting particles
    if (!isAura) {
      _drawParticles(canvas, center, radius, 6, 0.5);
    }
  }

  void _paintNebulaVortex(Canvas canvas, Offset center, double radius) {
    if (isAura) {
      return; // Vortex is contained
    }

    // Dense, fast whisps
    for (int i = 0; i < 4; i++) {
      final whispPaint = Paint()
        ..shader = SweepGradient(
          colors: [
            inkAccent.withValues(alpha: 0.0),
            inkAccent.withValues(alpha: 0.34 - (i * 0.05)),
            inkAccent.withValues(alpha: 0.0),
          ],
          stops: const [0.0, 0.5, 1.0],
          // Perfect loop: multiplier must be integer
          transform: GradientRotation(animationValue * math.pi * 2 * (i + 2)),
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0 + i * 1.5
        ..strokeCap = StrokeCap.round;

      canvas.drawCircle(center, radius - 2 - (i * 4), whispPaint);
    }

    _drawParticles(canvas, center, radius, 16, 2.0);

    // Core Pulse
    final coreGlow = Paint()
      ..color = inkAccent.withValues(
        alpha: 0.12 + (math.sin(animationValue * math.pi * 4) * 0.05),
      )
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 10);
    canvas.drawCircle(center, 12, coreGlow);
  }

  void _paintNebulaCoalesce(Canvas canvas, Offset center, double radius) {
    if (isAura) {
      return;
    }

    // Success uses the monochrome ink for brand consistency.
    // Error keeps semantic red for critical feedback.
    final color = state == RecordingState.success ? inkAccent : errorColor;

    // Transition Logic for Success State
    double expansion = 1.0;
    double alphaMult = 1.0;

    if (state == RecordingState.success) {
      // EaseOutBack for a nice "pop" effect
      final curve = Curves.easeOutBack.transform(transitionValue);
      expansion = 0.5 + (curve * 0.5); // Start at 50% size, expand to 100%
      alphaMult = transitionValue; // Fade in during expansion
    }

    // Settling glow
    final settlePaint = Paint()
      ..color = color
          .withValues(alpha: 0.15 * alphaMult) // Increased base glow slightly
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 15);
    canvas.drawCircle(center, radius * 0.8 * expansion, settlePaint);

    // Dynamic Ring Shockwave (during transition)
    if (transitionValue > 0 &&
        transitionValue < 1.0 &&
        state == RecordingState.success) {
      final shockwavePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0 * (1.0 - transitionValue)
        ..color = color.withValues(
          alpha: 0.5 * (1.0 - transitionValue),
        ); // Fade out
      canvas.drawCircle(center, radius * transitionValue * 1.2, shockwavePaint);
    }

    _drawParticles(
      canvas,
      center,
      radius * expansion, // Particles expand with the glow
      8,
      0.2,
      color: color.withValues(alpha: 1.0 * alphaMult),
    );
  }

  void _drawParticles(
    Canvas canvas,
    Offset center,
    double maxRadius,
    int count,
    double speedMult, {
    Color? color,
  }) {
    final drawColor = color ?? inkAccent;
    final dotPaint = Paint()..color = drawColor.withValues(alpha: 0.5);

    for (int i = 0; i < count; i++) {
      // Logic for perfect loop:
      // Speed multiplier must be integer for the particle to return to start position
      final int integerSpeed = (speedMult * (i % 2 == 0 ? 1 : -1)).round();
      // Ensure it's never 0 to keep motion
      final travelSpeed = integerSpeed == 0
          ? (i % 2 == 0 ? 1 : -1)
          : integerSpeed;

      final radiusFactor = 0.2 + (i * 0.04);
      final angle = (animationValue * math.pi * 2 * travelSpeed) + (i * 1.5);
      final dist = maxRadius * radiusFactor;

      final particlePos = Offset(
        center.dx + math.cos(angle) * dist,
        center.dy + math.sin(angle) * dist,
      );

      final pulsate = 0.6 + (math.sin(animationValue * math.pi * 6 + i) * 0.4);
      canvas.drawCircle(particlePos, 0.8 * pulsate, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _UnifiedNebulaPainter oldDelegate) => true;
}
