import 'dart:io';
import 'dart:typed_data';

import 'package:beeamvo/services/recording_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late File file;
  late Uint8List wav;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'beeamvo-readiness-test-',
    );
    file = File('${directory.path}/clip.wav');
    wav = RecordingService.buildMono16kWav(Uint8List(16000));
  });

  tearDown(() async => directory.delete(recursive: true));

  test('finalized WAV is ready without any polling delay', () async {
    await file.writeAsBytes(wav);
    var waits = 0;
    await RecordingService.waitForRecordingFile(
      file.path,
      delay: (_) async {
        waits++;
      },
    );
    expect(waits, 0);
  });

  test('unfinished WAV still waits for finalization', () async {
    final unfinished = Uint8List.fromList(wav);
    ByteData.sublistView(unfinished).setUint32(4, 36, Endian.little);
    await file.writeAsBytes(unfinished);
    var waits = 0;
    await RecordingService.waitForRecordingFile(
      file.path,
      delay: (_) async {
        waits++;
        await file.writeAsBytes(wav);
      },
    );
    expect(waits, 1);
  });

  test('a timed-out probe is not reported as a ready recording', () async {
    expect(
      await RecordingService.waitForRecordingFile(
        file.path,
        timeout: Duration.zero,
      ),
      isFalse,
    );
  });

  test('header fast path rejects truncated, mismatched and non-WAV files', () {
    expect(
      RecordingService.hasFinalizedWavHeader(wav.sublist(0, 12), wav.length),
      isTrue,
    );
    expect(
      RecordingService.hasFinalizedWavHeader(wav.sublist(0, 8), wav.length),
      isFalse,
    );
    expect(
      RecordingService.hasFinalizedWavHeader(wav, wav.length - 1),
      isFalse,
    );
    expect(
      RecordingService.hasFinalizedWavHeader(Uint8List(12), wav.length),
      isFalse,
    );
    expect(RecordingService.hasFinalizedWavHeader(wav, 44), isFalse);
  });
}
