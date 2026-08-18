import 'package:beeamvo/services/settings_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SettingsService privacy defaults', () {
    test('clipboard history and watcher default off for new users', () {
      final settings = SettingsService();

      expect(settings.clipboardHistoryEnabled, isFalse);
      expect(settings.clipboardWatcherEnabled, isFalse);
    });

    test('auto-paste remains enabled by default for the hotkey workflow', () {
      final settings = SettingsService();

      expect(settings.autoPasteEnabled, isTrue);
    });
  });

  group('clipboard history sensitive text filter', () {
    test('allows ordinary clipboard text', () {
      expect(
        SettingsService.shouldSkipClipboardHistoryText(
          'Please send the release notes after lunch.',
        ),
        isFalse,
      );
    });

    test('skips obvious secret assignments and tokens', () {
      // Build scanner-shaped strings at runtime so repository secret scanners
      // do not flag these intentionally fake privacy-filter fixtures.
      final samples = [
        'api_${'key'} = "${'sk'}-testkey12345678901234567890"',
        'pass${'word'}: correct-horse-battery-staple',
        'Authorization: ${'Bearer'} abcdefghijklmnopqrstuvwxyz123456',
        'github_${'pat'}_1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ',
        '${'eyJ'}aaaaaaaaaa.bbbbbbbbbb.cccccccccc',
        '-----BEGIN ${'PRIVATE'} KEY-----',
      ];

      for (final sample in samples) {
        expect(
          SettingsService.shouldSkipClipboardHistoryText(sample),
          isTrue,
          reason: sample,
        );
      }
    });
  });

  test('Gemini API surface defaults to legacy and persists changes', () async {
    final settings = SettingsService();
    expect(settings.geminiApiSurface, equals(GeminiApiSurface.generateContent));

    await settings.setGeminiApiSurface(GeminiApiSurface.interactions);
    expect(settings.geminiApiSurface, equals(GeminiApiSurface.interactions));
  });

  test('macOS launch approval status keeps launch at startup enabled', () {
    expect(SettingsService.launchAtStartupStatusIsEnabled('enabled'), isTrue);
    expect(
      SettingsService.launchAtStartupStatusIsEnabled('requiresApproval'),
      isTrue,
    );
    expect(SettingsService.launchAtStartupStatusIsEnabled('disabled'), isFalse);
  });
}
