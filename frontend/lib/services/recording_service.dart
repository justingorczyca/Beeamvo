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
        await done.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () {},
        );
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
