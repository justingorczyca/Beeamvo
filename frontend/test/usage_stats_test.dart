import 'package:beeamvo/models/usage_stats.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the shared-mutable `dailyWordCount` defect.
///
/// Bug: the field was typed `final Map<String,int>` but `fromMap`/`copyWith`
/// reused a *growable* map by reference, so mutating one instance's map (or
/// the view exposed via `toMap`) corrupted related instances. The map is now
/// always unmodifiable.
void main() {
  group('UsageStats.dailyWordCount immutability', () {
    test('fromMap produces an unmodifiable map', () {
      final stats = UsageStats.fromMap({
        'dailyWordCount': {'2025-01-01': 10, '2025-01-02': 20},
      });
      final daily = stats.dailyWordCount;
      expect(daily['2025-01-01'], 10);
      expect(() => daily['2025-01-09'] = 5, throwsUnsupportedError);
      expect(() => daily.clear(), throwsUnsupportedError);
    });

    test('copyWith does not share mutable state with the source', () {
      final stats = UsageStats.fromMap({
        'dailyWordCount': {'2025-01-01': 10},
      });
      final copy = stats.copyWith(totalWords: 5, dailyWordCount: {
        '2025-01-01': 10,
      });

      // Mutating the source's map view must be rejected…
      expect(
        () => stats.dailyWordCount['2025-01-01'] = 99,
        throwsUnsupportedError,
      );
      // …and must not affect the copy or vice-versa.
      expect(copy.dailyWordCount['2025-01-01'], 10);
      expect(stats.dailyWordCount['2025-01-01'], 10);
      // A map explicitly passed into copyWith is also frozen.
      expect(
        () => copy.dailyWordCount['2025-01-01'] = 1,
        throwsUnsupportedError,
      );
    });

    test('toMap exposes an unmodifiable daily map', () {
      final stats = UsageStats.fromMap({
        'dailyWordCount': {'2025-01-01': 1},
      });
      final daily = stats.toMap()['dailyWordCount'] as Map<String, int>;
      expect(() => daily['x'] = 1, throwsUnsupportedError);
    });
  });
}
