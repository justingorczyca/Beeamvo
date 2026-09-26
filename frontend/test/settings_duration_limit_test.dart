import 'package:beeamvo/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SettingsService duration limit clamping', () {
    test('getters do not throw when uninitialized (in-memory defaults)', () {
      final settings = SettingsService();
      // Auto-stop is off by default; the value still resolves to a safe default.
      expect(settings.durationLimitEnabled, isFalse);
      expect(settings.durationLimit, 300);
    });

    test('clampDurationLimit maps out-of-range values into [5, 3600]', () {
      // Values below the UI minimum collapse to the smallest accepted value so
      // a corrupt/legacy persisted value can never arm a Duration(seconds: 0)
      // timer that would stop a recording the instant it starts.
      expect(SettingsService.clampDurationLimit(0), 5);
      expect(SettingsService.clampDurationLimit(-5), 5);
      expect(SettingsService.clampDurationLimit(1), 5);
      expect(SettingsService.clampDurationLimit(4), 5);

      // Values above the UI maximum collapse to the largest accepted value so an
      // absurd hand-edited value (e.g. multi-day) cannot become the cap.
      expect(SettingsService.clampDurationLimit(3601), 3600);
      expect(SettingsService.clampDurationLimit(9999999), 3600);
    });

    test('clampDurationLimit preserves values already inside [5, 3600]', () {
      expect(SettingsService.clampDurationLimit(5), 5);
      expect(SettingsService.clampDurationLimit(300), 300);
      expect(SettingsService.clampDurationLimit(3600), 3600);
    });

    test('Boundary constants match the duration-limit dialog contract', () {
      // These bounds are duplicated from general_settings_page.dart's duration
      // dialog; locking them here catches accidental drift between the UI guard
      // and the persisted-value guard.
      expect(SettingsService.minDurationLimitSeconds, 5);
      expect(SettingsService.maxDurationLimitSeconds, 3600);
    });
  });
}
