import 'dart:io';

import 'package:flutter/foundation.dart';

import 'keyboard_service_stub.dart'
    if (dart.library.ffi) 'keyboard_service_windows.dart'
    as platform_impl;
import 'keyboard_service_macos.dart'; // New native macOS helper
import 'macos_permission_service.dart'; // CGEvent paste + permission channel

/// Service for simulating keyboard input
///
/// Platform-specific implementation for Ctrl+V / Cmd+V paste simulation.
class KeyboardService {
  // Prevent duplicate paste calls
  static bool _isPasting = false;

  static void _debugLog(String message) {
    if (kDebugMode) debugPrint(message);
  }

  /// Simulate Ctrl+V (Windows) or Cmd+V (macOS) to paste clipboard content
  Future<void> simulateCtrlV() async {
    // Guard against duplicate paste calls
    if (_isPasting) {
      _debugLog('KeyboardService: Already pasting, ignoring duplicate call');
      return;
    }
    _isPasting = true;

    try {
      if (Platform.isWindows) {
        await platform_impl.simulateCtrlVWindows();
      } else if (Platform.isMacOS) {
        await _simulateCtrlVMacOS();
      } else if (Platform.isLinux) {
        await _simulateCtrlVLinux();
      } else {
        throw UnsupportedError(
          'Keyboard simulation not supported on this platform',
        );
      }
    } finally {
      // Reset flag after a short delay to allow for any lingering inputs
      Future.delayed(const Duration(milliseconds: 500), () {
        _isPasting = false;
      });
    }
  }

  /// macOS implementation using native CGEvent keystroke synthesis.
  ///
  /// Unlike the old osascript/System Events path, this needs ONLY the
  /// Accessibility permission — no separate Automation permission. If the
  /// permission is missing, the text remains on the clipboard for a manual
  /// Cmd+V, and the paste-failure path can open the onboarding dialog.
  Future<void> _simulateCtrlVMacOS() async {
    // Wait for modifier keys to be released (user may still be holding Cmd/Ctrl+Shift from hotkey)
    await Future.delayed(const Duration(milliseconds: 300));

    // Fast synchronous pre-check before the channel round-trip.
    if (!KeyboardServiceMacOS.checkAccessibility()) {
      _debugLog('KeyboardService: Accessibility permission MISSING — skipping paste.');
      _debugLog(
        'Text is on the clipboard — manual Cmd+V available, or enable Accessibility.',
      );
      return;
    }

    try {
      _debugLog('KeyboardService: Attempting native CGEvent paste...');

      final posted = await MacOsPermissionService.pasteCmdV();
      if (posted) {
        _debugLog('KeyboardService: CGEvent paste posted successfully');
      } else {
        _debugLog(
          'KeyboardService: CGEvent paste not posted '
          '(missing Accessibility permission or channel error). '
          'Text is on the clipboard — manual Cmd+V available.',
        );
      }
    } catch (e) {
      _debugLog('Keyboard simulation error: ${e.runtimeType}');
      _debugLog(
        'Text has been copied to clipboard - please paste manually with Cmd+V',
      );
    }

    await Future.delayed(const Duration(milliseconds: 100));
  }

  /// Linux implementation using xdotool (X11) or wtype (Wayland)
  Future<void> _simulateCtrlVLinux() async {
    await Future.delayed(const Duration(milliseconds: 300));

    try {
      final sessionType = Platform.environment['XDG_SESSION_TYPE'] ?? '';
      final isWayland = sessionType.toLowerCase() == 'wayland';

      ProcessResult result;
      if (isWayland) {
        // Wayland: use wtype
        result = await Process.run('wtype', [
          '-M',
          'ctrl',
          '-P',
          'v',
          '-p',
          'v',
          '-m',
          'ctrl',
        ]);
      } else {
        // X11: use xdotool
        result = await Process.run('xdotool', [
          'key',
          '--clearmodifiers',
          'ctrl+v',
        ]);
      }

      if (result.exitCode != 0) {
        final tool = isWayland ? 'wtype' : 'xdotool';
        _debugLog(
          'Linux paste failed ($tool exit ${result.exitCode}); stderr redacted',
        );
        _debugLog('Install $tool: sudo apt install $tool');
      } else {
        _debugLog('KeyboardService: Linux paste executed successfully');
      }
    } catch (e) {
      _debugLog('Linux keyboard simulation error: ${e.runtimeType}');
      _debugLog(
        'Text has been copied to clipboard - please paste manually with Ctrl+V. '
        'Install xdotool (X11) or wtype (Wayland) for auto-paste.',
      );
    }

    await Future.delayed(const Duration(milliseconds: 100));
  }

  /// Check if the app has the necessary Accessibility permission.
  ///
  /// This is the only permission now required for paste + global hotkeys — the
  /// old Automation permission is no longer needed since paste uses CGEvent.
  Future<bool> checkAccessibilityPermissions() async {
    if (!Platform.isMacOS) return true;
    return MacOsPermissionService.isGranted();
  }

  /// Automation is no longer required.
  ///
  /// The paste path now uses native CGEvent keystroke synthesis (needs only
  /// Accessibility) instead of osascript → System Events. We keep this method
  /// returning true so existing callers/UI stay consistent.
  Future<bool> checkAutomationPermissions() async {
    return true;
  }

      /// Open macOS System Settings to Accessibility
      Future<void> openAccessibilitySettings() async {
        if (!Platform.isMacOS) return;
        await MacOsPermissionService.openSettings();
      }
    }
