import 'package:beeamvo/models/enums.dart';
import 'package:beeamvo/models/transcription_backend_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('resolveSessionBackend', () {
    test('falls back to the global default when no override is set', () {
      expect(
        resolveSessionBackend(
          globalDefault: TranscriptionBackend.cloud,
          promptBackendOverride: null,
        ),
        TranscriptionBackend.cloud,
      );
      expect(
        resolveSessionBackend(
          globalDefault: TranscriptionBackend.whisper,
          promptBackendOverride: null,
        ),
        TranscriptionBackend.whisper,
      );
    });

    test('honors a per-prompt override over the global default', () {
      expect(
        resolveSessionBackend(
          globalDefault: TranscriptionBackend.cloud,
          promptBackendOverride: TranscriptionBackend.whisper.value,
        ),
        TranscriptionBackend.whisper,
      );
      expect(
        resolveSessionBackend(
          globalDefault: TranscriptionBackend.whisper,
          promptBackendOverride: TranscriptionBackend.cloud.value,
        ),
        TranscriptionBackend.cloud,
      );
    });

    test('treats an unrecognised override as Cloud, matching fromValue', () {
      expect(
        resolveSessionBackend(
          globalDefault: TranscriptionBackend.whisper,
          promptBackendOverride: 'nonsense',
        ),
        TranscriptionBackend.cloud,
      );
    });
  });
}
