import 'dart:async';

import 'package:beeamvo/services/hotkey_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

// These tests pin the contract that the recording session relies on for its
// bare Escape (cancel) / Enter (commit) keys. They guard against the
// regression tracked here, where those keys were briefly bound with
// HotKeyScope.inapp: the recording orb is shown WITHOUT OS keyboard focus, so
// inapp bindings (delivered through HardwareKeyboard, which only fires for the
// focused window) never received the keystrokes. The session keys must be
// HotKeyScope.system so the OS keyboard hook routes them regardless of which
// app is focused.

/// No-op platform so [HotKeyManager] can be exercised in the test zone without
/// a native plugin (the real method/event channels would otherwise raise
/// MissingPluginException on register/listen).
class _NoopHotKeyManagerPlatform extends HotKeyManagerPlatform {
  @override
  Stream<Map<Object?, Object?>> get onKeyEventReceiver =>
      const Stream<Map<Object?, Object?>>.empty();

  @override
  Future<void> register(HotKey hotKey) async {}

  @override
  Future<void> unregister(HotKey hotKey) async {}

  @override
  Future<void> unregisterAll() async {}
}

void main() {
  late HotkeyService service;

  setUp(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    // Install the no-op platform BEFORE [HotKeyManager.instance] is constructed
    // (a [HotkeyService] construction triggers that), so the constructor's
    // event-channel listener is inert.
    HotKeyManagerPlatform.instance = _NoopHotKeyManagerPlatform();
    // Reset any singleton state left by an earlier test.
    await HotKeyManager.instance.unregisterAll();
    service = HotkeyService();
  });

  group('recording-session Escape/Enter bindings', () {
    test(
      'cancel and commit register without conflicting with each other',
      () async {
        // Mirrors the pair registered in _startRecording.
        await service.registerHotkey(
          id: 'cancel',
          key: LogicalKeyboardKey.escape,
          scope: HotKeyScope.system,
          onPressed: () {},
        );
        await service.registerHotkey(
          id: 'commit',
          key: LogicalKeyboardKey.enter,
          scope: HotKeyScope.system,
          onPressed: () {},
        );

        expect(service.isRegistered('cancel'), isTrue);
        expect(service.isRegistered('commit'), isTrue);
      },
    );

    test(
      'session keys are GLOBAL/system scope so they fire without app focus',
      () async {
        await service.registerHotkey(
          id: 'cancel',
          key: LogicalKeyboardKey.escape,
          scope: HotKeyScope.system,
          onPressed: () {},
        );
        await service.registerHotkey(
          id: 'commit',
          key: LogicalKeyboardKey.enter,
          scope: HotKeyScope.system,
          onPressed: () {},
        );

        final registered = HotKeyManager.instance.registeredHotKeyList;
        final cancel = registered.firstWhere(
          (h) => h.logicalKey == LogicalKeyboardKey.escape,
        );
        final commit = registered.firstWhere(
          (h) => h.logicalKey == LogicalKeyboardKey.enter,
        );
        // The crux of this fix: inapp scope would be inert for the unfocused
        // recording orb, so these MUST be system/global.
        expect(cancel.scope, HotKeyScope.system);
        expect(commit.scope, HotKeyScope.system);
      },
    );

    test(
      're-registering an id replaces, never duplicates, the binding',
      () async {
        await service.registerHotkey(
          id: 'cancel',
          key: LogicalKeyboardKey.escape,
          scope: HotKeyScope.system,
          onPressed: () {},
        );
        // The same id may be re-registered on every recording.
        await service.registerHotkey(
          id: 'cancel',
          key: LogicalKeyboardKey.escape,
          scope: HotKeyScope.system,
          onPressed: () {},
        );

        // Exactly one Escape binding tracked by the manager (no duplicate
        // handlers → no double invocation of cancel).
        final escapeCount = HotKeyManager.instance.registeredHotKeyList
            .where((h) => h.logicalKey == LogicalKeyboardKey.escape)
            .length;
        expect(escapeCount, 1);
      },
    );

    test('stop/cancel unregister the session keys', () async {
      await service.registerHotkey(
        id: 'cancel',
        key: LogicalKeyboardKey.escape,
        scope: HotKeyScope.system,
        onPressed: () {},
      );
      await service.registerHotkey(
        id: 'commit',
        key: LogicalKeyboardKey.enter,
        scope: HotKeyScope.system,
        onPressed: () {},
      );

      // Mirrors _stopRecordingAndProcess / _cancelRecording cleanup.
      await service.unregisterHotkey('cancel');
      await service.unregisterHotkey('commit');

      expect(service.isRegistered('cancel'), isFalse);
      expect(service.isRegistered('commit'), isFalse);
      final remaining = HotKeyManager.instance.registeredHotKeyList
          .where(
            (h) =>
                h.logicalKey == LogicalKeyboardKey.escape ||
                h.logicalKey == LogicalKeyboardKey.enter,
          )
          .length;
      expect(remaining, 0);
    });
  });

  test(
    'conflict detection ignores scope: a bare key is single-occupancy',
    () async {
      // The recording 'cancel' (system Escape) and a popup-style 'mode_cancel'
      // (inapp Escape) collide because the signature does not include scope.
      // This is why the app unregisters one before registering the other — they
      // must never coexist. Asserting it here keeps that ordering invariant
      // explicit so someone cannot assume the scopes are independent.
      await service.registerHotkey(
        id: 'cancel',
        key: LogicalKeyboardKey.escape,
        scope: HotKeyScope.system,
        onPressed: () {},
      );

      await expectLater(
        service.registerHotkey(
          id: 'mode_cancel',
          key: LogicalKeyboardKey.escape,
          scope: HotKeyScope.inapp,
          onPressed: () {},
        ),
        throwsA(isA<HotkeyConflictException>()),
      );
    },
  );
}
