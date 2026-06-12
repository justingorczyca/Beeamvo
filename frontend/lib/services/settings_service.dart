import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:launch_at_startup/launch_at_startup.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';
import '../models/enums.dart';
export '../models/enums.dart';
import '../models/system_prompt.dart';
import '../models/prompt_settings.dart';
import '../models/hotkey_config.dart';
import '../models/clipboard_history_entry.dart';
import '../config.dart';
import 'secure_credential_store.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Robust file-based settings storage.
///
/// We use a JSON file in [getApplicationSupportDirectory] rather than
/// SharedPreferences because the Windows implementation of SharedPreferences
/// can silently fail to persist data to disk in some configurations, resulting
/// in all settings being reset on every restart.
///
/// The service is a [ChangeNotifier] so top-level consumers (such as the app
/// shell that owns the active [ThemeMode]) can rebuild when a setting that
/// affects the whole tree changes — currently just [setThemeMode].
class SettingsService extends ChangeNotifier {
  SettingsService({SecureCredentialStore? credentialStore})
    : _credentialStore =
          credentialStore ?? const FlutterSecureCredentialStore();
  // ── keys ──────────────────────────────────────────────────────────────────
  static const _kLaunchAtStartup = 'launch_at_startup';
  static const _kSelectedPromptId = 'active_system_prompt_id';
  static const _kCustomPrompts = 'custom_prompts';
  static const _kSelectedModelId = 'selected_model_id';
  static const _kTwoPassTranscription = 'two_pass_transcription';
  static const _kTwoPassTranscriptionModelId =
      'two_pass_transcription_model_id';
  static const _kTwoPassRefinementModelId = 'two_pass_refinement_model_id';
  static const _kHotkey = 'global_hotkey';
  static const _kClipboardHistoryEnabled = 'clipboard_history_enabled';
  static const _kClipboardWatcherEnabled = 'clipboard_watcher_enabled';
  static const _kClipboardHistoryMaxItems = 'clipboard_history_max_items';
  static const _kClipboardHistoryItems = 'clipboard_history_items';
  static const _kClipboardPopupHotkey = 'clipboard_popup_hotkey';
  static const _kAutoPasteEnabled = 'auto_paste_enabled';
  static const _kModeSelectionHotkey = 'mode_selection_hotkey';
  static const _kRecordingMode = 'recording_mode';
  static const _kSelectedAudioDeviceId = 'selected_audio_device_id';
  static const _kDurationLimitEnabled = 'duration_limit_enabled';
  static const _kDurationLimit = 'duration_limit';
  static const _kWhisperModelId = 'whisper_model_id';
  static const _kWhisperLanguage = 'whisper_language';
  static const _kTranscriptionBackend = 'transcription_backend';
  static const _kCloudProvider = 'cloud_provider';

  static const _kVertexProjectId = 'vertex_project_id';
  static const _kRephraseLevel = 'rephrase_level';
  static const _kOnboardingComplete = 'onboarding_complete';
  static const _kPromptOverrides = 'prompt_overrides';
  static const _kThemeMode = 'theme_mode';

  // ── internal state ────────────────────────────────────────────────────────
  final SecureCredentialStore _credentialStore;
  late File _file;
  Map<String, dynamic> _data = {};
  List<SystemPrompt> _customPrompts = [];
  Map<String, PromptSettings> _promptOverrides = {};
  List<ClipboardHistoryEntry> _clipboardHistory = [];
  bool _hasGeminiApiKey = false;

  // ── init ──────────────────────────────────────────────────────────────────
  Future<void> initialize() async {
    // Resolve the settings file path
    final dir = await getApplicationSupportDirectory();
    final folder = Directory('${dir.path}${Platform.pathSeparator}Beeamvo');
    if (!folder.existsSync()) {
      folder.createSync(recursive: true);
    }
    _file = File('${folder.path}${Platform.pathSeparator}settings.json');

    // Load existing data
    await _load();

    // System integrations
    final packageInfo = await PackageInfo.fromPlatform();
    // launch_at_startup plugin doesn't support macOS, use native implementation
    if (!Platform.isMacOS) {
      launchAtStartup.setup(
        appName: packageInfo.appName,
        appPath: Platform.resolvedExecutable,
      );
    }

    _loadCustomPrompts();
    _loadPromptOverrides();
    _migrateCustomPromptOverrides();
    _loadClipboardHistory();
    _migrateModelId();
    await _loadSecureState();
    await _migrateCloudSettings();

    debugPrint('[SettingsService] initialized');
  }

