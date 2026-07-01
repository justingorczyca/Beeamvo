import 'package:beeamvo/providers/settings_provider.dart';
import 'package:beeamvo/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression test for the SettingsService → SettingsProvider notification
/// relay.
///
/// Bug: `SettingsProvider` stored the `SettingsService` but never added itself
/// as a listener, so `SettingsProviderScope` (an InheritedNotifier over the
/// provider) never rebuilt when persisted settings changed — defeating the
/// provider abstraction. The constructor now forwards service notifications.
void main() {
  group('SettingsProvider notification relay', () {
    test('relays SettingsService changes to its own listeners', () {
      final service = SettingsService();
      final provider = SettingsProvider(settingsService: service);

      var notifyCount = 0;
      provider.addListener(() => notifyCount++);

      // A change driven through the underlying service must propagate to the
      // provider's listeners (the part that was previously broken).
      service.notifyListeners();
      expect(notifyCount, greaterThan(0));
    });

    test('stops relaying after dispose', () {
      final service = SettingsService();
      final provider = SettingsProvider(settingsService: service);

      var notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.dispose();
      final before = notifyCount;
      service.notifyListeners();
      expect(notifyCount, before);
    });
  });
}
