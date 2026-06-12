import 'package:flutter/services.dart';

/// macOS-specific window helper that uses native method channel
/// for proper overlay behavior with orderOut/orderFront
class WindowHelperMacOS {
  static const MethodChannel _channel = MethodChannel('beeamvo/window');

  /// Show overlay window with focus
  static Future<void> show() async {
    try {
      await _channel.invokeMethod('show');
    } catch (e) {
      // Fallback handled by caller
      rethrow;
    }
  }

  /// Show overlay window without stealing focus
  static Future<void> showWithoutFocus() async {
    try {
      await _channel.invokeMethod('showWithoutFocus');
    } catch (e) {
      rethrow;
    }
  }

  /// Hide overlay window using native orderOut
  static Future<void> hide() async {
    try {
      await _channel.invokeMethod('hide');
    } catch (e) {
      rethrow;
    }
  }

  /// Check if window is currently visible
  static Future<bool> isVisible() async {
    try {
      final result = await _channel.invokeMethod<bool>('isVisible');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Get screen size
  static Future<(double, double)> getScreenSize() async {
    try {
      final result = await _channel.invokeMethod<Map>('getScreenSize');
      if (result != null) {
        return (
          (result['width'] as num).toDouble(),
          (result['height'] as num).toDouble()
        );
      }
    } catch (e) {
      // Fallback
    }
    return (1920.0, 1080.0);
  }

  /// Position window at specific coordinates
  static Future<void> setPosition(double x, double y) async {
    try {
      await _channel.invokeMethod('setPosition', {'x': x, 'y': y});
    } catch (e) {
      rethrow;
    }
  }

  /// Set window size
  static Future<void> setSize(double width, double height) async {
    try {
      await _channel.invokeMethod('setSize', {'width': width, 'height': height});
    } catch (e) {
      rethrow;
    }
  }

  /// Position and show window at bottom center of active screen
  static Future<void> positionAtBottomCenter(double width, double height) async {
    try {
      await _channel.invokeMethod('positionAtBottomCenter', {
        'width': width,
        'height': height,
      });
    } catch (e) {
      rethrow;
    }
  }
}
