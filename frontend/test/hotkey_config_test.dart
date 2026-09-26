import 'package:beeamvo/models/hotkey_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// Regression tests for the `HotkeyConfig.fromJson` fallback default.
///
/// Bug: `fromJson` used to hardcode `defaultHotkey` (Ctrl+Shift+V) for *every*
/// caller. A corrupt value for the clipboard-popup or mode-selection hotkey
/// was therefore silently rebound onto the main dictate hotkey, so two
/// distinct actions collided on one combo. The factory now takes the
/// action-appropriate `defaultTo`.
void main() {
  group('HotkeyConfig.fromJson fallback default', () {
    test('returns the caller-provided default for malformed JSON', () {
      final result = HotkeyConfig.fromJson(
        '{not valid json',
        defaultTo: HotkeyConfig.defaultClipboardPopupHotkey,
      );
      expect(result, equals(HotkeyConfig.defaultClipboardPopupHotkey));
      expect(result, isNot(equals(HotkeyConfig.defaultHotkey)));
    });

    test('returns the caller-provided default for an unknown key id', () {
      final bad = '{"keyId":9999999,"modifiers":["control","shift"]}';
      final result = HotkeyConfig.fromJson(
        bad,
        defaultTo: HotkeyConfig.defaultModeSelectionHotkey,
      );
      expect(result, equals(HotkeyConfig.defaultModeSelectionHotkey));
      expect(result, isNot(equals(HotkeyConfig.defaultHotkey)));
    });

    test('returns the caller-provided default when modifiers are missing', () {
      final bad = '{"keyId":86,"modifiers":[]}';
      final result = HotkeyConfig.fromJson(
        bad,
        defaultTo: HotkeyConfig.defaultModeSelectionHotkey,
      );
      expect(result, equals(HotkeyConfig.defaultModeSelectionHotkey));
    });

    test('the three default actions use distinct keys', () {
      // Guard against a regression where a fallback rebinds to the main key.
      final mainKey = HotkeyConfig.defaultHotkey.key.keyId;
      final clipboardKey = HotkeyConfig.defaultClipboardPopupHotkey.key.keyId;
      final modeKey = HotkeyConfig.defaultModeSelectionHotkey.key.keyId;
      expect(clipboardKey, isNot(equals(mainKey)));
      expect(modeKey, isNot(equals(mainKey)));
      expect(clipboardKey, isNot(equals(modeKey)));
    });

    test('parses a well-formed value regardless of provided default', () {
      final source = HotkeyConfig.defaultClipboardPopupHotkey;
      final result = HotkeyConfig.fromJson(
        source.toJson(),
        defaultTo: HotkeyConfig.defaultHotkey,
      );
      expect(result, equals(source));
      expect(result, isNot(equals(HotkeyConfig.defaultHotkey)));
    });
  });
}
