import 'package:flutter/material.dart';
import 'settings_shared.dart';

/// Canonical text-field decoration for the entire settings surface — **one
/// recipe** replacing the former three:
///
///   1. AI/General dialogs: amber focus ring (`beeYellow`) + `beeBlack` fill.
///   2. Prompts dialog: ink focus (`beeTextSub`), explicitly "no yellow".
///   3. Clipboard: borderless search field + grey-filled pinned field.
///
/// The unified recipe is monochrome — color is reserved for *true* semantic
/// feedback, so a text field never flashes amber. Focus is signalled by a
/// darker, thicker (1.5px) hairline rather than a hue shift.
///
/// Pass [context] so fill/border colors resolve to the active theme variant.
InputDecoration beeInputDecoration(
  BuildContext context, {
  String? label,
  String? hint,
  IconData? prefixIcon,
  Widget? suffix,
}) {
  final hairline = beeBorder(context).withValues(alpha: kBeeChromeBorderAlpha);
  return InputDecoration(
    filled: true,
    fillColor: beeSurfaceHighest(context),
    labelText: label,
    hintText: hint,
    prefixIcon: prefixIcon != null
        ? Icon(prefixIcon, size: 18, color: beeTextSub(context))
        : null,
    suffixIcon: suffix,
    isDense: true,
    contentPadding:
        const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(kBeeRadiusMd),
      borderSide: BorderSide(color: hairline),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(kBeeRadiusMd),
      borderSide: BorderSide(color: hairline),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(kBeeRadiusMd),
      // Monochrome focus: full-opacity hairline, slightly thicker.
      borderSide: BorderSide(color: beeBorder(context), width: 1.5),
    ),
  );
}
