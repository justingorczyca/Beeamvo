import 'package:beeamvo/models/usage_achievements.dart';
import 'package:beeamvo/models/usage_stats.dart';
import 'package:flutter_test/flutter_test.dart';

UsageStats _stats({
  int words = 0,
  int recordings = 0,
  int longestStreak = 0,
  Map<String, int>? daily,
}) {
  return UsageStats(
    totalWords: words,
    totalRecordings: recordings,
    longestStreak: longestStreak,
    dailyWordCount: daily ?? const {},
  );
}

Achievement _byId(String id) =>
    kUsageAchievements.firstWhere((a) => a.id == id);

void main() {
  group('Achievement ladder', () {
    test('has 12 unique achievements', () {
      expect(kUsageAchievements.length, 12);
      final ids = kUsageAchievements.map((a) => a.id).toSet();
      expect(ids.length, 12);
    });

    test('all thresholds are positive', () {
      for (final a in kUsageAchievements) {
        expect(a.threshold, greaterThan(0), reason: a.id);
      }
    });
  });

  group('progress + unlock logic', () {
    test('recordings dimension unlocks at threshold and clamps progress', () {
      final firstSteps = _byId('first_steps');
      expect(firstSteps.dimension, AchievementDimension.recordings);

      expect(firstSteps.isUnlocked(_stats(recordings: 0)), isFalse);
      expect(firstSteps.progress(_stats(recordings: 0)), 0);

      // Exactly at threshold → unlocked + full.
      expect(firstSteps.isUnlocked(_stats(recordings: 1)), isTrue);
      expect(firstSteps.progress(_stats(recordings: 1)), 1);

      // Above threshold stays clamped at 1.
      expect(firstSteps.progress(_stats(recordings: 99)), 1);
    });

    test('words dimension reports a mid progress ratio', () {
      final firstWords = _byId('first_words'); // threshold 500
      expect(firstWords.progress(_stats(words: 250)), 0.5);
      expect(firstWords.isUnlocked(_stats(words: 250)), isFalse);
      expect(firstWords.isUnlocked(_stats(words: 500)), isTrue);
    });

    test('streak dimension measures longestStreak', () {
      final unbroken = _byId('unbroken'); // threshold 30
      expect(unbroken.progress(_stats(longestStreak: 7)), closeTo(7 / 30, 1e-9));
      expect(unbroken.isUnlocked(_stats(longestStreak: 30)), isTrue);
    });

    test('activeDays dimension uses totalSessionDays', () {
      final consistent = _byId('consistent'); // threshold 30
      final stats = _stats(daily: {
        '2025-01-01': 10,
        '2025-01-02': 5,
        '2025-01-03': 0, // counts as an active day (key present)
      });
      expect(stats.totalSessionDays, 3);
      expect(consistent.progress(stats), closeTo(3 / 30, 1e-9));
      expect(consistent.isUnlocked(stats), isFalse);
    });

    test('timeSaved dimension derives from totalWords / 40 WPM', () {
      final timeKeeper = _byId('time_keeper'); // threshold 60 minutes
      // 2400 words / 40 = 60 minutes exactly.
      final stats = _stats(words: 2400);
      expect(timeKeeper.valueFor(stats), 60);
      expect(timeKeeper.isUnlocked(stats), isTrue);
      expect(timeKeeper.isUnlocked(_stats(words: 2399)), isFalse);
    });
  });

  group('progress caption formatting', () {
    test('formats value / threshold with the dimension unit', () {
      final firstWords = _byId('first_words'); // 500 words
      expect(
        achievementProgressCaption(firstWords, _stats(words: 250)),
        '250 / 500 words',
      );
    });

    test('caps the shown value at the threshold', () {
      final prolific = _byId('prolific'); // 100,000 words
      expect(
        achievementProgressCaption(prolific, _stats(words: 999999)),
        '100,000 / 100,000 words',
      );
    });

    test('renders thousand separators', () {
      final storyteller = _byId('storyteller'); // 25,000 words
      expect(
        achievementProgressCaption(storyteller, _stats(words: 1500)),
        '1,500 / 25,000 words',
      );
    });
  });
}
