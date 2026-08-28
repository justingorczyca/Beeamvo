import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import '../models/prompt_settings.dart';
import '../models/system_prompt.dart';
import '../services/cloud_transcription_client.dart';
import '../services/cloud_transcription_service.dart';
import '../services/recording_service.dart';
import '../services/settings_service.dart';
import '../services/usage_stats_service.dart';

enum MobileTranscriptionState { idle, recording, processing, success, error }

enum MobileErrorAction { none, openSettings }

abstract class MobileAudioRecorder {
  Future<bool> hasPermission();
  Future<bool> startRecording();
  Future<String?> stopRecording();
  Future<Uint8List?> getAudioBytes();
  Future<void> deleteRecording();
  Stream<double> get amplitudeStream;
  Future<void> dispose();
}

class RecordingServiceMobileAudioRecorder implements MobileAudioRecorder {
  final RecordingService service;

  RecordingServiceMobileAudioRecorder({RecordingService? service})
    : service = service ?? RecordingService();

  @override
  Future<bool> hasPermission() => service.hasPermission();

  @override
  Future<bool> startRecording() => service.startRecording();

  @override
  Future<String?> stopRecording() => service.stopRecording();

  @override
  Future<Uint8List?> getAudioBytes() => service.getAudioBytes();

  @override
  Future<void> deleteRecording() => service.deleteRecording();

  @override
  Stream<double> get amplitudeStream => service.amplitudeStream;

  @override
  Future<void> dispose() => service.dispose();
}

class MobileTranscriptionController extends ChangeNotifier {
  MobileTranscriptionController({
    required this.settingsService,
    required this.cloudService,
    required this.usageStatsService,
    required this.recorder,
  }) {
    cloudService.attachSettings(settingsService);
  }

  final SettingsService settingsService;
  final CloudTranscriptionService cloudService;
  final UsageStatsService usageStatsService;
  final MobileAudioRecorder recorder;

  MobileTranscriptionState _state = MobileTranscriptionState.idle;
  String? _resultText;
  String? _errorMessage;
  Duration _duration = Duration.zero;
  double _amplitude = 0;
  Timer? _durationTimer;
  Timer? _limitTimer;
  Timer? _successTimer;
  StreamSubscription<double>? _amplitudeSubscription;
  bool _disposed = false;
  bool _stopRequested = false;
  bool _hasRetryableRecording = false;
  MobileErrorAction _errorAction = MobileErrorAction.none;
  int _operation = 0;

  MobileTranscriptionState get state => _state;
  String? get resultText => _resultText;
  String? get errorMessage => _errorMessage;
  Duration get duration => _duration;
  double get amplitude => _amplitude;
  bool get isRecording => _state == MobileTranscriptionState.recording;
  bool get isProcessing => _state == MobileTranscriptionState.processing;
  bool get canRetry =>
      _state == MobileTranscriptionState.error && _hasRetryableRecording;
  MobileErrorAction get errorAction => _errorAction;

