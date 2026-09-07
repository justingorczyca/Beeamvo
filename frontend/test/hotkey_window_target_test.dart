import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win32/win32.dart';

void main() {
  test(
    'hotkey plugin receives the runner HWND instead of an unattached view',
    () {
      final runner = File(
        'windows/runner/flutter_window.cpp',
      ).readAsStringSync();
      final plugin = File(
        'windows/runner/hotkey_plugin.cpp',
      ).readAsStringSync();
      expect(
        RegExp(
          r'HotkeyPlugin::RegisterWithRegistrar\([\s\S]*?GetHandle\(\)\s*\)',
        ).hasMatch(runner),
        isTrue,
      );
      expect(plugin, contains('window_(window)'));
      expect(plugin, isNot(contains('window_(GetAncestor')));
    },
  );

  test('Win32 keeps hotkeys bound to the original HWND after reparenting', () {
    final className = 'STATIC'.toNativeUtf16(allocator: calloc);
    var parent = 0;
    var child = 0;
    const id = 1;
    const modifiers = MOD_CONTROL | MOD_ALT | MOD_SHIFT | MOD_NOREPEAT;
    try {
      parent = CreateWindowEx(
        0,
        className,
        nullptr,
        WS_POPUP,
        0,
        0,
        1,
        1,
        0,
        0,
        0,
        nullptr,
      );
      child = CreateWindowEx(
        0,
        className,
        nullptr,
        WS_POPUP,
        0,
        0,
        1,
        1,
        0,
        0,
        0,
        nullptr,
      );
      expect(parent, isNot(0));
      expect(child, isNot(0));
      final prematurelyCapturedRoot = GetAncestor(child, GA_ROOT);
      expect(prematurelyCapturedRoot, child);

      SetParent(child, parent);
      expect(GetAncestor(child, GA_ROOT), parent);
      expect(
        RegisterHotKey(prematurelyCapturedRoot, id, modifiers, VK_F24),
        isNot(0),
      );
      expect(UnregisterHotKey(parent, id), 0);
      expect(UnregisterHotKey(child, id), isNot(0));

      expect(RegisterHotKey(parent, id, modifiers, VK_F24), isNot(0));
      expect(UnregisterHotKey(parent, id), isNot(0));
    } finally {
      if (child != 0) {
        UnregisterHotKey(child, id);
        DestroyWindow(child);
      }
      if (parent != 0) {
        UnregisterHotKey(parent, id);
        DestroyWindow(parent);
      }
      calloc.free(className);
    }
  }, skip: !Platform.isWindows);
}
