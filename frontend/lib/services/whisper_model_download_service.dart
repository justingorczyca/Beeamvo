import 'dart:async';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'pinned_http_client.dart';
import 'whisper_service.dart';

/// Download status enum for tracking download progress
enum DownloadStatus { idle, downloading, completed, error, cancelled }

/// Model info for available whisper models
class WhisperModelInfo {
  final String id;
  final String name;
  final String url;
  final int sizeBytes;
  final String sizeDisplay;
  final int maxSizeBytes;
  final String sha256;
  final String sha1;

  const WhisperModelInfo({
    required this.id,
    required this.name,
    required this.url,
    required this.sizeBytes,
    required this.sizeDisplay,
    this.sha256 = '',
    this.sha1 = '',
    int? maxSizeBytes,
  }) : maxSizeBytes = maxSizeBytes ?? sizeBytes;
}

/// Service for downloading whisper.cpp models from Hugging Face
class WhisperModelDownloadService extends ChangeNotifier {
  static const String _huggingFaceBaseUrl =
      'https://huggingface.co/ggerganov/whisper.cpp/resolve/main';
  static const Duration requestTimeout = Duration(seconds: 30);
  static const Duration downloadIdleTimeout = Duration(minutes: 2);
  static const Duration progressNotifyInterval = Duration(milliseconds: 200);
  static const double progressNotifyStep = 0.01;

  static void _debugLog(String message) {
    if (kDebugMode) debugPrint(message);
  }

  /// Available models for download
  static const List<WhisperModelInfo> availableModels = [
    WhisperModelInfo(
      id: 'ggml-tiny.bin',
      name: 'Tiny',
      url: '$_huggingFaceBaseUrl/ggml-tiny.bin',
      sizeBytes: 77691713,
      sizeDisplay: '~75 MB',
      sha256:
          'be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21',
      sha1: 'bd577a113a864445d4c299885e0cb97d4ba92b5f',
    ),
    WhisperModelInfo(
      id: 'ggml-tiny.en.bin',
      name: 'Tiny (English)',
      url: '$_huggingFaceBaseUrl/ggml-tiny.en.bin',
      sizeBytes: 77704715,
      sizeDisplay: '~75 MB',
      sha256:
          '921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f',
      sha1: 'c78c86eb1a8faa21b369bcd33207cc90d64ae9df',
    ),
    WhisperModelInfo(
      id: 'ggml-tiny-q5_1.bin',
      name: 'Tiny Q5 (Quantized)',
      url: '$_huggingFaceBaseUrl/ggml-tiny-q5_1.bin',
      sizeBytes: 32152673,
      sizeDisplay: '~32 MB',
      sha256:
          '818710568da3ca15689e31a743197b520007872ff9576237bda97bd1b469c3d7',
      sha1: '2827a03e495b1ed3048ef28a6a4620537db4ee51',
    ),
    WhisperModelInfo(
      id: 'ggml-base.bin',
      name: 'Base',
      url: '$_huggingFaceBaseUrl/ggml-base.bin',
      sizeBytes: 147951465,
      sizeDisplay: '~148 MB',
      sha256:
          '60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe',
      sha1: '465707469ff3a37a2b9b8d8f89f2f99de7299dac',
    ),
    WhisperModelInfo(
      id: 'ggml-small.bin',
      name: 'Small',
      url: '$_huggingFaceBaseUrl/ggml-small.bin',
      sizeBytes: 487601967,
      sizeDisplay: '~488 MB',
      sha256:
          '1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b',
      sha1: '55356645c2b361a969dfd0ef2c5a50d530afd8d5',
    ),
  ];

  /// Get the default model info (tiny)
  static WhisperModelInfo get defaultModel => availableModels.first;

  DownloadStatus _status = DownloadStatus.idle;
  double _progress = 0.0;
  String? _errorMessage;
  String? _currentModelId;
  int _bytesDownloaded = 0;
  int _totalBytes = 0;
  DateTime? _lastProgressNotificationAt;
  double _lastNotifiedProgress = -1.0;

  http.Client? _httpClient;
  IOSink? _fileSink;
  File? _tempFile;
  StreamIterator<List<int>>? _activeStreamIterator;
  Future<void>? _cleanupFuture;
  bool _isCancelled = false;
  bool _isDisposed = false;
  final http.Client? _providedHttpClient;

  // This hook and [beginDownloadForTesting] allow lifecycle behavior to be
  // exercised without starting a platform-specific file or HTTP download.
  final Future<void> Function()? _testCleanup;

