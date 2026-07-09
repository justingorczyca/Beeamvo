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

// ─── Interaction Tint / Alpha Tokens (single source of truth) ─────
//
// Before these existed every control hand-rolled its own alpha literal:
// 0.03, 0.035, 0.04, 0.05, 0.06, 0.10, 0.12, 0.55, 0.65, 0.72, 0.82 …
// Now "subtle ink fill" is one of exactly four steps. All tints are
// applied to the runtime `beeText(context)` color so they fade with the
// theme automatically.
const double kBeeTintRecess = 0.04; // group / recessed container background
const double kBeeTintHover = 0.06; // hover / focus fill
const double kBeeTintActive = 0.10; // selected segment / active fill
const double kBeeTintDisabled = 0.03; // inert / disabled fill
const double kBeeTintBadge = 0.12; // badge / status-pill background

// ── Border strengths (the chrome-to-content seam had 3 conventions) ──
const double kBeeRowDividerAlpha =
    1.0; // flat-row hairlines — full-strength divider token
const double kBeeChromeBorderAlpha =
    0.7; // dialog / popup / panel chrome outline

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

/// The shared toggle thumb color (white / warm off-white).
Color beeThumb(BuildContext c) => beeColors(c).toggleThumb;

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
    sideColor: kBeeBorder.withValues(alpha: kBeeChromeBorderAlpha),
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
    // Desktop-native: highlight on hover OR keyboard focus — but only while
    // the item is actually interactive. Disabled/selected items always pin to
    // their idle look, so the builder never sees an "active" state for them.
    final active = enabled && (_isHovered || _isFocused);
    final child = widget.builder(context, active);

    // The MouseRegion is mounted unconditionally so tracked hover stays in
    // sync with the pointer even while this widget is disabled/selected.
    // If it were only mounted in the interactive branch (as it used to be),
    // unmounting it would freeze `_isHovered` at its last value: a category
    // clicked into the selected state would keep a stale "hovered" flag that
    // resurfaced the instant it was re-enabled later, leaving it visually
    // highlighted until the pointer crossed it again.
    final tracked = MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) {
        if (!_isHovered) setState(() => _isHovered = true);
      },
      onExit: (_) {
        if (_isHovered) setState(() => _isHovered = false);
      },
      child: child,
    );

    if (!enabled) {
      final passive = Semantics(
        label: widget.semanticLabel,
        selected: widget.selected,
        toggled: widget.toggled,
        child: tracked,
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
      child: Focus(
        onFocusChange: (focused) {
          if (_isFocused != focused) setState(() => _isFocused = focused);
        },
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
              child: tracked,
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
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              // Was hardcoded Colors.white — now the shared token so the
              // dark-mode thumb matches the Material switch (#F4F4F2).
              color: beeThumb(context),
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
              duration: kBeeTransitionDuration,
              curve: kBeeTransitionCurve,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                // Selection = solid subtle ink fill, no border. Hover = slight
                // ink tint. Idle = transparent. When disabled the selection
                // fill drops to a much fainter tint so it doesn't read as
                // "actively selected".
                color: sel
                    ? text.withValues(
                        alpha: enabled ? kBeeTintActive : kBeeTintDisabled,
                      )
                    : (focused && enabled)
                    ? text.withValues(alpha: kBeeTintHover)
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
            color: text.withValues(
              alpha: enabled ? kBeeTintRecess : kBeeTintDisabled,
            ),
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
            color: text.withValues(alpha: kBeeTintRecess),
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
            ? text.withValues(alpha: kBeeTintRecess)
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
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _BeeChoiceIcon(icon: option.icon),
                const SizedBox(width: 12),
                Expanded(
                  child: _BeeChoiceText(
                    option: option,
                    selected: selected,
                    compact: horizontal,
                  ),
                ),
                const SizedBox(width: 12),
                BeeRadioIndicator(selected: selected),
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

  const _BeeChoiceIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    // Selection inversion was removed for harmony: the icon no longer
    // inverts. Selection is conveyed solely by the shared radio dot + the
    // subtle recess fill — one signal, consistent with [BeeRadioTile].
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: beeSurfaceRaised(context),
        borderRadius: BorderRadius.circular(kBeeRadiusSm),
        border: Border.all(color: beeDivider(context)),
      ),
      child: Icon(
        icon,
        size: 14,
        color: beeTextSub(context),
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
              beeBadge(context, option.badge!, BeeBadgeTone.neutral),
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

/// Shared radio indicator — **one selection grammar** across [BeeRadioTile]
/// and [BeeChoiceGroup]. A 16px ring that fills with an inner 7px dot when
/// selected (the clean macOS pattern); a plain 1.5px ring otherwise.
///
/// Replaces the former `_BeeChoiceRadio` (a 17px inverted check-circle) so
/// "selected" no longer looks different per control family.
class BeeRadioIndicator extends StatelessWidget {
  final bool selected;
  const BeeRadioIndicator({super.key, required this.selected});

  @override
  Widget build(BuildContext context) {
    final accent = beeYellow(context);
    final muted = beeTextMuted(context);
    return SizedBox(
      width: 16,
      height: 16,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? accent : muted.withValues(alpha: 0.55),
            width: 1.5,
          ),
        ),
        child: selected
            ? Center(
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent,
                  ),
                ),
              )
            : null,
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
                    BeeRadioIndicator(selected: widget.isSelected),
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
/// Tonal key for [beeBadge]. Resolves to the matching runtime color so the
/// badge stays consistent across light/dark.
enum BeeBadgeTone { neutral, success, info, amber }

/// Small flat text pill (no border) — the **canonical** status badge for the
/// entire settings surface. One style replaces the former six bespoke
/// variants (sidebar update notice, General update chip, AI provider-status
/// pill, AI BETA tag, both `_buildKindTag`s, the override `_customizedPill`).
///
/// Pass [tone] for the standard semantic colors, or [color] to override.
Widget beeBadge(
  BuildContext context,
  String text,
  BeeBadgeTone tone, {
  Color? color,
}) {
  final c = color ?? _beeBadgeColor(context, tone);
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: c.withValues(alpha: kBeeTintBadge),
      borderRadius: BorderRadius.circular(kBeeRadiusXs),
    ),
    child: Text(
      text,
      style: GoogleFonts.inter(
        fontSize: 9,
        fontWeight: FontWeight.w700,
        color: c,
        letterSpacing: 0.5,
      ),
    ),
  );
}

