import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Beeamvo brand identity and theme system.
///
/// Design philosophy: "Monochrome porcelain" — the light UI should feel like
/// ink on crisp white ceramic: neutral surfaces, graphite/black highlights, and
/// chromatic color reserved for true semantic feedback. Legacy `amber` naming
/// is retained as a compatibility alias while the visual accent is monochrome.
class AppTheme {
  AppTheme._();

  // ─── Neutral Color Scale ─────────────────────────────────────────
  static const Color neutral0 = Color(0xFFFFFFFF);
  static const Color neutral50 = Color(0xFFFAFAF8);
  static const Color neutral100 = Color(0xFFF4F4F2);
  static const Color neutral150 = Color(0xFFEDEDEA);
  static const Color neutral200 = Color(0xFFE2E2DE);
  static const Color neutral300 = Color(0xFFC9C9C3);
  static const Color neutral600 = Color(0xFF606060);
  static const Color neutral700 = Color(0xFF3F3F3F);
  static const Color neutral900 = Color(0xFF111111);
  static const Color neutral1000 = Color(0xFF000000);

  // ─── Brand / Accent Colors ───────────────────────────────────────
  // Future-facing semantic names for the monochrome signal layer.
  static const Color accent = neutral900;
  static const Color accentLight = Color(0xFF343434);
  static const Color accentDim = neutral1000;

  // Compatibility names are retained because many widgets still reference
  // `amber`/`kBeeYellow`. Visually these now represent monochrome ink, not a
  // yellow or green hue.
  static const Color amber = accent;
  static const Color amberLight = accentLight;
  static const Color amberDim = accentDim;

  // Compatibility name retained because many widgets already consume
  // `chromeBlack`/`kBeeBlack` as the app chrome surface or on-accent color.
  // In the light system it is the clean white chrome layer.
  static const Color chromeBlack = neutral0;
  static const Color surfaceBase = neutral100;
  static const Color surfaceRaised = neutral50;
  static const Color surface = Color(0xFFF7F7F5);
  static const Color surfaceContainer = neutral0;
  static const Color surfaceContainerHigh = neutral150;
  static const Color surfaceBright = neutral200;

  static const Color textPrimary = neutral900;
  static const Color textSecondary = neutral700;
  static const Color textTertiary = neutral600;

  static const Color success = Color(0xFF176B46);
  static const Color error = Color(0xFFB3261E);
  static const Color info = Color(0xFF0F5E9A);

  static const Color divider = neutral200;
  static const Color border = neutral300;

  // ─── Gradients ──────────────────────────────────────────────────
  static const LinearGradient amberGradient = LinearGradient(
    colors: [amber, amberLight],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient surfaceGradient = LinearGradient(
    colors: [surfaceContainer, surface],
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
  );

  // ─── Shadows ────────────────────────────────────────────────────
  static List<BoxShadow> get glowShadow => [
    BoxShadow(
      color: neutral1000.withValues(alpha: 0.10),
      blurRadius: 24,
      spreadRadius: 1,
    ),
  ];

  static List<BoxShadow> get subtleShadow => [
    BoxShadow(
      color: neutral1000.withValues(alpha: 0.08),
      blurRadius: 14,
      spreadRadius: 0,
      offset: const Offset(0, 6),
    ),
  ];

  static List<BoxShadow> get windowShadow => [
    BoxShadow(
      color: neutral1000.withValues(alpha: 0.14),
      blurRadius: 46,
      spreadRadius: 4,
      offset: const Offset(0, 18),
    ),
    BoxShadow(
      color: neutral1000.withValues(alpha: 0.06),
      blurRadius: 72,
      spreadRadius: 10,
    ),
  ];

  // ─── Spacing ─────────────────────────────────────────────────────
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space24 = 24;
  static const double space32 = 32;

  // ─── Border Radius ──────────────────────────────────────────────
  static const double radiusXs = 6;
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 20;
  static const double radius2xl = 24;
  static const double radiusPill = 999;

  static RoundedRectangleBorder roundedShape(
    double radius, {
    Color? sideColor,
    double sideWidth = 1,
  }) {
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: sideColor == null
          ? BorderSide.none
          : BorderSide(color: sideColor, width: sideWidth),
    );
  }

