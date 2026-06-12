import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../theme/app_theme.dart';

// ─── Bee Color Tokens ─────────────────────────────────────────────
//
// Two layers:
//  1) `const Color kBee*` — compile-time light-mode defaults. Kept for
//     backwards compatibility so any call site that has not been migrated
//     still compiles and renders identically to the pre-dark-mode app.
//  2) Runtime accessors (`beeColors`, `beeText`, ...) that resolve the
//     active [BeeColors] theme extension via [BuildContext]. Use these
//     inside `build()` to pick up light / dark automatically.
const Color kBeeYellow = AppTheme.amber;
const Color kBeeYellowDim = AppTheme.amberDim;
const Color kBeeBlack = AppTheme.chromeBlack;
const Color kBeeSurface = AppTheme.surfaceBase;
const Color kBeeSurfaceRaised = AppTheme.surfaceRaised;
const Color kBeeSurfaceHighest = AppTheme.surfaceContainer;
const Color kBeeText = AppTheme.textPrimary;
const Color kBeeTextSub = AppTheme.textSecondary;
const Color kBeeTextMuted = AppTheme.textTertiary;
const Color kBeeBorder = AppTheme.border;
const Color kBeeDivider = AppTheme.divider;
const Color kBeeSidebar = AppTheme.surfaceContainerHigh;
const Color kBeeSuccess = AppTheme.success;
const Color kBeeError = AppTheme.error;

const double kBeeRadiusXs = AppTheme.radiusXs;
const double kBeeRadiusSm = AppTheme.radiusSm;
const double kBeeRadiusMd = AppTheme.radiusMd;
const double kBeeRadiusLg = AppTheme.radiusLg;
const double kBeeRadiusXl = AppTheme.radiusXl;
const double kBeeRadiusPill = AppTheme.radiusPill;

const double kBeeSpace4 = AppTheme.space4;
const double kBeeSpace8 = AppTheme.space8;
const double kBeeSpace12 = AppTheme.space12;
const double kBeeSpace16 = AppTheme.space16;
const double kBeeSpace24 = AppTheme.space24;
const double kBeeSpace32 = AppTheme.space32;

const Duration kBeeTransitionDuration = Duration(milliseconds: 140);
const Curve kBeeTransitionCurve = Curves.easeOutCubic;

/// Runtime-resolved colors from the active [ThemeData]. Use this inside any
/// builder that has a [BuildContext] to pick up the light or dark variant
/// automatically.
BeeColors beeColors(BuildContext context) =>
    Theme.of(context).extension<BeeColors>()!;

// ── Per-token runtime accessors (for mechanical `kBeeFoo` → `beeFoo(c)`
//    migration). Every primitive in this file should prefer these.
Color beeYellow(BuildContext c) => beeColors(c).yellow;
Color beeYellowDim(BuildContext c) => beeColors(c).yellowDim;
Color beeBlack(BuildContext c) => beeColors(c).black;
Color beeSurface(BuildContext c) => beeColors(c).surface;
Color beeSurfaceRaised(BuildContext c) => beeColors(c).surfaceRaised;
Color beeSurfaceHighest(BuildContext c) => beeColors(c).surfaceHighest;
Color beeSidebar(BuildContext c) => beeColors(c).sidebar;
Color beeText(BuildContext c) => beeColors(c).text;
Color beeTextSub(BuildContext c) => beeColors(c).textSub;
Color beeTextMuted(BuildContext c) => beeColors(c).textMuted;
Color beeBorder(BuildContext c) => beeColors(c).border;
Color beeDivider(BuildContext c) => beeColors(c).divider;
Color beeSuccess(BuildContext c) => beeColors(c).success;
Color beeError(BuildContext c) => beeColors(c).error;

BoxDecoration beePanelDecoration({
  Color? color,
  double radius = kBeeRadiusLg,
  Color? borderColor,
  double borderOpacity = 1,
  List<BoxShadow>? shadows,
}) {
  return AppTheme.panelDecoration(
    color: color ?? kBeeBlack,
    radius: radius,
    outlineColor: borderColor ?? kBeeBorder,
    outlineOpacity: borderOpacity,
    shadows: shadows,
  );
}

RoundedRectangleBorder beeDialogShape([double radius = kBeeRadiusLg]) {
  return AppTheme.roundedShape(
    radius,
    sideColor: kBeeBorder.withValues(alpha: 0.65),
  );
}