Color _beeBadgeColor(BuildContext context, BeeBadgeTone tone) {
  switch (tone) {
    case BeeBadgeTone.neutral:
      return beeTextSub(context);
    case BeeBadgeTone.success:
      return beeSuccess(context);
    case BeeBadgeTone.info:
      return AppTheme.info;
    case BeeBadgeTone.amber:
      return beeYellow(context);
  }
}

// ─── Empty State (flat, no bordered card) ──────────────────────────
/// Size variant for [BeeEmptyState]. `normal` is the default list/block
/// placeholder; `compact` fits inline small lists (clipboard entries);
/// `prominent` suits page-level/hero empties (the Home dashboard).
enum BeeEmptySize { compact, normal, prominent }

class BeeEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final BeeEmptySize size;

  const BeeEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.size = BeeEmptySize.normal,
  });

  @override
  Widget build(BuildContext context) {
    final (iconSize, gap, vPad) = switch (size) {
      BeeEmptySize.compact => (18.0, 6.0, 12.0),
      BeeEmptySize.normal => (22.0, 8.0, 18.0),
      BeeEmptySize.prominent => (44.0, 12.0, 24.0),
    };
    return Padding(
      padding: EdgeInsets.symmetric(vertical: vPad, horizontal: 8),
      child: Column(
        children: [
          Icon(icon, size: iconSize, color: beeTextMuted(context)),
          SizedBox(height: gap),
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