  static BoxDecoration panelDecoration({
    Color color = surfaceContainer,
    double radius = radiusLg,
    Color? outlineColor,
    double outlineOpacity = 1,
    List<BoxShadow>? shadows,
  }) {
    return BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(
        color: (outlineColor ?? border).withValues(alpha: outlineOpacity),
      ),
      boxShadow: shadows ?? const [],
    );
  }

  // ─── Text Styles (used standalone outside ThemeData) ────────────
  static TextStyle get heading => GoogleFonts.spaceGrotesk(
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: textPrimary,
    letterSpacing: -0.5,
  );

  static TextStyle get subheading => GoogleFonts.spaceGrotesk(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    color: textPrimary,
  );

  static TextStyle get body => GoogleFonts.inter(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: textPrimary,
  );

  static TextStyle get bodySecondary => GoogleFonts.inter(
    fontSize: 13,
    fontWeight: FontWeight.w400,
    color: textSecondary,
  );

  static TextStyle get caption => GoogleFonts.inter(
    fontSize: 11,
    fontWeight: FontWeight.w500,
    color: textTertiary,
    letterSpacing: 0.5,
  );

  static TextStyle get label => GoogleFonts.inter(
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: textSecondary,
  );

  // ─── Dark Palette Constants ──────────────────────────────────────
  // True graphite neutrals with the same barely-warm undertone family as the
  // light `#FAFAF8` series. The hierarchy is layered so each "raised" surface
  // appears one perceptual step brighter than the layer below it.
  //
  // Reference baselines (kept here as documentation for future tuning):
  //   content surface   ~ #1A1A1A  (darkest — main scroll area)
  //   sidebar           ~ #212121  (slightly raised vs content)
  //   raised (cards)    ~ #252525
  //   highest (popups)  ~ #2D2D2D
  //   border            ~ #3A3A3A
  //   divider           ~ #2E2E2E
  //   text  primary     ~ #EDEDED  (≥4.5:1 on #1A1A1A)
  //   text  secondary   ~ #A0A0A0
  //   text  muted       ~ #777777
  //   accent (ink)      ~ #E8E8E8
  //   on-accent fg      ~ #1A1A1A
  //   success           ~ #4EC38B
  //   error             ~ #F4685C
  static const Color darkSurface = Color(0xFF1A1A1A);
  static const Color darkSidebar = Color(0xFF212121);
  static const Color darkSurfaceRaised = Color(0xFF252525);
  static const Color darkSurfaceHighest = Color(0xFF2D2D2D);
  static const Color darkBorder = Color(0xFF3A3A3A);
  static const Color darkDivider = Color(0xFF2E2E2E);
  static const Color darkText = Color(0xFFEDEDED);
  static const Color darkTextSub = Color(0xFFA0A0A0);
  static const Color darkTextMuted = Color(0xFF777777);
  static const Color darkAccent = Color(0xFFE8E8E8);
  static const Color darkAccentDim = Color(0xFFC9C9C9);
  static const Color darkOnAccent = Color(0xFF1A1A1A);
  static const Color darkSuccess = Color(0xFF4EC38B);
  static const Color darkError = Color(0xFFF4685C);

  // ─── Toggle thumb tokens (shared by Material Switch + BeeToggle) ──
  // Both light and dark give the toggle the same crisp macOS-style knob.
  static const Color lightToggleThumb = neutral0; // #FFFFFF
  static const Color darkToggleThumb =
      Color(0xFFF4F4F2); // tuned warm white, matches dark switchTheme

  // ─── ThemeData ──────────────────────────────────────────────────
  static ThemeData get lightTheme {
    final base = _buildLightTheme();
    return base.copyWith(
      extensions: List<ThemeExtension<dynamic>>.from(base.extensions.values)
        ..add(BeeColors.light()),
    );
  }

  /// Real dark theme — a true graphite counterpart to [lightTheme].
  static ThemeData get darkTheme {
    final base = _buildDarkTheme();
    return base.copyWith(
      extensions: List<ThemeExtension<dynamic>>.from(base.extensions.values)
        ..add(BeeColors.dark()),
    );
  }

  static ThemeData _buildLightTheme() {
    // ── Force Material 2 ──
    // Material 3 renders built-in "state layers" (semi-transparent overlays)
    // on interactive widgets during hover/focus/press.  These overlays are
    // controlled at the Flutter engine level and CANNOT be fully suppressed
    // through theme properties alone.  Disabling Material 3 restores the
    // simpler M2 behaviour where hoverColor / focusColor / splashColor are
    // the sole visual feedback mechanisms — and we already set those all
    // to transparent.
    return ThemeData(
      useMaterial3: false,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: surfaceContainer,
      splashFactory: NoSplash.splashFactory,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      highlightColor: Colors.transparent,
      colorScheme: const ColorScheme.light(
        primary: amber,
        onPrimary: chromeBlack,
        secondary: amberLight,
        onSecondary: chromeBlack,
        surface: surface,
        onSurface: textPrimary,
        error: error,
        onError: chromeBlack,
        outline: border,
        outlineVariant: divider,
        surfaceContainerHighest: surfaceContainerHigh,
        // Material 3 uses surfaceTint for tonal elevation overlays.
        // Force transparent to prevent any tint shift on hover/focus/press.
        surfaceTint: Colors.transparent,
      ),
      // Additional failsafe: splashColor is the Ink splash color used by
      // InkWell / InkWell-based widgets (DropdownButton items, etc.).
      splashColor: Colors.transparent,
      textTheme: _buildTextTheme(
        primary: textPrimary,
        secondary: textSecondary,
        tertiary: textTertiary,
      ),
      iconTheme: const IconThemeData(color: textSecondary, size: 20),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(textSecondary),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusXs),
            ),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return amber;
          return surfaceContainer;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return neutral200;
          }
          return surfaceBright.withValues(alpha: 0.62);
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return neutral300;
          }
          return border;
        }),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceContainer,
        shape: roundedShape(
          radiusMd,
          sideColor: border.withValues(alpha: 0.72),
        ),
        elevation: 10,
        textStyle: body,
      ),
      // Suppress hover / splash on DropdownButton popup items.
      // DropdownButton internally uses InkWell for each menu item; these
      // theme-level overrides ensure no visual feedback on hover.
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          elevation: const WidgetStatePropertyAll(10),
          backgroundColor: const WidgetStatePropertyAll(surfaceContainer),
          shape: WidgetStatePropertyAll(
            roundedShape(radiusMd, sideColor: border.withValues(alpha: 0.72)),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surfaceContainer,
        shape: roundedShape(
          radiusLg,
          sideColor: border.withValues(alpha: 0.75),
        ),
        elevation: 18,
        titleTextStyle: heading.copyWith(fontSize: 18),
        contentTextStyle: body,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceContainer,
        labelStyle: label,
        hintStyle: const TextStyle(color: textTertiary),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: border.withValues(alpha: 0.82)),
        ),
        // Suppress hover overlay tint so TextField border looks the same
        // on mouse-over as when idle (no visited/active color shift).
        hoverColor: Colors.transparent,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: amber, width: 1.5),
        ),
      ),
      sliderTheme: SliderThemeData(overlayColor: Colors.transparent),
      // ── Button themes — hover overlay suppressed ──
      // Material 3 buttons use overlayColor (not hoverColor) for their
      // hover/focus/press tint layer.  We explicitly return transparent for
      // ALL interaction states so that NO background color change occurs.
      // surfaceTintColor is ALSO pinned to transparent to suppress Material
      // 3 tonal-elevation overlays.
      elevatedButtonTheme: ElevatedButtonThemeData(
        style:
            ElevatedButton.styleFrom(
              backgroundColor: amber,
              foregroundColor: chromeBlack,
              shadowColor: neutral1000.withValues(alpha: 0.16),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radiusMd),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              textStyle: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ).copyWith(
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              surfaceTintColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
              // Pin elevation to zero across ALL states so hover never adds shadow.
              elevation: const WidgetStatePropertyAll(0),
            ),
      ),
      textButtonTheme: TextButtonThemeData(
        style:
            TextButton.styleFrom(
              foregroundColor: textSecondary,
              textStyle: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ).copyWith(
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              surfaceTintColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
            ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              foregroundColor: textSecondary,
              side: const BorderSide(color: border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radiusMd),
              ),
              textStyle: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ).copyWith(
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              surfaceTintColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
            ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: surfaceContainer,
        contentTextStyle: body,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: const BorderSide(color: border),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: const DividerThemeData(
        color: divider,
        thickness: 1,
        space: 1,
      ),
      // ── ListTile & ExpansionTile — hover overlay suppressed ──
      // ListTile hover tint is inherited from ThemeData.hoverColor
      // (already transparent, line 184).  The tileColor override ensures
      // no default background fill appears on hover or idle state.
      listTileTheme: const ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: Colors.transparent,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
      ),
    );
  }

  static ThemeData _buildDarkTheme() {
    return ThemeData(
      useMaterial3: false,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: darkSurfaceHighest,
      splashFactory: NoSplash.splashFactory,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      highlightColor: Colors.transparent,
      colorScheme: ColorScheme.dark(
        primary: darkAccent,
        onPrimary: darkOnAccent,
        secondary: darkAccentDim,
        onSecondary: darkOnAccent,
        surface: darkSurface,
        onSurface: darkText,
        error: darkError,
        onError: darkOnAccent,
        outline: darkBorder,
        outlineVariant: darkDivider,
        surfaceContainerHighest: darkSurfaceHighest,
        // No tonal-elevation overlays in dark mode — we control the layering
        // explicitly via the BeeColors palette so popups/cards/sidebars stay
        // on the intended graphite step.
        surfaceTint: Colors.transparent,
      ),
      splashColor: Colors.transparent,
      textTheme: _buildTextTheme(
        primary: darkText,
        secondary: darkTextSub,
        tertiary: darkTextMuted,
      ),
      iconTheme: const IconThemeData(color: darkTextSub, size: 20),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(darkTextSub),
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusXs),
            ),
          ),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            // Engaged thumb: bright #F4F4F2 (warm white). This is the
            // standard macOS/iOS dark-mode pattern — a crisp white handle
            // on a saturated engaged track. Reads as "clearly on" without
            // glare because the brighter track provides the energy, not
            // the thumb. Previously #1A1A1A which disappeared into the
            // dim engaged track at 1.6:1 contrast.
            return const Color(0xFFF4F4F2);
          }
          // Disengaged thumb: a clearly raised mid-gray that sits above
          // the dim track. Previously #2D2D2D which was too close to the
          // disengaged track's #494949 — only ~1.5:1 contrast.
          return const Color(0xFFB5B5B5);
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            // Engaged track: solid warm-white at ~78% opacity blended onto
            // the dark surface yields an effective ~#BFBFBD — clearly
            // bright, clearly engaged, with a contrast ratio of ~3.4:1
            // against the #F4F4F2 thumb (visible as a faint line, enough
            // to perceive the thumb as a distinct handle).
            return darkAccent.withValues(alpha: 0.78);
          }
          // Disengaged track: #888888-equivalent readable as "off" —
          // clearly distinguishable from both the thumb (#B5B5B5, ~1.8:1)
          // and from the engaged track. Increased from the previous
          // #494949 to push the overall switch shape out of the dark
          // background so the user can read the affordance.
          return const Color(0xFF6B6B6B).withValues(alpha: 0.62);
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            // Hide the outline on the engaged side — the bright track
            // is the affordance now.
            return Colors.transparent;
          }
          return const Color(0xFF494949);
        }),
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: darkSurfaceHighest,
        shape: roundedShape(
          radiusMd,
          sideColor: darkBorder.withValues(alpha: 0.72),
        ),
        elevation: 10,
        textStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: darkText,
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        menuStyle: MenuStyle(
          elevation: const WidgetStatePropertyAll(10),
          backgroundColor: const WidgetStatePropertyAll(darkSurfaceHighest),
          shape: WidgetStatePropertyAll(
            roundedShape(
              radiusMd,
              sideColor: darkBorder.withValues(alpha: 0.72),
            ),
          ),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: darkSurfaceHighest,
        shape: roundedShape(
          radiusLg,
          sideColor: darkBorder.withValues(alpha: 0.75),
        ),
        elevation: 18,
        titleTextStyle: GoogleFonts.spaceGrotesk(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: darkText,
        ),
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: darkText,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurfaceHighest,
        labelStyle: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: darkTextSub,
        ),
        hintStyle: TextStyle(color: darkTextMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: BorderSide(color: darkBorder.withValues(alpha: 0.82)),
        ),
        hoverColor: Colors.transparent,
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          borderSide: const BorderSide(color: darkAccent, width: 1.5),
        ),
      ),
      sliderTheme: SliderThemeData(overlayColor: Colors.transparent),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style:
            ElevatedButton.styleFrom(
              backgroundColor: darkAccent,
              foregroundColor: darkOnAccent,
              shadowColor: Colors.transparent,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radiusMd),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              textStyle: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ).copyWith(
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              surfaceTintColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
              elevation: const WidgetStatePropertyAll(0),
            ),
      ),
      textButtonTheme: TextButtonThemeData(
        style:
            TextButton.styleFrom(
              foregroundColor: darkTextSub,
              textStyle: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ).copyWith(
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              surfaceTintColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
            ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style:
            OutlinedButton.styleFrom(
              foregroundColor: darkTextSub,
              side: const BorderSide(color: darkBorder),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(radiusMd),
              ),
              textStyle: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ).copyWith(
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              surfaceTintColor: const WidgetStatePropertyAll(
                Colors.transparent,
              ),
            ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: darkSurfaceHighest,
        contentTextStyle: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: darkText,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: const BorderSide(color: darkBorder),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      dividerTheme: const DividerThemeData(
        color: darkDivider,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        tileColor: Colors.transparent,
        selectedTileColor: Colors.transparent,
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
      ),
    );
  }

  static TextTheme _buildTextTheme({
    required Color primary,
    required Color secondary,
    required Color tertiary,
  }) {
    return TextTheme(
      headlineLarge: GoogleFonts.spaceGrotesk(
        fontSize: 28,
        fontWeight: FontWeight.w700,
        color: primary,
        letterSpacing: -0.5,
      ),
      headlineMedium: GoogleFonts.spaceGrotesk(
        fontSize: 22,
        fontWeight: FontWeight.w700,
        color: primary,
        letterSpacing: -0.5,
      ),
      headlineSmall: GoogleFonts.spaceGrotesk(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      titleLarge: GoogleFonts.spaceGrotesk(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w500,
        color: primary,
      ),
      titleSmall: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: secondary,
      ),
      bodyLarge: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w400,
        color: primary,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: primary,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: secondary,
      ),
      labelLarge: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      labelMedium: GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: secondary,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.w500,
        color: tertiary,
        letterSpacing: 0.5,
      ),
    );
  }
}