/// Primary button style — the brand "engaged" button (graphite pill in
/// light mode, warm-white pill in dark mode). Background and foreground
/// resolve at runtime via the current theme so the button always has
/// proper contrast against the surrounding surface.
///
/// [context] must be the build context where the button will be
/// rendered, so the theme extension lookup matches the surrounding
/// tree (i.e. inside the same Overlay as the button).
ButtonStyle beePrimaryButtonStyle(
  BuildContext context, {
  Color? backgroundColor,
  Color? foregroundColor,
}) {
  final bg = backgroundColor ?? beeYellow(context);
  final fg = foregroundColor ?? beeBlack(context);
  return ElevatedButton.styleFrom(
    backgroundColor: bg,
    foregroundColor: fg,
    shape: AppTheme.roundedShape(kBeeRadiusMd),
  ).copyWith(
    overlayColor: const WidgetStatePropertyAll(Colors.transparent),
    // Keep the icon label color crisp against the accent background.
    iconColor: WidgetStatePropertyAll(fg),
  );
}

/// Secondary button style — the ghost-text-style "cancel" button.
/// Foreground resolves to the runtime sub-text color so the button
/// reads clearly on both light and dark surfaces.
ButtonStyle beeSecondaryButtonStyle(
  BuildContext context, {
  Color? foregroundColor,
}) {
  final fg = foregroundColor ?? beeTextSub(context);
  return TextButton.styleFrom(
    foregroundColor: fg,
    shape: AppTheme.roundedShape(kBeeRadiusMd),
  ).copyWith(overlayColor: const WidgetStatePropertyAll(Colors.transparent));
}

/// Builder that receives an "active" state (hover or keyboard focus).
///
/// On desktop, every interactive element provides visual feedback when
/// the pointer hovers over it, matching native platform conventions.
typedef BeeInteractiveBuilder =
    Widget Function(BuildContext context, bool focused);

class BeeInteractive extends StatefulWidget {
  final VoidCallback? onTap;
  final BeeInteractiveBuilder builder;
  final String? semanticLabel;
  final String? tooltip;
  final bool selected;
  final bool? toggled;

  const BeeInteractive({
    super.key,
    required this.builder,
    this.onTap,
    this.semanticLabel,
    this.tooltip,
    this.selected = false,
    this.toggled,
  });

  @override
  State<BeeInteractive> createState() => _BeeInteractiveState();
}

class _BeeInteractiveState extends State<BeeInteractive> {
  bool _isHovered = false;
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    // Desktop-native: highlight on hover OR keyboard focus.
    final active = _isHovered || _isFocused;
    final child = widget.builder(context, active);

    if (!enabled) {
      final passive = Semantics(
        label: widget.semanticLabel,
        selected: widget.selected,
        toggled: widget.toggled,
        child: child,
      );

      if (widget.tooltip == null || widget.tooltip!.trim().isEmpty) {
        return passive;
      }

      return Tooltip(message: widget.tooltip!, child: passive);
    }

    // ── Interactive: Focus + hover + cursor + keyboard shortcuts ──
    final interactive = Semantics(
      label: widget.semanticLabel,
      button: true,
      selected: widget.selected,
      toggled: widget.toggled,
      enabled: true,
      onTap: widget.onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _isHovered = true),
        onExit: (_) => setState(() => _isHovered = false),
        child: Focus(
          onFocusChange: (focused) => setState(() => _isFocused = focused),
          child: Shortcuts(
            shortcuts: const <ShortcutActivator, Intent>{
              SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
              SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
            },
            child: Actions(
              actions: <Type, Action<Intent>>{
                ActivateIntent: CallbackAction<ActivateIntent>(
                  onInvoke: (_) {
                    widget.onTap?.call();
                    return null;
                  },
                ),
              },
              child: GestureDetector(
                excludeFromSemantics: true,
                behavior: HitTestBehavior.opaque,
                onTap: widget.onTap,
                child: child,
              ),
            ),
          ),
        ),
      ),
    );

    if (widget.tooltip == null || widget.tooltip!.trim().isEmpty) {
      return interactive;
    }

    return Tooltip(message: widget.tooltip!, child: interactive);
  }
}

class BeeActionChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final Color? color;
  final EdgeInsetsGeometry padding;
  final String? tooltip;
  final String? semanticLabel;

  const BeeActionChip({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.color,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    this.tooltip,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final accessibleName =
        semanticLabel ?? (label.isEmpty ? tooltip ?? 'Action' : label);
    // Native macOS-style action chip: flat text + optional icon, no border,
    // tiny 6% ink tint on hover. Default color is muted text (links/actions).
    final effectiveColor = color ?? beeTextSub(context);
    return BeeInteractive(
      onTap: onTap,
      semanticLabel: accessibleName,
      tooltip: tooltip,
      builder: (context, focused) => AnimatedContainer(
        duration: kBeeTransitionDuration,
        curve: kBeeTransitionCurve,
        padding: padding,
        decoration: BoxDecoration(
          color: focused && onTap != null
              ? beeText(context).withValues(alpha: 0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(kBeeRadiusXs),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 0.5),
                child: Icon(icon, size: 12, color: effectiveColor),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: effectiveColor,
                height: 1.0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Section Group Label ──────────────────────────────────────────
class BeeGroupLabel extends StatelessWidget {
  final String label;
  const BeeGroupLabel({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 14, 0, 6),
      child: Text(
        label.toUpperCase(),
        overflow: TextOverflow.ellipsis,
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: beeTextSub(context),
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

// ─── Flat Settings Row ────────────────────────────────────────────
class BeeSettingsRow extends StatefulWidget {
  final IconData? icon;
  final String label;
  final String? description;
  final Widget? trailing;
  final Widget? warningBadge;
  final VoidCallback? onTap;
  final bool showDivider;
  final bool enabled;

  const BeeSettingsRow({
    super.key,
    this.icon,
    required this.label,
    this.description,
    this.trailing,
    this.warningBadge,
    this.onTap,
    this.showDivider = true,
    this.enabled = true,
  });

  @override
  State<BeeSettingsRow> createState() => _BeeSettingsRowState();
}

class _BeeSettingsRowState extends State<BeeSettingsRow> {
  @override
  Widget build(BuildContext context) {
    // When the row is disabled, dim label + description + icon, and
    // drop the hover/interactivity of the outer wrapper. Children
    // (trailing widget) are responsible for their own disabled state.
    final text = beeText(context);
    final textSub = beeTextSub(context);
    final textMuted = beeTextMuted(context);
    final labelColor = widget.enabled ? text : textMuted;
    final descColor = widget.enabled ? textSub : textMuted;
    final iconColor = widget.enabled ? textMuted : textMuted;
    return BeeInteractive(
      onTap: widget.enabled ? widget.onTap : null,
      semanticLabel: widget.label,
      builder: (context, focused) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon!, size: 15, color: iconColor),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              widget.label,
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: labelColor,
                              ),
                            ),
                          ),
                          if (widget.warningBadge != null) ...[
                            const SizedBox(width: 8),
                            widget.warningBadge!,
                          ],
                        ],
                      ),
                      if (widget.description != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          widget.description!,
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: descColor,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (widget.trailing != null) ...[
                  const SizedBox(width: 12),
                  widget.trailing!,
                ],
              ],
            ),
          ),
          if (widget.showDivider)
            Container(
              height: 1,
              color: beeDivider(context).withValues(alpha: 0.55),
            ),
        ],
      ),
    );
  }
}

