import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Windows and macOS use release events without the old watchdog', () {
    final source = File('lib/main.dart').readAsStringSync();
    expect(source, isNot(contains('_holdTimer')));
    expect(source, isNot(contains('watchdogMs')));
    final start = source.indexOf('void _onHotkeyReleased()');
    final end = source.indexOf('bool _canStartRecording()', start);
    expect(
      source.substring(start, end),
      contains('_stopRecordingAndProcess()'),
    );
  });

  test('processing requests are captured before the startup lock check', () {
    final source = File('lib/main.dart').readAsStringSync();
    final start = source.indexOf('Future<void> _stopRecordingAndProcess(');
    final end = source.indexOf('final recordingDuration', start);
    final method = source.substring(start, end);
    expect(
      method.indexOf('_recordingStart.requestProcessing()'),
      allOf(
        greaterThanOrEqualTo(0),
        lessThan(method.indexOf('if (_isLockActive)')),
      ),
    );
  });

  test('Windows hotkeys provide release events and suppress key repeats', () {
    final source = File('windows/runner/hotkey_plugin.cpp').readAsStringSync();
    expect(source, contains('WM_KEYUP'));
    expect(source, contains('WM_SYSKEYUP'));
    expect(source, contains('MOD_NOREPEAT'));
    expect(source, contains('"onKeyUp"'));
    expect(source, contains('LLKHF_INJECTED'));
    expect(source, isNot(contains('Sleep(')));
    expect(source, isNot(contains('SetTimer(')));
  });
}
