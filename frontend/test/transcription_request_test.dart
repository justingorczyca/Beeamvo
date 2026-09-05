import 'dart:async';

import 'package:beeamvo/services/transcription_request.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

void main() {
  test('a slow generation gets one timeout, not three attempts', () async {
    var calls = 0;
    final request = TranscriptionRequest(
      timeout: const Duration(milliseconds: 30),
    );
    await expectLater(
      request.send(() {
        calls++;
        return Completer<http.Response>().future;
      }),
      throwsA(isA<TimeoutException>()),
    );
    expect(calls, 1);
  });

  test('does not sleep or retry beyond Retry-After budget', () async {
    var calls = 0;
    final response = await TranscriptionRequest().send(() async {
      calls++;
      return http.Response('{}', 429, headers: {'retry-after': '3600'});
    });
    expect(response.statusCode, 429);
    expect(calls, 1);
  });

  test('transient errors still recover within the budget', () async {
    var calls = 0;
    final response = await TranscriptionRequest().send(() async {
      calls++;
      return http.Response(
        '{}',
        calls == 1 ? 503 : 200,
        headers: {'retry-after': '0'},
      );
    });
    expect(response.statusCode, 200);
    expect(calls, 2);
  });

  test('persistent transient errors stop after three attempts', () async {
    var calls = 0;
    final response = await TranscriptionRequest().send(() async {
      calls++;
      return http.Response('{}', 503, headers: {'retry-after': '0'});
    });
    expect(response.statusCode, 503);
    expect(calls, 3);
  });

  test('backoff consumes the same deadline as generation', () async {
    var calls = 0;
    final watch = Stopwatch()..start();
    await expectLater(
      TranscriptionRequest(timeout: const Duration(milliseconds: 1200)).send(
        () async {
          calls++;
          if (calls == 1) {
            return http.Response('{}', 429, headers: {'retry-after': '1'});
          }
          return Completer<http.Response>().future;
        },
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(calls, 2);
    expect(watch.elapsedMilliseconds, lessThan(2000));
  });

  test('an exhausted budget cannot restart for an auth retry', () async {
    final request = TranscriptionRequest(
      timeout: const Duration(milliseconds: 30),
    );
    await expectLater(
      request.send(() => Completer<http.Response>().future),
      throwsA(isA<TimeoutException>()),
    );
    var calls = 0;
    await expectLater(
      request.send(() async {
        calls++;
        return http.Response('{}', 200);
      }),
      throwsA(isA<TimeoutException>()),
    );
    expect(calls, 0);
  });

  test('non-transient errors are not retried', () async {
    var calls = 0;
    final response = await TranscriptionRequest().send(() async {
      calls++;
      return http.Response('{}', 403);
    });
    expect(response.statusCode, 403);
    expect(calls, 1);
  });
}
