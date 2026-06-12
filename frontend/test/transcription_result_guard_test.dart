import 'package:beeamvo/services/cloud_transcription_client.dart';
import 'package:beeamvo/services/transcription_result_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TranscriptionResultGuard', () {
    test('rejects recordings that are too short', () {
      expect(
        () => TranscriptionResultGuard.ensureRecordingLongEnough(
          const Duration(milliseconds: 200),
        ),
        throwsA(
          isA<CloudTranscriptionException>().having(
            (error) => error.message,
            'message',
            equals('Nothing was transcribed.'),
          ),
        ),
      );
    });

    test('accepts trimmed transcript text', () {
      expect(
        TranscriptionResultGuard.requireTranscript('  hello world  '),
        equals('hello world'),
      );
    });

    test('rejects the explicit no-transcript marker', () {
      expect(
        () => TranscriptionResultGuard.requireTranscript('[NO_TRANSCRIPT]'),
        throwsA(isA<CloudTranscriptionException>()),
      );
    });
  });
}
