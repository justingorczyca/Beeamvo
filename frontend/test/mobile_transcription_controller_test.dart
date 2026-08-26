import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:beeamvo/config.dart';
import 'package:beeamvo/mobile/mobile_transcription_controller.dart';
import 'package:beeamvo/models/clipboard_history_entry.dart';
import 'package:beeamvo/models/prompt_settings.dart';
import 'package:beeamvo/models/system_prompt.dart';
import 'package:beeamvo/services/cloud_transcription_client.dart';
import 'package:beeamvo/services/cloud_transcription_service.dart';
import 'package:beeamvo/services/settings_service.dart';
import 'package:beeamvo/services/usage_stats_service.dart';

class FakeSettings extends SettingsService {
  FakeSettings({
    this.credentials = true,
    this.twoPass = false,
    this.limitEnabled = false,
    this.limit = 5,
    this.historyEnabled = true,
  });

  bool credentials;
  bool twoPass;
  bool limitEnabled;
  int limit;
  bool historyEnabled;
  String promptId = 'standard';
  PromptSettings? overrides;
  final entries = <ClipboardHistoryEntry>[];

  @override
  bool get hasCloudCredentials => credentials;
  @override
  String get selectedPromptId => promptId;
  @override
  List<SystemPrompt> get customPrompts => const [];
  @override
  PromptSettings? getPromptOverrides(String _) => overrides;
  @override
  CloudProvider get cloudProvider => CloudProvider.geminiApiKey;
  @override
  String get selectedModelId => AppConfig.defaultModelId;
  @override
  GeminiThinkingLevel? getThinkingLevelForModel(String _) => null;
  @override
  RephraseLevel get rephraseLevel => RephraseLevel.off;
  @override
  bool get twoPassTranscriptionEnabled => twoPass;
  @override
  bool get durationLimitEnabled => limitEnabled;
  @override
  int get durationLimit => limit;
  @override
  List<ClipboardHistoryEntry> get clipboardHistory => entries;
  @override
  bool get clipboardHistoryEnabled => historyEnabled;
  @override
  Future<void> addClipboardEntry(String text, {bool isPinned = false}) async {
    if (!clipboardHistoryEnabled && !isPinned) return;
    final now = DateTime.now();
    entries.insert(
      0,
      ClipboardHistoryEntry(
        id: 'id',
        text: text,
        createdAt: now,
        updatedAt: now,
        isPinned: isPinned,
      ),
    );
  }

  @override
  Future<void> setClipboardHistoryEnabled(bool value) async {
    historyEnabled = value;
  }

  @override
  Future<void> setSelectedPromptId(String value) async {
    promptId = value;
  }
}

class FakeUsageStats extends UsageStatsService {
  int calls = 0;
  @override
  Future<void> recordTranscription(String text, Duration duration) async {
    calls++;
  }
}

class FakeRecorder implements MobileAudioRecorder {
  FakeRecorder({this.permission = true, Uint8List? bytes})
    : bytes = bytes ?? Uint8List.fromList([1, 2, 3]);

  bool permission;
  Uint8List bytes;
  bool started = false;
  bool deleted = false;
  final _amplitude = StreamController<double>.broadcast();

  @override
  Future<bool> hasPermission() async => permission;
  @override
  Future<bool> startRecording() async {
    started = true;
    return true;
  }

  @override
  Future<String?> stopRecording() async {
    started = false;
    return 'recording.wav';
  }

  @override
  Future<Uint8List?> getAudioBytes() async => bytes;
  @override
  Future<void> deleteRecording() async => deleted = true;
  @override
  Stream<double> get amplitudeStream => _amplitude.stream;
  @override
  Future<void> dispose() async => _amplitude.close();
}

class FakeCloud extends CloudTranscriptionService {
  FakeCloud() : super(geminiApiService: _FakeClient());

  bool fail = false;
  int transcribeCalls = 0;
  int improveCalls = 0;
  bool overrideActive = false;
  int clearOverrideCalls = 0;
  Completer<String>? pendingResult;

  @override
  void attachSettings(SettingsService settings) {}

  @override
  void setProviderOverride(CloudProvider provider) {
    overrideActive = true;
  }

  @override
  void clearProviderOverride() {
    overrideActive = false;
    clearOverrideCalls++;
  }

