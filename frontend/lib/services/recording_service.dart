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
    return await _recorder.listInputDevices();
  }

  /// Set the preferred input device (null for default)
  void setPreferredDevice(String? deviceId) {
    _selectedDeviceId = deviceId;
  }

  /// Check if microphone permission is available
  Future<bool> hasPermission() async {
    return await _recorder.hasPermission();
  }

  /// Start recording audio
  ///
  /// Returns true if recording started successfully.
  Future<bool> startRecording() async {
    if (_isRecording || _isStreamRecording) {
      return false;
    }

    // Check permission
    if (!await hasPermission()) {
      return false;
    }

    // Get temp directory for audio file
    final directory = await getTemporaryDirectory();
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    _currentRecordingPath =
        '${directory.path}/beeamvo_recording_$timestamp.wav';

    // Configure recording - WAV format for best Gemini compatibility
    final config = RecordConfig(
      encoder: AudioEncoder.wav,
      sampleRate: 16000, // 16kHz as recommended for speech
      numChannels: 1, // Mono
      device: _selectedDeviceId != null
          ? InputDevice(id: _selectedDeviceId!, label: '')
          : null,
    );

    // Start recording
    await _recorder.start(config, path: _currentRecordingPath!);

    _isRecording = true;
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
      return false;
    }

    // Check permission
    if (!await hasPermission()) {
      return false;
    }

    // Use native PCM16 stream mode to avoid file-system round-trips.
    final config = RecordConfig(
      encoder: AudioEncoder.pcm16bits,
      sampleRate: 16000,
      numChannels: 1,
      device: _selectedDeviceId != null
          ? InputDevice(id: _selectedDeviceId!, label: '')
          : null,
    );

    try {
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
          _streamError = error;
          _completeStreamDone();
        },
        onDone: () {
          _completeStreamDone();
        },
      );

      return true;
    } catch (e) {
      debugPrint('[RecordingService] stream start failed: $e');
      _isRecording = false;
      _isStreamRecording = false;
      await _stopStreamRecording();
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
      if (hadError || data.isEmpty) {
        return null;
      }
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

  void _completeStreamDone() {
    final done = _streamDoneCompleter;
    if (done != null && !done.isCompleted) {
      done.complete();
    }
  }
}
