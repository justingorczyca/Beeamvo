import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Typed wrapper around the `beeamvo/permission` platform channel.
///
/// On macOS this exposes:
///  - Accessibility permission state (silent check + native prompt)
///  - A CGEvent-based Cmd+V paste that needs ONLY Accessibility (no Automation)
///  - A deep-link helper to open System Settings → Privacy & Security → Accessibility
///
/// On non-macOS platforms every method is a safe no-op / returns defaults so
/// call sites can stay cross-platform without platform checks.
class MacOsPermissionService {
  MacOsPermissionService();

  static const _channel = MethodChannel('beeamvo/permission');

  /// True if Accessibility is granted. On non-macOS, always true.
  static Future<bool> isGranted() async {
    if (!Platform.isMacOS) return true;
    try {
      final result = await _channel.invokeMethod<bool>('checkAccessibility');
      return result ?? false;
    } catch (e) {
      debugPrint('MacOsPermissionService.isGranted error: $e');
      return false;
    }
  }

  /// Request Accessibility permission.
  ///
  /// On macOS this calls AXIsProcessTrustedWithOptions with the prompt flag,
  /// which triggers the native one-click dialog that deep-links straight to the
  /// correct System Settings pane. Returns the current granted state.
  static Future<bool> request() async {
    if (!Platform.isMacOS) return true;
    try {
      final result = await _channel.invokeMethod<bool>('requestAccessibility');
      return result ?? false;
    } catch (e) {
      debugPrint('MacOsPermissionService.request error: $e');
      return false;
    }
  }

  /// Open System Settings directly to the Accessibility pane (backup path).
  static Future<void> openSettings() async {
    if (!Platform.isMacOS) return;
    try {
      await _channel.invokeMethod<void>('openAccessibilitySettings');
    } catch (e) {
      debugPrint('MacOsPermissionService.openSettings error: $e');
    }
  }

    /// Synthesize a Cmd+V keystroke via native CGEvent.
    ///
    /// Requires Accessibility permission (NOT Automation). Returns true if the
    /// keystroke was posted. If Accessibility is missing this returns false and
    /// the caller should fall back to the clipboard (manual paste).
    static Future<bool> pasteCmdV() async {
      if (!Platform.isMacOS) return false;
      try {
        final result = await _channel.invokeMethod<bool>('pasteWithCmdV');
        return result ?? false;
      } catch (e) {
        debugPrint('MacOsPermissionService.pasteCmdV error: $e');
        return false;
      }
    }

    /// Reset ONLY this app's Accessibility entry in the TCC privacy database.
    ///
    /// Clears a stale "stuck" toggle (e.g. leftover from a prior ad-hoc build
    /// whose CDHash no longer matches) so a fresh native prompt can fire. Scoped
    /// to our bundle id — other apps are untouched. Pair with [request] to
    /// re-surface the system prompt immediately afterwards.
    static Future<bool> resetEntry() async {
      if (!Platform.isMacOS) return true;
      try {
        final result =
            await _channel.invokeMethod<bool>('resetAccessibilityEntry');
        return result ?? false;
      } catch (e) {
        debugPrint('MacOsPermissionService.resetEntry error: $e');
        return false;
      }
    }

    /// Convenience: clear the stale entry and immediately re-fire the native
    /// prompt. Returns true if Accessibility is granted afterwards.
    static Future<bool> autoRepair() async {
      if (!Platform.isMacOS) return true;
      await resetEntry();
      // Brief pause so the TCC database settles before re-prompting.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      final granted = await request();
      return granted;
    }
  }