// ─── Bee Toggle (macOS-style solid pill) ──────────────────────────
class BeeToggle extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;
  final String? semanticLabel;

  const BeeToggle({
    super.key,
    required this.value,
    required this.onChanged,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final accent = beeYellow(context);
    final muted = beeTextMuted(context);
    // The thumb stays white in both modes — same as macOS — so it remains
    // high-contrast against the colored track when on, and against the
    // dimmed track when off.
    return BeeInteractive(
      semanticLabel: semanticLabel ?? (value ? 'On' : 'Off'),
      toggled: value,
      onTap: () => onChanged(!value),
      builder: (context, focused) => AnimatedContainer(
        duration: kBeeTransitionDuration,
        curve: kBeeTransitionCurve,
        width: 32,
        height: 19,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(kBeeRadiusPill),
          // Solid macOS-style: opaque when on (accent), gray when off.
          // Hover nudges the off-track slightly lighter so it affords tap.
          color: value
              ? accent
              : (focused
                    ? muted.withValues(alpha: 0.55)
                    : muted.withValues(alpha: 0.35)),
        ),
        child: AnimatedAlign(
          duration: kBeeTransitionDuration,
          curve: kBeeTransitionCurve,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 15,
            height: 15,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Segment Control (macOS-style flat segmented pill) ────────────
class BeeSegmented<T> extends StatelessWidget {
  final T value;
  final List<({T val, String label, IconData? icon})> options;
  final ValueChanged<T> onChanged;
  final bool enabled;

  const BeeSegmented({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final text = beeText(context);
    final textSub = beeTextSub(context);
    final textMuted = beeTextMuted(context);
    // When disabled, the selected highlight fades and the label color
    // drops to muted — the control is still visible (user can see the
    // current value) but reads as inert.
    final selLabelColor = enabled ? text : textMuted;
    final idleLabelColor = enabled ? textSub : textMuted;
    return LayoutBuilder(
      builder: (context, constraints) {
        final bounded = constraints.hasBoundedWidth;

        Widget option(({T val, String label, IconData? icon}) o) {
          final sel = o.val == value;
          final child = BeeInteractive(
            onTap: enabled ? () => onChanged(o.val) : null,
            semanticLabel: o.label,
            selected: sel,
            builder: (context, focused) => AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              curve: kBeeTransitionCurve,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                // Selection = solid subtle ink fill, no border. Hover = slight
                // ink tint. Idle = transparent. When disabled the selection
                // fill drops to a much fainter tint so it doesn't read as
                // "actively selected".
                color: sel
                    ? text.withValues(alpha: enabled ? 0.10 : 0.05)
                    : (focused && enabled)
                    ? text.withValues(alpha: 0.05)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(kBeeRadiusXs),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (o.icon != null) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 0.5),
                      child: Icon(
                        o.icon!,
                        size: 13,
                        color: sel ? selLabelColor : idleLabelColor,
                      ),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (bounded)
                    Flexible(
                      child: Text(
                        o.label,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                          color: sel ? selLabelColor : idleLabelColor,
                          height: 1.0,
                        ),
                      ),
                    )
                  else
                    Text(
                      o.label,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                        color: sel ? selLabelColor : idleLabelColor,
                        height: 1.0,
                      ),
                    ),
                ],
              ),
            ),
          );
          return bounded ? Expanded(child: child) : child;
        }

        // Flat row of options with thin dividers between them — no outer
        // bordered container, no tinted background. When disabled the
        // container tint drops to a barely-visible alpha so the whole
        // control recedes from the user's attention.
        return Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: text.withValues(alpha: enabled ? 0.05 : 0.03),
            borderRadius: BorderRadius.circular(kBeeRadiusSm),
          ),
          child: Row(
            mainAxisSize: bounded ? MainAxisSize.max : MainAxisSize.min,
            children: options.map(option).toList(),
          ),
        );
      },
    );
  }
}

class BeeChoiceOption<T> {
  final T value;
  final String title;
  final String description;
  final IconData icon;
  final String? detail;
  final String? badge;

  const BeeChoiceOption({
    required this.value,
    required this.title,
    required this.description,
    required this.icon,
    this.detail,
    this.badge,
  });
}

/// Desktop-native selector for important binary or small-set preferences.
///
/// This intentionally behaves more like a macOS/Windows settings list than a
/// marketing card grid: compact rows, one shared border, strong text hierarchy,
/// and a quiet but unmistakable selected state.
class BeeChoiceGroup<T> extends StatelessWidget {
  final T value;
  final List<BeeChoiceOption<T>> options;
  final ValueChanged<T> onChanged;

