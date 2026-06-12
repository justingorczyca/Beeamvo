import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:screen_retriever/screen_retriever.dart';
import 'package:window_manager/window_manager.dart';

import 'window_helper_stub.dart' if (dart.library.ffi) 'window_helper_windows.dart' as win32_impl;

/// macOS method channel for native window control
const _macOSChannel = MethodChannel('beeamvo/window');

/// Window helper service for showing/hiding window
class WindowHelper {
  /// Show window WITHOUT stealing focus from other applications
  static Future<void> showWithoutFocus() async {
    if (Platform.isWindows) {
      win32_impl.showWithoutFocusWindows();
    } else if (Platform.isMacOS) {
      try {
        await _macOSChannel.invokeMethod('showWithoutFocus');
      } catch (e) {
        debugPrint('WindowHelper.showWithoutFocus macOS fallback: $e');
        await windowManager.show();
        await windowManager.setAlwaysOnTop(true);
      }
    } else {
      await windowManager.show();
      await windowManager.setAlwaysOnTop(true);
    }
  }

  /// Hide the window completely
  static Future<void> hide() async {
    if (Platform.isWindows) {
      win32_impl.hideWindows();
    } else if (Platform.isMacOS) {
      try {
        // Use native alpha transparency for hiding
        await _macOSChannel.invokeMethod('hide');
      } catch (e) {
        debugPrint('WindowHelper.hide macOS fallback: $e');
        // Fallback: move far off-screen
        await windowManager.setPosition(const Offset(-50000, -50000));
      }
    } else {
      try {
        await windowManager.hide();
      } catch (e) {
        debugPrint('WindowHelper.hide error: $e');
      }
    }
  }

  /// Show the window normally (and focus it)
  static Future<void> show() async {
    if (Platform.isWindows) {
      win32_impl.showWindows();
    } else if (Platform.isMacOS) {
      try {
        await _macOSChannel.invokeMethod('show');
      } catch (e) {
        debugPrint('WindowHelper.show macOS fallback: $e');
        await windowManager.show();
        await windowManager.focus();
      }
    } else {
      try {
        await windowManager.show();
        await windowManager.focus();
      } catch (e) {
        debugPrint('WindowHelper.show error: $e');
      }
    }
  }

  /// Check if window is currently visible
  static Future<bool> isVisible() async {
    if (Platform.isWindows) {
      return win32_impl.isVisibleWindows();
    } else if (Platform.isMacOS) {
      try {
        final result = await _macOSChannel.invokeMethod<bool>('isVisible');
        return result ?? false;
      } catch (e) {
        return await windowManager.isVisible();
      }
    } else {
      return await windowManager.isVisible();
    }
  }

  /// Get screen dimensions
  static (int, int) getScreenSize() {
    if (Platform.isWindows) {
      return win32_impl.getScreenSizeWindows();
    } else {
      // Fallback for synchronous call; async callers should use getScreenSizeAsync
      return (1920, 1080);
    }
  }

  /// Async screen size using screen_retriever (works on all platforms)
  static Future<(int, int)> getScreenSizeAsync() async {
    if (Platform.isWindows) {
      return win32_impl.getScreenSizeWindows();
    }
    try {
      final primaryDisplay = await screenRetriever.getPrimaryDisplay();
      final size = primaryDisplay.size;
      return (size.width.toInt(), size.height.toInt());
    } catch (e) {
      debugPrint('getScreenSizeAsync error: $e');
      return (1920, 1080);
    }
  }

  /// Position window at bottom center of the active monitor
  static Future<void> positionAtActiveMonitorBottomCenter(int windowWidth, int windowHeight) async {
    if (Platform.isWindows) {
      win32_impl.positionAtActiveMonitorBottomCenterWindows(windowWidth, windowHeight);
    } else if (Platform.isMacOS) {
      try {
        // Use native method for proper positioning
        await _macOSChannel.invokeMethod('positionAtBottomCenter', {
          'width': windowWidth.toDouble(),
          'height': windowHeight.toDouble(),
        });
      } catch (e) {
        debugPrint('WindowHelper.positionAtActiveMonitorBottomCenter macOS fallback: $e');
        await windowManager.setSize(Size(windowWidth.toDouble(), windowHeight.toDouble()));
        const screenHeight = 900.0;
        const screenWidth = 1440.0;
        final xPos = (screenWidth / 2) - (windowWidth / 2);
        final yPos = screenHeight - 120.0;
        await windowManager.setPosition(Offset(xPos, yPos));
        await windowManager.setAlwaysOnTop(true);
        await windowManager.show();
      }
    } else {
      try {
        await windowManager.setSize(Size(windowWidth.toDouble(), windowHeight.toDouble()));
        // Use screen_retriever for actual display dimensions
        final cursorPos = await screenRetriever.getCursorScreenPoint();
        final displays = await screenRetriever.getAllDisplays();
        // Find the display containing the cursor
        Display? activeDisplay;
        for (final display in displays) {
          final bounds = display.visiblePosition ?? Offset.zero;
          final size = display.size;
          if (cursorPos.dx >= bounds.dx &&
              cursorPos.dx < bounds.dx + size.width &&
              cursorPos.dy >= bounds.dy &&
              cursorPos.dy < bounds.dy + size.height) {
            activeDisplay = display;
            break;
          }
        }
        activeDisplay ??= await screenRetriever.getPrimaryDisplay();
        final displayPos = activeDisplay.visiblePosition ?? Offset.zero;
        final screenWidth = activeDisplay.size.width;
        final screenHeight = activeDisplay.size.height;
        final xPos = displayPos.dx + (screenWidth / 2) - (windowWidth / 2);
        final yPos = displayPos.dy + screenHeight - 120.0;
        await windowManager.setPosition(Offset(xPos, yPos));
        await windowManager.setAlwaysOnTop(true);
        await windowManager.show();
      } catch (e) {
        debugPrint('WindowHelper.positionAtActiveMonitorBottomCenter error: $e');
      }
    }
  }
}
