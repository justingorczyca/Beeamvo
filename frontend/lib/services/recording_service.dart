import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

/// Service for audio recording
///
/// Handles microphone access and audio capture.
class RecordingService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _currentRecordingPath;
  bool _isRecording = false;
  String? _selectedDeviceId;

  // Stream-based recording support
  bool _isStreamRecording = false;
  StreamSubscription<Uint8List>? _audioStreamSub;
  BytesBuilder _streamBuffer = BytesBuilder(copy: false);
  Completer<void>? _streamDoneCompleter;
  Object? _streamError;

  /// Get the list of available input devices
  Future<List<InputDevice>> listInputDevices() async {
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

    final path = await _recorder.stop();
    _isRecording = false;
    if (_isStreamRecording) {
      await _stopStreamRecording();
    }
    return path;
  }

  /// Get the audio file as bytes
  Future<Uint8List?> getAudioBytes() async {
    if (_currentRecordingPath == null) {
      return null;
    }

    final file = File(_currentRecordingPath!);
    if (await file.exists()) {
      return await file.readAsBytes();
    }
    return null;
  }

  /// Extracts mono, 16 kHz, 16-bit little-endian PCM data from a RIFF/WAV file.
  ///
  /// WAV containers may include optional chunks (for example `LIST` or `fact`),
  /// so callers must not assume the PCM data always begins at byte 44. Throws a
  /// [FormatException] for truncated containers and formats Whisper cannot
  /// process directly.
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
        bitsPerSample = data.getUint16(chunkDataOffset + 14, Endian.little);
      } else if (chunkId == 'data') {
        dataOffset = chunkDataOffset;
        dataLength = chunkLength;
      }

      // RIFF chunks are word-aligned; odd-sized chunks include one pad byte.
      offset = chunkEnd + (chunkLength.isOdd ? 1 : 0);
    }

    if (audioFormat != 1 ||
        channels != 1 ||
        sampleRate != 16000 ||
        bitsPerSample != 16) {
      throw FormatException(
        'Unsupported WAV format: expected mono 16 kHz PCM-16, received '
        'format=$audioFormat channels=$channels sampleRate=$sampleRate '
        'bits=$bitsPerSample.',
      );
    }
    if (dataOffset == null || dataLength == null || dataLength == 0) {
      throw const FormatException('WAV file contains no PCM audio data.');
    }
    if (dataLength.isOdd) {
      throw const FormatException(
        'PCM-16 audio data must have an even byte length.',
      );
    }

    return Uint8List.sublistView(wavBytes, dataOffset, dataOffset + dataLength);
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
    if (_isRecording) {
      await stopRecording();
    }
    await _stopStreamRecording();
    await deleteRecording();
    await _recorder.dispose();
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
    if (!_isStreamRecording) {
      return null;
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
      debugPrint(
        '[RecordingService] stream stop ok: ${data.length} PCM bytes',
      );
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

  /// Best-effort native recorder stop used on cleanup/failure paths.
  ///
  /// Stopping a recorder that is idle (e.g. one that never fully started) may
  /// throw on some platforms, so failures are swallowed — this method must
  /// never throw and never leave the microphone hot when a recorder *is*
  /// running.
  Future<void> _bestEffortStopRecorder() async {
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
