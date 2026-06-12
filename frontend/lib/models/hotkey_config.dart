import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'dart:convert';

/// Represents a global hotkey configuration.
///
/// Encapsulates key + modifiers with serialization support.
class HotkeyConfig {
  final LogicalKeyboardKey key;
  final Set<HotKeyModifier> modifiers;

  const HotkeyConfig({required this.key, required this.modifiers});

  /// Default hotkey: Ctrl + Shift + V
  static const HotkeyConfig defaultHotkey = HotkeyConfig(
    key: LogicalKeyboardKey.keyV,
    modifiers: {HotKeyModifier.control, HotKeyModifier.shift},
  );

  /// Default clipboard popup hotkey: Ctrl + Shift + H
  static const HotkeyConfig defaultClipboardPopupHotkey = HotkeyConfig(
    key: LogicalKeyboardKey.keyH,
    modifiers: {HotKeyModifier.control, HotKeyModifier.shift},
  );

  /// Default mode selection hotkey: Ctrl + Shift + M
  static const HotkeyConfig defaultModeSelectionHotkey = HotkeyConfig(
    key: LogicalKeyboardKey.keyM,
    modifiers: {HotKeyModifier.control, HotKeyModifier.shift},
  );

  /// Human-readable display string (e.g., "Ctrl + Shift + V")
  String get displayString {
    final parts = <String>[];

    if (modifiers.contains(HotKeyModifier.control)) parts.add('Ctrl');
    if (modifiers.contains(HotKeyModifier.alt)) parts.add('Alt');
    if (modifiers.contains(HotKeyModifier.shift)) parts.add('Shift');
    if (modifiers.contains(HotKeyModifier.meta)) {
      parts.add('Win'); // Windows key
    }

    parts.add(_keyLabel(key));
    return parts.join(' + ');
  }

  /// Get readable label for a key
  static String _keyLabel(LogicalKeyboardKey key) {
    // Handle letter keys
    if (key.keyId >= LogicalKeyboardKey.keyA.keyId &&
        key.keyId <= LogicalKeyboardKey.keyZ.keyId) {
      return String.fromCharCode(
        'A'.codeUnitAt(0) + (key.keyId - LogicalKeyboardKey.keyA.keyId),
      );
    }

    // Handle number keys
    if (key.keyId >= LogicalKeyboardKey.digit0.keyId &&
        key.keyId <= LogicalKeyboardKey.digit9.keyId) {
      return String.fromCharCode(
        '0'.codeUnitAt(0) + (key.keyId - LogicalKeyboardKey.digit0.keyId),
      );
    }

    // Handle F-keys
    if (key.keyId >= LogicalKeyboardKey.f1.keyId &&
        key.keyId <= LogicalKeyboardKey.f12.keyId) {
      return 'F${1 + (key.keyId - LogicalKeyboardKey.f1.keyId)}';
    }

    // Common special keys
    final specialKeys = {
      LogicalKeyboardKey.space: 'Space',
      LogicalKeyboardKey.enter: 'Enter',
      LogicalKeyboardKey.tab: 'Tab',
      LogicalKeyboardKey.escape: 'Esc',
      LogicalKeyboardKey.backspace: 'Backspace',
      LogicalKeyboardKey.delete: 'Delete',
      LogicalKeyboardKey.insert: 'Insert',
      LogicalKeyboardKey.home: 'Home',
      LogicalKeyboardKey.end: 'End',
      LogicalKeyboardKey.pageUp: 'Page Up',
      LogicalKeyboardKey.pageDown: 'Page Down',
      LogicalKeyboardKey.arrowUp: '↑',
      LogicalKeyboardKey.arrowDown: '↓',
      LogicalKeyboardKey.arrowLeft: '←',
      LogicalKeyboardKey.arrowRight: '→',
      LogicalKeyboardKey.numpad0: 'Num 0',
      LogicalKeyboardKey.numpad1: 'Num 1',
      LogicalKeyboardKey.numpad2: 'Num 2',
      LogicalKeyboardKey.numpad3: 'Num 3',
      LogicalKeyboardKey.numpad4: 'Num 4',
      LogicalKeyboardKey.numpad5: 'Num 5',
      LogicalKeyboardKey.numpad6: 'Num 6',
      LogicalKeyboardKey.numpad7: 'Num 7',
      LogicalKeyboardKey.numpad8: 'Num 8',
      LogicalKeyboardKey.numpad9: 'Num 9',
      LogicalKeyboardKey.minus: '-',
      LogicalKeyboardKey.equal: '=',
      LogicalKeyboardKey.bracketLeft: '[',
      LogicalKeyboardKey.bracketRight: ']',
      LogicalKeyboardKey.semicolon: ';',
      LogicalKeyboardKey.quote: "'",
      LogicalKeyboardKey.backquote: '`',
      LogicalKeyboardKey.comma: ',',
      LogicalKeyboardKey.period: '.',
      LogicalKeyboardKey.slash: '/',
      LogicalKeyboardKey.backslash: '\\',
    };

    return specialKeys[key] ?? key.keyLabel;
  }

  /// Serialize to JSON string for persistence
  String toJson() {
    return jsonEncode({
      'keyId': key.keyId,
      'keyLabel': key.keyLabel,
      'modifiers': modifiers.map((m) => m.name).toList(),
    });
  }