/// Runtime-resolvable color tokens for the Beeamvo design system.
///
/// Use [BeeColors.light] / [BeeColors.dark] to construct the variant for a
/// [ThemeData]. Reach the active variant inside `build()` via
/// `Theme.of(context).extension<BeeColors>()!` (or the convenience helpers in
/// `settings_shared.dart`).
///
/// These tokens are the single source of truth for every component-level
/// color decision; the legacy `kBee*` compile-time constants in
/// `settings_shared.dart` are kept as light-mode defaults for backwards
/// compatibility.
@immutable
class BeeColors extends ThemeExtension<BeeColors> {
  /// Monochrome ink accent — buttons, focus outlines, the "engaged" UI state.
  /// In light mode this is graphite/black; in dark mode a soft off-white so it
  /// holds presence on dark surfaces.
  final Color yellow;

  /// A slightly dimmed variant of [yellow] for borders and track outlines on
  /// the off/idle state of toggles.
  final Color yellowDim;

  /// The "engaged" foreground painted on top of [yellow] (e.g. button text on
  /// a filled accent background). Always high-contrast *against* the accent —
  /// so light in light-mode, dark in dark-mode.
  final Color black;

  /// Main scroll / content area background. Darkest layer in dark mode.
  final Color surface;

  /// Cards, dropdowns, popovers, raised inputs.
  final Color surfaceRaised;

