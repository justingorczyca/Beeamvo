import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Virtual key code for 'V'
const int _vkV = 0x56;

/// Windows implementation using Win32 SendInput API
Future<void> simulateCtrlVWindows() async {
  await Future.delayed(const Duration(milliseconds: 50));

  final pInputs = calloc<INPUT>(4);
  
  try {
    // 1. Press Ctrl
    pInputs[0].type = INPUT_KEYBOARD;
    pInputs[0].Anonymous.ki.wVk = VK_CONTROL;
    pInputs[0].Anonymous.ki.dwFlags = 0;
    
    // 2. Press V
    pInputs[1].type = INPUT_KEYBOARD;
    pInputs[1].Anonymous.ki.wVk = _vkV;
    pInputs[1].Anonymous.ki.dwFlags = 0;
    
    // 3. Release V
    pInputs[2].type = INPUT_KEYBOARD;
    pInputs[2].Anonymous.ki.wVk = _vkV;
    pInputs[2].Anonymous.ki.dwFlags = KEYEVENTF_KEYUP;
    
    // 4. Release Ctrl
    pInputs[3].type = INPUT_KEYBOARD;
    pInputs[3].Anonymous.ki.wVk = VK_CONTROL;
    pInputs[3].Anonymous.ki.dwFlags = KEYEVENTF_KEYUP;
    
    final result = SendInput(4, pInputs, sizeOf<INPUT>());
    
    if (result != 4) {
      throw Exception('SendInput failed: expected 4, got $result');
    }
    
    await Future.delayed(const Duration(milliseconds: 50));
  } finally {
    calloc.free(pInputs);
  }
}
