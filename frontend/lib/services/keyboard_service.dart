import 'dart:io';

import 'package:flutter/foundation.dart';

import 'keyboard_service_stub.dart'
    if (dart.library.ffi) 'keyboard_service_windows.dart'
    as platform_impl;
import 'keyboard_service_macos.dart'; // New native macOS helper

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

  /// macOS implementation using AppleScript
  /// Note: Requires Accessibility AND Automation permissions
  Future<void> _simulateCtrlVMacOS() async {
    // Wait for modifier keys to be released (user may still be holding Ctrl+Shift from hotkey)
    await Future.delayed(const Duration(milliseconds: 300));

    // First, check Accessibility natively
    final hasAccessibility = KeyboardServiceMacOS.checkAccessibility();
    if (!hasAccessibility) {
      _debugLog('KeyboardService: Accessibility permission MISSING.');
      return;
    }

    try {
      _debugLog('KeyboardService: Attempting AppleScript paste...');

      // Use AppleScript to simulate Cmd+V
      // This requires Automation permission to control "System Events"
      final result = await Process.run('osascript', [
        '-e',
        'tell application "System Events" to keystroke "v" using command down',
      ]);

      if (result.exitCode != 0) {
        final error = result.stderr.toString();
        _debugLog('AppleScript paste failed (Exit ${result.exitCode})');
        _debugLog('AppleScript stderr redacted (${error.length} chars)');

        if (error.contains('not authorized to send Apple events')) {
          _debugLog(
            'CRITICAL: Automation permission for "System Events" is missing!',
          );
          _debugLog(
            'Please go to System Settings > Privacy & Security > Automation and enable System Events for this app.',
          );
        } else {
          _debugLog(
            'Make sure to grant Accessibility permissions in System Settings > Privacy & Security > Accessibility',
          );
        }
      } else {
        _debugLog('KeyboardService: Paste command executed successfully');
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

  /// Check if the app has the necessary accessibility permissions
  Future<bool> checkAccessibilityPermissions() async {
    if (!Platform.isMacOS) return true;

    // Use native FFI check instead of osascript for Accessibility
    // This avoids the "Automation" permission prompt just for checking status
    return KeyboardServiceMacOS.checkAccessibility();
  }

  /// Check if the app has Automation permissions for System Events
  Future<bool> checkAutomationPermissions() async {
    if (!Platform.isMacOS) return true;

    try {
      // Try a very simple command that requires System Events but does no action
      final result = await Process.run('osascript', [
        '-e',
        'tell application "System Events" to get name',
      ]);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  /// Open macOS System Settings to Accessibility
  Future<void> openAccessibilitySettings() async {
    if (!Platform.isMacOS) return;

    try {
      // This URL is the most compatible for Accessibility
      await Process.run('open', [
        'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility',
      ]);
    } catch (e) {
      _debugLog('Failed to open settings: ${e.runtimeType}');
    }
  }

  /// Open macOS System Settings to Automation
  Future<void> openAutomationSettings() async {
    if (!Platform.isMacOS) return;

    try {
      await Process.run('open', [
        'x-apple.systempreferences:com.apple.preference.security?Privacy_Automation',
      ]);
    } catch (e) {
      _debugLog('Failed to open settings: ${e.runtimeType}');
    }
  }
}
