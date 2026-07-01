import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../models/usage_achievements.dart';
import '../../../models/usage_stats.dart';
import '../settings_shared.dart';

/// Achievements section — a ladder of 12 monochrome "porcelain seal"
/// milestones.
///
/// Unlocked seals render as ink-filled stamps (text color on black-on-ceramic)
/// with a soft ink glow; locked seals are ghosted. Each seal pairs with a thin
/// ink progress bar so in-progress milestones read at a glance. All tokens are
/// the runtime `bee*` accessors so the section resolves identically in light
/// and dark mode and harmonizes with the rest of the dashboard.
class HomeAchievementsSection extends StatelessWidget {
  final UsageStats stats;

  const HomeAchievementsSection({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final total = kUsageAchievements.length;
    final unlocked = kUsageAchievements
        .where((a) => a.isUnlocked(stats))
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(child: BeeGroupLabel(label: 'Achievements')),
            Text(
              '$unlocked / $total unlocked',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: beeTextMuted(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
          decoration: BoxDecoration(
            color: beeSurfaceHighest(context),
            borderRadius: BorderRadius.circular(kBeeRadiusMd),
            border: Border.all(
              color: beeBorder(context).withValues(alpha: 0.5),
            ),
          ),
          child: Column(
            children: [
              for (int i = 0; i < kUsageAchievements.length; i += 2) ...[
                if (i > 0) const SizedBox(height: 12),
                IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: _AchievementSeal(
                          achievement: kUsageAchievements[i],
                          stats: stats,
                        ),
                      ),
                      const SizedBox(width: 12),
                      if (i + 1 < kUsageAchievements.length)
                        Expanded(
                          child: _AchievementSeal(
                            achievement: kUsageAchievements[i + 1],
                            stats: stats,
                          ),
                        )
                      else
                        const Expanded(child: SizedBox.shrink()),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Single seal tile — glyph badge + title + ink progress bar
// ═════════════════════════════════════════════════════════════════════════════

class _AchievementSeal extends StatefulWidget {
  final Achievement achievement;
  final UsageStats stats;

  const _AchievementSeal({required this.achievement, required this.stats});

  @override
  State<_AchievementSeal> createState() => _AchievementSealState();
}

class _AchievementSealState extends State<_AchievementSeal> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final achievement = widget.achievement;
    final stats = widget.stats;
    final unlocked = achievement.isUnlocked(stats);
    final progress = achievement.progress(stats);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: kBeeTransitionDuration,
        curve: kBeeTransitionCurve,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          // Same ~6% ink tint the rest of the dashboard uses for hovered
          // surfaces (see `BeeInteractive`), so the tile reads as one with
          // the OS rather than a dead, flat block.
          color: _hovered
              ? beeText(context).withValues(alpha: 0.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(kBeeRadiusSm),
        ),
        child: Opacity(
          opacity: unlocked ? 1.0 : 0.72,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // ── Seal badge ──────────────────────────────────────────────
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: unlocked
                      ? beeText(context)
                      : beeSurfaceRaised(context),
                  borderRadius: BorderRadius.circular(kBeeRadiusSm),
                  border: unlocked
                      ? null
                      : Border.all(color: beeBorder(context)),
                  // Unlocked seals deepen their glow on hover for a little
                  // tactile lift.
                  boxShadow: unlocked
                      ? [
                          BoxShadow(
                            color: beeText(
                              context,
                            ).withValues(alpha: _hovered ? 0.18 : 0.10),
                            blurRadius: _hovered ? 14 : 10,
                            offset: const Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Icon(
                  achievementGlyphIcon(achievement.glyph),
                  size: 20,
                  // Inverted on the ink seal; ghosted on the locked ceramic.
                  color: unlocked ? beeSurface(context) : beeTextMuted(context),
                ),
              ),
              const SizedBox(width: 11),
              // ── Title + progress ────────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      achievement.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: unlocked
                            ? beeText(context)
                            : beeTextSub(context),
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 5),
                    _InkProgressBar(progress: unlocked ? 1.0 : progress),
                    const SizedBox(height: 4),
                    Text(
                      unlocked
                          ? 'Reached'
                          : achievementProgressCaption(achievement, stats),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.inter(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                        color: beeTextMuted(context),
                        height: 1.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Thin monochrome progress bar — track fades from border, fill is solid ink
// ═════════════════════════════════════════════════════════════════════════════

class _InkProgressBar extends StatelessWidget {
  final double progress;

  const _InkProgressBar({required this.progress});

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackW = constraints.maxWidth;
        final fillW = (trackW * clamped).clamp(0.0, trackW);
        return Container(
          height: 3,
          decoration: BoxDecoration(
            color: beeBorder(context).withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(kBeeRadiusPill),
          ),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedContainer(
              duration: kBeeTransitionDuration,
              curve: kBeeTransitionCurve,
              width: fillW == 0 ? 0 : fillW,
              decoration: BoxDecoration(
                color: beeText(context),
                borderRadius: BorderRadius.circular(kBeeRadiusPill),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// Glyph → IconData resolution (keeps the model free of Flutter imports)
// ═════════════════════════════════════════════════════════════════════════════

IconData achievementGlyphIcon(AchievementGlyph glyph) {
  switch (glyph) {
    case AchievementGlyph.firstSteps:
      return Icons.mic_rounded;
    case AchievementGlyph.rising:
      return Icons.trending_up_rounded;
    case AchievementGlyph.century:
      return Icons.emoji_events_rounded;
    case AchievementGlyph.firstWords:
      return Icons.edit_rounded;
    case AchievementGlyph.wordsmith:
      return Icons.create_rounded;
    case AchievementGlyph.storyteller:
      return Icons.auto_stories_rounded;
    case AchievementGlyph.prolific:
      return Icons.menu_book_rounded;
    case AchievementGlyph.momentum:
      return Icons.bolt_rounded;
    case AchievementGlyph.weekStrong:
      return Icons.calendar_view_week_rounded;
    case AchievementGlyph.unbroken:
      return Icons.shield_rounded;
    case AchievementGlyph.timeKeeper:
      return Icons.schedule_rounded;
    case AchievementGlyph.consistent:
      return Icons.event_available_rounded;
  }
}
