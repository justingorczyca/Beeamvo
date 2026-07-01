// Stub implementation for non-Windows platforms
// This file is used when compiling on macOS/Linux to avoid win32 import errors

void showWithoutFocusWindows() {
  throw UnsupportedError('Windows window helper not available on this platform');
}

void hideWindows() {
  throw UnsupportedError('Windows window helper not available on this platform');
}

void showWindows() {
  throw UnsupportedError('Windows window helper not available on this platform');
}

bool isVisibleWindows() {
  throw UnsupportedError('Windows window helper not available on this platform');
}

(int, int) getScreenSizeWindows() {
  throw UnsupportedError('Windows window helper not available on this platform');
}

void positionAtActiveMonitorBottomCenterWindows(int windowWidth, int windowHeight) {
  throw UnsupportedError('Windows window helper not available on this platform');
}