  /// Modal sheets, popups, peek surfaces — the highest "raised" tier.
  final Color surfaceHighest;

  /// Sidebar / chrome layer. Slightly lighter than [surface] in dark mode so
  /// the sidebar reads as raised against the content.
  final Color sidebar;

  /// Primary text on [surface].
  final Color text;

  /// Secondary text — labels, subtitles, supporting copy.
  final Color textSub;

  /// Tertiary / hint text — captions, disabled copy.
  final Color textMuted;

  /// Input borders, focused outlines.
  final Color border;

  /// Hairline dividers / group separators (subtler than [border]).
  final Color divider;

  /// Semantic success.
  final Color success;

  /// Semantic error.
  final Color error;

  /// The knob painted on top of a [BeeToggle] / engaged switch track.
  /// White in light mode, warm off-white (#F4F4F2) in dark mode — the same
  /// tuned value the Material switch already uses, now shared.
  final Color toggleThumb;

  const BeeColors({
    required this.yellow,
    required this.yellowDim,
    required this.black,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceHighest,
    required this.sidebar,
    required this.text,
    required this.textSub,
    required this.textMuted,
    required this.border,
    required this.divider,
    required this.success,
    required this.error,
    required this.toggleThumb,
  });

  /// Light-mode variant — values mirror the legacy compile-time tokens so the
  /// historical light-mode look is preserved byte-for-byte.
  const BeeColors.light()
    : yellow = AppTheme.amber,
      yellowDim = AppTheme.amberDim,
      black = AppTheme.chromeBlack,
      surface = AppTheme.surfaceBase,
      surfaceRaised = AppTheme.surfaceRaised,
      surfaceHighest = AppTheme.surfaceContainer,
      sidebar = AppTheme.surfaceContainerHigh,
      text = AppTheme.textPrimary,
      textSub = AppTheme.textSecondary,
      textMuted = AppTheme.textTertiary,
      border = AppTheme.border,
      divider = AppTheme.divider,
          success = AppTheme.success,
          error = AppTheme.error,
          toggleThumb = AppTheme.lightToggleThumb;

