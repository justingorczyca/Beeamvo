// Milestone definitions for usage-based achievements ("porcelain seals").
//
// Pure-data model (no Flutter imports), matching `usage_stats.dart`, so the
// ladder can be unit-tested without booting the framework. The
// [AchievementGlyph] enum is resolved to an IconData in the presentation
// layer (`home_achievements_section.dart`).

import 'usage_stats.dart';

/// A measurable dimension that an achievement tracks against a [UsageStats].
enum AchievementDimension {
  /// `stats.totalRecordings`
  recordings,

  /// `stats.totalWords`
  words,

  /// `stats.longestStreak`
  streak,

  /// `stats.totalTypingTimeSavedMinutes`
  timeSaved,

  /// `stats.totalSessionDays` (unique active days).
  activeDays,
}

/// Icon hint stored as data so the model stays free of Flutter imports.
/// Resolved via [achievementGlyphIcon] in the UI layer.
enum AchievementGlyph {
  firstSteps,
  rising,
  century,
  firstWords,
  wordsmith,
  storyteller,
  prolific,
  momentum,
  weekStrong,
  unbroken,
  timeKeeper,
  consistent,
}

/// One milestone seal on the ladder.
class Achievement {
  final String id;
  final String title;

  /// Short descriptive goal, e.g. "Speak your first 1,000 words".
  final String subtitle;
  final AchievementDimension dimension;

  /// The value at which this seal unlocks.
  final double threshold;
  final AchievementGlyph glyph;

  const Achievement({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.dimension,
    required this.threshold,
    required this.glyph,
  });

  /// The live value from [stats] for this achievement's dimension.
  double valueFor(UsageStats stats) {
    switch (dimension) {
      case AchievementDimension.recordings:
        return stats.totalRecordings.toDouble();
      case AchievementDimension.words:
        return stats.totalWords.toDouble();
      case AchievementDimension.streak:
        return stats.longestStreak.toDouble();
      case AchievementDimension.timeSaved:
        return stats.totalTypingTimeSavedMinutes;
      case AchievementDimension.activeDays:
        return stats.totalSessionDays.toDouble();
    }
  }

  /// Whether the threshold has been met.
  bool isUnlocked(UsageStats stats) => valueFor(stats) >= threshold;

  /// Clamped 0..1 completion ratio.
  double progress(UsageStats stats) {
    if (threshold <= 0) return 0;
    final ratio = valueFor(stats) / threshold;
    if (ratio < 0) return 0;
    if (ratio > 1) return 1;
    return ratio;
  }
}

/// The unit suffix used for progress captions per dimension.
String achievementUnitLabel(AchievementDimension d) {
  switch (d) {
    case AchievementDimension.recordings:
      return 'recordings';
    case AchievementDimension.words:
      return 'words';
    case AchievementDimension.streak:
      return 'days';
    case AchievementDimension.timeSaved:
      return 'min';
    case AchievementDimension.activeDays:
      return 'days';
  }
}

/// Human-readable progress caption such as "1,234 / 5,000 words" or
/// "45 / 100 min".
String achievementProgressCaption(Achievement a, UsageStats stats) {
  final value = a.valueFor(stats);
  final unit = achievementUnitLabel(a.dimension);
  String fmt(double v) {
    final n = v.round();
    return n.toString().replaceAllMapped(
          RegExp(r'\B(?=(\d{3})+(?!\d))'),
          (m) => ',',
        );
  }

  final shown = value > a.threshold ? a.threshold : value;
  final suffix = unit.isEmpty ? '' : ' $unit';
  return '${fmt(shown)} / ${fmt(a.threshold)}$suffix';
}

/// The full milestone ladder — 12 seals across 5 dimensions, ordered so each
/// dimension ramps from easiest to hardest.
const List<Achievement> kUsageAchievements = [
  Achievement(
    id: 'first_steps',
    title: 'First Steps',
    subtitle: 'Make your first recording',
    dimension: AchievementDimension.recordings,
    threshold: 1,
    glyph: AchievementGlyph.firstSteps,
  ),
  Achievement(
    id: 'getting_warm',
    title: 'Getting Warmed Up',
    subtitle: 'Reach 25 recordings',
    dimension: AchievementDimension.recordings,
    threshold: 25,
    glyph: AchievementGlyph.rising,
  ),
  Achievement(
    id: 'century',
    title: 'Centurion',
    subtitle: 'Reach 100 recordings',
    dimension: AchievementDimension.recordings,
    threshold: 100,
    glyph: AchievementGlyph.century,
  ),
  Achievement(
    id: 'first_words',
    title: 'First Words',
    subtitle: 'Speak your first 500 words',
    dimension: AchievementDimension.words,
    threshold: 500,
    glyph: AchievementGlyph.firstWords,
  ),
  Achievement(
    id: 'wordsmith',
    title: 'Wordsmith',
    subtitle: 'Reach 5,000 words',
    dimension: AchievementDimension.words,
    threshold: 5000,
    glyph: AchievementGlyph.wordsmith,
  ),
  Achievement(
    id: 'storyteller',
    title: 'Storyteller',
    subtitle: 'Reach 25,000 words',
    dimension: AchievementDimension.words,
    threshold: 25000,
    glyph: AchievementGlyph.storyteller,
  ),
  Achievement(
    id: 'prolific',
    title: 'Prolific',
    subtitle: 'Reach 100,000 words',
    dimension: AchievementDimension.words,
    threshold: 100000,
    glyph: AchievementGlyph.prolific,
  ),
  Achievement(
    id: 'momentum',
    title: 'Momentum',
    subtitle: 'Keep a 3-day streak',
    dimension: AchievementDimension.streak,
    threshold: 3,
    glyph: AchievementGlyph.momentum,
  ),
  Achievement(
    id: 'week_strong',
    title: 'Week Strong',
    subtitle: 'Keep a 7-day streak',
    dimension: AchievementDimension.streak,
    threshold: 7,
    glyph: AchievementGlyph.weekStrong,
  ),
  Achievement(
    id: 'unbroken',
    title: 'Unbroken',
    subtitle: 'Keep a 30-day streak',
    dimension: AchievementDimension.streak,
    threshold: 30,
    glyph: AchievementGlyph.unbroken,
  ),
  Achievement(
    id: 'time_keeper',
    title: 'Time Keeper',
    subtitle: 'Save 1 hour of typing',
    dimension: AchievementDimension.timeSaved,
    threshold: 60,
    glyph: AchievementGlyph.timeKeeper,
  ),
  Achievement(
    id: 'consistent',
    title: 'Consistent',
    subtitle: 'Be active on 30 separate days',
    dimension: AchievementDimension.activeDays,
    threshold: 30,
    glyph: AchievementGlyph.consistent,
  ),
];
