import 'dart:typed_data';

import 'package:beeamvo/services/recording_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Uint8List wav({
    List<int> pcm = const [1, 2, 3, 4],
    List<int> extraChunk = const [],
    int channels = 1,
    int sampleRate = 16000,
    int bitsPerSample = 16,
  }) {
    final bytes = BytesBuilder();
    void ascii(String value) => bytes.add(value.codeUnits);
    void u32(int value) => bytes.add(<int>[
      value & 0xff,
      value >> 8 & 0xff,
      value >> 16 & 0xff,
      value >> 24 & 0xff,
    ]);

    final fmt = BytesBuilder()
      ..add(<int>[1, 0])
      ..add(<int>[channels & 0xff, channels >> 8 & 0xff])
      ..add(<int>[
        sampleRate & 0xff,
        sampleRate >> 8 & 0xff,
        sampleRate >> 16 & 0xff,
        sampleRate >> 24 & 0xff,
      ])
      ..add(<int>[0, 0, 0, 0])
      ..add(<int>[0, 0])
      ..add(<int>[bitsPerSample & 0xff, bitsPerSample >> 8 & 0xff]);

    final extraPadding = extraChunk.length.isOdd ? 1 : 0;
    final pcmPadding = pcm.length.isOdd ? 1 : 0;
    ascii('RIFF');
    u32(
      4 +
          8 +
          16 +
          (extraChunk.isEmpty ? 0 : 8 + extraChunk.length + extraPadding) +
          8 +
          pcm.length +
          pcmPadding,
    );
    ascii('WAVE');
    ascii('fmt ');
    u32(16);
    bytes.add(fmt.takeBytes());
    if (extraChunk.isNotEmpty) {
      ascii('LIST');
      u32(extraChunk.length);
      bytes.add(extraChunk);
      if (extraPadding == 1) bytes.addByte(0);
    }
    ascii('data');
    u32(pcm.length);
    bytes.add(pcm);
    if (pcmPadding == 1) bytes.addByte(0);
    return bytes.takeBytes();
  }

  group('RecordingService.extractMono16kPcmFromWav', () {
    test('extracts PCM after an optional RIFF chunk', () {
      final result = RecordingService.extractMono16kPcmFromWav(
        wav(extraChunk: const [9, 8, 7], pcm: const [10, 11, 12, 13]),
      );

      expect(result, orderedEquals(const [10, 11, 12, 13]));
    });

    test('rejects non-WAV data and truncated chunks', () {
      expect(
        () => RecordingService.extractMono16kPcmFromWav(
          Uint8List.fromList([1, 2, 3]),
        ),
        throwsFormatException,
      );
      final truncated = wav().sublist(0, 30);
      expect(
        () => RecordingService.extractMono16kPcmFromWav(truncated),
        throwsFormatException,
      );
    });

    test('rejects formats Whisper cannot consume directly', () {
      expect(
        () => RecordingService.extractMono16kPcmFromWav(wav(channels: 2)),
        throwsFormatException,
      );
      expect(
        () => RecordingService.extractMono16kPcmFromWav(wav(sampleRate: 44100)),
        throwsFormatException,
      );
      expect(
        () => RecordingService.extractMono16kPcmFromWav(wav(bitsPerSample: 24)),
        throwsFormatException,
      );
    });
  });
}