      /// Dark-mode variant — neutral graphite palette layered so each "raised"
  /// surface is one perceptual step brighter than the layer below.
  const BeeColors.dark()
    : yellow = AppTheme.darkAccent,
      yellowDim = AppTheme.darkAccentDim,
      black = AppTheme.darkOnAccent,
      surface = AppTheme.darkSurface,
      surfaceRaised = AppTheme.darkSurfaceRaised,
      surfaceHighest = AppTheme.darkSurfaceHighest,
      sidebar = AppTheme.darkSidebar,
      text = AppTheme.darkText,
      textSub = AppTheme.darkTextSub,
      textMuted = AppTheme.darkTextMuted,
      border = AppTheme.darkBorder,
      divider = AppTheme.darkDivider,
      success = AppTheme.darkSuccess,
      error = AppTheme.darkError,
      toggleThumb = AppTheme.darkToggleThumb;

  @override
  BeeColors copyWith({
    Color? yellow,
    Color? yellowDim,
    Color? black,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceHighest,
    Color? sidebar,
    Color? text,
    Color? textSub,
    Color? textMuted,
    Color? border,
    Color? divider,
    Color? success,
    Color? error,
    Color? toggleThumb,
  }) {
    return BeeColors(
      yellow: yellow ?? this.yellow,
      yellowDim: yellowDim ?? this.yellowDim,
      black: black ?? this.black,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceHighest: surfaceHighest ?? this.surfaceHighest,
      sidebar: sidebar ?? this.sidebar,
      text: text ?? this.text,
      textSub: textSub ?? this.textSub,
      textMuted: textMuted ?? this.textMuted,
      border: border ?? this.border,
      divider: divider ?? this.divider,
          success: success ?? this.success,
          error: error ?? this.error,
          toggleThumb: toggleThumb ?? this.toggleThumb,
        );
      }

