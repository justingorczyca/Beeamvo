import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'settings_shared.dart';

/// A single selectable choice exposed by a [BeeDropdown].
///
/// The generic [value] is what flows back to [BeeDropdown.onChanged]; the
/// [label] is what the user sees in both the trigger chip and the popup row.
/// An optional [icon] leads either when provided.
class BeeDropdownOption<T> {
  /// The underlying value this option represents.
  final T value;

  /// Human-readable text shown in the trigger and the popup list.
  final String label;

  /// Optional leading icon rendered next to the label in both places.
  final IconData? icon;

  const BeeDropdownOption({
    required this.value,
    required this.label,
    this.icon,
  });
}

/// A flat, BeeChip-style dropdown that opens a native [showMenu] popup.
///
/// Merges the two former bespoke implementations — `_buildRefinedDropdown`
/// (AI Models page) and `_OverrideDropdown` (Prompt Override panel) — into a
/// single generic, reusable control.
///
/// The trigger paints the current value's label in `beeTextSub` at 12px next
/// to a chevron-down affordance, with a subtle `kBeeTintHover` ink fill that
/// animates in on hover/focus (powered by [BeeInteractive]). Tapping it opens
/// a popup anchored just below the trigger; each option is a plain labeled
/// row and the currently-selected one carries a monochrome check.
///
/// The widget is generic over [T] so callers can bind it to enums, ids, or
/// any domain type without a parallel string-id mapping.
class BeeDropdown<T> extends StatelessWidget {
  /// The current selection. Compared against each option's
  /// [BeeDropdownOption.value] with `==` to resolve the displayed label and
  /// the popup's initial highlight.
  final T value;

  /// The full set of selectable choices, in display order.
  final List<BeeDropdownOption<T>> options;

  /// Invoked with the user's new selection. Skipped when the popup is
  /// dismissed or when the picked item is already the current [value].
  final ValueChanged<T> onChanged;

  /// Optional accessibility label for the trigger. Defaults to the current
  /// value's label (or `'Select'` when the value matches no option).
  final String? semanticLabel;

  /// Maximum width of the popup menu in logical pixels. Also caps the trigger
  /// chip width so long labels never overflow their host row. Defaults to
  /// 280 for the popup (the trigger itself never exceeds 240).
  final double? menuMaxWidth;

  const BeeDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.semanticLabel,
    this.menuMaxWidth,
  });

  /// Effective popup max width, clamped to a sensible range so an absurd
  /// caller value can never produce a menu wider than the window.
  double get _menuWidth {
    final w = menuMaxWidth ?? 280.0;
    if (w < 120.0) return 120.0;
    if (w > 600.0) return 600.0;
    return w;
  }

  /// Effective trigger max width — never wider than 240, and never wider than
  /// the popup so a compact [menuMaxWidth] shrinks the chip too.
  double get _triggerWidth {
    final menu = _menuWidth;
    return menu < 240.0 ? menu : 240.0;
  }

  BeeDropdownOption<T>? _optionForValue(T v) {
    for (final option in options) {
      if (option.value == v) return option;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final current = _optionForValue(value);
    final label = current?.label ?? '';
    final leadingIcon = current?.icon;
    final effectiveSemantic = semanticLabel ?? label;

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: _triggerWidth),
      child: BeeInteractive(
        onTap: options.isEmpty ? null : () => _openMenu(context),
        semanticLabel: effectiveSemantic.isEmpty ? 'Select' : effectiveSemantic,
        builder: (context, focused) {
          final text = beeText(context);
          return AnimatedContainer(
            duration: kBeeTransitionDuration,
            curve: kBeeTransitionCurve,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              // Flat BeeChip-style: transparent at rest, a 6% ink tint on
              // hover/focus. Monochrome — never an amber accent.
              color: focused
                  ? text.withValues(alpha: kBeeTintHover)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(kBeeRadiusXs),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (leadingIcon != null) ...[
                  Icon(leadingIcon, size: 12, color: beeTextSub(context)),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: beeTextSub(context),
                      height: 1.0,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Icon(
                  Icons.expand_more_rounded,
                  size: 14,
                  color: beeTextMuted(context),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openMenu(BuildContext context) async {
    if (options.isEmpty) return;

    // Resolve the popup chrome up front from the trigger's own context. The
    // menu mounts in the root overlay which inherits the same app theme, so
    // these resolve identically there.
    final baseColor = beeSurfaceHighest(context);
    final outline = beeBorder(context).withValues(alpha: kBeeChromeBorderAlpha);
    final maxW = _menuWidth;
    final minW = maxW < 176.0 ? maxW : 176.0;

    final selected = await showMenu<T>(
      context: context,
      elevation: 8,
      position: _menuPosition(context),
      color: baseColor,
      constraints: BoxConstraints(minWidth: minW, maxWidth: maxW),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kBeeRadiusSm),
        side: BorderSide(color: outline),
      ),
      initialValue: value,
      items: _buildItems(),
    );

    if (selected == null) return; // dismissed
    if (!context.mounted) return;
    if (selected == value) return; // no change
    onChanged(selected);
  }

  /// Build the flat, monochrome popup rows. Each row resolves its colors from
  /// the overlay's own context (via [Builder]) so light/dark theming is always
  /// correct regardless of where the menu is mounted.
  List<PopupMenuEntry<T>> _buildItems() {
    return options.map((option) {
      return PopupMenuItem<T>(
        value: option.value,
        height: 40,
        child: Builder(
          builder: (context) {
            final isSelected = option.value == value;
            final text = beeText(context);
            final textSub = beeTextSub(context);
            final icon = option.icon;
            return Row(
              children: [
                // Fixed-width leading slot so every label's left edge aligns,
                // whether or not the row is selected / has an icon.
                SizedBox(
                  width: 18,
                  child: isSelected
                      ? Icon(Icons.check_rounded, size: 14, color: text)
                      : const SizedBox.shrink(),
                ),
                if (icon != null) ...[
                  Icon(icon, size: 13, color: textSub),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    option.label,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? text : textSub,
                      height: 1.0,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      );
    }).toList();
  }

  /// Position the popup just below the trigger's left edge, reserving a safe
  /// margin on every side so it stays on screen near window edges. Mirrors the
  /// RenderBox-based anchoring used by the original page-level dropdowns.
  RelativeRect _menuPosition(BuildContext context) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      return RelativeRect.fill;
    }
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final size = box.size;
    final offset = box.localToGlobal(Offset.zero, ancestor: overlay);
    final overlayWidth = overlay.size.width;
    final overlayHeight = overlay.size.height;

    // Left-align the menu with the trigger, giving it up to [_menuWidth] of
    // room before it would clip the right edge of the overlay.
    final desiredWidth = _menuWidth;
    final left = offset.dx < 0.0 ? 0.0 : offset.dx;
    final rightRaw = overlayWidth - left - desiredWidth;
    final right = rightRaw < 0.0 ? 0.0 : rightRaw;
    final top = offset.dy + size.height + 4.0;
    final bottomRaw = overlayHeight - top - 8.0;
    final bottom = bottomRaw < 0.0 ? 0.0 : bottomRaw;

    return RelativeRect.fromLTRB(left, top, right, bottom);
  }
}
