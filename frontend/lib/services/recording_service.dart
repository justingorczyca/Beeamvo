import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

/// Service for audio recording
///
/// Handles microphone access and audio capture.
///
/// On macOS this routes through a custom native `AVAudioEngine` plugin
/// (`com.beeamvo/mac_audio_capture`) because the third-party `record_macos`
/// plugin races file finalize and routinely returns empty WAVs for
/// menu-bar / LSUIElement apps. Windows/Linux keep using the `record` package.
class RecordingService {
  RecordingService() {
    unawaited(_sweepStaleRecordings());
  }

  static final DateTime _processStartedAt = DateTime.now();
  static const MethodChannel _macChannel = MethodChannel(
    'com.beeamvo/mac_audio_capture',
  );

  final AudioRecorder _recorder = AudioRecorder();
  String? _currentRecordingPath;
  bool _isRecording = false;
  String? _selectedDeviceId;

  Future<void> _sweepStaleRecordings() async {
    try {
      final directory = await getTemporaryDirectory();
      final pattern = RegExp(r'^beeamvo_recording_(\d+)\.wav$');
      await for (final entity in directory.list()) {
        if (entity is! File) continue;
        final match = pattern.firstMatch(entity.uri.pathSegments.last);
        final timestamp = match == null ? null : int.tryParse(match.group(1)!);
        if (timestamp == null ||
            timestamp >= _processStartedAt.millisecondsSinceEpoch) {
          continue;
        }
        try {
          final lastModified = await entity.lastModified();
          if (DateTime.now().difference(lastModified) <
              const Duration(minutes: 10)) {
            continue;
          }
          await entity.delete();
        } catch (_) {
          // Best effort: a stale recording must never block startup or dispose.
        }
      }
    } catch (_) {
      // Best effort: temporary-directory access can fail during shutdown.
    }
  }

  // Stream-based recording support
  bool _isStreamRecording = false;
  StreamSubscription<Uint8List>? _audioStreamSub;
  BytesBuilder _streamBuffer = BytesBuilder(copy: false);
  Completer<void>? _streamDoneCompleter;
  Object? _streamError;

  /// True while the macOS native AVAudioEngine path owns the session.
  bool _usingMacNative = false;

  /// PCM captured via the macOS native path, held until [getAudioBytes] /
  /// [stopStreamAndGetPcm] consumes it (or a WAV is materialized).
  Uint8List? _macNativePcm;

  static bool get _useMacNativeCapture => Platform.isMacOS;

  /// Get the list of available input devices
  Future<List<InputDevice>> listInputDevices() async {
    if (_useMacNativeCapture) {
      try {
        final raw = await _macChannel.invokeMethod<List<dynamic>>(
          'listInputDevices',
        );
        if (raw == null) return const [];
        return raw
            .whereType<Map>()
            .map(
              (m) => InputDevice(
                id: (m['id'] as String?) ?? '',
                label: (m['label'] as String?) ?? '',
              ),
            )
            .where((d) => d.id.isNotEmpty)
            .toList(growable: false);
      } catch (e) {
        debugPrint('[RecordingService] mac listInputDevices failed: $e');
        // Fall through to the package list as a secondary source.
      }
    }
    try {
      return await _recorder.listInputDevices();
    } catch (e) {
      debugPrint('[RecordingService] listInputDevices failed: $e');
      return const [];
    }
  }

  /// Set the preferred input device (null for default)
  void setPreferredDevice(String? deviceId) {
    final normalized = (deviceId == null || deviceId.isEmpty) ? null : deviceId;
    if (_selectedDeviceId != normalized) {
      debugPrint(
        '[RecordingService] preferred device → ${normalized ?? "System Default"}',
      );
    }
    _selectedDeviceId = normalized;
  }

  /// Currently preferred device id, or null for system default.
  String? get preferredDeviceId => _selectedDeviceId;