      @override
      BeeColors lerp(ThemeExtension<BeeColors>? other, double t) {
    if (other is! BeeColors) return this;
    return BeeColors(
      yellow: Color.lerp(yellow, other.yellow, t)!,
      yellowDim: Color.lerp(yellowDim, other.yellowDim, t)!,
      black: Color.lerp(black, other.black, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceHighest: Color.lerp(surfaceHighest, other.surfaceHighest, t)!,
      sidebar: Color.lerp(sidebar, other.sidebar, t)!,
      text: Color.lerp(text, other.text, t)!,
      textSub: Color.lerp(textSub, other.textSub, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      border: Color.lerp(border, other.border, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
          success: Color.lerp(success, other.success, t)!,
          error: Color.lerp(error, other.error, t)!,
          toggleThumb: Color.lerp(toggleThumb, other.toggleThumb, t)!,
        );
      }

      @override
      bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! BeeColors) return false;
    return yellow == other.yellow &&
        yellowDim == other.yellowDim &&
        black == other.black &&
        surface == other.surface &&
        surfaceRaised == other.surfaceRaised &&
        surfaceHighest == other.surfaceHighest &&
        sidebar == other.sidebar &&
        text == other.text &&
        textSub == other.textSub &&
        textMuted == other.textMuted &&
        border == other.border &&
        divider == other.divider &&
              success == other.success &&
              error == other.error &&
              toggleThumb == other.toggleThumb;
        }

  @override
  int get hashCode => Object.hash(
    yellow,
    yellowDim,
    black,
    surface,
    surfaceRaised,
    surfaceHighest,
    sidebar,
    text,
    textSub,
    textMuted,
    border,
    divider,
        success,
        error,
        toggleThumb,
      );
    }
