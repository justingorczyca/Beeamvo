import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'retry_after.dart';

class TranscriptionRequest {
  TranscriptionRequest({this.timeout = const Duration(seconds: 60)});

  final Duration timeout;
  final Stopwatch _elapsed = Stopwatch();
  final Random _random = Random();

  Duration get _remaining => timeout - _elapsed.elapsed;

  Future<http.Response> send(Future<http.Response> Function() request) async {
    _elapsed.start();
    for (var attempt = 0; ; attempt++) {
      final remaining = _remaining;
      if (remaining <= Duration.zero) {
        throw TimeoutException('Transcription request timed out.', timeout);
      }
      final watch = Stopwatch()..start();
      final http.Response response;
      try {
        response = await request().timeout(remaining);
      } on TimeoutException {
        if (kDebugMode) {
          debugPrint(
            '[TranscriptionRequest] timeout after '
            '${_elapsed.elapsedMilliseconds}ms; not resubmitting generation',
          );
        }
        rethrow;
      }
      if (kDebugMode) {
        debugPrint(
          '[TranscriptionRequest] attempt=${attempt + 1} '
          'http=${response.statusCode} elapsed=${watch.elapsedMilliseconds}ms',
        );
      }
      if ((response.statusCode != 429 && response.statusCode < 500) ||
          attempt >= 2) {
        return response;
      }
      final delay = Duration(
        milliseconds:
            retryAfterDelayMilliseconds(response.headers['retry-after']) ??
            (500 * (1 << attempt) + _random.nextInt(500)),
      );
      if (delay >= _remaining) return response;
      if (kDebugMode) {
        debugPrint(
          '[TranscriptionRequest] retry delay=${delay.inMilliseconds}ms',
        );
      }
      await Future<void>.delayed(delay);
    }
  }
}