  WhisperModelDownloadService({http.Client? httpClient})
    : _providedHttpClient = httpClient,
      _testCleanup = null;

  @visibleForTesting
  WhisperModelDownloadService.forTesting({Future<void> Function()? cleanup})
    : _providedHttpClient = null,
      _testCleanup = cleanup;

  @visibleForTesting
  void beginDownloadForTesting() {
    if (_isDisposed) return;
    _resetState();
    _isCancelled = false;
    _status = DownloadStatus.downloading;
    _notifyListenersSafely();
  }

  // Getters
  DownloadStatus get status => _status;
  double get progress => _progress;
  String? get errorMessage => _errorMessage;
  String? get currentModelId => _currentModelId;
  int get bytesDownloaded => _bytesDownloaded;
  int get totalBytes => _totalBytes;

  /// Check if a model exists at the given path
  static bool modelExists(String modelPath) =>
      WhisperService.modelExistsAtPath(modelPath);

  /// Get the resolved model path (supports legacy executable-dir placement).
  static String getModelPath(String modelFileName) {
    return WhisperService.getModelPath(modelFileName);
  }

  /// Get the writable model path for downloads.
  static String getWritableModelPath(String modelFileName) {
    return WhisperService.getWritableModelPath(modelFileName);
  }

  /// Get model info by ID
  static WhisperModelInfo? getModelInfo(String modelId) {
    try {
      final safeModelId = WhisperService.validateModelFileName(modelId);
      return availableModels.firstWhere((m) => m.id == safeModelId);
    } catch (_) {
      return null;
    }
  }

  /// Download a model to the specified path
  Future<bool> downloadModel(
    WhisperModelInfo model, {
    String? targetPath,
    void Function(double progress, int downloaded, int total)? onProgress,
  }) async {
    if (_isDisposed || _status == DownloadStatus.downloading) {
      _debugLog('[WhisperDownload] Download already in progress');
      return false;
    }

    final downloadModel = getModelInfo(model.id);
    if (downloadModel == null) {
      _resetState();
      _errorMessage = 'Unknown or unsafe whisper model id: ${model.id}';
      _status = DownloadStatus.error;
      _notifyListenersSafely();
      return false;
    }

    _resetState();
    _currentModelId = downloadModel.id;
    _status = DownloadStatus.downloading;
    _totalBytes = downloadModel.sizeBytes;
    _notifyListenersSafely();

    // Default to the certificate-pinning client. huggingface.co ships with an
    // empty pin allow-list, so this is identical to a plain http.Client() until a
    // maintainer captures and pins a leaf hash. The injected seam is preserved:
    // tests/production can still pass their own http.Client via the ctor.
    _httpClient = _providedHttpClient ?? createPinnedHttpClient();
    _isCancelled = false;

    try {
      final outputPath = WhisperService.resolveAllowedModelPath(
        targetPath ?? getWritableModelPath(downloadModel.id),
        expectedFileName: downloadModel.id,
      );

      _debugLog('[WhisperDownload] Starting download for ${downloadModel.id}');
      _debugLog(
        '[WhisperDownload] Target path resolved for ${downloadModel.id}',
      );

      final request = http.Request('GET', Uri.parse(downloadModel.url));
      final response = await _httpClient!.send(request).timeout(requestTimeout);

      if (_isCancelled) {
        return _finishCancellation();
      }

      if (response.statusCode != 200) {
        throw Exception(
          'HTTP ${response.statusCode}: Failed to download model',
        );
      }

      // Get actual content length if available
      final contentLength = response.contentLength;
      if (contentLength != null && contentLength > 0) {
        _validateExpectedSize(contentLength, downloadModel);
        _totalBytes = contentLength;
      }

      // Create temp file for download
      _tempFile = File('$outputPath.download');
      final tempLink = Link(_tempFile!.path);
      if (await tempLink.exists()) {
        await tempLink.delete();
      }
      if (await _tempFile!.exists()) {
        await _tempFile!.delete();
      }
      _fileSink = _tempFile!.openWrite();

      _bytesDownloaded = 0;
      final streamIterator = StreamIterator<List<int>>(
        response.stream.timeout(downloadIdleTimeout),
      );
      _activeStreamIterator = streamIterator;
      try {
        while (await streamIterator.moveNext()) {
          if (_isCancelled) {
            return _finishCancellation();
          }

          final chunk = streamIterator.current;
          _fileSink!.add(chunk);
          _bytesDownloaded += chunk.length;
          _validateExpectedSize(_bytesDownloaded, downloadModel);

          // Update progress
          if (_totalBytes > 0) {
            _progress = _bytesDownloaded / _totalBytes;
          }

          if (!_isDisposed) {
            onProgress?.call(_progress, _bytesDownloaded, _totalBytes);
          }
          _notifyProgressListeners();
        }
      } finally {
        if (identical(_activeStreamIterator, streamIterator)) {
          _activeStreamIterator = null;
        }
        await streamIterator.cancel();
      }

      if (_isCancelled) {
        return _finishCancellation();
      }

      await _fileSink!.flush();
      await _fileSink!.close();
      _fileSink = null;

      if (_isCancelled) {
        return _finishCancellation();
      }

      if (!await _verifyIntegrity(downloadModel)) {
        await _cleanup();
        _errorMessage =
            'Download integrity check failed. The file may be corrupted or '
            'tampered with. Please try again.';
        _status = DownloadStatus.error;
        _notifyListenersSafely();
        return false;
      }

      if (_isCancelled) {
        return _finishCancellation();
      }

      // Move temp file to final destination
      if (_tempFile != null && await _tempFile!.exists()) {
        // Delete existing file if present
        final finalFile = File(outputPath);
        final finalLink = Link(outputPath);
        if (await finalFile.exists()) {
          WhisperService.resolveAllowedModelPath(
            outputPath,
            mustExist: true,
            expectedFileName: downloadModel.id,
          );
          await finalFile.delete();
        } else if (await finalLink.exists()) {
          await finalLink.delete();
        }

        await _tempFile!.rename(outputPath);
        _debugLog('[WhisperDownload] Download complete: ${downloadModel.id}');
      }

      _status = DownloadStatus.completed;
      _progress = 1.0;
      _notifyListenersSafely();
      return true;
    } catch (e) {
      if (_isCancelled) {
        return _finishCancellation();
      }
      _debugLog('[WhisperDownload] Download error: ${e.runtimeType}');
      _errorMessage = e.toString();
      _status = DownloadStatus.error;
      await _cleanup();
      _notifyListenersSafely();
      return false;
    } finally {
      if (_providedHttpClient == null) {
        _httpClient?.close();
      }
      _httpClient = null;
    }
  }