  /// Check if microphone permission is available
  Future<bool> hasPermission() async {
    if (_useMacNativeCapture) {
      try {
        final ok = await _macChannel.invokeMethod<bool>('hasPermission');
        return ok ?? false;
      } catch (e) {
        debugPrint('[RecordingService] mac hasPermission failed: $e');
        return false;
      }
    }
    try {
      return await _recorder.hasPermission();
    } catch (e) {
      debugPrint('[RecordingService] hasPermission failed: $e');
      return false;
    }
  }

  /// Snapshot of mic readiness used before starting a session.
  ///
  /// Validates that a previously selected device still exists. When the saved
  /// id is stale (unplugged headset, renamed driver, empty picker), the
  /// preferred device is cleared so the next start uses the OS default instead
  /// of failing with an opaque empty capture.
  Future<MicReadiness> assessMicReadiness() async {
    final permission = await hasPermission();
    final devices = await listInputDevices();
    final preferred = _selectedDeviceId;
    var resolvedDeviceId = preferred;
    var fellBackToDefault = false;

    if (preferred != null) {
      final stillPresent = devices.any((d) => d.id == preferred);
      if (!stillPresent) {
        debugPrint(
          '[RecordingService] preferred device "$preferred" not in '
          '${devices.length} available input(s); falling back to System Default',
        );
        _selectedDeviceId = null;
        resolvedDeviceId = null;
        fellBackToDefault = true;
      }
    }

    // On some platforms an empty device list still allows the OS default mic.
    // We only hard-fail when permission is denied; empty list is a warning.
    return MicReadiness(
      hasPermission: permission,
      devices: devices,
      resolvedDeviceId: resolvedDeviceId,
      fellBackToDefault: fellBackToDefault,
    );
  }

  InputDevice? _deviceForConfig() {
    final id = _selectedDeviceId;
    if (id == null || id.isEmpty) return null;
    return InputDevice(id: id, label: '');
  }

  /// Start recording audio
  ///
  /// Returns true if recording started successfully.
  Future<bool> startRecording() async {
    if (_isRecording || _isStreamRecording) {
      debugPrint('[RecordingService] startRecording ignored: already active');
      return false;
    }

    // Check permission
    if (!await hasPermission()) {
      debugPrint('[RecordingService] startRecording blocked: no permission');
      return false;
    }

    if (_useMacNativeCapture) {
      return _startMacNative(asStream: false);
    }

    // Get temp directory for audio file
    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _currentRecordingPath =
        '${directory.path}/beeamvo_recording_$timestamp.wav';

    // Configure recording - WAV format for best Gemini compatibility
    final preferredConfig = RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000, // 16kHz as recommended for speech
      numChannels: 1, // Mono
      device: _deviceForConfig(),
    );