  const BeeChoiceGroup({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final text = beeText(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final useHorizontalLayout =
            options.length == 2 && constraints.maxWidth >= 560;

        // Flat group with thin dividers between rows — no outer bordered
        // card, just an ink-tinted background to separate from the page.
        return Container(
          decoration: BoxDecoration(
            color: text.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(kBeeRadiusSm),
          ),
          child: useHorizontalLayout
              ? IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < options.length; i++) ...[
                        if (i > 0)
                          VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: beeDivider(context),
                          ),
                        Expanded(
                          child: _BeeChoiceRow<T>(
                            option: options[i],
                            selected: options[i].value == value,
                            onTap: () => onChanged(options[i].value),
                            horizontal: true,
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              : Column(
                  children: [
                    for (var i = 0; i < options.length; i++) ...[
                      if (i > 0) Divider(height: 1, color: beeDivider(context)),
                      _BeeChoiceRow<T>(
                        option: options[i],
                        selected: options[i].value == value,
                        onTap: () => onChanged(options[i].value),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}

class _BeeChoiceRow<T> extends StatelessWidget {
  final BeeChoiceOption<T> option;
  final bool selected;
  final VoidCallback onTap;
  final bool horizontal;

  const _BeeChoiceRow({
    required this.option,
    required this.selected,
    required this.onTap,
    this.horizontal = false,
  });

  @override
  Widget build(BuildContext context) {
    final text = beeText(context);
    final accent = beeYellow(context);
    return BeeInteractive(
      onTap: onTap,
      semanticLabel: option.title,
      selected: selected,
      toggled: selected,
      builder: (context, focused) {
        final selectionColor = selected
            ? text.withValues(alpha: 0.035)
            : Colors.transparent;
        final focusOutline = focused ? accent.withValues(alpha: 0.45) : null;

        return AnimatedContainer(
          duration: kBeeTransitionDuration,
          curve: kBeeTransitionCurve,
          decoration: BoxDecoration(
            color: selectionColor,
            border: focusOutline == null
                ? null
                : Border.all(color: focusOutline),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedContainer(
                  duration: kBeeTransitionDuration,
                  width: 3,
                  color: selected ? text : Colors.transparent,
                ),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      horizontal ? 13 : 14,
                      horizontal ? 11 : 12,
                      horizontal ? 12 : 14,
                      horizontal ? 11 : 12,
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _BeeChoiceIcon(icon: option.icon, selected: selected),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _BeeChoiceText(
                            option: option,
                            selected: selected,
                            compact: horizontal,
                          ),
                        ),
                        const SizedBox(width: 12),
                        _BeeChoiceRadio(selected: selected),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BeeChoiceIcon extends StatelessWidget {
  final IconData icon;
  final bool selected;

  const _BeeChoiceIcon({required this.icon, required this.selected});

  @override
  Widget build(BuildContext context) {
    final text = beeText(context);
    return AnimatedContainer(
      duration: kBeeTransitionDuration,
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: selected ? text : beeSurfaceRaised(context),
        borderRadius: BorderRadius.circular(kBeeRadiusSm),
        border: Border.all(color: selected ? text : beeDivider(context)),
      ),
      child: Icon(
        icon,
        size: 14,
        color: selected ? beeBlack(context) : beeTextSub(context),
      ),
    );
  }
}

class _BeeChoiceText<T> extends StatelessWidget {
  final BeeChoiceOption<T> option;
  final bool selected;
  final bool compact;

  const _BeeChoiceText({
    required this.option,
    required this.selected,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final detail = option.detail?.trim();
    final secondary = detail == null || detail.isEmpty
        ? option.description
        : '${option.description} $detail';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                option.title,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: beeText(context),
                  letterSpacing: -0.1,
                ),
              ),
            ),
            if (!compact && option.badge != null) ...[
              const SizedBox(width: 8),
              _BeeChoiceBadge(label: option.badge!, selected: selected),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Text(
          secondary,
          maxLines: compact ? 3 : 2,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: beeTextSub(context),
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _BeeChoiceRadio extends StatelessWidget {
  final bool selected;

  const _BeeChoiceRadio({required this.selected});

  @override
  Widget build(BuildContext context) {
    final text = beeText(context);
    return AnimatedContainer(
      duration: kBeeTransitionDuration,
      width: 17,
      height: 17,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: selected ? text : Colors.transparent,
        border: Border.all(
          color: selected ? text : beeBorder(context),
          width: selected ? 1 : 1.2,
        ),
      ),
      child: selected
          ? Icon(Icons.check_rounded, size: 12, color: beeBlack(context))
          : null,
    );
  }
}

class _BeeChoiceBadge extends StatelessWidget {
  final String label;
  final bool selected;

  const _BeeChoiceBadge({required this.label, required this.selected});

  @override
  Widget build(BuildContext context) {
    final text = beeText(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: selected ? text : beeSurfaceRaised(context),
        borderRadius: BorderRadius.circular(kBeeRadiusXs),
        border: Border.all(color: selected ? text : beeDivider(context)),
      ),
      child: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: selected ? beeBlack(context) : beeTextMuted(context),
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ─── Clickable Value Chip (trailing display chip — flat text style) ─
class BeeChip extends StatefulWidget {
  final Widget displayValue;
  final VoidCallback onTap;
  final bool isLoading;

  const BeeChip({
    super.key,
    required this.displayValue,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  State<BeeChip> createState() => _BeeChipState();
}

class _BeeChipState extends State<BeeChip> {
  @override
  Widget build(BuildContext context) {
    return BeeInteractive(
      onTap: widget.onTap,
      semanticLabel: 'Change',
      builder: (context, focused) => AnimatedContainer(
        duration: kBeeTransitionDuration,
        curve: kBeeTransitionCurve,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: focused
              ? beeText(context).withValues(alpha: 0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(kBeeRadiusXs),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(fit: FlexFit.loose, child: widget.displayValue),
            const SizedBox(width: 6),
            if (widget.isLoading)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  valueColor: AlwaysStoppedAnimation(beeTextSub(context)),
                ),
              )
            else
              Icon(
                Icons.chevron_right_rounded,
                size: 13,
                color: beeTextMuted(context),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Radio Tile (flat row + thin divider, no card) ────────────────
class BeeRadioTile extends StatefulWidget {
  final bool isSelected;
  final String label;
  final String? subtitle;
  final Widget? badge;
  final Widget? warningBadge;
  final VoidCallback onTap;
  final bool showDivider;

  /// When true, the tile content is rendered at reduced opacity to read as
  /// "inactive" while remaining tappable (e.g. a prompt that needs a cloud
  /// model before it can take effect). The tap handler is expected to
  /// surface the relevant guidance rather than silently selecting.
  final bool dimmed;

  const BeeRadioTile({
    super.key,
    required this.isSelected,
    required this.label,
    this.subtitle,
    this.badge,
    this.warningBadge,
    required this.onTap,
    this.showDivider = true,
    this.dimmed = false,
  });

  @override
  State<BeeRadioTile> createState() => _BeeRadioTileState();
}

class _BeeRadioTileState extends State<BeeRadioTile> {
  @override
  Widget build(BuildContext context) {
    final accent = beeYellow(context);
    final muted = beeTextMuted(context);
    return BeeInteractive(
      onTap: widget.onTap,
      semanticLabel: widget.label,
      selected: widget.isSelected,
      builder: (context, focused) {
        final badge = widget.badge;

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Opacity(
                opacity: widget.dimmed ? 0.45 : 1.0,
                child: Row(
                  children: [
                    // macOS-style radio: small filled circle with inner dot
                    // when selected, plain gray ring otherwise.
                    Container(
                      width: 15,
                      height: 15,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: widget.isSelected
                              ? accent
                              : muted.withValues(alpha: 0.55),
                          width: 1.5,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: widget.isSelected
                          ? Container(
                              width: 7,
                              height: 7,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: accent,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  widget.label,
                                  style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: widget.isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                    color: widget.isSelected
                                        ? beeText(context)
                                        : beeTextSub(context),
                                  ),
                                ),
                              ),
                              if (widget.warningBadge != null) ...[
                                const SizedBox(width: 8),
                                widget.warningBadge!,
                              ],
                            ],
                          ),
                          if (widget.subtitle != null) ...[
                            const SizedBox(height: 2),
                            Text(
                              widget.subtitle!,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: beeTextMuted(context),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (badge != null) ...[const SizedBox(width: 10), badge],
                  ],
                ),
              ),
            ),
            if (widget.showDivider)
              Container(
                height: 1,
                color: beeDivider(context).withValues(alpha: 0.55),
              ),
          ],
        );
      },
    );
  }
}

// ─── Badge (macOS-style: small flat text pill, no border) ─────────
/// Renders a small flat text pill (no border). The [color] is still a
/// compile-time constant (typically `beeSuccess(context)` or
/// `beeError(context)` from the caller) — pass a runtime-resolved color
/// when calling from a build method.
Widget beeBadge(String text, Color color) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(kBeeRadiusXs),
    ),
    child: Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: color,
        letterSpacing: 0.5,
      ),
    ),
  );
}

// ─── Empty State (flat, no bordered card) ──────────────────────────
class BeeEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const BeeEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: Icon(icon, size: 22, color: beeTextMuted(context)),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: beeTextSub(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: GoogleFonts.inter(
              fontSize: 11,
              color: beeTextMuted(context),
              height: 1.4,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ─── Keycaps (flat text style, no bordered boxes) ─────────────────
// Note: these render static text styles. Callers should wrap them in a
// runtime-aware widget if the surrounding context's text color matters
// (most callers already paint them onto a parent that defaults to
// [ThemeData.textTheme] colors or an explicit bee*() color).
List<Widget> renderKeycaps(String hotkeyStr) {
  final parts = hotkeyStr.split(' + ');
  final widgets = <Widget>[];
  for (int i = 0; i < parts.length; i++) {
    if (i > 0) {
      widgets.add(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Builder(
            builder: (context) => Text(
              '+',
              style: GoogleFonts.inter(
                fontSize: 11,
                color: beeTextMuted(context),
              ),
            ),
          ),
        ),
      );
    }
    widgets.add(
      Builder(
        builder: (context) => Text(
          parts[i].trim(),
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: beeText(context),
            letterSpacing: 0.1,
          ),
        ),
      ),
    );
  }
  return widgets;
}
