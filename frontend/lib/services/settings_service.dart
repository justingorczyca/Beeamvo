import 'dart:async';
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
import '../models/hotkey_config.dart';
import '../models/clipboard_history_entry.dart';
import '../config.dart';
import 'codex_oauth_manager.dart';
import 'secure_credential_store.dart';
import 'update_check_service.dart';
import 'xai_oauth_manager.dart';
import 'file_permissions.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class LaunchAtStartupException implements Exception {
  const LaunchAtStartupException(this.message);

  final String message;

  @override
  String toString() => message;
}

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
  SettingsService({
    SecureCredentialStore? credentialStore,
    @visibleForTesting this._applicationSupportDirectory,
  }) : _credentialStore =
           credentialStore ?? const FlutterSecureCredentialStore();
  // ── keys ──────────────────────────────────────────────────────────────────
  static const _kLaunchAtStartup = 'launch_at_startup';
  static const _kSelectedPromptId = 'active_system_prompt_id';
  static const _kToneRefinement = 'tone_refinement';
  static const _kCustomPrompts = 'custom_prompts';
  static const _kSelectedModelId = 'selected_model_id';
  static const _kTwoPassTranscription = 'two_pass_transcription';
  static const _kTwoPassRefinementModelId = 'two_pass_refinement_model_id';
  static const _kRefinementProvider = 'refinement_provider';
  static const _kLegacyPrimaryRolesMigrated = 'legacy_primary_roles_migrated';

  /// Set once the pass-2 thinking levels were split from the first-pass
  /// levels, so the one-time copy never re-couples later choices.
  static const _kRefinementThinkingSplit = 'refinement_thinking_split';

  /// Releases that allowed a text-only primary provider stored its separate
  /// audio first pass here. Read once by [_migrate], then retired.
  static const _kLegacyFirstPassProvider = 'two_pass_cloud_provider';
  static const _kLegacyFirstPassModelId = 'two_pass_transcription_model_id';
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
  static const _kSpokenLanguage = 'spoken_language';
  static const _kTranscriptionBackend = 'transcription_backend';
  static const _kCloudProvider = 'cloud_provider';
  static const _kOpenAiBaseUrl = 'openai_base_url';

  /// When true, `CodexOAuthManager` must not import the Codex CLI's
  /// `~/.codex/auth.json`. Set by an explicit sign-out so the user stays
  /// signed out across launches; cleared on every successful sign-in.
  static const _kCodexCliImportDisabled = 'codex_cli_import_disabled';

  /// Secure-store account names (values live in the OS credential store, not
  /// in `settings.json`).
  static const _kOpenAiApiKeyAccount = 'openai_api_key';

  /// Keys from earlier releases whose features no longer exist. Removed on
  /// load so an upgraded install carries no stale state. (The step-2
  /// refinement model key was retired once and is live again, so it must
  /// never appear here — stale values are validated on read instead.)
  static const _retiredKeys = <String>[
    'whisper_language',
    'transcription_language',
    'transcription_mode',
    'transcription_diarization',
    'transcription_word_timestamps',
    'gemini_api_surface',
    'openai_compatible_provider_id',
    'openai_compatible_model_id',
    'rephrase_level',
    'prompt_overrides',
    'transcription_custom_vocabulary',
    _kLegacyFirstPassProvider,
    _kLegacyFirstPassModelId,
  ];
  static const _retiredKeyPrefixes = <String>[
    'openai_compatible_base_url_',
    '${_kLegacyFirstPassModelId}_',
  ];

  // Update notifications
  static const _kLastUpdateCheckAt = 'last_update_check_at';
  static const _kAvailableUpdateVersion = 'available_update_version';
  static const _kAvailableUpdateUrl = 'available_update_url';
  static const _kAvailableUpdateNotes = 'available_update_notes';

  static const _kVertexProjectId = 'vertex_project_id';
  static const _kOnboardingComplete = 'onboarding_complete';
  static const _kThemeMode = 'theme_mode';

  // ── internal state ────────────────────────────────────────────────────────
  final SecureCredentialStore _credentialStore;
  final Directory? _applicationSupportDirectory;
  late File _file;
  Map<String, dynamic> _data = {};
  List<SystemPrompt> _customPrompts = [];
  List<ClipboardHistoryEntry> _clipboardHistory = [];
  bool _hasGeminiApiKey = false;
  String? _geminiApiKey;
  bool _hasOpenAiApiKey = false;
  String? _openAiApiKey;
  bool _hasCodexAuth = false;
  CodexOAuthManager? _codexOAuth;
  bool _hasGrokAuth = false;
  XAiOAuthManager? _xaiOAuth;
  bool _launchAtStartupRequiresApproval = false;

  // ── init ──────────────────────────────────────────────────────────────────
  Future<void> initialize() async {
    // Resolve the settings file path
    final dir =
        _applicationSupportDirectory ?? await getApplicationSupportDirectory();
    final folder = Directory('${dir.path}${Platform.pathSeparator}Beeamvo');
    if (!folder.existsSync()) {
      folder.createSync(recursive: true);
    }
    await setPosixPermissions(folder.path, '700');
    _file = File('${folder.path}${Platform.pathSeparator}settings.json');
    if (_file.existsSync()) {
      await setPosixPermissions(_file.path, '600');
    }

    // Load existing data
    await _load();

    // System integrations
    if (!Platform.isAndroid && !Platform.isIOS) {
      final packageInfo = await PackageInfo.fromPlatform();
      // launch_at_startup plugin doesn't support macOS, use native implementation
      if (!Platform.isMacOS) {
        launchAtStartup.setup(
          appName: packageInfo.appName,
          appPath: Platform.resolvedExecutable,
        );
      }
      await _reconcileLaunchAtStartup();
    }

    _loadCustomPrompts();
    _loadClipboardHistory();
    await _migrate();
    await _loadSecureState();

    debugPrint('[SettingsService] initialized');
  }

  // ── JSON persistence ──────────────────────────────────────────────────────
  //
  // Persistence is crash-safe: `_save()` writes atomically (temp-file →
  // rename) and keeps a `.bak` of the previous-good file, so a power loss /
  // process kill / disk-full mid-write can never produce a truncated live
  // file. On load we try the live file, then `.bak`, then the leftover
  // `.tmp`, before falling back to an empty document.
  Future<void> _load() async {
    _data =
        await _readJsonMap(_file) ??
        await _readJsonMap(File('${_file.path}.bak')) ??
        await _readJsonMap(File('${_file.path}.tmp')) ??
        <String, dynamic>{};
  }

  /// Decode [f] as a JSON object map, or `null` if missing/empty/corrupt.
  Future<Map<String, dynamic>?> _readJsonMap(File f) async {
    try {
      if (!f.existsSync()) return null;
      final raw = (await f.readAsString()).trim();
      if (raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      debugPrint('[SettingsService] ${f.path}: top-level not an object');
      return null;
    } catch (e) {
      debugPrint('[SettingsService] load error from ${f.path}: $e');
      return null;
    }
  }

  /// Serial queue for all writes. Concurrent callers (migrations, settings
  /// setters, the 1.2s clipboard watcher) enqueue here so partial `_data`
  /// snapshots never interleave on disk. Each enqueued write is itself atomic.
  Future<void> _saveQueue = Future<void>.value();

  Future<void> _save() {
    final task = _saveQueue.then((_) => _doSave());
    // Keep the chain alive even if a single write errors, so a transient
    // failure can never permanently break persistence for later writes.
    _saveQueue = task.catchError((Object _) {});
    return task;
  }

  Future<void> _doSave() async {
    try {
      final encoded = const JsonEncoder.withIndent('  ').convert(_data);
      await _writeAtomic(_file, encoded);
    } catch (e) {
      debugPrint('[SettingsService] save error: $e');
    }
  }

  /// Atomically persist [content] to [target], keeping a `.bak` of the
  /// previous-good file. Renames always target a non-existent path, so they
  /// are atomic and cross-platform safe (avoiding replace-existing quirks on
  /// Windows). If a crash lands between the two renames, `_load()` recovers
  /// from the `.bak`.
  Future<void> _writeAtomic(File target, String content) async {
    final tmp = File('${target.path}.tmp');
    final backup = File('${target.path}.bak');
    final targetExisted = target.existsSync();
    await tmp.writeAsString(content, flush: true);
    await setPosixPermissions(tmp.path, '600');
    if (targetExisted) {
      if (backup.existsSync()) {
        await backup.delete();
      }
      await target.rename(backup.path);
    }
    await tmp.rename(target.path);
  }

  Future<void> _loadSecureState() async {
    final geminiApiKey = await _credentialStore.readGeminiApiKey();
    _geminiApiKey = geminiApiKey;
    _hasGeminiApiKey = geminiApiKey != null && geminiApiKey.trim().isNotEmpty;

    final openAiApiKey = await _credentialStore.readApiKey(
      _kOpenAiApiKeyAccount,
    );
    _openAiApiKey = openAiApiKey;
    _hasOpenAiApiKey = openAiApiKey != null && openAiApiKey.trim().isNotEmpty;

    // Presence check only; transparently imports the Codex CLI's auth.json
    // when the user has not disabled that import.
    _hasCodexAuth = await codexOAuth.loadCredentials() != null;
    _hasGrokAuth = await xaiOAuth.loadCredentials() != null;
  }

  /// Brings a settings file from any earlier release up to the current
  /// schema. Idempotent; writes only when something changed.
  Future<void> _migrate() async {
    var dirty = false;

    final backend = _getString(_kTranscriptionBackend);
    if (backend == null || backend == 'gemini') {
      _data[_kTranscriptionBackend] = TranscriptionBackend.cloud.name;
      dirty = true;
    }
    if (_getString(_kCloudProvider) == null) {
      _data[_kCloudProvider] = CloudProvider.geminiApiKey.name;
      dirty = true;
    }

    // Earlier releases treated every primary except Gemini and Vertex as a
    // polish provider. Run this migration once so a newly selected ChatGPT
    // first pass is not moved on a later launch.
    if (_data[_kLegacyPrimaryRolesMigrated] != true) {
      const legacyAudioProviders = {
        CloudProvider.geminiApiKey,
        CloudProvider.vertexAi,
      };
      final savedPrimary = CloudProviderExtension.fromValue(
        _getString(_kCloudProvider),
      );
      if (!legacyAudioProviders.contains(savedPrimary)) {
        final legacyFirst = CloudProviderExtension.fromValue(
          _getString(_kLegacyFirstPassProvider),
        );
        final firstPass = legacyAudioProviders.contains(legacyFirst)
            ? legacyFirst
            : CloudProvider.geminiApiKey;
        _data[_kCloudProvider] = firstPass.name;
        _data[_kRefinementProvider] ??= savedPrimary.name;
        // A text-only primary only ever worked in two-step mode.
        _data[_kTwoPassTranscription] = true;
        final legacyModel = _getString(_kLegacyFirstPassModelId);
        if (AppConfig.audioModelsForProvider(
          firstPass,
        ).any((m) => m.id == legacyModel)) {
          _data[_kSelectedModelId] = legacyModel;
        }
      }
      _data[_kLegacyPrimaryRolesMigrated] = true;
      dirty = true;
    }

    // Pass-2 thinking levels used to share the first-pass keys. Copy the
    // existing choices once so both passes start where they were, then let
    // them diverge independently.
    if (_data[_kRefinementThinkingSplit] != true) {
      for (final key in _data.keys.toList()) {
        if (!key.startsWith('thinking_level_')) continue;
        final modelId = key.substring('thinking_level_'.length);
        _data[_refinementThinkingLevelKey(modelId)] ??= _data[key];
      }
      _data[_kRefinementThinkingSplit] = true;
      dirty = true;
    }

    // The rephraser became the built-in Professional prompt.
    final rephrase = _getString('rephrase_level');
    if (rephrase != null &&
        rephrase != 'off' &&
        selectedPromptId == SystemPrompt.defaultId) {
      _data[_kSelectedPromptId] = SystemPrompt.professionalId;
      dirty = true;
    }

    // Whisper and cloud language settings merged into one.
    if (_getString(_kSpokenLanguage) == null) {
      final legacy =
          _getString('transcription_language') ??
          _getString('whisper_language');
      if (legacy != null) {
        _data[_kSpokenLanguage] = legacy;
        dirty = true;
      }
    }

    // Preserve any offered primary preference; provider/pipeline restrictions
    // apply at use time. Clear a retired optional transcription model.
    final savedModel = _getString(_kSelectedModelId);
    final resolvedModel = AppConfig.resolveModelId(savedModel);
    if (savedModel != resolvedModel) {
      _data[_kSelectedModelId] = resolvedModel;
      dirty = true;
    }
    for (final key in _retiredKeys) {
      if (_data.remove(key) != null) dirty = true;
    }
    final prefixed = _data.keys
        .where((k) => _retiredKeyPrefixes.any(k.startsWith))
        .toList();
    for (final key in prefixed) {
      _data.remove(key);
      dirty = true;
    }

    if (await _resetStyleIfUnavailable()) dirty = true;
    if (dirty) await _save();
  }

  // ── typed accessors ───────────────────────────────────────────────────────
  //
  // These use `is` guards rather than `as` casts: a stored value that is
  // present-but-mistyped (an `int` where a `String` is expected, from a
  // partially written file, a manual edit, or a future schema change) must
  // NOT throw on launch — it should gracefully default, matching the rest of
  // the file's defensive intent. (`x as String?` throws _TypeError on a
  // non-String, non-null value instead of returning null.)
  String? _getString(String key) {
    final v = _data[key];
    return v is String ? v : null;
  }

  bool _getBool(String key, {bool defaultValue = false}) {
    final v = _data[key];
    return v is bool ? v : defaultValue;
  }

  int _getInt(String key, {required int defaultValue}) {
    final v = _data[key];
    if (v is int) return v;
    // Tolerate JSON numbers parsed as doubles (e.g. an externally edited file).
    if (v is num) return v.toInt();
    return defaultValue;
  }

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
  bool get launchAtStartupRequiresApproval => _launchAtStartupRequiresApproval;

  Future<void> setLaunchAtStartup(bool value) async {
    if (Platform.isAndroid || Platform.isIOS) return;
    try {
      final succeeded = Platform.isMacOS
          ? await _setMacOSLaunchAtLogin(value)
          : await _setPluginLaunchAtStartup(value);
      if (!succeeded) {
        throw const LaunchAtStartupException(
          'Could not update launch at login. Check your system settings and try again.',
        );
      }
      await _reconcileLaunchAtStartup();
      notifyListeners();
    } on LaunchAtStartupException {
      rethrow;
    } catch (e) {
      debugPrint('[SettingsService] Failed to set launch at login: $e');
      throw LaunchAtStartupException(
        'Could not update launch at login. Check your system settings and try again.',
      );
    }
  }

  static const _launchAtLoginChannel = MethodChannel('beeamvo/launch_at_login');

  Future<bool> _setPluginLaunchAtStartup(bool enabled) async {
    if (enabled) {
      return launchAtStartup.enable();
    } else {
      return launchAtStartup.disable();
    }
  }

  Future<bool> _setMacOSLaunchAtLogin(bool enabled) async {
    final result = await _launchAtLoginChannel.invokeMethod<bool>(
      enabled ? 'enable' : 'disable',
    );
    return result == true;
  }

  Future<void> _reconcileLaunchAtStartup() async {
    try {
      bool enabled;
      if (Platform.isMacOS) {
        final status = await _launchAtLoginChannel.invokeMethod<String>(
          'status',
        );
        _launchAtStartupRequiresApproval = status == 'requiresApproval';
        enabled = launchAtStartupStatusIsEnabled(status);
      } else {
        _launchAtStartupRequiresApproval = false;
        enabled = await launchAtStartup.isEnabled();
      }
      _data[_kLaunchAtStartup] = enabled;
      await _save();
    } catch (e) {
      debugPrint('[SettingsService] Failed to reconcile launch at login: $e');
    }
  }

  @visibleForTesting
  static bool launchAtStartupStatusIsEnabled(String? status) =>
      status == 'enabled' || status == 'requiresApproval';

  // ── Prompt selection ──────────────────────────────────────────────────────
  String get selectedPromptId =>
      _getString(_kSelectedPromptId) ?? SystemPrompt.defaultId;

  Future<void> setSelectedPromptId(String value) async {
    if (!promptIsApplied && value != SystemPrompt.defaultId) return;
    await _setString(_kSelectedPromptId, value);
    notifyListeners();
  }

  ToneRefinement get toneRefinement =>
      ToneRefinementExtension.fromValue(_getString(_kToneRefinement));

  Future<void> setToneRefinement(ToneRefinement value) async {
    if (!promptIsApplied && value != ToneRefinement.off) return;
    await _setString(_kToneRefinement, value.name);
    notifyListeners();
  }

  /// The currently selected prompt (built-in or custom).
  SystemPrompt get selectedPrompt =>
      SystemPrompt.getById(selectedPromptId, customPrompts: _customPrompts);

  // ── Custom prompts ────────────────────────────────────────────────────────
  List<SystemPrompt> get customPrompts => _customPrompts;

  Future<void> addCustomPrompt(SystemPrompt prompt) async {
    _customPrompts.add(prompt);
    await _saveCustomPrompts();
    notifyListeners();
  }

  Future<void> removeCustomPrompt(String id) async {
    _customPrompts.removeWhere((p) => p.id == id);
    if (selectedPromptId == id) {
      await setSelectedPromptId(SystemPrompt.defaultId);
    }
    await _saveCustomPrompts();
    notifyListeners();
  }

  Future<void> updateCustomPrompt(SystemPrompt prompt) async {
    final idx = _customPrompts.indexWhere((p) => p.id == prompt.id);
    if (idx != -1) {
      _customPrompts[idx] = prompt;
      await _saveCustomPrompts();
      notifyListeners();
    }
  }

  // ── Model selection ───────────────────────────────────────────────────────
  //
  // Model preferences are stored per provider so switching providers never
  // erases another provider's choice. Gemini and Vertex share one catalog and
  // therefore share the legacy `_kSelectedModelId` key; OpenAI and Codex get
  // their own suffixed keys.
  static String _selectedModelKeyFor(CloudProvider provider) {
    switch (provider) {
      case CloudProvider.geminiApiKey:
      case CloudProvider.vertexAi:
        return _kSelectedModelId;
      case CloudProvider.openaiApiKey:
        return '${_kSelectedModelId}_openai';
      case CloudProvider.codexOAuth:
        return '${_kSelectedModelId}_codex';
      case CloudProvider.grokOAuth:
        return '${_kSelectedModelId}_grok';
    }
  }

  static String _refinementModelKeyFor(CloudProvider provider) {
    switch (provider) {
      case CloudProvider.geminiApiKey:
      case CloudProvider.vertexAi:
        return _kTwoPassRefinementModelId;
      case CloudProvider.openaiApiKey:
        return '${_kTwoPassRefinementModelId}_openai';
      case CloudProvider.codexOAuth:
        return '${_kTwoPassRefinementModelId}_codex';
      case CloudProvider.grokOAuth:
        return '${_kTwoPassRefinementModelId}_grok';
    }
  }

  /// Models selectable for the audio first pass: single-pass dictation runs
  /// on it directly, and it stays pass 1 when two-step refinement is on.
  List<GeminiModelConfig> get primaryModels =>
      AppConfig.audioModelsForProvider(cloudProvider);

  String resolvePrimaryModelId(String? id) {
    final models = primaryModels;
    if (models.any((model) => model.id == id)) return id!;
    final fallback = AppConfig.defaultModelIdForProvider(cloudProvider);
    return models.any((m) => m.id == fallback) ? fallback : models.first.id;
  }

  /// The first-pass (audio) model. The polish (pass-2) model is chosen
  /// separately via [twoPassRefinementModelId].
  String get selectedModelId =>
      resolvePrimaryModelId(_getString(_selectedModelKeyFor(cloudProvider)));

  Future<void> setSelectedModelId(String value) async {
    await _setString(_selectedModelKeyFor(cloudProvider), value);
    await _resetStyleIfUnavailable();
    notifyListeners();
  }

  // ── Thinking Level (per model, per pass) ──────────────────────────────────
  //
  // The audio first pass (single-pass dictation or pass 1 of two-step) and
  // the pass-2 polish store their levels under separate keys, so choosing
  // the same model for both passes never couples their thinking levels.
  static String _thinkingLevelKey(String modelId) => 'thinking_level_$modelId';
  static String _refinementThinkingLevelKey(String modelId) =>
      'refinement_thinking_level_$modelId';

  /// First-pass thinking level chosen for [modelId], or null if the user has
  /// never changed it (meaning the pass default is used).
  GeminiThinkingLevel? getThinkingLevelForModel(String modelId) =>
      GeminiThinkingLevelExtension.fromString(
        _getString(_thinkingLevelKey(modelId)),
      );

  Future<void> setThinkingLevelForModel(
    String modelId,
    GeminiThinkingLevel level,
  ) async {
    await _setString(_thinkingLevelKey(modelId), level.apiValue);
    notifyListeners();
  }

  /// Clears any first-pass override, reverting to the pass default.
  Future<void> resetThinkingLevelForModel(String modelId) async {
    await _remove(_thinkingLevelKey(modelId));
    notifyListeners();
  }

  /// Pass-2 (polish) thinking level chosen for [modelId], or null for the
  /// model default. Independent of [getThinkingLevelForModel].
  GeminiThinkingLevel? getRefinementThinkingLevel(String modelId) =>
      GeminiThinkingLevelExtension.fromString(
        _getString(_refinementThinkingLevelKey(modelId)),
      );

  Future<void> setRefinementThinkingLevel(
    String modelId,
    GeminiThinkingLevel level,
  ) async {
    await _setString(_refinementThinkingLevelKey(modelId), level.apiValue);
    notifyListeners();
  }

  // ── Two-step refinement ───────────────────────────────────────────────────
  //
  // Pass 1 turns audio into raw text with Gemini, Vertex, Codex Transcribe, or
  // Whisper offline. Pass 2 applies the selected prompt with a separately
  // chosen provider and model, which only receives the validated transcript.
  bool get twoPassTranscriptionEnabled => _getBool(_kTwoPassTranscription);

  Future<void> setTwoPassTranscriptionEnabled(bool value) async {
    await _setBool(_kTwoPassTranscription, value);
    await _resetStyleIfUnavailable();
    notifyListeners();
  }

  /// Provider that polishes the transcript in pass 2. Any provider may
  /// refine; it defaults to the first-pass provider until chosen explicitly.
  CloudProvider get refinementProvider {
    final saved = _getString(_kRefinementProvider);
    for (final p in CloudProvider.values) {
      if (p.name == saved) return p;
    }
    return cloudProvider;
  }

  Future<void> setRefinementProvider(CloudProvider provider) async {
    await _setString(_kRefinementProvider, provider.name);
    notifyListeners();
  }

  /// Prompt-capable models offered for the pass-2 polish role.
  List<GeminiModelConfig> get refinementModels =>
      AppConfig.promptCapableModelsForProvider(refinementProvider);

  /// Model that polishes the pass-1 transcript. Independent of the first-pass
  /// model: it may be the same model, or any prompt-capable model of
  /// [refinementProvider].
  String get twoPassRefinementModelId {
    final provider = refinementProvider;
    final models = refinementModels;
    final saved = _getString(_refinementModelKeyFor(provider));
    if (models.any((m) => m.id == saved)) return saved!;
    // Honor a prompt-capable primary preference as the initial polish model.
    // This covers upgrades from releases where text-only providers were the
    // primary account and their primary slot held the polish model.
    final rawPrimary = _getString(_selectedModelKeyFor(provider));
    if (models.any((m) => m.id == rawPrimary)) return rawPrimary!;
    final fallback = AppConfig.defaultModelIdForProvider(provider);
    return models.any((m) => m.id == fallback) ? fallback : models.first.id;
  }

  Future<void> setTwoPassRefinementModelId(String value) async {
    if (!refinementModels.any((m) => m.id == value)) {
      throw ArgumentError(
        '$value cannot polish text for ${refinementProvider.displayName}.',
      );
    }
    await _setString(_refinementModelKeyFor(refinementProvider), value);
    notifyListeners();
  }

  /// Whether the pass-2 provider has local credentials.
  bool get hasRefinementCredentials =>
      hasCredentialsForProvider(refinementProvider);

  /// Local credential presence, not an assertion that remote credentials work.
  /// Gates recording on every stage the active pipeline uses.
  bool get isTranscriptionReady => transcriptionSetupIssue == null;

  /// User-facing reason recording is blocked, or null when every stage of
  /// the active pipeline has local credentials.
  String? get transcriptionSetupIssue {
    if (transcriptionBackend == TranscriptionBackend.cloud &&
        !hasCloudCredentials) {
      return '${_credentialAction(cloudProvider)} in Settings to start '
          'dictating.';
    }
    if (twoPassTranscriptionEnabled && !hasRefinementCredentials) {
      return '${_credentialAction(refinementProvider)} in Settings to use it '
          'for two-step polish.';
    }
    return null;
  }

  static String _credentialAction(CloudProvider provider) => switch (provider) {
    CloudProvider.codexOAuth ||
    CloudProvider.grokOAuth => 'Sign in to ${provider.displayName}',
    _ => 'Add your ${provider.displayName} ${provider.credentialLabel}',
  };

  /// Whether the selected prompt shapes the output. When false, the style is
  /// pinned to Default and tone to Off.
  bool get promptIsApplied =>
      twoPassTranscriptionEnabled ||
      (transcriptionBackend == TranscriptionBackend.cloud &&
          !AppConfig.getModelById(selectedModelId).isTranscriptionOnly);

  Future<bool> _resetStyleIfUnavailable() async {
    if (promptIsApplied ||
        (selectedPromptId == SystemPrompt.defaultId &&
            toneRefinement == ToneRefinement.off)) {
      return false;
    }

    _data[_kSelectedPromptId] = SystemPrompt.defaultId;
    _data[_kToneRefinement] = ToneRefinement.off.name;
    await _save();
    return true;
  }

  // ── Hotkey ────────────────────────────────────────────────────────────────
  HotkeyConfig get hotkey {
    final json = _getString(_kHotkey);
    if (json == null) return HotkeyConfig.defaultHotkey;
    return HotkeyConfig.fromJson(json);
  }

  Future<void> setHotkey(HotkeyConfig config) async {
    await _setString(_kHotkey, config.toJson());
    notifyListeners();
  }

  Future<void> resetHotkey() async {
    await _remove(_kHotkey);
    notifyListeners();
  }

  // ── Clipboard History ─────────────────────────────────────────────────────
  bool get clipboardHistoryEnabled => _getBool(_kClipboardHistoryEnabled);

  Future<void> setClipboardHistoryEnabled(bool value) async {
    await _setBool(_kClipboardHistoryEnabled, value);
    notifyListeners();
  }

  /// Mobile delivers results via history, so enable it on first run only —
  /// an explicit user choice is never overridden.
  Future<void> applyMobileDefaults() async {
    if (_data[_kClipboardHistoryEnabled] is! bool) {
      await setClipboardHistoryEnabled(true);
    }
  }

  bool get clipboardWatcherEnabled => _getBool(_kClipboardWatcherEnabled);

  Future<void> setClipboardWatcherEnabled(bool value) async {
    await _setBool(_kClipboardWatcherEnabled, value);
    notifyListeners();
  }

  int get clipboardHistoryMaxItems =>
      _getInt(_kClipboardHistoryMaxItems, defaultValue: 40).clamp(10, 200);

  Future<void> setClipboardHistoryMaxItems(int value) async {
    final safeValue = value.clamp(10, 200);
    await _setInt(_kClipboardHistoryMaxItems, safeValue);
    _trimClipboardHistory();
    await _saveClipboardHistory();
    notifyListeners();
  }

  List<ClipboardHistoryEntry> get clipboardHistory =>
      List.unmodifiable(_clipboardHistory);

  List<ClipboardHistoryEntry> get pinnedClipboardPrompts =>
      List.unmodifiable(_clipboardHistory.where((e) => e.isPinned));

  bool get autoPasteEnabled => _getBool(_kAutoPasteEnabled, defaultValue: true);

  Future<void> setAutoPasteEnabled(bool value) async {
    await _setBool(_kAutoPasteEnabled, value);
    notifyListeners();
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
        r'''\b(gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9_-]{20,}|xox[baprs]-[A-Za-z0-9-]{20,})\b''',
      ),
      RegExp(r'''\bAKIA[0-9A-Z]{16}\b'''),
      RegExp(r'''\b(?:sk|rk)_(?:live|test)_[A-Za-z0-9]{16,}\b'''),
      RegExp(
        r'''\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b''',
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
    return HotkeyConfig.fromJson(
      json,
      defaultTo: HotkeyConfig.defaultClipboardPopupHotkey,
    );
  }

  Future<void> setClipboardPopupHotkey(HotkeyConfig config) async {
    await _setString(_kClipboardPopupHotkey, config.toJson());
    notifyListeners();
  }

  Future<void> resetClipboardPopupHotkey() async {
    await _remove(_kClipboardPopupHotkey);
    notifyListeners();
  }

  // ── Mode Selection Hotkey ─────────────────────────────────────────────────
  HotkeyConfig get modeSelectionHotkey {
    final json = _getString(_kModeSelectionHotkey);
    if (json == null) {
      return HotkeyConfig.defaultModeSelectionHotkey;
    }
    return HotkeyConfig.fromJson(
      json,
      defaultTo: HotkeyConfig.defaultModeSelectionHotkey,
    );
  }

  Future<void> setModeSelectionHotkey(HotkeyConfig config) async {
    await _setString(_kModeSelectionHotkey, config.toJson());
    notifyListeners();
  }

  Future<void> resetModeSelectionHotkey() async {
    await _remove(_kModeSelectionHotkey);
    notifyListeners();
  }

  // ── Recording Mode ────────────────────────────────────────────────────────
  RecordingMode get recordingMode {
    final value = _getString(_kRecordingMode);
    if (value == 'hold') return RecordingMode.hold;
    return RecordingMode.toggle;
  }

  Future<void> setRecordingMode(RecordingMode mode) async {
    await _setString(_kRecordingMode, mode.name);
    notifyListeners();
  }

  // ── Audio Input Device ────────────────────────────────────────────────────
  String? get selectedAudioDeviceId => _getString(_kSelectedAudioDeviceId);

  Future<void> setSelectedAudioDeviceId(String? deviceId) async {
    if (deviceId == null) {
      await _remove(_kSelectedAudioDeviceId);
    } else {
      await _setString(_kSelectedAudioDeviceId, deviceId);
    }
    notifyListeners();
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
    await _resetStyleIfUnavailable();
    notifyListeners();
  }

  // ── Cloud provider & credentials ──────────────────────────────────────────
  /// First-pass cloud provider: the one that receives audio. Always a member
  /// of [AppConfig.firstPassAudioProviders]; OpenAI API-key and Grok providers
  /// are chosen separately as [refinementProvider].
  CloudProvider get cloudProvider {
    final saved = CloudProviderExtension.fromValue(_getString(_kCloudProvider));
    return AppConfig.canTranscribeAudio(saved)
        ? saved
        : CloudProvider.geminiApiKey;
  }

  Future<void> setCloudProvider(CloudProvider provider) async {
    if (!AppConfig.canTranscribeAudio(provider)) {
      throw ArgumentError(
        '${provider.displayName} cannot transcribe audio; choose it as a '
        'two-step refinement provider instead.',
      );
    }
    await _setString(_kCloudProvider, provider.name);
    await _resetStyleIfUnavailable();
    notifyListeners();
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
    if (_geminiApiKey != null || _hasGeminiApiKey) return _geminiApiKey;
    final stored = await _credentialStore.readGeminiApiKey();
    _geminiApiKey = stored;
    _hasGeminiApiKey = stored != null && stored.trim().isNotEmpty;
    return stored;
  }

  Future<void> setGeminiApiKey(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await clearGeminiApiKey();
      return;
    }
    await _credentialStore.writeGeminiApiKey(trimmed);
    _geminiApiKey = trimmed;
    _hasGeminiApiKey = true;
    notifyListeners();
  }

  Future<void> clearGeminiApiKey() async {
    await _credentialStore.deleteGeminiApiKey();
    _geminiApiKey = null;
    _hasGeminiApiKey = false;
    notifyListeners();
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
    notifyListeners();
  }

  Future<void> clearVertexProjectId() async {
    await _remove(_kVertexProjectId);
    notifyListeners();
  }

  // ── OpenAI-compatible credentials ─────────────────────────────────────────
  bool get hasOpenAiApiKey {
    return _envValue('OPENAI_API_KEY') != null || _hasOpenAiApiKey;
  }

  Future<String?> readOpenAiApiKey() async {
    final envKey = _envValue('OPENAI_API_KEY');
    if (envKey != null) return envKey;
    if (_openAiApiKey != null || _hasOpenAiApiKey) return _openAiApiKey;
    final stored = await _credentialStore.readApiKey(_kOpenAiApiKeyAccount);
    _openAiApiKey = stored;
    _hasOpenAiApiKey = stored != null && stored.trim().isNotEmpty;
    return stored;
  }

  Future<void> setOpenAiApiKey(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await clearOpenAiApiKey();
      return;
    }
    await _credentialStore.writeApiKey(_kOpenAiApiKeyAccount, trimmed);
    _openAiApiKey = trimmed;
    _hasOpenAiApiKey = true;
    notifyListeners();
  }

  Future<void> clearOpenAiApiKey() async {
    await _credentialStore.deleteApiKey(_kOpenAiApiKeyAccount);
    _openAiApiKey = null;
    _hasOpenAiApiKey = false;
    notifyListeners();
  }

  /// Base URL for the OpenAI-compatible endpoint, or `null` for the default
  /// `https://api.openai.com/v1`. `OPENAI_BASE_URL` in `.env` wins.
  String? get openAiBaseUrl {
    final envValue = _envValue('OPENAI_BASE_URL');
    if (envValue != null) return envValue;
    final stored = _getString(_kOpenAiBaseUrl)?.trim();
    if (stored == null || stored.isEmpty) return null;
    return stored;
  }

  Future<void> setOpenAiBaseUrl(String? value) async {
    final trimmed = value?.trim() ?? '';
    if (trimmed.isEmpty) {
      await _remove(_kOpenAiBaseUrl);
    } else {
      await _setString(_kOpenAiBaseUrl, trimmed);
    }
    notifyListeners();
  }

  // ── ChatGPT Codex OAuth ───────────────────────────────────────────────────
  /// Lazily-built OAuth manager. The CLI-import callbacks persist their flag
  /// in the regular settings file; tokens themselves live in the secure
  /// credential store.
  CodexOAuthManager get codexOAuth => _codexOAuth ??= CodexOAuthManager(
    credentialStore: _credentialStore,
    isCliImportDisabled: () => _getBool(_kCodexCliImportDisabled),
    setCliImportDisabled: (disabled) async {
      if (disabled) {
        await _setBool(_kCodexCliImportDisabled, true);
      } else {
        await _remove(_kCodexCliImportDisabled);
      }
    },
  );

  /// Whether stored (or imported) Codex credentials are present. Refreshed at
  /// startup and after sign-in/sign-out via [refreshCodexAuthState].
  bool get hasCodexAuth => _hasCodexAuth;

  /// Re-reads the credential store so [hasCodexAuth] reflects the latest
  /// sign-in state (including a transparent Codex CLI import).
  Future<void> refreshCodexAuthState() async {
    _hasCodexAuth = await codexOAuth.loadCredentials() != null;
    notifyListeners();
  }

  /// Signs out of ChatGPT Codex: deletes the stored credentials and blocks
  /// future CLI imports so the sign-out survives restarts.
  Future<void> signOutCodex() async {
    await codexOAuth.signOut();
    _hasCodexAuth = false;
    notifyListeners();
  }

  // ── xAI Grok OAuth ─────────────────────────────────────────────────────
  /// Lazily-built OAuth manager. Tokens live in the secure credential store
  /// under `xai_oauth_credentials`.
  XAiOAuthManager get xaiOAuth =>
      _xaiOAuth ??= XAiOAuthManager(credentialStore: _credentialStore);

  /// Whether stored xAI credentials are present. Refreshed at startup and
  /// after sign-in/sign-out via [refreshGrokAuthState].
  bool get hasGrokAuth => _hasGrokAuth;

  /// Re-reads the credential store so [hasGrokAuth] reflects the latest
  /// sign-in state.
  Future<void> refreshGrokAuthState() async {
    _hasGrokAuth = await xaiOAuth.loadCredentials() != null;
    notifyListeners();
  }

  /// Signs out of xAI Grok: deletes the stored credentials.
  Future<void> signOutGrok() async {
    await xaiOAuth.signOut();
    _hasGrokAuth = false;
    notifyListeners();
  }

  /// Whether the currently-selected cloud provider has the credentials
  /// needed to run a cloud transcription or refinement pass right now.
  /// Mirrors the readiness checks used in onboarding and troubleshooting.
  bool get hasCloudCredentials => hasCredentialsForProvider(cloudProvider);

  bool hasCredentialsForProvider(CloudProvider provider) {
    switch (provider) {
      case CloudProvider.geminiApiKey:
        return hasGeminiApiKey;
      case CloudProvider.vertexAi:
        return vertexProjectId != null;
      case CloudProvider.openaiApiKey:
        return hasOpenAiApiKey;
      case CloudProvider.codexOAuth:
        return hasCodexAuth;
      case CloudProvider.grokOAuth:
        return hasGrokAuth;
    }
  }

  String get whisperModelId => _getString(_kWhisperModelId) ?? 'ggml-tiny.bin';

  Future<void> setWhisperModelId(String value) async {
    await _setString(_kWhisperModelId, value);
    notifyListeners();
  }

  // ── Spoken language & vocabulary ──────────────────────────────────────────
  /// ISO 639-1 code of the language being spoken, or `'auto'` to detect.
  /// Shared by Whisper and the cloud transcription step.
  String get spokenLanguage => _getString(_kSpokenLanguage) ?? 'auto';

  Future<void> setSpokenLanguage(String value) async {
    await _setString(_kSpokenLanguage, value);
    notifyListeners();
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
    notifyListeners();
  }

  /// Smallest auto-stop duration the duration-limit dialog accepts.
  static const int minDurationLimitSeconds = 5;

  /// Largest auto-stop duration the duration-limit dialog accepts.
  static const int maxDurationLimitSeconds = 3600;

  /// Clamps a recording auto-stop value to `[5, 3600]` — the same range the
  /// duration-limit dialog (`general_settings_page.dart`) already enforces.
  ///
  /// Mirrors the defensive clamp already applied to
  /// [clipboardHistoryMaxItems]. Guarding at this getter/setter means a
  /// corrupt, hand-edited, or pre-clamp persisted value can never arm a
  /// `Duration(seconds: 0)` timer (which would stop a recording the instant it
  /// started once auto-stop is enabled) or allow an absurd multi-day cap.
  static int clampDurationLimit(int seconds) {
    if (seconds < minDurationLimitSeconds) return minDurationLimitSeconds;
    if (seconds > maxDurationLimitSeconds) return maxDurationLimitSeconds;
    return seconds;
  }

  int get durationLimit =>
      clampDurationLimit(_getInt(_kDurationLimit, defaultValue: 300));

  Future<void> setDurationLimit(int seconds) async {
    await _setInt(_kDurationLimit, clampDurationLimit(seconds));
    notifyListeners();
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

  // ── Update Notifications ────────────────────────────────────────────────
  /// Milliseconds-since-epoch of the last time an update check was performed,
  /// or `0` if a check has never run.
  int get _lastUpdateCheckAt => _getInt(_kLastUpdateCheckAt, defaultValue: 0);

  /// True when >= 24h have elapsed since the last check (or on first launch).
  /// Used to rate-limit the background check so we hit GitHub at most once
  /// per day per user.
  bool get shouldCheckForUpdates {
    final last = _lastUpdateCheckAt;
    if (last == 0) return true;
    const oneDayMs = 24 * 60 * 60 * 1000;
    return DateTime.now().millisecondsSinceEpoch - last >= oneDayMs;
  }

  /// Records that an update check just happened so the next one is throttled.
  /// Does not notify: a timestamp change alone has no UI impact.
  Future<void> recordUpdateCheck() async {
    await _setInt(_kLastUpdateCheckAt, DateTime.now().millisecondsSinceEpoch);
  }

  /// The most recently discovered newer release, or `null` if none is known.
  /// Hydrated directly from the persisted JSON so it survives restarts.
  UpdateInfo? get availableUpdate {
    final version = _getString(_kAvailableUpdateVersion);
    final url = _getString(_kAvailableUpdateUrl);
    if (version == null || url == null || version.isEmpty || url.isEmpty) {
      return null;
    }
    return UpdateInfo(
      latestVersion: version,
      releaseUrl: url,
      releaseNotes: _getString(_kAvailableUpdateNotes) ?? '',
      publishedAt: '',
    );
  }

  /// Caches a discovered newer release and notifies any listening UI so the
  /// sidebar badge and About row rebuild immediately.
  Future<void> setAvailableUpdate(UpdateInfo info) async {
    _data[_kAvailableUpdateVersion] = info.latestVersion;
    _data[_kAvailableUpdateUrl] = info.releaseUrl;
    _data[_kAvailableUpdateNotes] = info.releaseNotes;
    await _save();
    notifyListeners();
  }

  /// Clears any cached release and notifies listeners. Called when a check
  /// confirms the running build is already the latest.
  Future<void> clearAvailableUpdate() async {
    _data.remove(_kAvailableUpdateVersion);
    _data.remove(_kAvailableUpdateUrl);
    _data.remove(_kAvailableUpdateNotes);
    await _save();
    notifyListeners();
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
