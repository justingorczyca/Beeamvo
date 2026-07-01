import 'dart:ffi';
import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

/// Get the handle to the Flutter window
int _getWindowHandle() {
  final hwnd = FindWindow(TEXT('BEEAMVO_WIN32_WINDOW'), nullptr);
  return hwnd;
}

/// Show window WITHOUT stealing focus from other applications
void showWithoutFocusWindows() {
  final hwnd = _getWindowHandle();
  if (hwnd != 0) {
    ShowWindow(hwnd, SW_SHOWNOACTIVATE);
    SetWindowPos(
      hwnd,
      HWND_TOPMOST,
      0, 0, 0, 0,
      SWP_NOMOVE | SWP_NOSIZE | SWP_NOACTIVATE | SWP_SHOWWINDOW,
    );
  }
}

/// Hide the window completely
void hideWindows() {
  final hwnd = _getWindowHandle();
  if (hwnd != 0) {
    ShowWindow(hwnd, SW_HIDE);
  }
}

/// Show the window normally (and focus it)
void showWindows() {
  final hwnd = _getWindowHandle();
  if (hwnd != 0) {
    ShowWindow(hwnd, SW_SHOW);
    SetForegroundWindow(hwnd);
  }
}

/// Check if window is currently visible
bool isVisibleWindows() {
  final hwnd = _getWindowHandle();
  if (hwnd != 0) {
    return IsWindowVisible(hwnd) != 0;
  }
  return false;
}

/// Get actual primary screen dimensions using Win32 API
(int, int) getScreenSizeWindows() {
  final width = GetSystemMetrics(SM_CXSCREEN);
  final height = GetSystemMetrics(SM_CYSCREEN);
  return (width, height);
}

/// Position window at bottom center of the active monitor
void positionAtActiveMonitorBottomCenterWindows(int windowWidth, int windowHeight) {
  final hwnd = _getWindowHandle();
  if (hwnd == 0) return;
  
  final bounds = _getActiveMonitorBounds();
  
  final xPos = bounds.$1 + (bounds.$3 ~/ 2) - (windowWidth ~/ 2);
  final yPos = bounds.$2 + bounds.$4 - 60 - windowHeight;
  
  ShowWindow(hwnd, SW_SHOWNOACTIVATE);
  
  SetWindowPos(
    hwnd,
    HWND_TOPMOST,
    xPos,
    yPos,
    windowWidth,
    windowHeight,
    SWP_NOACTIVATE | SWP_SHOWWINDOW,
  );
}

/// Get the monitor bounds where the currently active window is displayed
/// Returns (left, top, width, height)
(int, int, int, int) _getActiveMonitorBounds() {
  final foregroundWindow = GetForegroundWindow();
  final hMonitor = MonitorFromWindow(foregroundWindow, MONITOR_DEFAULTTONEAREST);
  
  final monitorInfo = calloc<MONITORINFO>();
  monitorInfo.ref.cbSize = sizeOf<MONITORINFO>();
  
  try {
    if (GetMonitorInfo(hMonitor, monitorInfo) != 0) {
      final rcMonitor = monitorInfo.ref.rcMonitor;
      return (
        rcMonitor.left,
        rcMonitor.top,
        rcMonitor.right - rcMonitor.left,
        rcMonitor.bottom - rcMonitor.top,
      );
    }
  } finally {
    calloc.free(monitorInfo);
  }
  
  return (0, 0, GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN));
}
