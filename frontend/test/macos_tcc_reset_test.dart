import 'package:beeamvo/services/macos_tcc_reset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('scopedTccutilArgs', () {
    test('scopes a reset to a single bundle id', () {
      expect(
        scopedTccutilArgs(
          service: 'Accessibility',
          bundleId: 'com.beeamvo.app',
        ),
        ['reset', 'Accessibility', 'com.beeamvo.app'],
      );
    });

    test('trims whitespace around the bundle id before emitting args', () {
      expect(
        scopedTccutilArgs(
          service: 'AppleEvents',
          bundleId: '  com.beeamvo.app  ',
        ),
        ['reset', 'AppleEvents', 'com.beeamvo.app'],
      );
    });

    test(
      'returns null for an empty bundle id (fail safe — never unscoped)',
      () {
        expect(
          scopedTccutilArgs(service: 'Accessibility', bundleId: ''),
          isNull,
        );
      },
    );

    test('returns null for a whitespace-only bundle id', () {
      expect(
        scopedTccutilArgs(service: 'Accessibility', bundleId: '   \t '),
        isNull,
      );
    });

    test('never emits a 2-arg (unscoped) reset for any valid id', () {
      // An unscoped `tccutil reset <service>` would clear the entry for ALL
      // apps; the scoped form always emits exactly three args.
      final args = scopedTccutilArgs(
        service: 'Accessibility',
        bundleId: 'com.beeamvo.app',
      );
      expect(args, isNotNull);
      expect(args!.length, 3, reason: 'a scoped reset must always be 3 args');
    });
  });

  test('tccutilExecutable is the absolute path (no PATH lookup)', () {
    expect(tccutilExecutable, '/usr/bin/tccutil');
  });
}
