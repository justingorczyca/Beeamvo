import 'package:beeamvo/config.dart';
import 'package:beeamvo/models/hotkey_config.dart';
import 'package:beeamvo/models/system_prompt.dart';
import 'package:beeamvo/services/secure_credential_store.dart';
import 'package:beeamvo/services/settings_service.dart';

class OnboardingTestSettingsService extends SettingsService {
  OnboardingTestSettingsService({
    this.backend = TranscriptionBackend.cloud,
    this.provider = CloudProvider.geminiApiKey,
    this.hasGeminiKey = false,
  }) : super(credentialStore: InMemorySecureCredentialStore());

  TranscriptionBackend backend;
  CloudProvider provider;
  bool hasGeminiKey;
  String? _vertexProjectId;
  String _modelId = AppConfig.defaultModelId;
  String _promptId = SystemPrompt.defaultId;
  String _whisperModelId = 'ggml-tiny.bin';
  RecordingMode _recordingMode = RecordingMode.toggle;
  HotkeyConfig _hotkey = HotkeyConfig.defaultHotkey;

  @override
  TranscriptionBackend get transcriptionBackend => backend;

  @override
  Future<void> setTranscriptionBackend(TranscriptionBackend backend) async {
    this.backend = backend;
  }

  @override
  CloudProvider get cloudProvider => provider;

  @override
  Future<void> setCloudProvider(CloudProvider provider) async {
    this.provider = provider;
  }

  @override
  List<GeminiModelConfig> get primaryModels =>
      AppConfig.audioModelsForProvider(provider);

  @override
  String get selectedModelId =>
      primaryModels.any((model) => model.id == _modelId)
      ? _modelId
      : primaryModels.first.id;

  @override
  Future<void> setSelectedModelId(String value) async {
    _modelId = value;
  }

  @override
  String get selectedPromptId => _promptId;

  @override
  Future<void> setSelectedPromptId(String value) async {
    _promptId = value;
  }

  @override
  bool get promptIsApplied =>
      backend == TranscriptionBackend.cloud &&
      !AppConfig.getModelById(selectedModelId).isTranscriptionOnly;

  @override
  String get whisperModelId => _whisperModelId;

  @override
  Future<void> setWhisperModelId(String value) async {
    _whisperModelId = value;
  }

  @override
  RecordingMode get recordingMode => _recordingMode;

  @override
  Future<void> setRecordingMode(RecordingMode mode) async {
    _recordingMode = mode;
  }

  @override
  HotkeyConfig get hotkey => _hotkey;

  @override
  Future<void> setHotkey(HotkeyConfig config) async {
    _hotkey = config;
  }

  @override
  Future<void> resetHotkey() async {
    _hotkey = HotkeyConfig.defaultHotkey;
  }

  @override
  bool get hasGeminiApiKey => hasGeminiKey;

  @override
  Future<void> setGeminiApiKey(String value) async {
    hasGeminiKey = value.trim().isNotEmpty;
  }

  @override
  String? get vertexProjectId => _vertexProjectId;

  @override
  Future<void> setVertexProjectId(String value) async {
    _vertexProjectId = value.trim().isEmpty ? null : value.trim();
  }

  @override
  bool get hasCloudCredentials => switch (provider) {
    CloudProvider.geminiApiKey => hasGeminiKey,
    CloudProvider.vertexAi => _vertexProjectId != null,
    CloudProvider.openaiApiKey ||
    CloudProvider.codexOAuth ||
    CloudProvider.grokOAuth => false,
  };

  @override
  bool get isTranscriptionReady => hasCloudCredentials;

  @override
  Future<void> setOnboardingComplete() async {}
}
