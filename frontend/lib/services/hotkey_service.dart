import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thrown when [HotkeyService.registerHotkey] is asked to bind a
/// `{key + modifiers}` combination that a *different* id already holds.
///
/// **Note to callers:** consumers such as `main.dart`'s
/// `_registerMainHotkey` / `_registerClipboardPopupHotkey` /
/// `_registerModeSelectionHotkey` currently do **not** catch this exception,
/// so registering *can* throw a [HotkeyConflictException] when two configured
/// hotkeys resolve to the same key+modifiers. Treat such a throw as a
/// configuration error: the already-registered binding is left untouched and
/// the new registration is aborted. This type is exported (public) so callers
/// may catch it if they want to react gracefully.
class HotkeyConflictException implements Exception {
  /// Descriptive message, typically naming the already-bound combo and id.
  final String message;

  HotkeyConflictException(this.message);

  @override
  String toString() => 'HotkeyConflictException: $message';
}

/// Service for managing global hotkeys
///
/// Handles registration and callbacks for system-wide keyboard shortcuts.
///
/// ## Concurrency / serialization
/// Every register/unregister for a given `id` is serialized through a per-id
/// [Future] chain ([_locks]). Two concurrent `registerHotkey(id)` calls for the
/// *same* id therefore execute strictly one after another, so their
/// unregister→register sequences can never interleave. Distinct ids stay fully
/// concurrent.
///
/// ## Conflict detection
/// Before registering, the requested `{key + modifiers}` is compared against
/// all currently-registered hotkeys; binding a combo already owned by another
/// id throws [HotkeyConflictException]. Re-registering the *same* id is always
/// allowed (its old binding is removed first).
class HotkeyService {
  final HotKeyManager _hotKeyManager = HotKeyManager.instance;
  final Map<String, HotKey> _hotkeys = {};

  /// Per-id serialization chains. The stored [Future] is the tail of all work
  /// queued for that id and never propagates errors, so a failing op can't
  /// short-circuit later ops on the same id.
  final Map<String, Future<void>> _locks = {};

  /// Run [action] strictly after any earlier op queued for [id].
  Future<T> _withLock<T>(String id, Future<T> Function() action) {
    final previous = _locks[id] ?? Future<void>.value();
    // Execute the action only once the previous tail completes.
    final result = previous.then((_) => action());
    // Replace the tail with a future that never throws, so an error thrown by
    // [action] is reported to *this* caller (via [result]) but does not poison
    // the chain for subsequent ops on the same id.
    _locks[id] = result.then(
      (_) {},
      // ignore: only_used_errors / irrelevant param names
      onError: (Object e, StackTrace st) {},
    );
    return result;
  }

  /// Order-independent signature string for a `{key + modifiers}` combo. Two
  /// combos collide iff these strings are equal. Handles null/empty modifiers.
  static String _comboSignature(
    LogicalKeyboardKey key,
    List<HotKeyModifier>? modifiers,
  ) {
    final modNames =
        (modifiers ?? const <HotKeyModifier>[]).map((m) => m.name).toList()
          ..sort();
    return '${modNames.join(',')}#${key.keyId}';
  }

  /// Human-readable combo label (e.g. "Ctrl + Shift + V"), for logs & errors.
  static String _comboLabel(
    LogicalKeyboardKey key,
    List<HotKeyModifier>? modifiers,
  ) {
    final parts = <String>[];
    if (modifiers != null) {
      if (modifiers.contains(HotKeyModifier.control)) parts.add('Ctrl');
      if (modifiers.contains(HotKeyModifier.alt)) parts.add('Alt');
      if (modifiers.contains(HotKeyModifier.shift)) parts.add('Shift');
      if (modifiers.contains(HotKeyModifier.meta)) parts.add('Win');
    }
    parts.add(key.keyLabel);
    return parts.join(' + ');
  }

  /// Register a global hotkey
  ///
  /// [onPressed] is called when the hotkey is pressed down.
  /// [onReleased] is called when the hotkey is released (for hold-to-record mode).
  ///
  /// Re-registering an already-registered [id] first removes the old binding.
  /// Throws [HotkeyConflictException] if a *different* id already binds the
  /// same `{key + modifiers}`. On any registration failure the internal map is
  /// left untouched (no stale entry) — the internal binding is only recorded
  /// after [HotKeyManager.register] succeeds, and a failed registration is
  /// cleaned up defensively.
  Future<void> registerHotkey({
    required String id,
    required LogicalKeyboardKey key,
    List<HotKeyModifier> modifiers = const [],
    HotKeyScope scope = HotKeyScope.system,
    required Function() onPressed,
    Function()? onReleased,
  }) async {
    return _withLock(id, () async {
      // --- Cross-hotkey conflict detection (before any mutation) -----------
      final requested = _comboSignature(key, modifiers);
      for (final entry in _hotkeys.entries) {
        if (entry.key == id) continue; // refreshing the same id is allowed
        final existing = entry.value;
        if (_comboSignature(existing.logicalKey, existing.modifiers) ==
            requested) {
          throw HotkeyConflictException(
            'Hotkey "${_comboLabel(key, modifiers)}" is already bound to id '
            '"${entry.key}".',
          );
        }
      }

      // --- Remove any prior binding for this id ---------------------------
      await _unregisterInternal(id);

      final hotkey = HotKey(key: key, modifiers: modifiers, scope: scope);

      debugPrint(
        'HotkeyService: Registering hotkey id=$id, '
        'key=${key.keyLabel} (keyId=${key.keyId}), modifiers=$modifiers, '
        'scope=${scope.name}',
      );

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
        // Commit to the map ONLY after a successful registration so a failure
        // never leaves a stale/desynced entry.
        _hotkeys[id] = hotkey;
        debugPrint('HotkeyService: Successfully registered hotkey id=$id');
      } catch (e) {
        // Defensive: ensure no half-registered hotkey lingers in the OS.
        await _safeUnregister(hotkey);
        debugPrint('HotkeyService: Failed to register hotkey id=$id: $e');
        rethrow;
      }
    });
  }

  /// Unregister a specific hotkey.
  ///
  /// Idempotent: an unknown or already-removed id is a silent no-op. Errors
  /// from the underlying manager are swallowed so cleanup never throws at the
  /// call site (e.g. unregistering a never-registered id).
  Future<void> unregisterHotkey(String id) {
    return _withLock(id, () => _unregisterInternal(id));
  }

  /// Internal unregister that does NOT acquire the per-id lock. Safe to call
  /// from within an already-locked section (used by [registerHotkey]).
  Future<void> _unregisterInternal(String id) async {
    final hotkey = _hotkeys.remove(id);
    if (hotkey == null) return; // never registered → idempotent no-op
    await _safeUnregister(hotkey);
  }

  /// Best-effort unregister via the manager; never throws.
  Future<void> _safeUnregister(HotKey hotkey) async {
    try {
      await _hotKeyManager.unregister(hotkey);
    } catch (e) {
      debugPrint('HotkeyService: unregister ignored error: $e');
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
