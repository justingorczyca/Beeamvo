import 'package:flutter/material.dart';
import 'settings_shared.dart';

/// The sanctioned "data-showcase" bordered card tier — the **only** bordered
/// surface in the settings UI, reserved for the Home dashboard's charts,
/// activity heatmap, and achievement seals.
///
/// Everywhere else the surface stays deliberately flat (the "porcelain"
/// philosophy). This consolidates the near-identical bordered containers that
/// were previously hand-built in `home_dashboard_page`, `home_achievements_section`,
/// and `home_activity_heatmap` (each used `beeSurfaceHighest` + border at 0.5
/// opacity + `kBeeRadiusMd` + padding 14/16).
class BeeDataCard extends StatelessWidget {
  final Widget child;

  /// Inner padding. Defaults to 16 (the most common value across the three
  /// former call sites).
  final EdgeInsetsGeometry padding;

  const BeeDataCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: beeSurfaceHighest(context),
        borderRadius: BorderRadius.circular(kBeeRadiusMd),
        border: Border.all(
          color: beeBorder(context).withValues(alpha: 0.5),
        ),
      ),
      child: child,
    );
  }
}
