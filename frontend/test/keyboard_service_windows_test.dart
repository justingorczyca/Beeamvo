import 'dart:ffi';

import 'package:beeamvo/services/keyboard_service_windows.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win32/win32.dart';

void main() {
  testWidgets(
    'immediate paste sends modifier releases and Ctrl+V without waiting',
    (tester) async {
      final events = <(int, int)>[];
      var calls = 0;
      final paste = simulateCtrlVWindows(
        waitForModifiers: false,
        sendInput: (count, inputs, size) {
          calls++;
          expectSync(size, sizeOf<INPUT>());
          for (var i = 0; i < count; i++) {
            expectSync(inputs[i].type, INPUT_KEYBOARD);
            events.add((
              inputs[i].Anonymous.ki.wVk,
              inputs[i].Anonymous.ki.dwFlags,
            ));
          }
          return count;
        },
      );

      final callsBeforeAdvancingTime = calls;
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 50));
      await paste;
      expect(callsBeforeAdvancingTime, 1);
      expect(calls, 1);
      expect(events, [
        (VK_LCONTROL, KEYEVENTF_KEYUP),
        (VK_RCONTROL, KEYEVENTF_KEYUP),
        (VK_LMENU, KEYEVENTF_KEYUP),
        (VK_RMENU, KEYEVENTF_KEYUP),
        (VK_LSHIFT, KEYEVENTF_KEYUP),
        (VK_RSHIFT, KEYEVENTF_KEYUP),
        (VK_LWIN, KEYEVENTF_KEYUP),
        (VK_RWIN, KEYEVENTF_KEYUP),
        (VK_CONTROL, 0),
        (0x56, 0),
        (0x56, KEYEVENTF_KEYUP),
        (VK_CONTROL, KEYEVENTF_KEYUP),
      ]);
    },
  );

  testWidgets('failed immediate SendInput surfaces an error without retrying', (
    tester,
  ) async {
    var calls = 0;
    final paste = simulateCtrlVWindows(
      waitForModifiers: false,
      sendInput: (count, inputs, size) {
        calls++;
        return 0;
      },
    );
    final result = expectLater(paste, throwsException);
    await tester.pump(const Duration(milliseconds: 350));
    await result;
    expect(calls, 1);
  });

  testWidgets('callers can still request a modifier-release grace period', (
    tester,
  ) async {
    var calls = 0;
    final paste = simulateCtrlVWindows(
      sendInput: (count, inputs, size) {
        calls++;
        return count;
      },
    );
    expect(calls, 0);
    await tester.pump(const Duration(milliseconds: 299));
    expect(calls, 0);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 1);
    await tester.pump(const Duration(milliseconds: 50));
    await paste;
  });
}
