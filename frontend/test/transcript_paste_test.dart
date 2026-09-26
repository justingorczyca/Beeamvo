import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'transcript delivery waits for clipboard but adds no pre-paste timer',
    () {
      final source = File('lib/main.dart').readAsStringSync();
      final start = source.indexOf('Future<void> _copyToClipboardAndPaste(');
      final end = source.indexOf('\n  @override', start);
      expect(start, greaterThanOrEqualTo(0));
      expect(end, greaterThan(start));
      final delivery = source.substring(start, end);

      expect(delivery, contains('await clipboard.write([item]);'));
      expect(delivery, contains('!_settingsService.autoPasteEnabled'));
      expect(delivery, contains('!didWriteClipboard'));
      expect(delivery, isNot(contains('Future.delayed')));
      expect(delivery, isNot(contains('Timer(')));
      expect(
        delivery,
        contains(
          'await keyboardService.simulateCtrlV(waitForModifiers: false);',
        ),
      );
      expect(
        delivery.indexOf('await clipboard.write'),
        lessThan(delivery.indexOf('await keyboardService.simulateCtrlV')),
      );
    },
  );
}