  Future<void> toggleRecording() async {
    if (_disposed || isProcessing) return;
    if (isRecording) {
      await stopRecording();
      return;
    }
    if (!settingsService.hasCloudCredentials) {
      _setError(
        'Add a cloud API key in Settings before recording.',
        action: MobileErrorAction.openSettings,
      );
      return;
    }
    if (!await recorder.hasPermission()) {
      _setError(
        'Microphone access is denied. Enable microphone access in your device settings.',
      );
      return;
    }
    try {
      final started = await recorder.startRecording();
      if (!started) {
        _setError(
          'Microphone access is unavailable. Enable microphone access in your device settings.',
        );
        return;
      }
      _resultText = null;
      _errorMessage = null;
      _errorAction = MobileErrorAction.none;
      _hasRetryableRecording = false;
      _successTimer?.cancel();
      _successTimer = null;
      _duration = Duration.zero;
      _stopRequested = false;
      _setState(MobileTranscriptionState.recording);
      _amplitudeSubscription = recorder.amplitudeStream.listen((value) {
        if (_disposed) return;
        _amplitude = value;
        _notify();
      });
      if (settingsService.durationLimitEnabled) {
        _limitTimer = Timer(
          Duration(seconds: settingsService.durationLimit),
          stopRecording,
        );
      }
      _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_disposed || !isRecording) return;
        _duration += const Duration(seconds: 1);
        _notify();
      });
    } catch (error) {
      _setError('Could not start recording: $error');
    }
  }

  Future<void> stopRecording() async {
    if (_disposed || !isRecording || _stopRequested) return;
    _stopRequested = true;
    final operation = ++_operation;
    _durationTimer?.cancel();
    _limitTimer?.cancel();
    _durationTimer = null;
    _limitTimer = null;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    final recordingPath = await recorder.stopRecording();
    if (_disposed) return;
    _hasRetryableRecording = recordingPath != null;
    _setState(MobileTranscriptionState.processing);
    await _processRecording(operation);
  }

  Future<void> retry() async {
    if (_disposed || !canRetry) return;
    _errorMessage = null;
    final operation = ++_operation;
    _setState(MobileTranscriptionState.processing);
    await _processRecording(operation);
  }

  Future<void> cancel() async {
    if (_disposed) return;
    _operation++;
    _durationTimer?.cancel();
    _limitTimer?.cancel();
    _successTimer?.cancel();
    _durationTimer = null;
    _limitTimer = null;
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    if (isRecording) await recorder.stopRecording();
    await recorder.deleteRecording();
    _hasRetryableRecording = false;
    _duration = Duration.zero;
    _resultText = null;
    _errorMessage = null;
    _stopRequested = false;
    _setState(MobileTranscriptionState.idle);
  }

  Future<void> clearResult() async {
    if (_disposed) return;
    await recorder.deleteRecording();
    _resultText = null;
    _errorMessage = null;
    _errorAction = MobileErrorAction.none;
    _hasRetryableRecording = false;
    _setState(MobileTranscriptionState.idle);
  }

  Future<void> _processRecording(int operation) async {
    try {
      final audio = await recorder.getAudioBytes();
      if (_disposed || operation != _operation) return;
      if (audio == null || audio.isEmpty) {
        throw CloudTranscriptionException(
          'No audio was captured. Please try recording again.',
        );
      }
      final prompt = SystemPrompt.getById(
        settingsService.selectedPromptId,
        customPrompts: settingsService.customPrompts,
      );
      final overrides = settingsService.getPromptOverrides(prompt.id);
      final provider = CloudProviderExtension.fromValue(
        overrides?.cloudProvider ?? settingsService.cloudProvider.name,
      );
      final modelId = overrides?.modelId ?? settingsService.selectedModelId;
      final thinkingLevel =
          overrides?.thinkingLevel ??
          settingsService.getThinkingLevelForModel(modelId);
      final rephrase =
          overrides?.rephraseLevel ?? settingsService.rephraseLevel;
      final instruction = [
        prompt.instruction,
        if (rephrase.promptFragment != null) rephrase.promptFragment!,
      ].join('\n');
      final twoPass =
          overrides?.twoPassTranscriptionEnabled ??
          settingsService.twoPassTranscriptionEnabled;
      late final String text;
      try {
        cloudService.setProviderOverride(provider);
        text = twoPass
            ? await _twoPass(
                audio,
                instruction,
                modelId,
                thinkingLevel,
                overrides,
              )
            : await _singlePass(audio, instruction, modelId, thinkingLevel);
      } finally {
        cloudService.clearProviderOverride();
      }
      if (_disposed || operation != _operation) return;
      await Clipboard.setData(ClipboardData(text: text));
      await settingsService.addClipboardEntry(text);
      await usageStatsService.recordTranscription(text, _duration);
      await recorder.deleteRecording();
      _hasRetryableRecording = false;
      _resultText = text;
      _errorMessage = null;
      _setState(MobileTranscriptionState.success);
      _successTimer?.cancel();
      _successTimer = Timer(const Duration(seconds: 1), () {
        if (!_disposed && _state == MobileTranscriptionState.success) {
          _setState(MobileTranscriptionState.idle);
        }
      });
    } on CloudTranscriptionException catch (error) {
      _setError(error.message);
    } catch (error) {
      _setError('Transcription failed: $error');
    }
  }

  Future<String> _singlePass(
    Uint8List audio,
    String instruction,
    String modelId,
    GeminiThinkingLevel? thinkingLevel,
  ) async {
    final effectiveModel = AppConfig.getModelById(modelId);
    if (effectiveModel.isTranscriptionOnly) {
      return cloudService.transcribeAudio(
        audio,
        'audio/wav',
        modelOverrideId: modelId,
      );
    }
    return cloudService.transcribeAndImprove(
      audio,
      'audio/wav',
      missionInstruction: instruction,
      modelOverrideId: modelId,
      thinkingLevelOverride: thinkingLevel,
    );
  }

  Future<String> _twoPass(
    Uint8List audio,
    String instruction,
    String modelId,
    GeminiThinkingLevel? thinkingLevel,
    PromptSettings? overrides,
  ) async {
    final raw = await cloudService.transcribeAudio(
      audio,
      'audio/wav',
      modelOverrideId: overrides?.twoPassTranscriptionModelId ?? modelId,
    );
    final refinementModelId = AppConfig.resolveRefinementModelId(
      overrides?.twoPassRefinementModelId ??
          settingsService.twoPassRefinementModelId,
    );
    return cloudService.improveTranscription(
      raw,
      missionInstruction: instruction,
      modelOverrideId: refinementModelId,
      thinkingLevelOverride:
          overrides?.twoPassRefinementThinkingLevel ?? thinkingLevel,
    );
  }

  void _setError(
    String message, {
    MobileErrorAction action = MobileErrorAction.none,
  }) {
    if (_disposed) return;
    _errorAction = action;
    _errorMessage = message;
    _setState(MobileTranscriptionState.error);
  }

  void _setState(MobileTranscriptionState state) {
    if (_disposed) return;
    _state = state;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _operation++;
    _durationTimer?.cancel();
    _limitTimer?.cancel();
    _successTimer?.cancel();
    _amplitudeSubscription?.cancel();
    unawaited(recorder.dispose());
    super.dispose();
  }
}
