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

    test('rejects non-PCM bit depths Whisper cannot consume', () {
          expect(
            () => RecordingService.extractMono16kPcmFromWav(wav(bitsPerSample: 24)),
            throwsFormatException,
          );
        });

        test('downmixes stereo PCM-16 to mono', () {
          // Two frames of stereo: L=1000, R=3000 then L=2000, R=4000
          // → mono averages 2000 and 3000.
          final pcm = <int>[
            1000 & 0xff, (1000 >> 8) & 0xff,
            3000 & 0xff, (3000 >> 8) & 0xff,
            2000 & 0xff, (2000 >> 8) & 0xff,
            4000 & 0xff, (4000 >> 8) & 0xff,
          ];
          final result = RecordingService.extractMono16kPcmFromWav(
            wav(channels: 2, pcm: pcm),
          );
          final view = ByteData.sublistView(result);
          expect(view.getInt16(0, Endian.little), closeTo(2000, 2));
          expect(view.getInt16(2, Endian.little), closeTo(3000, 2));
        });

        test('resamples 48 kHz mono PCM-16 down to 16 kHz', () {
          // 48 samples of a constant value → 16 samples after 3:1 downsample.
          const sample = 1234;
          final pcm = <int>[];
          for (var i = 0; i < 48; i++) {
            pcm.add(sample & 0xff);
            pcm.add((sample >> 8) & 0xff);
          }
          final result = RecordingService.extractMono16kPcmFromWav(
            wav(sampleRate: 48000, pcm: pcm),
          );
          expect(result.length, 16 * 2);
          final view = ByteData.sublistView(result);
          expect(view.getInt16(0, Endian.little), closeTo(sample, 2));
        });
      });
    }
