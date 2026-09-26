import 'package:beeamvo/services/retry_after.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Retry-After is seconds with a sixty-second ceiling', () {
    expect(retryAfterDelayMilliseconds('2'), 2000);
    expect(retryAfterDelayMilliseconds('60'), 60000);
    expect(retryAfterDelayMilliseconds('61'), 60000);
    expect(
      retryAfterDelayMilliseconds('Wed, 21 Oct 2015 07:28:00 GMT'),
      isNull,
    );
  });
}