  /// Deserialize from JSON string
  factory HotkeyConfig.fromJson(String jsonStr) {
    try {
      final map = jsonDecode(jsonStr) as Map<String, dynamic>;
      final keyId = map['keyId'] as int;
      final modifierNames = (map['modifiers'] as List).cast<String>();

      // Try to find key by ID first
      LogicalKeyboardKey? foundKey = LogicalKeyboardKey.findKeyByKeyId(keyId);

      // If not found by ID, try to reconstruct from common keys
      foundKey ??= _findKeyByIdFallback(keyId);

      // If still null, log and return default
      if (foundKey == null) {
        debugPrint(
          'HotkeyConfig: Could not find key for keyId=$keyId, using default',
        );
        return defaultHotkey;
      }

      final modifiers = modifierNames
          .map(_modifierFromName)
          .whereType<HotKeyModifier>()
          .toSet();

      // Validate we have at least one modifier
      if (modifiers.isEmpty) {
        debugPrint('HotkeyConfig: No valid modifiers found, using default');
        return defaultHotkey;
      }

      return HotkeyConfig(key: foundKey, modifiers: modifiers);
    } catch (e) {
      debugPrint('HotkeyConfig: Error parsing JSON: $e');
      return defaultHotkey;
    }
  }

  /// Fallback key lookup for common keys that might not be found by findKeyByKeyId
  static LogicalKeyboardKey? _findKeyByIdFallback(int keyId) {
    // Common letter keys (A-Z)
    if (keyId >= LogicalKeyboardKey.keyA.keyId &&
        keyId <= LogicalKeyboardKey.keyZ.keyId) {
      final offset = keyId - LogicalKeyboardKey.keyA.keyId;
      final keys = [
        LogicalKeyboardKey.keyA,
        LogicalKeyboardKey.keyB,
        LogicalKeyboardKey.keyC,
        LogicalKeyboardKey.keyD,
        LogicalKeyboardKey.keyE,
        LogicalKeyboardKey.keyF,
        LogicalKeyboardKey.keyG,
        LogicalKeyboardKey.keyH,
        LogicalKeyboardKey.keyI,
        LogicalKeyboardKey.keyJ,
        LogicalKeyboardKey.keyK,
        LogicalKeyboardKey.keyL,
        LogicalKeyboardKey.keyM,
        LogicalKeyboardKey.keyN,
        LogicalKeyboardKey.keyO,
        LogicalKeyboardKey.keyP,
        LogicalKeyboardKey.keyQ,
        LogicalKeyboardKey.keyR,
        LogicalKeyboardKey.keyS,
        LogicalKeyboardKey.keyT,
        LogicalKeyboardKey.keyU,
        LogicalKeyboardKey.keyV,
        LogicalKeyboardKey.keyW,
        LogicalKeyboardKey.keyX,
        LogicalKeyboardKey.keyY,
        LogicalKeyboardKey.keyZ,
      ];
      if (offset >= 0 && offset < keys.length) {
        return keys[offset];
      }
    }

    // Number keys (0-9)
    if (keyId >= LogicalKeyboardKey.digit0.keyId &&
        keyId <= LogicalKeyboardKey.digit9.keyId) {
      final offset = keyId - LogicalKeyboardKey.digit0.keyId;
      final keys = [
        LogicalKeyboardKey.digit0,
        LogicalKeyboardKey.digit1,
        LogicalKeyboardKey.digit2,
        LogicalKeyboardKey.digit3,
        LogicalKeyboardKey.digit4,
        LogicalKeyboardKey.digit5,
        LogicalKeyboardKey.digit6,
        LogicalKeyboardKey.digit7,
        LogicalKeyboardKey.digit8,
        LogicalKeyboardKey.digit9,
      ];
      if (offset >= 0 && offset < keys.length) {
        return keys[offset];
      }
    }

    // F-keys
    if (keyId >= LogicalKeyboardKey.f1.keyId &&
        keyId <= LogicalKeyboardKey.f12.keyId) {
      final offset = keyId - LogicalKeyboardKey.f1.keyId;
      final keys = [
        LogicalKeyboardKey.f1,
        LogicalKeyboardKey.f2,
        LogicalKeyboardKey.f3,
        LogicalKeyboardKey.f4,
        LogicalKeyboardKey.f5,
        LogicalKeyboardKey.f6,
        LogicalKeyboardKey.f7,
        LogicalKeyboardKey.f8,
        LogicalKeyboardKey.f9,
        LogicalKeyboardKey.f10,
        LogicalKeyboardKey.f11,
        LogicalKeyboardKey.f12,
      ];
      if (offset >= 0 && offset < keys.length) {
        return keys[offset];
      }
    }

    // Common special keys
    final specialKeyMap = <int, LogicalKeyboardKey>{
      LogicalKeyboardKey.space.keyId: LogicalKeyboardKey.space,
      LogicalKeyboardKey.enter.keyId: LogicalKeyboardKey.enter,
      LogicalKeyboardKey.tab.keyId: LogicalKeyboardKey.tab,
      LogicalKeyboardKey.backspace.keyId: LogicalKeyboardKey.backspace,
    };

    return specialKeyMap[keyId];
  }

  static HotKeyModifier? _modifierFromName(String name) {
    switch (name) {
      case 'control':
        return HotKeyModifier.control;
      case 'alt':
        return HotKeyModifier.alt;
      case 'shift':
        return HotKeyModifier.shift;
      case 'meta':
        return HotKeyModifier.meta;
      default:
        return null;
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! HotkeyConfig) return false;
    return key.keyId == other.key.keyId &&
        modifiers.length == other.modifiers.length &&
        modifiers.every((m) => other.modifiers.contains(m));
  }

  @override
  int get hashCode =>
      Object.hash(key.keyId, Object.hashAllUnordered(modifiers));
}
