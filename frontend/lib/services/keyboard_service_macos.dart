import 'dart:ffi';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'macos_permission_service.dart';

/// Fast synchronous read of the macOS Accessibility permission state via FFI,
/// plus the canonical async request that triggers the native prompt.
///
/// The native one-click prompt + deep-link is handled through
/// [MacOsPermissionService.request] (AXIsProcessTrustedWithOptions). The old
/// `AXIsProcessTrusted()` call did NOT reliably show a prompt, which is why the
/// earlier flow forced users to find the Setting pane manually.
class KeyboardServiceMacOS {
  static final DynamicLibrary? _appServices = Platform.isMacOS
      ? DynamicLibrary.open(
          '/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices',
        )
      : null;

  /// Synchronous Accessibility status check. Silent — never triggers a prompt.
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

  /// Request accessibility permission.
  ///
  /// Delegates to the native method channel which calls
  /// `AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt: true])` — the
  /// API that actually shows the native dialog deep-linking to the Accessibility
  /// pane. (The previous FFI `AXIsProcessTrusted()` no-op did not.)
  static Future<bool> requestAccessibility() {
    return MacOsPermissionService.request();
  }
}
