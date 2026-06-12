import 'package:beeamvo/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

Color _blendOn(Color foreground, Color background, double alpha) {
  return Color.alphaBlend(foreground.withValues(alpha: alpha), background);
}

void _expectTextContrast(String label, Color foreground, Color background) {
  expect(
    _contrastRatio(foreground, background),
    greaterThanOrEqualTo(4.5),
    reason: '$label must meet WCAG AA text contrast on light mode surfaces.',
  );
}

void _expectGraphicContrast(String label, Color foreground, Color background) {
  expect(
    _contrastRatio(foreground, background),
    greaterThanOrEqualTo(3.0),
    reason:
        '$label must meet WCAG non-text contrast for focus/selection indicators.',
  );
}

void main() {
  test('light theme foreground roles meet contrast on all app surfaces', () {
    final surfaces = <String, Color>{
      'chrome': AppTheme.chromeBlack,
      'surface': AppTheme.surface,
      'surfaceBase': AppTheme.surfaceBase,
      'surfaceContainerHigh': AppTheme.surfaceContainerHigh,
      'surfaceBright': AppTheme.surfaceBright,
    };

    final foregrounds = <String, Color>{
      'textPrimary': AppTheme.textPrimary,
      'textSecondary': AppTheme.textSecondary,
      'textTertiary': AppTheme.textTertiary,
      'amber': AppTheme.amber,
      'amberLight': AppTheme.amberLight,
      'success': AppTheme.success,
      'error': AppTheme.error,
      'info': AppTheme.info,
    };

    for (final surface in surfaces.entries) {
      for (final foreground in foregrounds.entries) {
        _expectTextContrast(
          '${foreground.key} on ${surface.key}',
          foreground.value,
          surface.value,
        );
      }
    }
  });

  test('filled accent states keep readable white foregrounds', () {
    final filledStates = <String, Color>{
      'amber': AppTheme.amber,
      'amberLight': AppTheme.amberLight,
      'amberDim': AppTheme.amberDim,
      'success': AppTheme.success,
      'error': AppTheme.error,
      'info': AppTheme.info,
    };

    for (final state in filledStates.entries) {
      _expectTextContrast(
        'white chrome foreground on ${state.key}',
        AppTheme.chromeBlack,
        state.value,
      );
    }
  });

  test(
    'translucent selection/focus borders do not wash out on light surfaces',
    () {
      final surfaces = <String, Color>{
        'chrome': AppTheme.chromeBlack,
        'surface': AppTheme.surface,
        'surfaceBase': AppTheme.surfaceBase,
        'surfaceContainerHigh': AppTheme.surfaceContainerHigh,
      };

      for (final surface in surfaces.entries) {
        _expectGraphicContrast(
          '65% amber selection border on ${surface.key}',
          _blendOn(AppTheme.amber, surface.value, 0.65),
          surface.value,
        );
        _expectGraphicContrast(
          '75% amber focus border on ${surface.key}',
          _blendOn(AppTheme.amber, surface.value, 0.75),
          surface.value,
        );
      }
    },
  );
}