  /// Cancel the current download and remove its partial download file.
  ///
  /// [notifyListeners] is disabled by page teardown so cancellation and cleanup
  /// can finish before the notifier is disposed without scheduling UI work.
  Future<void> cancelDownload({bool notifyListeners = true}) async {
    if (_status != DownloadStatus.downloading) return;

    _isCancelled = true;
    await _activeStreamIterator?.cancel();
    await _finishCancellation(notifyListeners: notifyListeners);
  }

  /// Ends page-owned work before disposing this notifier.
  ///
  /// Widget [State.dispose] cannot be async, so callers intentionally do not
  /// await this future. The notifier remains alive until cleanup has completed.
  Future<void> cancelAndDispose() async {
    await cancelDownload(notifyListeners: false);
    dispose();
  }

  /// Delete a downloaded model
  Future<bool> deleteModel(String modelId) async {
    try {
      final safeModelId = WhisperService.validateModelFileName(modelId);
      final path = WhisperService.resolveAllowedModelPath(
        getModelPath(safeModelId),
        mustExist: true,
        expectedFileName: safeModelId,
      );
      final file = File(path);
      final coreMlDir = Directory(_getCoreMlEncoderPath(path));
      if (await file.exists()) {
        String? resolvedCoreMlPath;
        if (await coreMlDir.exists()) {
          final modelDir = Directory(
            p.dirname(path),
          ).resolveSymbolicLinksSync();
          final resolvedCoreMl = coreMlDir.resolveSymbolicLinksSync();
          if (!p.isWithin(modelDir, resolvedCoreMl)) {
            throw Exception('Core ML encoder path is outside the model dir');
          }
          resolvedCoreMlPath = resolvedCoreMl;
        }

        await file.delete();
        if (resolvedCoreMlPath != null) {
          await Directory(resolvedCoreMlPath).delete(recursive: true);
        }
        _debugLog('[WhisperDownload] Deleted model: $safeModelId');
        _notifyListenersSafely();
        return true;
      }
      return false;
    } catch (e) {
      _debugLog('[WhisperDownload] Error deleting model: ${e.runtimeType}');
      return false;
    }
  }

  /// Reset the download state
  void resetState() {
    _resetState();
    _notifyListenersSafely();
  }

