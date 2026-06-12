import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

/// macOS implementation of keyboard and permission services using FFI
class KeyboardServiceMacOS {
  static final DynamicLibrary? _appServices = Platform.isMacOS
      ? DynamicLibrary.open(
          '/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices',
        )
      : null;

  /// Check if the current process has accessibility permissions
  /// This is the native way to check without triggering "Automation" permission prompts
  static bool checkAccessibility() {
    if (!Platform.isMacOS || _appServices == null) return true;

    try {
      final checkTrusted = _appServices!
          .lookupFunction<Int8 Function(), int Function()>(
            'AXIsProcessTrusted',
          );

      return checkTrusted() != 0;
    } catch (e) {
      debugPrint('Error checking accessibility: $e');
      return false;
    }
  }

  /// Request accessibility permissions
  /// This will trigger the macOS system dialog if not already granted
  static void requestAccessibility() {
    if (!Platform.isMacOS || _appServices == null) return;

    try {
      // Calling AXIsProcessTrusted() with no options usually triggers the prompt
      // if the app is NOT trusted.
      final checkTrusted = _appServices!
          .lookupFunction<Int8 Function(), int Function()>(
            'AXIsProcessTrusted',
          );

      checkTrusted();
    } catch (e) {
      debugPrint('Error requesting accessibility: $e');
    }
  }
}
