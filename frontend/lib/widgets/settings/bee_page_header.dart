import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'settings_shared.dart';

/// Canonical page-header pattern for every settings page.
///
/// Before this existed, every page dived straight into a `BeeGroupLabel`
/// (a small uppercase section eyebrow) with no top-level title — so the
/// sidebar selection ("Transcription", "AI Models"…) was never echoed at
/// the top of the content area, weakening place-orientation.
///
/// This also pins the **one** standard content padding and inter-group gap,
/// replacing the four drifting values (22 / 24 / 28, plus mixed 14/18 inside
/// AI Models) so every page shares the same vertical rhythm.
class BeePageHeader extends StatelessWidget {
  final String title;
  final String? description;

  const BeePageHeader({super.key, required this.title, this.description});

  /// The canonical settings-page content padding (sides 28, top 22, bottom 28).
  static const EdgeInsets contentPadding =
      EdgeInsets.fromLTRB(28, 22, 28, 28);

  /// The canonical inter-group gap between `BeeGroupLabel` sections.
  static const double groupGap = 24;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.spaceGrotesk(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: beeText(context),
              letterSpacing: -0.3,
            ),
          ),
          if (description != null) ...[
            const SizedBox(height: 4),
            Text(
              description!,
              style: GoogleFonts.inter(
                fontSize: 12.5,
                color: beeTextSub(context),
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Convenience wrapper: a settings page body padded with the canonical
/// [BeePageHeader.contentPadding] so pages need not redeclare insets.
Padding beePageBody(Widget child) => Padding(
      padding: BeePageHeader.contentPadding,
      child: child,
    );
