import 'dart:convert';
import 'dart:io';

import 'package:beeamvo/services/settings_service.dart';
import 'package:beeamvo/services/secure_credential_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/package_info'),
        (call) async => {
          'appName': 'Beeamvo',
          'packageName': 'com.beeamvo.app',
          'version': '1.0.0',
          'buildNumber': '1',
          'buildSignature': '',
          'installerStore': '',
        },
      );

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

  test(
    'mobile history default applies only when the preference is absent',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'beeamvo-mobile-history-',
      );
      final settings = SettingsService(
        applicationSupportDirectory: root,
        credentialStore: InMemorySecureCredentialStore(),
      );
      final file = File('${root.path}/Beeamvo/settings.json');
      try {
        await settings.initialize();
        await settings.addClipboardEntry('before mobile default');
        expect(settings.clipboardHistory, isEmpty);
        var persisted = jsonDecode(await file.readAsString());
        expect(persisted['clipboard_history_items'], isNull);

        await settings.applyMobileDefaults();
        await settings.addClipboardEntry('after mobile default');
        expect(settings.clipboardHistory.single.text, 'after mobile default');
        persisted = jsonDecode(await file.readAsString());
        expect(persisted['clipboard_history_enabled'], isTrue);
        final items =
            jsonDecode(persisted['clipboard_history_items'] as String)
                as List<dynamic>;
        expect(items, hasLength(1));

        await settings.setClipboardHistoryEnabled(false);
        await settings.applyMobileDefaults();
        expect(settings.clipboardHistoryEnabled, isFalse);
      } finally {
        settings.dispose();
        await root.delete(recursive: true);
      }
    },
  );

  test('macOS launch approval status keeps launch at startup enabled', () {
    expect(SettingsService.launchAtStartupStatusIsEnabled('enabled'), isTrue);
    expect(
      SettingsService.launchAtStartupStatusIsEnabled('requiresApproval'),
      isTrue,
    );
    expect(SettingsService.launchAtStartupStatusIsEnabled('disabled'), isFalse);
  });
}
