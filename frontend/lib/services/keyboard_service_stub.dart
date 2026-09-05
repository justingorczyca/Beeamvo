// Stub implementation for non-Windows platforms
// This file is used when compiling on macOS/Linux to avoid win32 import errors

Future<void> simulateCtrlVWindows({bool waitForModifiers = true}) async {
  throw UnsupportedError(
    'Windows keyboard simulation not available on this platform',
  );
}