    // Start recording. A throw can leave the native recorder partially
    // started; best-effort stop it so a failed start can never keep the
    // microphone hot, then surface the error to the caller as before.
    //
    // If a specific device fails (stale id / driver glitch), retry once with
    // the system default so an empty/broken selection cannot hard-crash the
    // session path.
    try {
      await _recorder.start(preferredConfig, path: _currentRecordingPath!);
    } catch (e) {
      debugPrint(
        '[RecordingService] start with preferred device failed: $e '
        '(device=${_selectedDeviceId ?? "default"})',
      );
      await _bestEffortStopRecorder();

      if (_selectedDeviceId != null) {
        debugPrint(
          '[RecordingService] retrying start with System Default device',
        );
        _selectedDeviceId = null;
        final fallbackConfig = RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
          device: null,
        );
        try {
          await _recorder.start(fallbackConfig, path: _currentRecordingPath!);
        } catch (fallbackError) {
          debugPrint(
            '[RecordingService] fallback start also failed: $fallbackError',
          );
          await _bestEffortStopRecorder();
          _currentRecordingPath = null;
          rethrow;
        }
      } else {
        _currentRecordingPath = null;
        rethrow;
      }
    }

    _isRecording = true;
    debugPrint(
      '[RecordingService] file recording started → $_currentRecordingPath',
    );
    return true;
  }

  /// Stop recording and return the audio file path
  ///
  /// Returns the path to the recorded audio file, or null if not recording.
  Future<String?> stopRecording() async {
    if (!_isRecording) {
      return null;
    }

    if (_usingMacNative) {
      return _stopMacNativeToWavPath();
    }

    final path = await _recorder.stop() ?? _currentRecordingPath;
    _isRecording = false;
    if (_isStreamRecording) {
      await _stopStreamRecording();
    }

    // Defensive wait for packages that finalize async (kept for non-macOS).
    if (path != null) {
      await _waitForRecordingFile(path);
    }
    return path;
  }

  /// Get the audio file as bytes
  Future<Uint8List?> getAudioBytes() async {
    // macOS native path: always prefer in-memory PCM → WAV. Do not require
    // the on-disk file to already exist (cloud used to crash with
    // PathNotFoundException when the cache dir/file had not been written).
    final nativePcm = _macNativePcm;
    if (nativePcm != null && nativePcm.isNotEmpty) {
      final wav = buildMono16kWav(nativePcm);
      // Best-effort persist for retry flows; cloud only needs the bytes.
      await _writeWavFileBestEffort(wav);
      return wav;
    }

    if (_currentRecordingPath == null) {
      return null;
    }

    final file = File(_currentRecordingPath!);
    if (await file.exists()) {
      await _waitForRecordingFile(_currentRecordingPath!);
      if (await file.exists()) {
        return await file.readAsBytes();
      }
    }
    return null;
  }

  /// True when in-memory PCM streaming is the preferred capture path.
  ///
  /// Offline Whisper prefers raw PCM. On macOS that is the native
  /// AVAudioEngine plugin; on Windows/Linux the `record` package stream.
  /// iOS is excluded until a dedicated capture path exists there.
  static bool get prefersStreamCapture => !Platform.isIOS;

  /// Poll until the WAV has real PCM payload or [timeout] elapses.
  ///
  /// A RIFF header alone is ~44 bytes. We wait until the file grows past that
  /// and its size stays stable for two consecutive polls, which is a practical
  /// signal that AVCapture finished flushing.
  Future<void> _waitForRecordingFile(
    String path, {
    Duration timeout = const Duration(milliseconds: 2000),
  }) async {
    final file = File(path);
    final deadline = DateTime.now().add(timeout);
    var lastSize = -1;
    var stableHits = 0;

    while (DateTime.now().isBefore(deadline)) {
      try {
        if (await file.exists()) {
          final size = await file.length();
          // 44-byte header + at least ~20ms of 16 kHz mono PCM-16 (~640 bytes).
          if (size >= 44 + 640) {
            if (size == lastSize) {
              stableHits++;
              if (stableHits >= 2) {
                debugPrint(
                  '[RecordingService] recording file ready: $size bytes',
                );
                return;
              }
            } else {
              stableHits = 0;
            }
          }
          lastSize = size;
        }
      } catch (e) {
        debugPrint('[RecordingService] file wait probe failed: $e');
      }
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }

    debugPrint(
      '[RecordingService] recording file wait timed out '
      '(lastSize=$lastSize path=$path)',
    );
  }

  /// Extracts mono, 16 kHz, 16-bit little-endian PCM data from a RIFF/WAV file.
  ///
  /// WAV containers may include optional chunks (for example `LIST` or `fact`),
  /// so callers must not assume the PCM data always begins at byte 44.
  ///
  /// Accepts mono or stereo PCM-16 at common sample rates (16 / 22.05 / 44.1 /
  /// 48 kHz, etc.) and downmixes + resamples to 16 kHz mono for Whisper.
  /// Throws a [FormatException] for truncated containers and unsupported codecs.
  static Uint8List extractMono16kPcmFromWav(Uint8List wavBytes) {
    if (wavBytes.length < 12 ||
        !_hasAsciiAt(wavBytes, 0, 'RIFF') ||
        !_hasAsciiAt(wavBytes, 8, 'WAVE')) {
      throw const FormatException('Recording is not a RIFF/WAV file.');
    }

    int? audioFormat;
    int? channels;
    int? sampleRate;
    int? bitsPerSample;
    int? blockAlign;
    int? dataOffset;
    int? dataLength;
    var offset = 12;

    while (offset < wavBytes.length) {
      if (offset + 8 > wavBytes.length) {
        throw const FormatException('WAV file has a truncated chunk header.');
      }

      final chunkId = String.fromCharCodes(
        wavBytes.sublist(offset, offset + 4),
      );
      final chunkLength = ByteData.sublistView(
        wavBytes,
      ).getUint32(offset + 4, Endian.little);
      final chunkDataOffset = offset + 8;
      final chunkEnd = chunkDataOffset + chunkLength;
      if (chunkEnd > wavBytes.length) {
        throw FormatException('WAV $chunkId chunk is truncated.');
      }

      if (chunkId == 'fmt ') {
        if (chunkLength < 16) {
          throw const FormatException('WAV format chunk is too short.');
        }
        final data = ByteData.sublistView(wavBytes);
        audioFormat = data.getUint16(chunkDataOffset, Endian.little);
        channels = data.getUint16(chunkDataOffset + 2, Endian.little);
        sampleRate = data.getUint32(chunkDataOffset + 4, Endian.little);
        blockAlign = data.getUint16(chunkDataOffset + 12, Endian.little);
        bitsPerSample = data.getUint16(chunkDataOffset + 14, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = chunkDataOffset;
        dataLength = chunkLength;
      }

      // RIFF chunks are word-aligned; odd-sized chunks include one pad byte.
      offset = chunkEnd + (chunkLength.isOdd ? 1 : 0);
    }

    // 1 = PCM, 65534 = WAVE_FORMAT_EXTENSIBLE (still linear PCM when bits=16).
    if (audioFormat != 1 && audioFormat != 65534) {
      throw FormatException(
        'Unsupported WAV codec: format=$audioFormat (need PCM).',
      );
    }
    final resolvedChannels = channels;
    final resolvedRate = sampleRate;
    final resolvedBits = bitsPerSample;
    final resolvedDataOffset = dataOffset;
    final resolvedDataLength = dataLength;
    if (resolvedChannels == null ||
        resolvedChannels < 1 ||
        resolvedRate == null ||
        resolvedRate <= 0 ||
        resolvedBits == null ||
        resolvedBits != 16) {
      throw FormatException(
        'Unsupported WAV format: expected PCM-16, received '
        'format=$audioFormat channels=$channels sampleRate=$sampleRate '
        'bits=$bitsPerSample.',
      );
    }
    if (resolvedDataOffset == null ||
        resolvedDataLength == null ||
        resolvedDataLength == 0) {
      throw const FormatException('WAV file contains no PCM audio data.');
    }
    if (resolvedDataLength.isOdd) {
      throw const FormatException(
        'PCM-16 audio data must have an even byte length.',
      );
    }

    // bits is known 16-bit PCM after the guard above.
    const bytesPerSample = 2;
    final bytesPerFrame = (blockAlign != null && blockAlign > 0)
        ? blockAlign
        : resolvedChannels * bytesPerSample;
    if (bytesPerFrame <= 0 || resolvedDataLength < bytesPerFrame) {
      throw const FormatException('WAV PCM payload is too short.');
    }

    // Fast path: already mono 16 kHz PCM-16 — return the payload as-is.
    if (resolvedChannels == 1 && resolvedRate == 16000 && bytesPerFrame == 2) {
      return Uint8List.sublistView(
        wavBytes,
        resolvedDataOffset,
        resolvedDataOffset + resolvedDataLength,
      );
    }

    final frameCount = resolvedDataLength ~/ bytesPerFrame;
    final dataView = ByteData.sublistView(
      wavBytes,
      resolvedDataOffset,
      resolvedDataOffset + (frameCount * bytesPerFrame),
    );

    // Downmix to mono float in [-1, 1].
    final mono = Float32List(frameCount);
    for (var frame = 0; frame < frameCount; frame++) {
      final frameOffset = frame * bytesPerFrame;
      var sampleSum = 0.0;
      for (var ch = 0; ch < resolvedChannels; ch++) {
        final s = dataView.getInt16(frameOffset + ch * 2, Endian.little);
        sampleSum += s / 32768.0;
      }
      mono[frame] = (sampleSum / resolvedChannels).clamp(-1.0, 1.0);
    }

    final Float32List at16k;
    if (resolvedRate == 16000) {
      at16k = mono;
    } else {
      at16k = _resampleLinear(mono, resolvedRate, 16000);
      debugPrint(
        '[RecordingService] resampled WAV $resolvedRate Hz → 16000 Hz '
        '(${mono.length} → ${at16k.length} frames, ch=$resolvedChannels)',
      );
    }

    final pcm = Uint8List(at16k.length * 2);
    final pcmView = ByteData.sublistView(pcm);
    for (var i = 0; i < at16k.length; i++) {
      final s = (at16k[i] * 32767.0).round().clamp(-32768, 32767);
      pcmView.setInt16(i * 2, s, Endian.little);
    }
    return pcm;
  }

  /// Linear-interpolation resampler for mono float audio.
  static Float32List _resampleLinear(
    Float32List input,
    int sourceRate,
    int targetRate,
  ) {
    if (input.isEmpty || sourceRate <= 0 || targetRate <= 0) {
      return Float32List(0);
    }
    if (sourceRate == targetRate) return input;

    final outLength = math.max(
      1,
      ((input.length * targetRate) / sourceRate).round(),
    );
    final output = Float32List(outLength);
    final ratio = sourceRate / targetRate;
    final last = input.length - 1;
    for (var i = 0; i < outLength; i++) {
      final srcPos = i * ratio;
      final i0 = srcPos.floor().clamp(0, last);
      final i1 = (i0 + 1).clamp(0, last);
      final frac = srcPos - i0;
      output[i] = input[i0] * (1.0 - frac) + input[i1] * frac;
    }
    return output;
  }

  static bool _hasAsciiAt(Uint8List bytes, int offset, String expected) {
    if (offset + expected.length > bytes.length) return false;
    for (var index = 0; index < expected.length; index++) {
      if (bytes[offset + index] != expected.codeUnitAt(index)) return false;
    }
    return true;
  }

  /// Delete the current recording file
  Future<void> deleteRecording() async {
    _macNativePcm = null;
    if (_currentRecordingPath != null) {
      final file = File(_currentRecordingPath!);
      if (await file.exists()) {
        await file.delete();
      }
      _currentRecordingPath = null;
    }
  }

  /// Check if currently recording
  bool get isRecording => _isRecording;

  /// Get current recording path
  String? get currentRecordingPath => _currentRecordingPath;

  /// Dispose and cleanup
  Future<void> dispose() async {
    if (_usingMacNative || _isRecording) {
      await _bestEffortStopRecorder();
      _isRecording = false;
      _isStreamRecording = false;
    }
    await _stopStreamRecording();
    await deleteRecording();
    await _sweepStaleRecordings();
    if (!_useMacNativeCapture) {
      await _recorder.dispose();
    } else {
      // Still dispose the package recorder in case device listing used it.
      try {
        await _recorder.dispose();
      } catch (_) {}
    }
  }

  // ===========================================================================
  // Stream-based Recording (for offline backends)
  // ===========================================================================

  /// Check if stream recording is active.
  bool get isStreamRecording => _isStreamRecording;

  /// Start stream-based recording for offline backends.
  ///
  /// Records audio into an in-memory buffer that can be passed directly
  /// to offline transcription models without file I/O overhead.
  /// Returns true if started successfully.
  Future<bool> startStreamRecording() async {
    if (_isRecording || _isStreamRecording) {
      debugPrint(
        '[RecordingService] startStreamRecording ignored: already active',
      );
      return false;
    }

    // Check permission
    if (!await hasPermission()) {
      debugPrint(
        '[RecordingService] startStreamRecording blocked: no permission',
      );
      return false;
    }

    if (_useMacNativeCapture) {
      return _startMacNative(asStream: true);
    }

    Future<bool> tryStart({required bool usePreferredDevice}) async {
      final config = RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        device: usePreferredDevice ? _deviceForConfig() : null,
      );

      await _stopStreamRecording();
      _isStreamRecording = true;
      _isRecording = true;
      _streamError = null;
      _streamBuffer = BytesBuilder(copy: false);
      _streamDoneCompleter = Completer<void>();

      final stream = await _recorder.startStream(config);
      _audioStreamSub = stream.listen(
        _streamBuffer.add,
        onError: (Object error, StackTrace stackTrace) {
          debugPrint('[RecordingService] stream error: $error');
          _streamError = error;
          _completeStreamDone();
        },
        onDone: () {
          _completeStreamDone();
        },
      );
      return true;
    }

    try {
      await tryStart(usePreferredDevice: true);
      debugPrint('[RecordingService] stream recording started');
      return true;
    } catch (e) {
      debugPrint(
        '[RecordingService] stream start failed: $e '
        '(device=${_selectedDeviceId ?? "default"})',
      );
      // The native recorder may have started before the stream became usable
      // (e.g. a platform error thrown mid-start). Stop it best-effort so a
      // partial start can never leave the microphone hot, then reset all of
      // the Dart-side stream resources and flags.
      await _bestEffortStopRecorder();
      await _stopStreamRecording();
      _isRecording = false;

      if (_selectedDeviceId != null) {
        debugPrint(
          '[RecordingService] retrying stream start with System Default',
        );
        _selectedDeviceId = null;
        try {
          await tryStart(usePreferredDevice: false);
          debugPrint(
            '[RecordingService] stream recording started via System Default',
          );
          return true;
        } catch (fallbackError) {
          debugPrint(
            '[RecordingService] stream fallback start failed: $fallbackError',
          );
          await _bestEffortStopRecorder();
          await _stopStreamRecording();
          _isRecording = false;
          return false;
        }
      }
      return false;
    }
  }

  /// Stop stream recording and return raw PCM bytes.
  ///
  /// Returns the raw PCM-16LE audio data, or null if not recording.
  Future<Uint8List?> stopStreamAndGetPcm() async {
    if (!_isStreamRecording && !(_usingMacNative && _isRecording)) {
      return null;
    }

    if (_usingMacNative) {
      final pcm = await _stopMacNativePcm();
      if (pcm == null || pcm.isEmpty) {
        debugPrint(
          '[RecordingService] mac native stream stop produced empty PCM',
        );
        return null;
      }
      debugPrint(
        '[RecordingService] mac native stream stop ok: ${pcm.length} PCM bytes',
      );
      return pcm;
    }

    try {
      await _recorder.stop();
      _isRecording = false;

      final done = _streamDoneCompleter;
      if (done != null && !done.isCompleted) {
        await done.future.timeout(const Duration(seconds: 2), onTimeout: () {});
      }

      final data = _streamBuffer.takeBytes();
      final hadError = _streamError != null;
      await _stopStreamRecording();
      if (hadError) {
        debugPrint(
          '[RecordingService] stream stop discarded buffer after error '
          '(${data.length} bytes)',
        );
        return null;
      }
      if (data.isEmpty) {
        debugPrint(
          '[RecordingService] stream stop produced empty PCM '
          '(no audio frames received — check mic selection/permission)',
        );
        return null;
      }
      debugPrint('[RecordingService] stream stop ok: ${data.length} PCM bytes');
      return data;
    } catch (e) {
      debugPrint('[RecordingService] stream stop failed: $e');
      _isRecording = false;
      await _stopStreamRecording();
      return null;
    }
  }

  Future<void> _stopStreamRecording() async {
    await _audioStreamSub?.cancel();
    _audioStreamSub = null;
    _completeStreamDone();
    _streamDoneCompleter = null;
    _streamError = null;
    _streamBuffer = BytesBuilder(copy: false);
    _isStreamRecording = false;
  }

  // ---------------------------------------------------------------------------
  // macOS native AVAudioEngine capture
  // ---------------------------------------------------------------------------

  Future<bool> _startMacNative({required bool asStream}) async {
    _macNativePcm = null;
    _usingMacNative = false;

    Future<bool> tryStart({String? deviceId}) async {
      final ok = await _macChannel.invokeMethod<bool>('start', {
        'deviceId': deviceId,
      });
      return ok ?? false;
    }

    try {
      var started = await tryStart(deviceId: _selectedDeviceId);
      if (!started && _selectedDeviceId != null) {
        debugPrint(
          '[RecordingService] mac native start with preferred device failed; '
          'retrying System Default',
        );
        _selectedDeviceId = null;
        started = await tryStart(deviceId: null);
      }
      if (!started) {
        debugPrint('[RecordingService] mac native start returned false');
        return false;
      }

      // Prepare a destination path for cloud/file consumers. PCM is held in
      // memory until stop; the WAV is only written then. Create the
      // directory eagerly — a missing cache dir caused PathNotFoundException
      // when cloud later tried to open the WAV.
      final directory = await getTemporaryDirectory();
      await directory.create(recursive: true);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath =
          '${directory.path}/beeamvo_recording_$timestamp.wav';

      _usingMacNative = true;
      _isRecording = true;
      _isStreamRecording = asStream;
      debugPrint(
        '[RecordingService] mac native recording started '
        '(stream=$asStream, device=${_selectedDeviceId ?? "default"})',
      );
      return true;
    } catch (e) {
      debugPrint('[RecordingService] mac native start failed: $e');
      await _bestEffortStopMacNative();
      _usingMacNative = false;
      _isRecording = false;
      _isStreamRecording = false;
      _currentRecordingPath = null;
      return false;
    }
  }

  Future<Uint8List?> _stopMacNativePcm() async {
    try {
      final result = await _macChannel.invokeMethod<dynamic>('stop');
      _isRecording = false;
      _isStreamRecording = false;
      _usingMacNative = false;
      final pcm = _coercePcmBytes(result);
      _macNativePcm = (pcm == null || pcm.isEmpty) ? null : pcm;
      debugPrint(
        '[RecordingService] mac native stop → ${_macNativePcm?.length ?? 0} PCM bytes',
      );
      return _macNativePcm;
    } catch (e) {
      debugPrint('[RecordingService] mac native stop failed: $e');
      _isRecording = false;
      _isStreamRecording = false;
      _usingMacNative = false;
      _macNativePcm = null;
      return null;
    }
  }

  /// Normalize method-channel binary payloads to [Uint8List].
  static Uint8List? _coercePcmBytes(dynamic result) {
    if (result == null) return null;
    if (result is Uint8List) return result;
    if (result is ByteBuffer) return result.asUint8List();
    if (result is List<int>) return Uint8List.fromList(result);
    if (result is List) {
      return Uint8List.fromList(result.cast<int>());
    }
    debugPrint(
      '[RecordingService] unexpected PCM payload type: ${result.runtimeType}',
    );
    return null;
  }

  Future<String?> _stopMacNativeToWavPath() async {
    final pcm = await _stopMacNativePcm();
    if (pcm == null || pcm.isEmpty) {
      debugPrint('[RecordingService] mac native WAV stop: empty PCM');
      return null;
    }

    // Ensure a destination path exists even if start never prepared one.
    if (_currentRecordingPath == null) {
      final directory = await getTemporaryDirectory();
      await directory.create(recursive: true);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath =
          '${directory.path}/beeamvo_recording_$timestamp.wav';
    }

    final path = _currentRecordingPath!;
    final wav = buildMono16kWav(pcm);
    final wrote = await _writeWavFileBestEffort(wav);
    if (!wrote) {
      // Cloud callers use getAudioBytes(), which can rebuild from
      // _macNativePcm. Still return the intended path so the session
      // continues; getAudioBytes will not need the file.
      debugPrint(
        '[RecordingService] mac native WAV not persisted to disk; '
        'bytes remain available in memory',
      );
    } else {
      debugPrint(
        '[RecordingService] mac native WAV written: ${wav.length} bytes → $path',
      );
    }
    return path;
  }

  /// Write [wav] to [_currentRecordingPath], creating parent dirs as needed.
  ///
  /// Returns false on failure without throwing — cloud transcription only
  /// needs the in-memory bytes; the file is for retry / debugging.
  Future<bool> _writeWavFileBestEffort(Uint8List wav) async {
    final path = _currentRecordingPath;
    if (path == null) return false;
    try {
      final file = File(path);
      final parent = file.parent;
      if (!await parent.exists()) {
        await parent.create(recursive: true);
      }
      await file.writeAsBytes(wav, flush: true);
      return true;
    } catch (e) {
      debugPrint('[RecordingService] WAV write failed ($path): $e');
      return false;
    }
  }

  Future<void> _bestEffortStopMacNative() async {
    try {
      await _macChannel.invokeMethod<void>('cancel');
    } catch (_) {
      // Best-effort.
    }
    _usingMacNative = false;
    _macNativePcm = null;
  }

  /// Build a minimal mono 16 kHz 16-bit PCM WAV container around [pcm16le].
  static Uint8List buildMono16kWav(Uint8List pcm16le) {
    const sampleRate = 16000;
    const channels = 1;
    const bitsPerSample = 16;
    final byteRate = sampleRate * channels * bitsPerSample ~/ 8;
    final blockAlign = channels * bitsPerSample ~/ 8;
    final dataLength = pcm16le.length;
    final fileSizeMinus8 = 36 + dataLength;

    final header = ByteData(44);
    void ascii(int offset, String value) {
      for (var i = 0; i < value.length; i++) {
        header.setUint8(offset + i, value.codeUnitAt(i));
      }
    }

    ascii(0, 'RIFF');
    header.setUint32(4, fileSizeMinus8, Endian.little);
    ascii(8, 'WAVE');
    ascii(12, 'fmt ');
    header.setUint32(16, 16, Endian.little); // PCM fmt chunk size
    header.setUint16(20, 1, Endian.little); // PCM format
    header.setUint16(22, channels, Endian.little);
    header.setUint32(24, sampleRate, Endian.little);
    header.setUint32(28, byteRate, Endian.little);
    header.setUint16(32, blockAlign, Endian.little);
    header.setUint16(34, bitsPerSample, Endian.little);
    ascii(36, 'data');
    header.setUint32(40, dataLength, Endian.little);

    final out = BytesBuilder(copy: false)
      ..add(header.buffer.asUint8List())
      ..add(pcm16le);
    return out.takeBytes();
  }

  /// Best-effort native recorder stop used on cleanup/failure paths.
  ///
  /// Stopping a recorder that is idle (e.g. one that never fully started) may
  /// throw on some platforms, so failures are swallowed — this method must
  /// never throw and never leave the microphone hot when a recorder *is*
  /// running.
  Future<void> _bestEffortStopRecorder() async {
    if (_usingMacNative) {
      await _bestEffortStopMacNative();
      return;
    }
    try {
      await _recorder.stop();
    } catch (_) {
      // Recorder may already be stopped; cleanup stays best-effort.
    }
  }

  void _completeStreamDone() {
    final done = _streamDoneCompleter;
    if (done != null && !done.isCompleted) {
      done.complete();
    }
  }
}

/// Result of [RecordingService.assessMicReadiness].
class MicReadiness {
  const MicReadiness({
    required this.hasPermission,
    required this.devices,
    required this.resolvedDeviceId,
    required this.fellBackToDefault,
  });

  final bool hasPermission;
  final List<InputDevice> devices;
  final String? resolvedDeviceId;
  final bool fellBackToDefault;

  bool get hasAnyDeviceListed => devices.isNotEmpty;
}