  // ── JSON persistence ──────────────────────────────────────────────────────
  Future<void> _load() async {
    try {
      if (_file.existsSync()) {
        final raw = await _file.readAsString();
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          _data = decoded;
        }
      }
    } catch (e) {
      debugPrint('[SettingsService] load error: $e – starting fresh');
      _data = {};
    }
  }

  Future<void> _save() async {
    try {
      final encoded = const JsonEncoder.withIndent('  ').convert(_data);
      await _file.writeAsString(encoded, flush: true);
    } catch (e) {
      debugPrint('[SettingsService] save error: $e');
    }
  }

  Future<void> _loadSecureState() async {
    final geminiApiKey = await _credentialStore.readGeminiApiKey();
    _hasGeminiApiKey = geminiApiKey != null && geminiApiKey.trim().isNotEmpty;
  }

  Future<void> _migrateCloudSettings() async {
    final legacyBackend = _getString(_kTranscriptionBackend);
    if (legacyBackend == 'gemini') {
      _data[_kTranscriptionBackend] = TranscriptionBackend.cloud.name;
    } else if (legacyBackend == null) {
      _data[_kTranscriptionBackend] = TranscriptionBackend.cloud.name;
    }

    if (_getString(_kCloudProvider) == null) {
      _data[_kCloudProvider] = CloudProvider.geminiApiKey.name;
    }

    await _save();
  }

  // ── typed accessors ───────────────────────────────────────────────────────
  String? _getString(String key) => _data[key] as String?;
  bool _getBool(String key, {bool defaultValue = false}) =>
      _data[key] as bool? ?? defaultValue;
  int _getInt(String key, {required int defaultValue}) =>
      _data[key] as int? ?? defaultValue;

  Future<void> _setString(String key, String value) async {
    _data[key] = value;
    await _save();
  }

  Future<void> _setBool(String key, bool value) async {
    _data[key] = value;
    await _save();
  }

  Future<void> _setInt(String key, int value) async {
    _data[key] = value;
    await _save();
  }

  Future<void> _remove(String key) async {
    _data.remove(key);
    await _save();
  }

  // ── model migration ───────────────────────────────────────────────────────
  void _migrateModelId() {
    final saved = _getString(_kSelectedModelId);
    if (saved != null) {
      final isValid = AppConfig.availableModels.any((m) => m.id == saved);
      if (!isValid) {
        _data.remove(_kSelectedModelId);
        _save(); // fire-and-forget OK here
      }
    }
  }

  // ── custom prompts ────────────────────────────────────────────────────────
  void _loadCustomPrompts() {
    final raw = _getString(_kCustomPrompts);
    if (raw != null) {
      try {
        final List<dynamic> decoded = jsonDecode(raw);
        _customPrompts = decoded.map((p) => SystemPrompt.fromMap(p)).toList();
      } catch (_) {
        _customPrompts = [];
      }
    }
  }

  Future<void> _saveCustomPrompts() async {
    final encoded = jsonEncode(_customPrompts.map((p) => p.toMap()).toList());
    await _setString(_kCustomPrompts, encoded);
  }

  // ── prompt overrides ──────────────────────────────────────────────────────
  void _loadPromptOverrides() {
    final raw = _getString(_kPromptOverrides);
    if (raw == null) {
      _promptOverrides = {};
      return;
    }
    try {
      final Map<String, dynamic> decoded = jsonDecode(raw);
      _promptOverrides = decoded.map(
        (k, v) =>
            MapEntry(k, PromptSettings.fromMap(v as Map<String, dynamic>)),
      );
    } catch (_) {
      _promptOverrides = {};
    }
  }

  Future<void> _savePromptOverrides() async {
    final encoded = jsonEncode(
      _promptOverrides.map((k, v) => MapEntry(k, v.toMap())),
    );
    await _setString(_kPromptOverrides, encoded);
  }

  /// One-time migration: move per-prompt overrides from inline custom prompt
  /// settings into the centralized override map.
  void _migrateCustomPromptOverrides() {
    var changed = false;
    for (final prompt in _customPrompts) {
      if (prompt.settings.hasAnyOverride) {
        _promptOverrides[prompt.id] = prompt.settings;
        // Replace with empty settings
        final idx = _customPrompts.indexWhere((p) => p.id == prompt.id);
        if (idx != -1) {
          _customPrompts[idx] = SystemPrompt(
            id: prompt.id,
            name: prompt.name,
            instruction: prompt.instruction,
            settings: const PromptSettings(),
          );
        }
        changed = true;
      }
    }
    if (changed) {
      _saveCustomPrompts(); // fire-and-forget
      _savePromptOverrides();
    }
  }

  /// Get the per-prompt setting overrides for [promptId], or null if none.
  PromptSettings? getPromptOverrides(String promptId) =>
      _promptOverrides[promptId];

  /// Set per-prompt setting overrides for [promptId].
  /// If [settings] has no overrides, the entry is removed.
  Future<void> setPromptOverrides(
    String promptId,
    PromptSettings settings,
  ) async {
    if (settings.hasAnyOverride) {
      _promptOverrides[promptId] = settings;
    } else {
      _promptOverrides.remove(promptId);
    }
    await _savePromptOverrides();
  }

  /// Clear all per-prompt setting overrides for [promptId].
  Future<void> clearPromptOverrides(String promptId) async {
    _promptOverrides.remove(promptId);
    await _savePromptOverrides();
  }

  // ── clipboard history ─────────────────────────────────────────────────────
  void _loadClipboardHistory() {
    final raw = _getString(_kClipboardHistoryItems);
    if (raw == null) {
      _clipboardHistory = [];
      return;
    }
    try {
      final List<dynamic> decoded = jsonDecode(raw);
      _clipboardHistory = decoded
          .map(
            (item) =>
                ClipboardHistoryEntry.fromMap(item as Map<String, dynamic>),
          )
          .toList();
    } catch (_) {
      _clipboardHistory = [];
    }
    _trimClipboardHistory();
  }

  Future<void> _saveClipboardHistory() async {
    final encoded = jsonEncode(
      _clipboardHistory.map((e) => e.toMap()).toList(),
    );
    await _setString(_kClipboardHistoryItems, encoded);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Public API
  // ═══════════════════════════════════════════════════════════════════════════

  // ── Launch at Startup ─────────────────────────────────────────────────────
  bool get launchAtStartupEnabled => _getBool(_kLaunchAtStartup);

  Future<void> setLaunchAtStartup(bool value) async {
    await _setBool(_kLaunchAtStartup, value);
    if (Platform.isMacOS) {
      await _setMacOSLaunchAtLogin(value);
    } else {
      if (value) {
        await launchAtStartup.enable();
      } else {
        await launchAtStartup.disable();
      }
    }
  }

  static const _launchAtLoginChannel = MethodChannel('beeamvo/launch_at_login');

  Future<void> _setMacOSLaunchAtLogin(bool enabled) async {
    try {
      await _launchAtLoginChannel.invokeMethod(enabled ? 'enable' : 'disable');
    } catch (e) {
      debugPrint('[SettingsService] Failed to set launch at login: $e');
    }
  }

  // ── Prompt selection ──────────────────────────────────────────────────────
  String get selectedPromptId => _getString(_kSelectedPromptId) ?? 'standard';

  Future<void> setSelectedPromptId(String value) async {
    await _setString(_kSelectedPromptId, value);
  }

  // ── Rephraser Level ───────────────────────────────────────────────────────
  RephraseLevel get rephraseLevel {
    final value = _getString(_kRephraseLevel);
    if (value == RephraseLevel.medium.name) return RephraseLevel.medium;
    if (value == RephraseLevel.high.name) return RephraseLevel.high;
    return RephraseLevel.off;
  }

  Future<void> setRephraseLevel(RephraseLevel level) async {
    await _setString(_kRephraseLevel, level.name);
    // Notify so UI bound to rephrase level (segmented control in the
    // prompts page, mode picker tooltip, etc.) rebuilds immediately.
    notifyListeners();
  }

  // ── Custom prompts ────────────────────────────────────────────────────────
  List<SystemPrompt> get customPrompts => _customPrompts;

  Future<void> addCustomPrompt(SystemPrompt prompt) async {
    _customPrompts.add(prompt);
    await _saveCustomPrompts();
  }

  Future<void> removeCustomPrompt(String id) async {
    _customPrompts.removeWhere((p) => p.id == id);
    if (selectedPromptId == id) {
      await setSelectedPromptId('standard');
    }
    await _saveCustomPrompts();
  }

  Future<void> updateCustomPrompt(SystemPrompt prompt) async {
    final idx = _customPrompts.indexWhere((p) => p.id == prompt.id);
    if (idx != -1) {
      _customPrompts[idx] = prompt;
      await _saveCustomPrompts();
    }
  }

  // ── Model selection ───────────────────────────────────────────────────────
  String get selectedModelId =>
      _getString(_kSelectedModelId) ?? AppConfig.defaultModelId;

  Future<void> setSelectedModelId(String value) async {
    await _setString(_kSelectedModelId, value);
  }

  // ── Thinking Level (per model) ────────────────────────────────────────────
  /// Key used to store the thinking level for a specific model.
  static String _thinkingLevelKey(String modelId) => 'thinking_level_$modelId';

  /// Returns the user-selected [GeminiThinkingLevel] for [modelId], or null
  /// if the user has never changed it (meaning the model default is used).
  GeminiThinkingLevel? getThinkingLevelForModel(String modelId) {
    final stored = _getString(_thinkingLevelKey(modelId));
    return GeminiThinkingLevelExtension.fromString(stored);
  }

  /// Persists [level] as the chosen thinking level for [modelId].
  Future<void> setThinkingLevelForModel(
    String modelId,
    GeminiThinkingLevel level,
  ) async {
    await _setString(_thinkingLevelKey(modelId), level.apiValue);
  }

  /// Clears any override, reverting to the model's built-in default.
  Future<void> resetThinkingLevelForModel(String modelId) async {
    await _remove(_thinkingLevelKey(modelId));
  }

  // ── Two-pass Transcription ────────────────────────────────────────────────
  bool get twoPassTranscriptionEnabled => _getBool(_kTwoPassTranscription);

  Future<void> setTwoPassTranscriptionEnabled(bool value) async {
    await _setBool(_kTwoPassTranscription, value);
    // Notify so UI bound to two-pass state (rephraser effectiveness
    // in the prompts page, mode picker tooltip, tray menu) rebuilds.
    notifyListeners();
  }

  String get twoPassTranscriptionModelId =>
      _getString(_kTwoPassTranscriptionModelId) ?? selectedModelId;

  Future<void> setTwoPassTranscriptionModelId(String value) async {
    await _setString(_kTwoPassTranscriptionModelId, value);
  }

  String get twoPassRefinementModelId =>
      _getString(_kTwoPassRefinementModelId) ?? selectedModelId;

  Future<void> setTwoPassRefinementModelId(String value) async {
    await _setString(_kTwoPassRefinementModelId, value);
  }

  // ── Hotkey ────────────────────────────────────────────────────────────────
  HotkeyConfig get hotkey {
    final json = _getString(_kHotkey);
    if (json == null) return HotkeyConfig.defaultHotkey;
    return HotkeyConfig.fromJson(json);
  }

  Future<void> setHotkey(HotkeyConfig config) async {
    await _setString(_kHotkey, config.toJson());
  }

  Future<void> resetHotkey() async {
    await _remove(_kHotkey);
  }

  // ── Clipboard History ─────────────────────────────────────────────────────
  bool get clipboardHistoryEnabled => _getBool(_kClipboardHistoryEnabled);

  Future<void> setClipboardHistoryEnabled(bool value) async {
    await _setBool(_kClipboardHistoryEnabled, value);
  }

  bool get clipboardWatcherEnabled => _getBool(_kClipboardWatcherEnabled);

  Future<void> setClipboardWatcherEnabled(bool value) async {
    await _setBool(_kClipboardWatcherEnabled, value);
  }

  int get clipboardHistoryMaxItems =>
      _getInt(_kClipboardHistoryMaxItems, defaultValue: 40).clamp(10, 200);

  Future<void> setClipboardHistoryMaxItems(int value) async {
    final safeValue = value.clamp(10, 200);
    await _setInt(_kClipboardHistoryMaxItems, safeValue);
    _trimClipboardHistory();
    await _saveClipboardHistory();
  }

  List<ClipboardHistoryEntry> get clipboardHistory =>
      List.unmodifiable(_clipboardHistory);

  List<ClipboardHistoryEntry> get pinnedClipboardPrompts =>
      List.unmodifiable(_clipboardHistory.where((e) => e.isPinned));

  bool get autoPasteEnabled => _getBool(_kAutoPasteEnabled, defaultValue: true);

  Future<void> setAutoPasteEnabled(bool value) async {
    await _setBool(_kAutoPasteEnabled, value);
  }

  static bool shouldSkipClipboardHistoryText(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) return true;

    final sensitivePatterns = [
      RegExp(
        r'''\b(api[_-]?key|access[_-]?token|refresh[_-]?token|auth[_-]?token|client[_-]?secret|secret|password|passwd|pwd)\b\s*[:=]\s*['"]?[^\s'"]{8,}''',
        caseSensitive: false,
      ),
      RegExp(r'''\bbearer\s+[a-z0-9._~+/=-]{20,}\b''', caseSensitive: false),
      RegExp(r'''\b(sk-[A-Za-z0-9_-]{20,}|AIza[A-Za-z0-9_-]{20,})\b'''),
      RegExp(
        r'''\b(gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[baprs]-[A-Za-z0-9-]{20,})\b''',
      ),
      RegExp(r'''-----BEGIN [A-Z ]*PRIVATE KEY-----''', caseSensitive: false),
    ];

    return sensitivePatterns.any((pattern) => pattern.hasMatch(normalized));
  }

  Future<void> addClipboardEntry(String text, {bool isPinned = false}) async {
    if (!clipboardHistoryEnabled && !isPinned) return;
    final normalized = text.trim();
    if (shouldSkipClipboardHistoryText(normalized)) return;

    final now = DateTime.now();
    final existingIndex = _clipboardHistory.indexWhere(
      (e) => e.text == normalized,
    );
    if (existingIndex != -1) {
      final existing = _clipboardHistory.removeAt(existingIndex);
      _clipboardHistory.insert(
        0,
        existing.copyWith(
          updatedAt: now,
          isPinned: existing.isPinned || isPinned,
        ),
      );
    } else {
      _clipboardHistory.insert(
        0,
        ClipboardHistoryEntry(
          id: 'clip_${now.microsecondsSinceEpoch}',
          text: normalized,
          createdAt: now,
          updatedAt: now,
          isPinned: isPinned,
        ),
      );
    }

    _trimClipboardHistory();
    await _saveClipboardHistory();
  }

  Future<void> addPinnedClipboardPrompt(String text) async {
    await addClipboardEntry(text, isPinned: true);
  }

  Future<void> setClipboardEntryPinned(String id, bool pinned) async {
    final index = _clipboardHistory.indexWhere((e) => e.id == id);
    if (index == -1) return;
    final existing = _clipboardHistory[index];
    _clipboardHistory[index] = existing.copyWith(
      isPinned: pinned,
      updatedAt: DateTime.now(),
    );
    _trimClipboardHistory();
    await _saveClipboardHistory();
  }

  Future<void> removeClipboardEntry(String id) async {
    _clipboardHistory.removeWhere((e) => e.id == id);
    await _saveClipboardHistory();
  }

  Future<void> clearClipboardHistory({bool keepPinned = true}) async {
    if (keepPinned) {
      _clipboardHistory = _clipboardHistory.where((e) => e.isPinned).toList();
    } else {
      _clipboardHistory = [];
    }
    await _saveClipboardHistory();
  }

  void _trimClipboardHistory() {
    final pinned = _clipboardHistory.where((e) => e.isPinned).toList();
    final nonPinned = _clipboardHistory.where((e) => !e.isPinned).toList();
    final maxNonPinned = clipboardHistoryMaxItems;
    if (nonPinned.length > maxNonPinned) {
      nonPinned.removeRange(maxNonPinned, nonPinned.length);
    }
    _clipboardHistory = [...pinned, ...nonPinned]
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  // ── Clipboard Popup Hotkey ────────────────────────────────────────────────
  HotkeyConfig get clipboardPopupHotkey {
    final json = _getString(_kClipboardPopupHotkey);
    if (json == null) {
      return HotkeyConfig.defaultClipboardPopupHotkey;
    }
    return HotkeyConfig.fromJson(json);
  }

  Future<void> setClipboardPopupHotkey(HotkeyConfig config) async {
    await _setString(_kClipboardPopupHotkey, config.toJson());
  }

  Future<void> resetClipboardPopupHotkey() async {
    await _remove(_kClipboardPopupHotkey);
  }

  // ── Mode Selection Hotkey ─────────────────────────────────────────────────
  HotkeyConfig get modeSelectionHotkey {
    final json = _getString(_kModeSelectionHotkey);
    if (json == null) {
      return HotkeyConfig.defaultModeSelectionHotkey;
    }
    return HotkeyConfig.fromJson(json);
  }

  Future<void> setModeSelectionHotkey(HotkeyConfig config) async {
    await _setString(_kModeSelectionHotkey, config.toJson());
  }

  Future<void> resetModeSelectionHotkey() async {
    await _remove(_kModeSelectionHotkey);
  }

  // ── Recording Mode ────────────────────────────────────────────────────────
  RecordingMode get recordingMode {
    final value = _getString(_kRecordingMode);
    if (value == 'hold') return RecordingMode.hold;
    return RecordingMode.toggle;
  }

  Future<void> setRecordingMode(RecordingMode mode) async {
    await _setString(_kRecordingMode, mode.name);
  }

  // ── Audio Input Device ────────────────────────────────────────────────────
  String? get selectedAudioDeviceId => _getString(_kSelectedAudioDeviceId);

  Future<void> setSelectedAudioDeviceId(String? deviceId) async {
    if (deviceId == null) {
      await _remove(_kSelectedAudioDeviceId);
    } else {
      await _setString(_kSelectedAudioDeviceId, deviceId);
    }
  }

  // ── Transcription Backend ─────────────────────────────────────────────────
  TranscriptionBackend get transcriptionBackend {
    final value = _getString(_kTranscriptionBackend);
    if (value == TranscriptionBackend.whisper.name) {
      return TranscriptionBackend.whisper;
    }
    return TranscriptionBackend.cloud;
  }

  Future<void> setTranscriptionBackend(TranscriptionBackend backend) async {
    await _setString(_kTranscriptionBackend, backend.name);
    // Notify so UI bound to backend choice (mode picker, tray menu,
    // prompts page rephraser availability) rebuilds immediately.
    notifyListeners();
  }

  // ── Prompt & rephraser activation ─────────────────────────────────────────
  /// Whether a cloud LLM is currently in the transcription pipeline — either
  /// the Cloud backend (cloud transcribes + refines) or Whisper with two-pass
  /// cloud refinement (Whisper transcribes locally, a cloud model refines).
  ///
  /// Prompt instructions and the rephraser only change the output text when
  /// this is true; on pure offline Whisper (no two-pass) the transcript is
  /// returned verbatim and neither takes effect.
  bool get isCloudRefinementInPipeline =>
      transcriptionBackend == TranscriptionBackend.cloud ||
      twoPassTranscriptionEnabled;

  /// Whether the prompt with [promptId] would have NO effect with the
  /// current pipeline.
  ///
  /// The Default prompt (`standard`) is never considered inactive — it is the
  /// implicit baseline Whisper uses. A per-prompt override that routes the
  /// prompt to Cloud or enables two-pass also keeps it active.
  bool isPromptInactiveOnLocalBackend(String promptId) {
    if (promptId == 'standard') return false;
    final overrides = getPromptOverrides(promptId);
    if (overrides != null) {
      if (overrides.transcriptionBackend == TranscriptionBackend.cloud.value) {
        return false;
      }
      if (overrides.twoPassTranscriptionEnabled == true) return false;
    }
    return !isCloudRefinementInPipeline;
  }

  /// Keep local Whisper transcription but enable the two-pass cloud
  /// refinement pass so the selected prompt is applied during refinement.
  /// Used when the user wants prompts to take effect without giving up
  /// offline transcription of the audio itself.
  Future<void> enableLocalTwoPassRefinement() async {
    await setTranscriptionBackend(TranscriptionBackend.whisper);
    await setTwoPassTranscriptionEnabled(true);
  }

  /// Switch to single-pass cloud transcription. Two-pass is turned off
  /// because a single cloud pass already transcribes and applies the prompt.
  Future<void> switchToCloudTranscription() async {
    await setTranscriptionBackend(TranscriptionBackend.cloud);
    await setTwoPassTranscriptionEnabled(false);
  }

  // ── Whisper Model Selection ───────────────────────────────────────────────
  CloudProvider get cloudProvider {
    final value = _getString(_kCloudProvider);
    if (value == CloudProvider.vertexAi.name) return CloudProvider.vertexAi;
    return CloudProvider.geminiApiKey;
  }

  Future<void> setCloudProvider(CloudProvider provider) async {
    await _setString(_kCloudProvider, provider.name);
  }

  String? _envValue(String key) {
    if (!dotenv.isInitialized) return null;
    final value = dotenv.env[key]?.trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  bool get hasGeminiApiKey {
    return _envValue('GEMINI_API_KEY') != null || _hasGeminiApiKey;
  }

  Future<String?> readGeminiApiKey() async {
    final envKey = _envValue('GEMINI_API_KEY');
    if (envKey != null) return envKey;
    return _credentialStore.readGeminiApiKey();
  }

  Future<void> setGeminiApiKey(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await clearGeminiApiKey();
      return;
    }
    await _credentialStore.writeGeminiApiKey(trimmed);
    _hasGeminiApiKey = true;
  }

  Future<void> clearGeminiApiKey() async {
    await _credentialStore.deleteGeminiApiKey();
    _hasGeminiApiKey = false;
  }

  String? get vertexProjectId {
    final envProjectId = _envValue('VERTEX_PROJECT_ID');
    if (envProjectId != null) return envProjectId;
    final projectId = _getString(_kVertexProjectId)?.trim();
    if (projectId == null || projectId.isEmpty) return null;
    return projectId;
  }

  Future<void> setVertexProjectId(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await clearVertexProjectId();
      return;
    }
    await _setString(_kVertexProjectId, trimmed);
  }

  Future<void> clearVertexProjectId() async {
    await _remove(_kVertexProjectId);
  }

  /// Whether the currently-selected cloud provider has the credentials
  /// needed to run a cloud transcription or refinement pass right now.
  /// Mirrors the readiness checks used in onboarding and troubleshooting.
  bool get hasCloudCredentials {
    switch (cloudProvider) {
      case CloudProvider.geminiApiKey:
        return hasGeminiApiKey;
      case CloudProvider.vertexAi:
        return vertexProjectId != null;
    }
  }

  String get whisperModelId => _getString(_kWhisperModelId) ?? 'ggml-tiny.bin';

  Future<void> setWhisperModelId(String value) async {
    await _setString(_kWhisperModelId, value);
  }

  // ── Whisper Language ─────────────────────────────────────────────────────
  String get whisperLanguage => _getString(_kWhisperLanguage) ?? 'en';

  Future<void> setWhisperLanguage(String value) async {
    await _setString(_kWhisperLanguage, value);
  }

  // ── Onboarding ────────────────────────────────────────────────────────────
  bool get isOnboardingComplete => _getBool(_kOnboardingComplete);

  Future<void> setOnboardingComplete() async {
    await _setBool(_kOnboardingComplete, true);
  }

    // ── Duration Limit ────────────────────────────────────────────────────────
    bool get durationLimitEnabled => _getBool(_kDurationLimitEnabled);

    Future<void> setDurationLimitEnabled(bool value) async {
      await _setBool(_kDurationLimitEnabled, value);
    }

    int get durationLimit => _getInt(_kDurationLimit, defaultValue: 300);

    Future<void> setDurationLimit(int seconds) async {
      await _setInt(_kDurationLimit, seconds);
    }

    // ── Theme Mode ────────────────────────────────────────────────────────────
    /// Stored theme-mode preference. One of `'system'`, `'light'`, `'dark'`.
    /// Defaults to `'system'` (follow the OS preference) when never set.
    String get themeMode => _getString(_kThemeMode) ?? 'system';

    /// Updates the persisted theme mode and notifies listeners so the app shell
    /// rebuilds the [MaterialApp] with the new [ThemeMode].
    Future<void> setThemeMode(String mode) async {
      await _setString(_kThemeMode, mode);
      notifyListeners();
    }

    /// Resolved [ThemeMode] used by [MaterialApp]. Maps the persisted string to
    /// the Flutter enum; unknown values fall back to [ThemeMode.system].
    ThemeMode get themeModeEnum {
      switch (themeMode) {
        case 'light':
          return ThemeMode.light;
        case 'dark':
          return ThemeMode.dark;
        default:
          return ThemeMode.system;
      }
    }
  }

// ── Recording Mode enum ────────────────────────────────────────────────────
enum RecordingMode { toggle, hold }

extension RecordingModeExtension on RecordingMode {
  String get displayName {
    switch (this) {
      case RecordingMode.toggle:
        return 'Toggle (Press to Start/Stop)';
      case RecordingMode.hold:
        return 'Hold to Record';
    }
  }

  String get shortName {
    switch (this) {
      case RecordingMode.toggle:
        return 'Toggle';
      case RecordingMode.hold:
        return 'Hold';
    }
  }
}
