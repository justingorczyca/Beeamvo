import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Service for managing global hotkeys
/// 
/// Handles registration and callbacks for system-wide keyboard shortcuts.
class HotkeyService {
  final HotKeyManager _hotKeyManager = HotKeyManager.instance;
  final Map<String, HotKey> _hotkeys = {};

  /// Register a global hotkey
  /// 
  /// [onPressed] is called when the hotkey is pressed down.
  /// [onReleased] is called when the hotkey is released (for hold-to-record mode).
  Future<void> registerHotkey({
    required String id,
    required LogicalKeyboardKey key,
    List<HotKeyModifier> modifiers = const [],
    required Function() onPressed,
    Function()? onReleased,
  }) async {
    await unregisterHotkey(id);

    final hotkey = HotKey(
      key: key,
      modifiers: modifiers,
      scope: HotKeyScope.system,
    );

    _hotkeys[id] = hotkey;

    debugPrint('HotkeyService: Registering hotkey id=$id, key=${key.keyLabel} (keyId=${key.keyId}), modifiers=$modifiers');

    try {
      await _hotKeyManager.register(
        hotkey,
        keyDownHandler: (hk) {
          debugPrint('HotkeyService: Key DOWN detected for id=$id');
          onPressed();
        },
        keyUpHandler: (hk) {
          debugPrint('HotkeyService: Key UP detected for id=$id');
          if (onReleased != null) {
            onReleased();
          }
        },
      );
      debugPrint('HotkeyService: Successfully registered hotkey id=$id');
    } catch (e) {
      debugPrint('HotkeyService: Failed to register hotkey id=$id: $e');
      rethrow;
    }
  }

  /// Unregister a specific hotkey
  Future<void> unregisterHotkey(String id) async {
    final hotkey = _hotkeys.remove(id);
    if (hotkey != null) {
      await _hotKeyManager.unregister(hotkey);
    }
  }

  /// Unregister all hotkeys
  Future<void> unregisterAll() async {
    for (final id in _hotkeys.keys.toList()) {
      await unregisterHotkey(id);
    }
  }

  /// Check if a hotkey is registered
  bool isRegistered(String id) => _hotkeys.containsKey(id);

  /// Dispose and cleanup
  Future<void> dispose() async {
    await unregisterAll();
  }
}