  @override
  Future<String> transcribeAndImprove(
    Uint8List audio,
    String mimeType, {
    String? missionInstruction,
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) async {
    if (pendingResult != null) return pendingResult!.future;
    if (fail) throw CloudTranscriptionException('network failed');
    transcribeCalls++;
    return 'single result';
  }

  @override
  Future<String> transcribeAudio(
    Uint8List audio,
    String mimeType, {
    String? modelOverrideId,
  }) async {
    transcribeCalls++;
    return 'raw result';
  }

  @override
  Future<String> improveTranscription(
    String rawText, {
    String? missionInstruction,
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) async {
    improveCalls++;
    return 'two pass result';
  }
}

class _FakeClient implements CloudTranscriptionClient {
  @override
  void attachSettings(SettingsService settings) {}
  @override
  Future<void> initialize() async {}
  @override
  Future<void> verifySetup() async {}
  @override
  void setModel(GeminiModelConfig model) {}
  @override
  void setModelById(String modelId) {}
  @override
  void dispose() {}
  @override
  GeminiModelConfig get currentModel =>
      AppConfig.getModelById(AppConfig.defaultModelId);
  @override
  bool get isInitialized => true;
  @override
  Future<String> improveTranscription(
    String rawText, {
    String? missionInstruction,
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) async => rawText;
  @override
  Future<String> transcribeAndImprove(
    Uint8List audioData,
    String mimeType, {
    String? missionInstruction,
    String? modelOverrideId,
    GeminiThinkingLevel? thinkingLevelOverride,
  }) async => audioData.toString();
  @override
  Future<String> transcribeAudio(
    Uint8List audioData,
    String mimeType, {
    String? modelOverrideId,
  }) async => audioData.toString();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        return null;
      });

  MobileTranscriptionController makeController({
    bool credentials = true,
    bool twoPass = false,
    FakeCloud? cloud,
    FakeRecorder? recorder,
    FakeUsageStats? usage,
  }) {
    return MobileTranscriptionController(
      settingsService: FakeSettings(credentials: credentials, twoPass: twoPass),
      cloudService: cloud ?? FakeCloud(),
      usageStatsService: usage ?? FakeUsageStats(),
      recorder: recorder ?? FakeRecorder(),
    );
  }

  test('single-pass transcription reaches success', () async {
    final controller = makeController();
    await controller.toggleRecording();
    await controller.toggleRecording();
    expect(controller.resultText, 'single result');
    expect(controller.state, MobileTranscriptionState.success);
    controller.dispose();
  });

  test('two-pass transcription calls both cloud stages', () async {
    final cloud = FakeCloud();
    final controller = makeController(twoPass: true, cloud: cloud);
    await controller.toggleRecording();
    await controller.toggleRecording();
    expect(cloud.transcribeCalls, 1);
    expect(cloud.improveCalls, 1);
    controller.dispose();
  });

  test('missing credentials and permission denial are actionable', () async {
    final missing = makeController(credentials: false);
    await missing.toggleRecording();
    expect(missing.state, MobileTranscriptionState.error);
    expect(missing.errorMessage, contains('API key'));
    expect(missing.canRetry, isFalse);
    expect(missing.errorAction, MobileErrorAction.openSettings);
    missing.dispose();

    final denied = makeController(recorder: FakeRecorder(permission: false));
    await denied.toggleRecording();
    expect(denied.errorMessage, contains('Microphone'));
    expect(denied.canRetry, isFalse);
    expect(denied.errorAction, MobileErrorAction.none);
    denied.dispose();
  });

  test('cloud failure can retry using the retained recording', () async {
    final cloud = FakeCloud()..fail = true;
    final recorder = FakeRecorder();
    final controller = makeController(cloud: cloud, recorder: recorder);
    await controller.toggleRecording();
    await controller.toggleRecording();
    expect(controller.state, MobileTranscriptionState.error);
    expect(recorder.deleted, isFalse);
    expect(controller.canRetry, isTrue);
    expect(cloud.clearOverrideCalls, 1);
    cloud.fail = false;
    await controller.retry();
    expect(controller.resultText, 'single result');
    expect(recorder.deleted, isTrue);
    expect(controller.canRetry, isFalse);
    controller.dispose();
  });

  test('provider override is cleared when processing is invalidated', () async {
    final cloud = FakeCloud()..pendingResult = Completer<String>();
    final controller = makeController(cloud: cloud);
    await controller.toggleRecording();
    final processing = controller.toggleRecording();
    while (!cloud.overrideActive) {
      await Future<void>.delayed(Duration.zero);
    }
    await controller.cancel();
    cloud.pendingResult!.complete('late result');
    await processing;
    expect(cloud.overrideActive, isFalse);
    expect(cloud.clearOverrideCalls, 1);
    controller.dispose();
  });

  test('provider override is cleared when controller is disposed', () async {
    final cloud = FakeCloud()..pendingResult = Completer<String>();
    final controller = makeController(cloud: cloud);
    await controller.toggleRecording();
    final processing = controller.toggleRecording();
    while (!cloud.overrideActive) {
      await Future<void>.delayed(Duration.zero);
    }
    controller.dispose();
    cloud.pendingResult!.complete('late result');
    await processing;
    expect(cloud.overrideActive, isFalse);
    expect(cloud.clearOverrideCalls, 1);
  });

  test(
    'success keeps the result after returning to idle and can record again',
    () async {
      final recorder = FakeRecorder();
      final controller = makeController(recorder: recorder);
      await controller.toggleRecording();
      await controller.toggleRecording();
      expect(controller.state, MobileTranscriptionState.success);
      await Future<void>.delayed(const Duration(seconds: 1, milliseconds: 50));
      expect(controller.state, MobileTranscriptionState.idle);
      expect(controller.resultText, 'single result');
      await controller.toggleRecording();
      expect(controller.state, MobileTranscriptionState.recording);
      expect(controller.resultText, isNull);
      controller.dispose();
    },
  );

  test('cancel stops and deletes the active recording', () async {
    final recorder = FakeRecorder();
    final controller = makeController(recorder: recorder);
    await controller.toggleRecording();
    await controller.cancel();
    expect(controller.state, MobileTranscriptionState.idle);
    expect(recorder.deleted, isTrue);
    controller.dispose();
  });

  test('duration limit automatically stops recording', () async {
    final settings = FakeSettings(limitEnabled: true, limit: 1);
    final recorder = FakeRecorder();
    final controller = MobileTranscriptionController(
      settingsService: settings,
      cloudService: FakeCloud(),
      usageStatsService: FakeUsageStats(),
      recorder: recorder,
    );
    await controller.toggleRecording();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(controller.state, MobileTranscriptionState.success);
    expect(recorder.started, isFalse);
    controller.dispose();
  });
}