  void _resetState() {
    _status = DownloadStatus.idle;
    _progress = 0.0;
    _errorMessage = null;
    _currentModelId = null;
    _bytesDownloaded = 0;
    _totalBytes = 0;
    _lastProgressNotificationAt = null;
    _lastNotifiedProgress = -1.0;
  }

  void _notifyProgressListeners() {
    final now = DateTime.now();
    final lastNotificationAt = _lastProgressNotificationAt;
    final progressDelta = (_progress - _lastNotifiedProgress).abs();
    final shouldNotify =
        lastNotificationAt == null ||
        now.difference(lastNotificationAt) >= progressNotifyInterval ||
        progressDelta >= progressNotifyStep;

    if (!shouldNotify) return;

    _lastProgressNotificationAt = now;
    _lastNotifiedProgress = _progress;
    _notifyListenersSafely();
  }

  Future<bool> _finishCancellation({bool notifyListeners = true}) async {
    _debugLog('[WhisperDownload] Download cancelled');
    await _cleanup();
    final statusChanged = _status != DownloadStatus.cancelled;
    _status = DownloadStatus.cancelled;
    if (notifyListeners && statusChanged) {
      _notifyListenersSafely();
    }
    return false;
  }

  Future<void> _cleanup() {
    final activeCleanup = _cleanupFuture;
    if (activeCleanup != null) return activeCleanup;

    late final Future<void> cleanup;
    cleanup = _performCleanup().whenComplete(() {
      if (identical(_cleanupFuture, cleanup)) {
        _cleanupFuture = null;
      }
    });
    _cleanupFuture = cleanup;
    return cleanup;
  }

  Future<void> _performCleanup() async {
    try {
      await _testCleanup?.call();
      await _fileSink?.close();
      _fileSink = null;

      if (_tempFile != null && await _tempFile!.exists()) {
        await _tempFile!.delete();
      }
      _tempFile = null;
    } catch (e) {
      _debugLog('[WhisperDownload] Cleanup error: ${e.runtimeType}');
    }
  }

  void _notifyListenersSafely() {
    if (!_isDisposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_isDisposed) return;
    final hasActiveDownload = _status == DownloadStatus.downloading;
    _isDisposed = true;
    _isCancelled = true;
    unawaited(_activeStreamIterator?.cancel() ?? Future<void>.value());
    if (hasActiveDownload) {
      unawaited(_cleanup());
    }
    if (_providedHttpClient == null) {
      _httpClient?.close();
    }
    _httpClient = null;
    super.dispose();
  }

  Future<bool> _verifyIntegrity(WhisperModelInfo model) async {
    if (_tempFile == null || !await _tempFile!.exists()) return false;

    if (model.sha256.isNotEmpty) {
      _debugLog('[WhisperDownload] Verifying SHA-256 checksum...');
      final digest = await sha256.bind(_tempFile!.openRead()).first;
      final actualHash = digest.toString();
      if (actualHash != model.sha256) {
        _debugLog('[WhisperDownload] SHA-256 mismatch for ${model.id}');
        return false;
      }
      _debugLog('[WhisperDownload] SHA-256 verified for ${model.id}');
      return true;
    }

    if (model.sha1.isNotEmpty) {
      _debugLog('[WhisperDownload] Verifying legacy SHA-1 checksum...');
      final digest = await sha1.bind(_tempFile!.openRead()).first;
      final actualHash = digest.toString();
      if (actualHash != model.sha1) {
        _debugLog('[WhisperDownload] SHA-1 mismatch for ${model.id}');
        return false;
      }
      _debugLog('[WhisperDownload] SHA-1 verified for ${model.id}');
    }

    return true;
  }

  static void _validateExpectedSize(int bytes, WhisperModelInfo model) {
    if (bytes > model.maxSizeBytes) {
      throw Exception(
        'Downloaded model exceeds the expected maximum size of '
        '${formatBytes(model.maxSizeBytes)}',
      );
    }
  }

  /// Format bytes to human-readable string
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  /// Format progress as percentage string
  static String formatProgress(double progress) {
    return '${(progress * 100).toStringAsFixed(1)}%';
  }

  static String _getCoreMlEncoderPath(String modelPath) {
    final dir = p.dirname(modelPath);
    var base = p.basenameWithoutExtension(modelPath);

    final quantizedSuffix = RegExp(
      r'-q[a-z0-9]+_[a-z0-9]+$',
      caseSensitive: false,
    );
    base = base.replaceFirst(quantizedSuffix, '');

    return p.join(dir, '$base-encoder.mlmodelc');
  }
}
