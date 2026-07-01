import 'dart:async';

import 'package:beeamvo/services/whisper_model_download_service.dart';
import 'package:beeamvo/services/whisper_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

class _MockStreamedClient extends http.BaseClient {
  _MockStreamedClient(this._handler);

  final FutureOr<http.StreamedResponse> Function(http.BaseRequest request)
  _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    return _handler(request);
  }
}

void main() {
  test('accepts only safe whisper model basenames', () {
    expect(WhisperService.isSafeModelFileName('ggml-tiny.bin'), isTrue);
    expect(WhisperService.isSafeModelFileName('ggml-tiny.en.bin'), isTrue);
    expect(WhisperService.isSafeModelFileName('ggml-tiny-q5_1.bin'), isTrue);

    expect(WhisperService.isSafeModelFileName('../ggml-tiny.bin'), isFalse);
    expect(WhisperService.isSafeModelFileName('models/ggml-tiny.bin'), isFalse);
    expect(
      WhisperService.isSafeModelFileName('ggml-tiny.bin.download'),
      isFalse,
    );
    expect(WhisperService.isSafeModelFileName('tiny.bin'), isFalse);
  });

  test('rejects traversal in model path helpers', () {
    expect(
      () => WhisperService.getWritableModelPath('../ggml-tiny.bin'),
      throwsArgumentError,
    );
    expect(
      () => WhisperService.resolveAllowedModelPath('models/ggml-tiny.bin'),
      throwsArgumentError,
    );
  });

  test(
    'download rejects unknown or unsafe model ids before network access',
    () async {
      final service = WhisperModelDownloadService(
        httpClient: _MockStreamedClient((request) {
          fail('Unsafe model ids must be rejected before HTTP is attempted');
        }),
      );

      final success = await service.downloadModel(
        const WhisperModelInfo(
          id: '../ggml-tiny.bin',
          name: 'Unsafe',
          url: 'https://example.invalid/ggml-tiny.bin',
          sizeBytes: 1,
          sizeDisplay: '1 B',
        ),
      );

      expect(success, isFalse);
      expect(service.status, DownloadStatus.error);
      expect(service.errorMessage, contains('Unknown or unsafe'));
    },
  );

  test(
    'download rejects target paths outside allowed model directories',
    () async {
      final model = WhisperModelDownloadService.defaultModel;
      final modelDir = p.dirname(
        WhisperModelDownloadService.getWritableModelPath(model.id),
      );
      final outsideModelDir = p.normalize(p.join(modelDir, '..', model.id));
      final service = WhisperModelDownloadService(
        httpClient: _MockStreamedClient((request) {
          fail(
            'Invalid target paths must be rejected before HTTP is attempted',
          );
        }),
      );

      final success = await service.downloadModel(
        model,
        targetPath: outsideModelDir,
      );

      expect(success, isFalse);
      expect(service.status, DownloadStatus.error);
      expect(service.errorMessage, contains('outside'));
    },
  );

  test(
    'download rejects responses larger than the model maximum size',
    () async {
      final model = WhisperModelDownloadService.defaultModel;
      final service = WhisperModelDownloadService(
        httpClient: _MockStreamedClient((request) {
          return http.StreamedResponse(
            const Stream<List<int>>.empty(),
            200,
            contentLength: model.maxSizeBytes + 1,
          );
        }),
      );

      final success = await service.downloadModel(model);

      expect(success, isFalse);
      expect(service.status, DownloadStatus.error);
      expect(service.errorMessage, contains('expected maximum size'));
    },
  );
}
