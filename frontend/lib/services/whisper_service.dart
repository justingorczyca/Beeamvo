import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

/// Service for offline transcription using whisper.cpp (Tiny model).
///
/// Wraps the native whisper.cpp plugin via a MethodChannel.
class WhisperService extends ChangeNotifier {
  static const MethodChannel _channel = MethodChannel('com.beeamvo/whisper');

  static const String defaultModelFileName = 'ggml-tiny.bin';
  static const String _appFolderName = 'Beeamvo';
  static const String _modelsFolderName = 'models';
  static final RegExp _safeModelFileNamePattern = RegExp(
    r'^ggml-[A-Za-z0-9][A-Za-z0-9._-]*\.bin$',
  );

  static String get _legacyExecutableDirectory =>
      File(Platform.resolvedExecutable).parent.path;

  static String get _preferredModelDirectory {
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return p.join(
          home,
          'Library',
          'Application Support',
          _appFolderName,
          _modelsFolderName,
        );
      }
    } else if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return p.join(appData, _appFolderName, _modelsFolderName);
      }
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        return p.join(localAppData, _appFolderName, _modelsFolderName);
      }
    } else if (Platform.isLinux) {
      // Use XDG_DATA_HOME or fallback to ~/.local/share
      final xdgDataHome = Platform.environment['XDG_DATA_HOME'];
      final home = Platform.environment['HOME'];
      if (xdgDataHome != null && xdgDataHome.isNotEmpty) {
        return p.join(xdgDataHome, _appFolderName, _modelsFolderName);
      } else if (home != null && home.isNotEmpty) {
        return p.join(
          home,
          '.local',
          'share',
          _appFolderName,
          _modelsFolderName,
        );
      }
    }
    return _legacyExecutableDirectory;
  }

  static Directory _ensureDirectory(String dirPath) {
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  /// Return true only for local whisper model basenames like `ggml-tiny.bin`.
  static bool isSafeModelFileName(String modelFileName) {
    try {
      validateModelFileName(modelFileName);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Validate and return a safe whisper model basename.
  static String validateModelFileName(String modelFileName) {
    final trimmed = modelFileName.trim();
    if (trimmed.isEmpty ||
        p.isAbsolute(trimmed) ||
        trimmed != p.basename(trimmed) ||
        !_safeModelFileNamePattern.hasMatch(trimmed)) {
      throw ArgumentError.value(
        modelFileName,
        'modelFileName',
        'Expected a safe whisper model basename such as ggml-tiny.bin',
      );
    }
    return trimmed;
  }

  /// Resolve a model path and require it to stay inside an allowed model dir.
  ///
  /// Relative input must be a safe model basename. Absolute input is accepted
  /// only if its resolved parent is the app model directory or the legacy
  /// executable directory.
  static String resolveAllowedModelPath(
    String modelPath, {
    bool mustExist = false,
    String? expectedFileName,
  }) {
    final input = modelPath.trim();
    final basename = validateModelFileName(p.basename(input));
    final expected = expectedFileName == null
        ? null
        : validateModelFileName(expectedFileName);

    if (expected != null && basename != expected) {
      throw ArgumentError.value(
        modelPath,
        'modelPath',
        'Model path basename must be $expected',
      );
    }

    final candidatePath = p.isAbsolute(input)
        ? input
        : input == basename
        ? getModelPath(basename)
        : throw ArgumentError.value(
            modelPath,
            'modelPath',
            'Relative model paths must be safe basenames',
          );

    final resolvedPath = mustExist
        ? File(candidatePath).resolveSymbolicLinksSync()
        : _resolvePathForWrite(candidatePath);

    if (!_isWithinAllowedModelDirectory(resolvedPath)) {
      throw ArgumentError.value(
        modelPath,
        'modelPath',
        'Resolved model path is outside the allowed model directories',
      );
    }

    return resolvedPath;
  }

  static String _buildPathInDirectory(
    String dirPath,
    String modelFileName, {
    bool create = false,
  }) {
    final safeFileName = validateModelFileName(modelFileName);
    final dir = create ? _ensureDirectory(dirPath) : Directory(dirPath);
    final resolvedDir = dir.resolveSymbolicLinksSync();
    final resolvedPath = p.normalize(p.join(resolvedDir, safeFileName));

    if (!p.isWithin(resolvedDir, resolvedPath)) {
      throw ArgumentError.value(
        modelFileName,
        'modelFileName',
        'Resolved model path is outside the model directory',
      );
    }

    return resolvedPath;
  }

  static String _resolvePathForWrite(String filePath) {
    final parent = Directory(p.dirname(filePath));
    final resolvedParent = parent.resolveSymbolicLinksSync();
    return p.normalize(p.join(resolvedParent, p.basename(filePath)));
  }

  static bool _isWithinAllowedModelDirectory(String filePath) {
    for (final dirPath in {
      _preferredModelDirectory,
      _legacyExecutableDirectory,
    }) {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) continue;

      final resolvedDir = dir.resolveSymbolicLinksSync();
      if (p.isWithin(resolvedDir, filePath)) return true;
    }

    return false;
  }

  /// Returns the writable model path for a model file.
  ///
  /// On macOS this is in `~/Library/Application Support/Beeamvo/models`.
  /// On Windows this is in `%APPDATA%\Beeamvo\models`.
  /// On Linux this is in `$XDG_DATA_HOME/Beeamvo/models` or `~/.local/share/Beeamvo/models`.
  /// The executable directory is kept only as a legacy read fallback.
  static String getWritableModelPath(String modelFileName) {
    return _buildPathInDirectory(
      _preferredModelDirectory,
      modelFileName,
      create: true,
    );
  }

  /// Get the default model path.
  static String get defaultModelPath => getModelPath(defaultModelFileName);

  /// Check if the default model exists
  static bool get modelExists => modelExistsAtPath(defaultModelFileName);

  /// Check if a specific model file exists
  static bool modelExistsAtPath(String modelPath) {
    try {
      return File(
        resolveAllowedModelPath(modelPath, mustExist: true),
      ).existsSync();
    } catch (_) {
      return false;
    }
  }

  /// Get the best path for a specific model file.
  ///
  /// Prefer the writable path, but fall back to legacy executable-dir placement
  /// if that file already exists there.
  static String getModelPath(String modelFileName) {
    final safeFileName = validateModelFileName(modelFileName);
    final preferredPath = getWritableModelPath(safeFileName);
    if (File(preferredPath).existsSync()) {
      return resolveAllowedModelPath(
        preferredPath,
        mustExist: true,
        expectedFileName: safeFileName,
      );
    }

    final legacyPath = _buildPathInDirectory(
      _legacyExecutableDirectory,
      safeFileName,
    );
    if (legacyPath != preferredPath && File(legacyPath).existsSync()) {
      return resolveAllowedModelPath(
        legacyPath,
        mustExist: true,
        expectedFileName: safeFileName,
      );
    }

    return preferredPath;
  }

  /// List all downloaded whisper models in the app directory
  static List<String> listDownloadedModels() {
    try {
      final modelIds = <String>{};
      final searchDirs = <String>{
        _preferredModelDirectory,
        _legacyExecutableDirectory,
      };

      for (final dirPath in searchDirs) {
        final dir = Directory(dirPath);
        if (!dir.existsSync()) continue;

        final files = dir.listSync();
        final ids = files
            .whereType<File>()
            .map((f) => p.basename(f.path))
            .where(isSafeModelFileName);
        modelIds.addAll(ids);
      }

      return modelIds.toList()..sort();
    } catch (e) {
      return [];
    }
  }

  /// Test seam for the native plugin. Production instances use [_channel].
  final Future<T?> Function<T>(String method, [Map<String, dynamic>? arguments])
  _invokeNative;

  /// Test seam for model-path validation. Production instances validate that
  /// the supplied path is an existing, allowed local model path.
  final String Function(String modelPath) _resolveModelPath;

  WhisperService({
    Future<T?> Function<T>(String method, [Map<String, dynamic>? arguments])?
    nativeInvoker,
    String Function(String modelPath)? modelPathResolver,
  }) : _invokeNative = nativeInvoker ?? _channel.invokeMethod,
       _resolveModelPath =
           modelPathResolver ??
           ((modelPath) => resolveAllowedModelPath(modelPath, mustExist: true));

  bool _isInitialized = false;
  bool _isLoading = false;
  bool _isDisposed = false;
  String? _loadedModelPath;
  String? _modelLoadError;

  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String? get loadedModelPath => _loadedModelPath;
  String? get modelLoadError => _modelLoadError;

  /// Notifies listeners only while this notifier is still usable.
  void _notifyListenersIfActive() {
    if (!_isDisposed) notifyListeners();
  }

  /// Initialize the whisper model from the given path.
  ///
  /// [modelPath] Path to the ggml model file (e.g., ggml-tiny.bin).
  /// [threads] Number of threads to use (0 = auto = CPU count).
  Future<bool> initialize({required String modelPath, int threads = 0}) async {
    // ChangeNotifier.dispose is terminal. In particular, do not validate a
    // path or notify listeners after final disposal.
    if (_isDisposed) return false;

    late final String safeModelPath;
    try {
      safeModelPath = _resolveModelPath(modelPath);
    } on ArgumentError catch (e) {
      _modelLoadError = 'Invalid model path: ${e.message}';
      _notifyListenersIfActive();
      return false;
    } on FileSystemException {
      _modelLoadError = 'Model file not found at $modelPath';
      _notifyListenersIfActive();
      return false;
    }

    if (_isInitialized) {
      // Already initialized with same model.
      if (_loadedModelPath == safeModelPath) return true;
      // Do not call dispose here: this instance and its listeners must remain
      // usable when switching models.
      await _unloadNativeModel();
    }

    // Final disposal can race an awaited unload in callers that do not
    // serialize transitions. Do not start another native operation then.
    if (_isDisposed) return false;

    _isLoading = true;
    _modelLoadError = null;
    _notifyListenersIfActive();

    try {
      final ok = await _invokeNative<bool>('init', {
        'modelPath': safeModelPath,
        'threads': threads,
      });
      final initialized = ok ?? false;

      // If final disposal occurred while native initialization was in flight,
      // release the just-created native model rather than reviving this
      // terminal notifier.
      if (_isDisposed) {
        if (initialized) await _cleanupNative();
        return false;
      }

      _isInitialized = initialized;
      if (_isInitialized) {
        _loadedModelPath = safeModelPath;
        _modelLoadError = null;
      } else {
        _modelLoadError = 'Model failed to load (init returned false)';
      }
      return _isInitialized;
    } catch (e) {
      _isInitialized = false;
      _modelLoadError = 'Model load error: $e';
      return false;
    } finally {
      _isLoading = false;
      _notifyListenersIfActive();
    }
  }

  /// Initialize with the default model.
  Future<bool> initializeDefault({int threads = 0}) async {
    if (_isDisposed) return false;
    return initialize(modelPath: defaultModelPath, threads: threads);
  }

  /// Transcribe raw PCM-16 audio bytes.
  ///
  /// [pcm16Bytes] Raw PCM-16LE audio data.
  /// [sampleRate] Sample rate (typically 16000).
  /// [channels] Number of channels (typically 1 = mono).
  /// [language] Language code (e.g., 'en', 'de', or 'auto' for auto-detect).
  Future<String> transcribeRawPcm(
    Uint8List pcm16Bytes, {
    int sampleRate = 16000,
    int channels = 1,
    String language = 'auto',
  }) async {
    if (!_isInitialized) {
      throw Exception(
        'WhisperService not initialized. Call initialize() first.',
      );
    }

    try {
      final text = await _invokeNative<String>('transcribeRaw', {
        'pcmBytes': pcm16Bytes,
        'sampleRate': sampleRate,
        'channels': channels,
        'language': language,
      });
      return text ?? '';
    } catch (e) {
      throw Exception('Transcription failed: $e');
    }
  }

  /// Request cancellation for an in-flight native transcription.
  ///
  /// Best-effort only: if no transcription is active, this is a no-op.
  Future<void> cancelTranscription() async {
    try {
      await _invokeNative<void>('cancel');
    } catch (_) {
      // Ignore cancellation errors to keep cancel path resilient.
    }
  }

  /// Unload the active native model without disposing this service.
  ///
  /// This is safe to call repeatedly and lets the same [WhisperService]
  /// instance be initialized again later. Callers that can request concurrent
  /// initialize/unload operations must serialize those operations.
  Future<void> unloadModel() async {
    if (_isDisposed) return;

    final changed = await _unloadNativeModel();
    if (changed) _notifyListenersIfActive();
  }

  /// Calls native cleanup and deliberately ignores plugin failures so that the
  /// Dart lifecycle state is always released.
  Future<void> _cleanupNative() async {
    try {
      await _invokeNative<void>('cleanup');
    } catch (_) {
      // Native cleanup is best effort.
    }
  }

  /// Release native model state without disposing the [ChangeNotifier].
  ///
  /// Returns whether a loaded model state was cleared. This private helper is
  /// used by both reusable unload and terminal disposal; it never notifies.
  Future<bool> _unloadNativeModel() async {
    final wasInitialized = _isInitialized;
    if (wasInitialized) await _cleanupNative();

    _isInitialized = false;
    _loadedModelPath = null;
    return wasInitialized;
  }

  /// Dispose and cleanup resources permanently.
  ///
  /// Final disposal is idempotent, but unlike [unloadModel] it makes this
  /// ChangeNotifier terminal and prevents all later notifications.
  @override
  Future<void> dispose() async {
    if (_isDisposed) return;
    _isDisposed = true;
    await _unloadNativeModel();
    super.dispose();
  }
}
