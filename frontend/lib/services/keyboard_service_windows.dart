import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Virtual key code for 'V'
const int _vkV = 0x56;

/// Modifier virtual-key codes whose KEYUP events are released *before*
/// synthesizing Ctrl+V, so a user still holding a hotkey modifier (e.g. from a
/// Ctrl+Shift+V hotkey) does not produce a phantom Ctrl+Shift+V and break the
/// plain paste.
///
/// Both left/right hand variants of Ctrl, Alt, Shift and Win are swept.
const List<int> _modifierVks = <int>[
  VK_LCONTROL,
  VK_RCONTROL,
  VK_LMENU,
  VK_RMENU,
  VK_LSHIFT,
  VK_RSHIFT,
  VK_LWIN,
  VK_RWIN,
];

/// Windows implementation using the Win32 SendInput API.
///
/// Before synthesizing Ctrl+V this:
///   (1) waits ~300ms for the user's hotkey modifiers to be physically released
///       (mirrors the macOS/Linux paste paths, which previously had a much
///       longer delay than the old ~50ms here), and
///   (2) sends an explicit KEYEVENTF_KEYUP sweep for Ctrl/Shift/Alt/Win so no
///       phantom modifiers remain held during the paste.
///
/// The existing calloc/free discipline is preserved in the surrounding
/// try/finally.
Future<void> simulateCtrlVWindows() async {
  // (a) Give the user time to physically release the hotkey modifiers.
  await Future.delayed(const Duration(milliseconds: 300));

  final modifierCount = _modifierVks.length; // modifier key-up events
  const pasteCount = 4; // Ctrl down, V down, V up, Ctrl up
  final total = modifierCount + pasteCount;

  final pInputs = calloc<INPUT>(total);

  try {
    // (b) Modifier release sweep: force KEYUP for every modifier so a held
    //     Shift/Alt/Win (or a sticky Ctrl) can't turn Ctrl+V into Ctrl+Shift+V
    //     and make the paste fail.
    for (var i = 0; i < modifierCount; i++) {
      pInputs[i].type = INPUT_KEYBOARD;
      pInputs[i].Anonymous.ki.wVk = _modifierVks[i];
      pInputs[i].Anonymous.ki.dwFlags = KEYEVENTF_KEYUP;
    }

    var i = modifierCount;

    // 1. Press Ctrl
    pInputs[i].type = INPUT_KEYBOARD;
    pInputs[i].Anonymous.ki.wVk = VK_CONTROL;
    pInputs[i].Anonymous.ki.dwFlags = 0;
    i++;

    // 2. Press V
    pInputs[i].type = INPUT_KEYBOARD;
    pInputs[i].Anonymous.ki.wVk = _vkV;
    pInputs[i].Anonymous.ki.dwFlags = 0;
    i++;

    // 3. Release V
    pInputs[i].type = INPUT_KEYBOARD;
    pInputs[i].Anonymous.ki.wVk = _vkV;
    pInputs[i].Anonymous.ki.dwFlags = KEYEVENTF_KEYUP;
    i++;

    // 4. Release Ctrl
    pInputs[i].type = INPUT_KEYBOARD;
    pInputs[i].Anonymous.ki.wVk = VK_CONTROL;
    pInputs[i].Anonymous.ki.dwFlags = KEYEVENTF_KEYUP;

    final result = SendInput(total, pInputs, sizeOf<INPUT>());

    if (result != total) {
      throw Exception('SendInput failed: expected $total, got $result');
    }

    await Future.delayed(const Duration(milliseconds: 50));
  } finally {
    calloc.free(pInputs);
  }
}
