import 'package:beeamvo/services/whisper_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  WhisperService createService(List<String> nativeMethods) {
    return WhisperService(
      modelPathResolver: (modelPath) => modelPath,
      nativeInvoker:
          <T>(String method, [Map<String, dynamic>? arguments]) async {
            nativeMethods.add(method);
            if (method == 'init') return true as T;
            return null;
          },
    );
  }

  test(
    'unloadModel is idempotent and the service can be reinitialized',
    () async {
      final nativeMethods = <String>[];
      final service = createService(nativeMethods);
      var notifications = 0;
      service.addListener(() => notifications++);

      await service.unloadModel();
      expect(nativeMethods, isEmpty);
      expect(notifications, 0);

      expect(
        await service.initialize(modelPath: '/test/ggml-tiny.bin'),
        isTrue,
      );
      expect(service.isInitialized, isTrue);
      expect(service.loadedModelPath, '/test/ggml-tiny.bin');

      await service.unloadModel();
      expect(service.isInitialized, isFalse);
      expect(service.loadedModelPath, isNull);
      expect(nativeMethods, <String>['init', 'cleanup']);

      // A repeated unload must be a no-op, not a second native cleanup.
      await service.unloadModel();
      expect(nativeMethods, <String>['init', 'cleanup']);

      expect(
        await service.initialize(modelPath: '/test/ggml-base.bin'),
        isTrue,
      );
      expect(service.isInitialized, isTrue);
      expect(service.loadedModelPath, '/test/ggml-base.bin');
      expect(nativeMethods, <String>['init', 'cleanup', 'init']);

      // Initialization notifies for loading and completion; unloading notifies
      // once, proving the ChangeNotifier remains usable after unloading.
      expect(notifications, 5);
      await service.dispose();
    },
  );

  test(
    'final dispose is terminal and suppresses later lifecycle work',
    () async {
      final nativeMethods = <String>[];
      var resolverCalls = 0;
      final service = WhisperService(
        modelPathResolver: (modelPath) {
          resolverCalls++;
          return modelPath;
        },
        nativeInvoker:
            <T>(String method, [Map<String, dynamic>? arguments]) async {
              nativeMethods.add(method);
              if (method == 'init') return true as T;
              return null;
            },
      );
      var notifications = 0;
      service.addListener(() => notifications++);

      expect(
        await service.initialize(modelPath: '/test/ggml-tiny.bin'),
        isTrue,
      );
      expect(resolverCalls, 1);

      await service.dispose();
      expect(service.isInitialized, isFalse);
      expect(nativeMethods, <String>['init', 'cleanup']);
      final notificationsAtDispose = notifications;

      // Post-disposal initialization neither resolves a path nor invokes native
      // code, and neither it nor reusable unload can notify a disposed notifier.
      expect(
        await service.initialize(modelPath: '/test/ggml-base.bin'),
        isFalse,
      );
      await service.unloadModel();
      await service.dispose();

      expect(resolverCalls, 1);
      expect(nativeMethods, <String>['init', 'cleanup']);
      expect(notifications, notificationsAtDispose);
    },
  );
}
