import 'dart:async';

import 'package:beeamvo/services/whisper_model_download_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'page teardown waits for active download cleanup before disposal',
    () async {
      final cleanupStarted = Completer<void>();
      final allowCleanupToFinish = Completer<void>();
      var cleanupCalls = 0;
      var notificationCount = 0;
      final service = WhisperModelDownloadService.forTesting(
        cleanup: () async {
          cleanupCalls += 1;
          cleanupStarted.complete();
          await allowCleanupToFinish.future;
        },
      );
      service.addListener(() => notificationCount += 1);
      service.beginDownloadForTesting();

      final pageTeardown = service.cancelAndDispose();
      await cleanupStarted.future;

      expect(service.status, DownloadStatus.downloading);
      expect(cleanupCalls, 1);
      // The page removes its listener before calling cancelAndDispose, and the
      // service also suppresses the cancellation notification for page teardown.
      expect(notificationCount, 1);

      allowCleanupToFinish.complete();
      await pageTeardown;

      expect(service.status, DownloadStatus.cancelled);
      expect(cleanupCalls, 1);

      // A late state transition from an already-finished download must not call
      // ChangeNotifier.notifyListeners after final disposal.
      service.resetState();
      expect(notificationCount, 1);
    },
  );

  test(
    'explicit cancellation cleans an active page download and notifies once',
    () async {
      var cleanupCalls = 0;
      var notificationCount = 0;
      final service = WhisperModelDownloadService.forTesting(
        cleanup: () async => cleanupCalls += 1,
      );
      service.addListener(() => notificationCount += 1);
      service.beginDownloadForTesting();

      await service.cancelDownload();

      expect(service.status, DownloadStatus.cancelled);
      expect(cleanupCalls, 1);
      expect(notificationCount, 2);
      service.dispose();
    },
  );
}
