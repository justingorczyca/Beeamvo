import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:flutter/services.dart';

import 'config.dart';
import 'services/cloud_transcription_service.dart';
import 'services/cloud_transcription_client.dart';
import 'services/hotkey_service.dart';
import 'services/recording_service.dart';
import 'services/keyboard_service.dart';
import 'services/transcription_result_guard.dart';
import 'services/window_helper.dart';
import 'services/tray_service.dart';
import 'services/settings_service.dart';
import 'services/usage_stats_service.dart';
import 'services/whisper_service.dart';
import 'models/system_prompt.dart';
import 'models/prompt_settings.dart';
import 'models/hotkey_config.dart';
import 'widgets/frosted_orb.dart';
import 'widgets/onboarding/onboarding_wizard.dart';
import 'widgets/settings/settings_window.dart';
import 'widgets/mode_selection_popup.dart';
import 'widgets/mode_cloud_confirm_popup.dart';
import 'providers/settings_provider.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppConfig.initialize();
  await windowManager.ensureInitialized();

  const windowOptions = WindowOptions(
    size: Size(150, 150),
    center: false,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setBackgroundColor(Colors.transparent);

    // macOS specific: ensure transparency is set
    if (Platform.isMacOS) {
      await windowManager.setHasShadow(false);
    }

    final (screenWidth, screenHeight) = await WindowHelper.getScreenSizeAsync();
    final xPos = (screenWidth / 2) - 75;
    final yPos = screenHeight - 120.0;

    await windowManager.setPosition(Offset(xPos, yPos));
    await windowManager.setSkipTaskbar(true);

    // Initial hide: on macOS, move off-screen first (method channel not ready yet)
    // The proper native hide will be called after initialization in _BeeamvoHomeState._initialize()
    if (Platform.isMacOS) {
      await windowManager.setPosition(const Offset(-10000, -10000));
    } else {
      await WindowHelper.hide();
    }
  });

  runApp(BeeamvoApp(settingsService: SettingsService()));
}

/// Root widget — owns the [SettingsService] and rebuilds the [MaterialApp]
/// whenever the persisted theme mode changes.
///
/// The service is eagerly awaited here (before [runApp]) so that the first
/// frame is rendered with the persisted [ThemeMode] (no flash of light mode
/// if the user previously chose dark). All other initialization (cloud, tray,
/// hotkeys, onboarding) is deferred to [BeeamvoHome] just like before.
class BeeamvoApp extends StatefulWidget {
  final SettingsService settingsService;

  const BeeamvoApp({super.key, required this.settingsService});

  @override
  State<BeeamvoApp> createState() => _BeeamvoAppState();
}

class _BeeamvoAppState extends State<BeeamvoApp> {
  late Future<void> _settingsInitialized;

  @override
  void initState() {
    super.initState();
    _settingsInitialized = widget.settingsService.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.settingsService,
      builder: (context, _) {
        return MaterialApp(
          title: AppConfig.appName,
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: widget.settingsService.themeModeEnum,
          home: BeeamvoHome(
            settingsService: widget.settingsService,
            settingsInitialized: _settingsInitialized,
          ),
        );
      },
    );
  }
}

class BeeamvoHome extends StatefulWidget {
  /// Shared with [BeeamvoApp] so initialization happens exactly once and the
  /// theme mode is available from the first frame (after the future returned
  /// by [SettingsService.initialize] completes).
  final SettingsService settingsService;

  /// Future that completes once [SettingsService.initialize] has finished.
  /// [BeeamvoHome] awaits this before reading any settings; until then the
  /// orb renders in its idle state.
  final Future<void> settingsInitialized;

  const BeeamvoHome({
    super.key,
    required this.settingsService,
    required this.settingsInitialized,
  });

  @override
  State<BeeamvoHome> createState() => _BeeamvoHomeState();
}

enum RecordingState {
  idle,
  recording,
  processing,
  success,
  error,
  settings,
  onboarding,
  modeSelection,
  modeCloudConfirm,
}

class _BeeamvoHomeState extends State<BeeamvoHome>
    with WindowListener, TickerProviderStateMixin {
  final CloudTranscriptionService _cloudService = CloudTranscriptionService();
  final WhisperService _whisperService = WhisperService();
  final HotkeyService _hotkeyService = HotkeyService();
  final RecordingService _recordingService = RecordingService();
  final TrayService _trayService = TrayService();
  final UsageStatsService _usageStatsService = UsageStatsService();
  late SettingsService _settingsService;
  late SettingsProvider _settingsProvider;

  RecordingState _state = RecordingState.idle;
  bool _isLockActive = false;
  bool _isHotkeyHeld = false; // Track physical key state for hold mode

  late AnimationController _pulseController;
  late AnimationController _rotationController;
  Timer? _holdTimer;
  Timer? _durationLimitTimer;
  Timer? _clipboardMonitorTimer;
  bool _isClipboardPollInProgress = false;
  String? _lastObservedClipboardText;
  String? _lastErrorMessage;
  String?
  _temporaryPromptId; // non-null overrides saved prompt for mode-selection session
  int? _modeSelectionIndex; // keyboard highlight index in mode popup
  // Inline cloud-switch confirm (Ctrl+M flow): the prompt awaiting a cloud
  // model and the highlighted option (0 = local two-pass, 1 = cloud).
  SystemPrompt? _modeCloudConfirmPrompt;
  int _modeCloudConfirmIndex = 0;
  bool _promptModelOverrideActive = false;
  bool _promptProviderOverrideActive = false;
  final Stopwatch _recordingStopwatch = Stopwatch();
  Duration? _retryRecordingDuration;
  bool _returnToRetryAfterSettings = false;
  bool _useCurrentSettingsForRetry = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _rotationController = AnimationController(
      duration: const Duration(milliseconds: 3000),
      vsync: this,
    );

    _settingsService = widget.settingsService;
    _settingsProvider = SettingsProvider(settingsService: _settingsService);

    // Listen for transcription backend changes from ANY source (the
    // AI Models page, the prompts-page rephraser popover, etc.) so
    // Whisper is always initialized or torn down correctly. Without
    // this, the popover's "Switch to cloud" button would flip the
    // persisted setting but leave Whisper loaded in memory.
    _settingsService.addListener(_onSettingsChanged);

    _initialize();
  }

  /// Tracks the last backend we saw so we only react to actual changes.
  TranscriptionBackend? _lastSeenBackend;

  /// SettingsService change listener. Routes backend changes through
  /// [_onBackendChanged] so Whisper is correctly initialized or
  /// disposed regardless of WHERE the change originated.
  void _onSettingsChanged() {
    final current = _settingsService.transcriptionBackend;
    if (_lastSeenBackend != null && _lastSeenBackend != current) {
      _onBackendChanged(current);
    }
    _lastSeenBackend = current;
  }

  @override
  void dispose() {
    _settingsService.removeListener(_onSettingsChanged);
    _pulseController.dispose();
    _rotationController.dispose();
    _holdTimer?.cancel();
    _durationLimitTimer?.cancel();
    _clipboardMonitorTimer?.cancel();
    windowManager.removeListener(this);
    _hotkeyService.dispose();
    _recordingService.dispose();
    _trayService.dispose();
    _whisperService.dispose();
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      debugPrint('Starting initialization...');

      // SettingsService.initialize() was already kicked off in
      // BeeamvoApp.initState so the persisted themeMode is applied from the
      // very first frame. Wait for it to finish here so the rest of init can
      // read every stored setting safely.
      await widget.settingsInitialized;
      debugPrint('Settings initialized');

      // Set the preferred audio input device from settings
      final selectedDeviceId = _settingsService.selectedAudioDeviceId;
      _recordingService.setPreferredDevice(selectedDeviceId);
      debugPrint('Audio device set: ${selectedDeviceId ?? "System Default"}');

      // ── First-run onboarding ─────────────────────────────────────────
      // Show onboarding only on truly first run (no saved config AND
      // no existing API key from a previous installation).
      if (!_settingsService.isOnboardingComplete &&
          !_settingsService.hasGeminiApiKey) {
        debugPrint('First run detected — showing onboarding wizard');
        await _showOnboarding();
        // After onboarding completes the rest of init continues below.
      } else if (!_settingsService.isOnboardingComplete) {
        // Existing user with credentials — silently mark onboarding as complete
        await _settingsService.setOnboardingComplete();
      }

      _cloudService.attachSettings(_settingsService);
      await _cloudService.initialize();
      _cloudService.setModelById(_settingsService.selectedModelId);
      debugPrint(
        'Cloud services initialized with model: ${_cloudService.currentModel.name}',
      );

      // Initialize usage stats tracking
      await _usageStatsService.initialize();
      debugPrint('Usage stats initialized');

      // Initialize offline backend if selected
      if (_settingsService.transcriptionBackend ==
          TranscriptionBackend.whisper) {
        await _initWhisper();
      }
      _lastSeenBackend = _settingsService.transcriptionBackend;

      // Initialize tray with error handling
      try {
        await _trayService.initialize(
          settingsService: _settingsService,
          onShowSettings: _showSettings,
          onExit: () async {
            _clipboardMonitorTimer?.cancel();
            _holdTimer?.cancel();
            _durationLimitTimer?.cancel();
            _recordingService.dispose();
            _whisperService.dispose();
            _hotkeyService.dispose();
            windowManager.destroy();
          },
          onPromptChanged: () {
            debugPrint(
              'Prompt changed to: ${_settingsService.selectedPromptId}',
            );
          },
          onModelChanged: () {
            _cloudService.setModelById(_settingsService.selectedModelId);
            debugPrint(
              'Model changed via tray to: ${_cloudService.currentModel.name}',
            );
          },
        );
        debugPrint('Tray initialized');
      } catch (e) {
        debugPrint('Tray initialization failed (non-critical): $e');
      }

      // Register global hotkey from settings
      final hotkeyConfig = _settingsService.hotkey;
      await _registerMainHotkey(hotkeyConfig);
      debugPrint('Hotkey registered: ${hotkeyConfig.displayString}');

      final clipboardHotkeyConfig = _settingsService.clipboardPopupHotkey;
      await _registerClipboardPopupHotkey(clipboardHotkeyConfig);
      debugPrint(
        'Clipboard popup hotkey registered: ${clipboardHotkeyConfig.displayString}',
      );

      final modeSelectionHotkeyConfig = _settingsService.modeSelectionHotkey;
      await _registerModeSelectionHotkey(modeSelectionHotkeyConfig);
      debugPrint(
        'Mode selection hotkey registered: ${modeSelectionHotkeyConfig.displayString}',
      );

      _syncClipboardMonitor();

      await Future.delayed(const Duration(milliseconds: 200));
      await WindowHelper.hide();
      debugPrint('Window hidden');
    } catch (e, stackTrace) {
      debugPrint('Initialization error: $e');
      if (kDebugMode) debugPrint('Stack trace: $stackTrace');
      setState(() => _state = RecordingState.error);
    }
  }

  bool get _clipboardMonitorEnabled =>
      _settingsService.clipboardWatcherEnabled &&
      _settingsService.clipboardHistoryEnabled;

  void _syncClipboardMonitor() {
    if (_clipboardMonitorEnabled) {
      _startClipboardMonitor();
    } else {
      _clipboardMonitorTimer?.cancel();
      _clipboardMonitorTimer = null;
      _lastObservedClipboardText = null;
    }
  }

  void _startClipboardMonitor() {
    _clipboardMonitorTimer?.cancel();
    if (!_clipboardMonitorEnabled) return;

    _clipboardMonitorTimer = Timer.periodic(
      const Duration(milliseconds: 1200),
      (_) => _pollClipboardText(),
    );

    _pollClipboardText();
  }

  Future<void> _pollClipboardText() async {
    if (_isClipboardPollInProgress) return;

    _isClipboardPollInProgress = true;
    try {
      if (!_settingsService.clipboardWatcherEnabled ||
          !_settingsService.clipboardHistoryEnabled) {
        _lastObservedClipboardText = null;
        return;
      }

      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();

      if (text == null || text.isEmpty) {
        _lastObservedClipboardText = null;
        return;
      }

      if (text == _lastObservedClipboardText) {
        return;
      }

      _lastObservedClipboardText = text;
      await _settingsService.addClipboardEntry(text);
    } catch (_) {
      // Best-effort watcher: ignore transient clipboard read failures.
    } finally {
      _isClipboardPollInProgress = false;
    }
  }

  /// Called when the hotkey is pressed down
  void _onHotkeyPressed() {
    final mode = _settingsService.recordingMode;

    // Always track that key is being held physically
    _isHotkeyHeld = true;

    if (mode == RecordingMode.hold) {
      // For Hold Mode: Reset the watchdog timer on EVERY key event (including repeats).
      // Two-tier duration: 600ms before recording starts (survives the initial OS repeat delay,
      // typically ~500ms on Windows), then 300ms once repeats are flowing (repeat interval is
      // much shorter at ~30-500ms). This keeps the fallback snappy after the first repeat.
      final isRepeat = _state == RecordingState.recording;
      final watchdogMs = isRepeat ? 300 : 600;
      _holdTimer?.cancel();
      _holdTimer = Timer(Duration(milliseconds: watchdogMs), () {
        _isHotkeyHeld =
            false; // Timer expired = key released (fallback for Windows)
        if (_state == RecordingState.recording && !_isLockActive) {
          _stopRecordingAndProcess();
        }
      });
    }

    // Safety check: if lock is active (e.g. initializing), ignore STARTING recording
    if (_isLockActive) return;

    if (mode == RecordingMode.toggle) {
      // Toggle mode:
      // - If idle/success/settings: Start recording
      // - If recording: Stop and send
      if (_state == RecordingState.recording) {
        _stopRecordingAndProcess();
      } else if (_canStartRecording()) {
        _startRecording();
      }
    } else {
      // Hold mode:
      // - If idle: Start recording
      if (_canStartRecording()) {
        _startRecording();
      }
    }
  }

  /// Called when the hotkey is released
  void _onHotkeyReleased() {
    final mode = _settingsService.recordingMode;

    // Track release
    _isHotkeyHeld = false;
    _holdTimer?.cancel();

    // Hold mode:
    // - Only stop if we are currently recording and not locked
    // - If locked, the post-start check in _startRecording will handle it
    if (mode == RecordingMode.hold &&
        _state == RecordingState.recording &&
        !_isLockActive) {
      _stopRecordingAndProcess();
    }
  }

  /// Helper to check if we can validly start recording
  bool _canStartRecording() {
    return _state == RecordingState.idle ||
        _state == RecordingState.success ||
        _state == RecordingState.error ||
        _state == RecordingState.settings;
  }

  /// Register the main global hotkey with the given configuration
  Future<void> _registerMainHotkey(HotkeyConfig config) async {
    await _hotkeyService.registerHotkey(
      id: 'main',
      key: config.key,
      modifiers: config.modifiers.toList(),
      onPressed: _onHotkeyPressed,
      onReleased: _onHotkeyReleased,
    );
  }

  Future<void> _registerClipboardPopupHotkey(HotkeyConfig config) async {
    await _hotkeyService.registerHotkey(
      id: 'clipboard_popup',
      key: config.key,
      modifiers: config.modifiers.toList(),
      onPressed: _openClipboardHistoryFromHotkey,
    );
  }

  Future<void> _registerModeSelectionHotkey(HotkeyConfig config) async {
    await _hotkeyService.registerHotkey(
      id: 'mode_selection',
      key: config.key,
      modifiers: config.modifiers.toList(),
      onPressed: _openModeSelection,
    );
  }

  /// Called when the hotkey is changed in settings
  Future<void> _onHotkeyChanged(HotkeyConfig newConfig) async {
    await _registerMainHotkey(newConfig);
    debugPrint('Hotkey updated to: ${newConfig.displayString}');
  }

  Future<void> _onClipboardHotkeyChanged(HotkeyConfig newConfig) async {
    await _registerClipboardPopupHotkey(newConfig);
    debugPrint('Clipboard popup hotkey updated to: ${newConfig.displayString}');
  }

  Future<void> _onModeSelectionHotkeyChanged(HotkeyConfig newConfig) async {
    await _registerModeSelectionHotkey(newConfig);
    debugPrint('Mode selection hotkey updated to: ${newConfig.displayString}');
  }

  /// Called when the recording mode is changed in settings
  void _onRecordingModeChanged(RecordingMode mode) {
    debugPrint('Recording mode changed to: ${mode.displayName}');
  }

  /// Called when the transcription backend is changed in settings.
  Future<void> _onBackendChanged(TranscriptionBackend backend) async {
    debugPrint('Transcription backend changed to: ${backend.name}');
    if (backend == TranscriptionBackend.whisper) {
      // Always call init to ensure the selected model is loaded.
      await _initWhisper();
    } else if (_whisperService.isInitialized) {
      // Free offline model resources when leaving whisper backend.
      await _whisperService.dispose();
    }
  }

  Future<void> _verifyCloudProvider(CloudProvider provider) async {
    await _cloudService.verifyProvider(provider);
  }

  /// Called when an offline model is downloaded or selected.
  Future<void> _onModelDownloaded() async {
    debugPrint('Model downloaded, reinitializing if needed...');
    // Reinitialize whisper when backend is active to apply model changes immediately.
    if (_settingsService.transcriptionBackend == TranscriptionBackend.whisper) {
      await _initWhisper();
    }
  }

  /// Load the whisper.cpp ggml model based on the selected setting.
  Future<void> _initWhisper({String? modelId}) async {
    final effectiveModelId = modelId ?? _settingsService.whisperModelId;
    final modelPath = WhisperService.getModelPath(effectiveModelId);
    debugPrint('Whisper: attempting to load model "$effectiveModelId"');
    if (!WhisperService.modelExistsAtPath(modelPath)) {
      debugPrint('Whisper: model file not found for "$effectiveModelId"');
      return;
    }
    try {
      final ok = await _whisperService.initialize(
        modelPath: modelPath,
        threads: 0,
      );
      debugPrint(
        ok
            ? 'Whisper: model "$effectiveModelId" loaded successfully'
            : 'Whisper: init returned false for "$effectiveModelId" (error: ${_whisperService.modelLoadError})',
      );
    } catch (e) {
      debugPrint('Whisper: initialization failed: ${e.runtimeType}');
    }
  }

  bool _isEnglishOnlyWhisperModel(String modelId) {
    return modelId.endsWith('.en.bin');
  }

  void _showSettings() async {
    // Resize to settings window size and center
    await windowManager.setMinimumSize(const Size(820, 560));
    await windowManager.setSize(const Size(980, 640));
    await windowManager.center();

    if (mounted) {
      setState(() => _state = RecordingState.settings);
    }

    WindowHelper.show();
  }

  void _showRetrySettings() {
    _returnToRetryAfterSettings = true;
    _useCurrentSettingsForRetry = true;
    _settingsProvider.selectCategory(SettingsCategory.aiModels);
    _showSettings();
  }

  Future<void> _showOnboarding() async {
    await windowManager.setMinimumSize(const Size(740, 560));
    await windowManager.setSize(const Size(740, 560));
    await windowManager.center();
    await WindowHelper.show();

    if (mounted) {
      setState(() => _state = RecordingState.onboarding);
    }

    // Wait until onboarding completes (state changes away from onboarding)
    // We use a completer-like approach: poll _state.
    while (mounted && _state == RecordingState.onboarding) {
      await Future.delayed(const Duration(milliseconds: 100));
    }

    // Reset window to orb size
    await WindowHelper.hide();
    await windowManager.setMinimumSize(const Size(150, 150));
    await windowManager.setSize(const Size(150, 150));
    debugPrint('Onboarding completed');
  }

  void _onOnboardingComplete() {
    if (mounted) {
      setState(() => _state = RecordingState.idle);
    }
  }

  void _openClipboardHistoryFromHotkey() {
    _showSettings();
    _settingsProvider.selectCategory(SettingsCategory.clipboard);
  }

  // ── Mode Selection (Ctrl+Shift+M) ────────────────────────────────────────

  void _openModeSelection() async {
    if (_state != RecordingState.idle &&
        _state != RecordingState.success &&
        _state != RecordingState.error) {
      return;
    }

    _modeSelectionIndex = 0;

    const popupWidth = 320.0;
    const popupHeight = 360.0;
    await windowManager.setMinimumSize(const Size(popupWidth, popupHeight));
    await windowManager.setSize(const Size(popupWidth, popupHeight));
    await WindowHelper.positionAtActiveMonitorBottomCenter(
      popupWidth.toInt(),
      popupHeight.toInt(),
    );

    setState(() => _state = RecordingState.modeSelection);
    await WindowHelper.showWithoutFocus();

    // Register keyboard navigation hotkeys
    await _hotkeyService.registerHotkey(
      id: 'mode_cancel',
      key: LogicalKeyboardKey.escape,
      onPressed: _cancelModeSelection,
    );
    await _hotkeyService.registerHotkey(
      id: 'mode_up',
      key: LogicalKeyboardKey.arrowUp,
      onPressed: () {
        setState(() {
          _modeSelectionIndex = (_modeSelectionIndex ?? 0) > 0
              ? _modeSelectionIndex! - 1
              : 0;
        });
      },
    );
    await _hotkeyService.registerHotkey(
      id: 'mode_down',
      key: LogicalKeyboardKey.arrowDown,
      onPressed: () {
        final count =
            SystemPrompt.availablePrompts.length +
            _settingsService.customPrompts.length;
        setState(() {
          _modeSelectionIndex = ((_modeSelectionIndex ?? 0) + 1).clamp(
            0,
            count - 1,
          );
        });
      },
    );
    await _hotkeyService.registerHotkey(
      id: 'mode_enter',
      key: LogicalKeyboardKey.enter,
      onPressed: () => _selectModeByIndex(_modeSelectionIndex ?? 0),
    );
  }

  Future<void> _unregisterModeSelectionHotkeys() async {
    await _hotkeyService.unregisterHotkey('mode_cancel');
    await _hotkeyService.unregisterHotkey('mode_up');
    await _hotkeyService.unregisterHotkey('mode_down');
    await _hotkeyService.unregisterHotkey('mode_enter');
  }

  void _cancelModeSelection() async {
    await _unregisterModeSelectionHotkeys();
    _temporaryPromptId = null;
    _modeSelectionIndex = null;

    await WindowHelper.hide();
    await windowManager.setMinimumSize(const Size(150, 150));
    await windowManager.setSize(const Size(150, 150));

    if (mounted) setState(() => _state = RecordingState.idle);
  }

  void _selectModeByIndex(int index) async {
    await _unregisterModeSelectionHotkeys();

    final allPrompts = [
      ...SystemPrompt.availablePrompts,
      ..._settingsService.customPrompts,
    ];
    if (index < 0 || index >= allPrompts.length) {
      _cancelModeSelection();
      return;
    }

    final prompt = allPrompts[index];

    // Non-default prompts only take effect with a cloud model in the
    // pipeline. On pure Whisper (no two-pass, no per-prompt Cloud override)
    // let the user choose how to enable it before recording: keep local
    // transcription + cloud refinement, or switch fully to cloud. This is
    // rendered INLINE inside the existing 320x360 popup (no resize, no modal)
    // so it reads as a natural drill-in of the mode list.
    if (_settingsService.isPromptInactiveOnLocalBackend(prompt.id)) {
      if (!mounted) return;
      _enterModeCloudConfirm(prompt);
      return;
    }

    _temporaryPromptId = prompt.id;
    _modeSelectionIndex = null;

    await windowManager.setMinimumSize(const Size(150, 150));
    await windowManager.setSize(const Size(150, 150));

    _startRecording();
  }

  // ── Inline cloud-switch confirm (Ctrl+M flow) ───────────────────────────
  //
  // Renders [ModeCloudConfirmPopup] inside the unfocused 320x360 popup. The
  // window keeps its size, and — because it has no OS focus — navigation is
  // driven by the same kind of global hotkeys the mode list uses.

  /// Drill into the inline cloud-switch confirm for [prompt]. The
  /// mode-selection navigation hotkeys are already unregistered by the caller,
  /// so there is no collision on the arrow/Enter/Esc keys.
  void _enterModeCloudConfirm(SystemPrompt prompt) async {
    _modeCloudConfirmPrompt = prompt;
    _modeCloudConfirmIndex = 0;
    // With no provider configured there is nothing to switch to yet — Enter
    // routes to Transcription settings instead of confirming an option.
    final needsCloudSetup = !_settingsService.hasCloudCredentials;

    setState(() => _state = RecordingState.modeCloudConfirm);

    await _hotkeyService.registerHotkey(
      id: 'mode_cloud_cancel',
      key: LogicalKeyboardKey.escape,
      onPressed: _cancelModeCloudConfirm,
    );
    if (needsCloudSetup) {
      await _hotkeyService.registerHotkey(
        id: 'mode_cloud_enter',
        key: LogicalKeyboardKey.enter,
        onPressed: _openSettingsFromCloudConfirm,
      );
      return;
    }
    await _hotkeyService.registerHotkey(
      id: 'mode_cloud_up',
      key: LogicalKeyboardKey.arrowUp,
      onPressed: () {
        setState(() {
          _modeCloudConfirmIndex = _modeCloudConfirmIndex > 0
              ? _modeCloudConfirmIndex - 1
              : 0;
        });
      },
    );
    await _hotkeyService.registerHotkey(
      id: 'mode_cloud_down',
      key: LogicalKeyboardKey.arrowDown,
      onPressed: () {
        setState(() {
          // Two options: 0 = local two-pass, 1 = cloud.
          _modeCloudConfirmIndex = (_modeCloudConfirmIndex + 1).clamp(0, 1);
        });
      },
    );
    await _hotkeyService.registerHotkey(
      id: 'mode_cloud_enter',
      key: LogicalKeyboardKey.enter,
      onPressed: () => _confirmModeCloudConfirm(_modeCloudConfirmIndex),
    );
  }

  Future<void> _unregisterModeCloudConfirmHotkeys() async {
    await _hotkeyService.unregisterHotkey('mode_cloud_cancel');
    await _hotkeyService.unregisterHotkey('mode_cloud_up');
    await _hotkeyService.unregisterHotkey('mode_cloud_down');
    await _hotkeyService.unregisterHotkey('mode_cloud_enter');
  }

  /// Apply the chosen transcription mode (0 = local two-pass, 1 = cloud) and
  /// proceed to record with the pending prompt — mirroring what the settings
  /// modal does before it returns.
  void _confirmModeCloudConfirm(int optionIndex) async {
    await _unregisterModeCloudConfirmHotkeys();
    final prompt = _modeCloudConfirmPrompt;
    if (prompt == null) {
      _cancelModeSelection();
      return;
    }
    try {
      if (optionIndex == 0) {
        await _settingsService.enableLocalTwoPassRefinement();
      } else {
        await _settingsService.switchToCloudTranscription();
      }
    } catch (_) {
      // Leave the user on the mode list if the backend change failed.
      _modeCloudConfirmPrompt = null;
      _reopeningModeSelection();
      return;
    }

    _modeCloudConfirmPrompt = null;
    _temporaryPromptId = prompt.id;
    _modeSelectionIndex = null;

    await windowManager.setMinimumSize(const Size(150, 150));
    await windowManager.setSize(const Size(150, 150));

    _startRecording();
  }

  /// Esc / cancel from the inline confirm — return to the mode-selection list.
  void _cancelModeCloudConfirm() async {
    await _unregisterModeCloudConfirmHotkeys();
    _modeCloudConfirmPrompt = null;
    _reopeningModeSelection();
  }

  /// No cloud provider configured — send the user to Transcription settings.
  void _openSettingsFromCloudConfirm() async {
    await _unregisterModeCloudConfirmHotkeys();
    _modeCloudConfirmPrompt = null;
    _modeSelectionIndex = null;
    _settingsProvider.selectCategory(SettingsCategory.aiModels);
    _showSettings();
  }

  /// Re-open the mode selection popup after a cancelled inline cloud-confirm.
  /// Re-registers keyboard hotkeys and restores the popup state. The window
  /// already sits at the popup size (the inline confirm never resizes it).
  void _reopeningModeSelection() async {
    const popupWidth = 320.0;
    const popupHeight = 360.0;
    await windowManager.setMinimumSize(const Size(popupWidth, popupHeight));
    await windowManager.setSize(const Size(popupWidth, popupHeight));
    await WindowHelper.positionAtActiveMonitorBottomCenter(
      popupWidth.toInt(),
      popupHeight.toInt(),
    );
    setState(() {
      _state = RecordingState.modeSelection;
      _modeSelectionIndex = _modeSelectionIndex ?? 0;
    });

    // Re-register keyboard navigation hotkeys.
    await _hotkeyService.registerHotkey(
      id: 'mode_cancel',
      key: LogicalKeyboardKey.escape,
      onPressed: _cancelModeSelection,
    );
    await _hotkeyService.registerHotkey(
      id: 'mode_up',
      key: LogicalKeyboardKey.arrowUp,
      onPressed: () {
        setState(() {
          _modeSelectionIndex = (_modeSelectionIndex ?? 0) > 0
              ? _modeSelectionIndex! - 1
              : 0;
        });
      },
    );
    await _hotkeyService.registerHotkey(
      id: 'mode_down',
      key: LogicalKeyboardKey.arrowDown,
      onPressed: () {
        final count =
            SystemPrompt.availablePrompts.length +
            _settingsService.customPrompts.length;
        setState(() {
          _modeSelectionIndex = ((_modeSelectionIndex ?? 0) + 1).clamp(
            0,
            count - 1,
          );
        });
      },
    );
    await _hotkeyService.registerHotkey(
      id: 'mode_enter',
      key: LogicalKeyboardKey.enter,
      onPressed: () => _selectModeByIndex(_modeSelectionIndex ?? 0),
    );
  }

  void _onSettingsClose() async {
    await WindowHelper.hide();
    _syncClipboardMonitor();
    // Reset window size to orb size and constraints
    await windowManager.setMinimumSize(const Size(150, 150));
    await windowManager.setSize(const Size(150, 150));
    if (mounted) {
      final shouldReturnToRetry =
          _returnToRetryAfterSettings && await _currentRecordingFileExists();
      _returnToRetryAfterSettings = false;
      setState(
        () => _state = shouldReturnToRetry
            ? RecordingState.error
            : RecordingState.idle,
      );
    }
  }

  Future<void> _startRecording() async {
    if (_isLockActive ||
        _state == RecordingState.recording ||
        _state == RecordingState.processing) {
      return;
    }
    _isLockActive = true;
    await _clearRetryRecording();
    _useCurrentSettingsForRetry = false;
    _returnToRetryAfterSettings = false;

    if (_state == RecordingState.settings ||
        _state == RecordingState.modeSelection ||
        _state == RecordingState.modeCloudConfirm) {
      setState(() => _state = RecordingState.idle);
      // Wait a frame for the UI to switch to the orb before resizing the window down to 150x150
      await Future.delayed(const Duration(milliseconds: 50));
      // Reset minimum size that was set by _showSettings()/_openModeSelection()
      await windowManager.setMinimumSize(const Size(150, 150));
      await windowManager.setSize(const Size(150, 150));
    }

    // Yield to the event loop before calling Win32 FFI window positioning.
    // This prevents synchronous WM_WINDOWPOSCHANGED messages from crashing the
    // Flutter engine when triggered directly from a platform channel hotkey callback.
    await Future.delayed(Duration.zero);

    await WindowHelper.positionAtActiveMonitorBottomCenter(150, 150);

    try {
      final hasPermission = await _recordingService.hasPermission();
      if (!hasPermission) {
        setState(() => _state = RecordingState.error);
        _hideAfterDelay(2);
        return;
      }

      final started = await _recordingService.startRecording();
      if (started) {
        _recordingStopwatch
          ..reset()
          ..start();
        _pulseController.repeat(reverse: true);
        _rotationController.repeat();
        setState(() => _state = RecordingState.recording);

        // Set up duration limit timer if enabled
        if (_settingsService.durationLimitEnabled) {
          final limitSeconds = _settingsService.durationLimit;
          _durationLimitTimer = Timer(Duration(seconds: limitSeconds), () {
            if (_state == RecordingState.recording) {
              debugPrint(
                'Recording duration limit of $limitSeconds seconds reached',
              );
              _stopRecordingAndProcess();
            }
          });
          debugPrint('Duration limit timer set to $limitSeconds seconds');
        }

        await _hotkeyService.registerHotkey(
          id: 'cancel',
          key: LogicalKeyboardKey.escape,
          onPressed: _cancelRecording,
        );

        // Register Enter key to commit/finish recording
        await _hotkeyService.registerHotkey(
          id: 'commit',
          key: LogicalKeyboardKey.enter,
          onPressed: _stopRecordingAndProcess,
        );
      } else {
        _recordingStopwatch
          ..stop()
          ..reset();
        setState(() => _state = RecordingState.error);
        _hideAfterDelay(2);
      }
    } catch (e) {
      _recordingStopwatch
        ..stop()
        ..reset();
      setState(() => _state = RecordingState.error);
      _hideAfterDelay(2);
    } finally {
      _isLockActive = false;

      // Post-start integrity check for Hold Mode
      // If user released the key while we were initializing (locked), we missed the KeyUp action.
      // So we check now: if we are supposed to be holding but aren't, stop immediately.
      // Skip this check for mode-selection sessions — they always use toggle semantics.
      if (_state == RecordingState.recording &&
          _settingsService.recordingMode == RecordingMode.hold &&
          !_isHotkeyHeld &&
          _temporaryPromptId == null) {
        debugPrint(
          'Hold mode: Key released during start-up, stopping immediately.',
        );
        _stopRecordingAndProcess();
      }
    }
  }

  void _hideAfterDelay([int seconds = 2]) {
    Future.delayed(Duration(seconds: seconds), () async {
      if (mounted &&
          _state != RecordingState.recording &&
          _state != RecordingState.processing) {
        _pulseController.stop();
        _rotationController.stop();
        await WindowHelper.hide();
        if (mounted) setState(() => _state = RecordingState.idle);
      }
    });
  }

  Future<void> _stopRecordingAndProcess({bool retryExisting = false}) async {
    if (_isLockActive) return;
    if (retryExisting) {
      final recordingPath = _recordingService.currentRecordingPath;
      if (_state != RecordingState.error ||
          _retryRecordingDuration == null ||
          recordingPath == null ||
          !await File(recordingPath).exists()) {
        return;
      }
    } else if (_state != RecordingState.recording) {
      return;
    }
    _isLockActive = true;
    final recordingDuration = retryExisting
        ? _retryRecordingDuration!
        : _recordingStopwatch.elapsed;

    if (!retryExisting) {
      _recordingStopwatch
        ..stop()
        ..reset();
      _durationLimitTimer?.cancel();
    }
    _pulseController.repeat(reverse: true);
    _rotationController.repeat();
    setState(() {
      _lastErrorMessage = null;
      _state = RecordingState.processing;
    });

    var keepSessionForRetry = false;
    var currentAttemptIsRetryable = false;

    try {
      // ── Resolve effective settings (prompt override > global default) ─────
      final effectivePromptId = (_useCurrentSettingsForRetry && retryExisting)
          ? _settingsService.selectedPromptId
          : (_temporaryPromptId ?? _settingsService.selectedPromptId);
      final selectedPrompt = SystemPrompt.getById(
        effectivePromptId,
        customPrompts: _settingsService.customPrompts,
      );
      final overrides =
          _settingsService.getPromptOverrides(effectivePromptId) ??
          const PromptSettings();

      final effectiveBackend = overrides.transcriptionBackend != null
          ? TranscriptionBackendExtension.fromValue(
              overrides.transcriptionBackend,
            )
          : _settingsService.transcriptionBackend;
      final isOffline = effectiveBackend == TranscriptionBackend.whisper;

      final effectiveRephraseLevel = overrides.rephraseLevel != null
          ? overrides.rephraseLevel!
          : _settingsService.rephraseLevel;

      final effectiveWhisperModelId =
          overrides.whisperModelId ?? _settingsService.whisperModelId;
      final effectiveWhisperLanguage =
          overrides.whisperLanguage ?? _settingsService.whisperLanguage;
      final effectiveTwoPassEnabled =
          overrides.twoPassTranscriptionEnabled ??
          _settingsService.twoPassTranscriptionEnabled;
      final effectiveTranscriptionModelId =
          overrides.twoPassTranscriptionModelId ??
          overrides.modelId ??
          _settingsService.twoPassTranscriptionModelId;
      final effectiveRefinementModelId =
          overrides.twoPassRefinementModelId ??
          overrides.modelId ??
          _settingsService.twoPassRefinementModelId;
      final cloudInPipeline = !isOffline || effectiveTwoPassEnabled;

      // ── Per-prompt model & provider override ─────────────────────────────
      _promptModelOverrideActive = false;
      _promptProviderOverrideActive = false;
      if (overrides.modelId != null && !isOffline) {
        _promptModelOverrideActive = true;
        _cloudService.setModelById(overrides.modelId!);
        debugPrint(
          'Per-prompt model override: using ${_cloudService.currentModel.name}',
        );
      }
      if (overrides.cloudProvider != null && cloudInPipeline) {
        _promptProviderOverrideActive = true;
        final provider = CloudProviderExtension.fromValue(
          overrides.cloudProvider,
        );
        _cloudService.setProviderOverride(provider);
        debugPrint('Per-prompt provider override: $provider');
      }

      final backend = effectiveBackend;

      // Stop recording — stream path for offline, file path for cloud.
      Uint8List? pcmBytes;
      String? audioPath;
      if (retryExisting) {
        audioPath = _recordingService.currentRecordingPath;
      } else if (isOffline && _recordingService.isStreamRecording) {
        pcmBytes = await _recordingService.stopStreamAndGetPcm();
      } else {
        audioPath = await _recordingService.stopRecording();
      }
      currentAttemptIsRetryable = !isOffline && audioPath != null;

      await _hotkeyService.unregisterHotkey('cancel');
      await _hotkeyService.unregisterHotkey('commit');

      TranscriptionResultGuard.ensureRecordingLongEnough(recordingDuration);

      // For cloud paths, read audio bytes from the file.
      Uint8List? audioBytes;
      if (!isOffline) {
        if (audioPath == null) throw Exception('Recorder error');
        audioBytes = await _recordingService.getAudioBytes();
        if (audioBytes == null || audioBytes.isEmpty) {
          throw CloudTranscriptionException(
            TranscriptionResultGuard.noTranscriptMessage,
          );
        }
      } else if (pcmBytes == null || pcmBytes.isEmpty) {
        // Stream fell back to file.
        if (audioPath == null) throw Exception('Recorder error');
        audioBytes = await _recordingService.getAudioBytes();
        if (audioBytes == null || audioBytes.isEmpty) {
          throw CloudTranscriptionException(
            TranscriptionResultGuard.noTranscriptMessage,
          );
        }
      }

      // Compose the final instruction: base prompt + optional rephraser addon
      final rephraserFragment = effectiveRephraseLevel.promptFragment;
      final effectiveInstruction = rephraserFragment != null
          ? '${selectedPrompt.instruction}$rephraserFragment'
          : selectedPrompt.instruction;

      String improvedText;
      if (backend == TranscriptionBackend.whisper) {
        // ── Offline via whisper.cpp (tiny model) ─────────────────────────
        await _initWhisper(modelId: effectiveWhisperModelId);
        if (!_whisperService.isInitialized) {
          throw Exception(
            'Whisper model not loaded. Download or select a Whisper model in '
            'Settings → AI Models and keep Offline (Whisper) selected.',
          );
        }
        final lang = effectiveWhisperLanguage;
        final modelId = effectiveWhisperModelId;
        if (_isEnglishOnlyWhisperModel(modelId) && lang != 'en') {
          throw Exception(
            'The selected Whisper model ($modelId) is English-only. '
            'Use ggml-tiny.bin, ggml-base.bin, or ggml-small.bin for '
            'Auto-Detect or German transcription.',
          );
        }
        final String rawTranscript;
        if (pcmBytes != null && pcmBytes.isNotEmpty) {
          final sw = Stopwatch()..start();
          rawTranscript = TranscriptionResultGuard.requireTranscript(
            await _whisperService.transcribeRawPcm(
              pcmBytes,
              sampleRate: 16000,
              channels: 1,
              language: lang,
            ),
          );
          improvedText = rawTranscript;
          debugPrint(
            'Whisper: ${sw.elapsedMilliseconds}ms lang=$lang completed',
          );
        } else {
          // Stream fell back to file — strip 44-byte WAV header for raw PCM.
          final recordedAudioBytes = audioBytes;
          if (recordedAudioBytes == null) {
            throw CloudTranscriptionException(
              TranscriptionResultGuard.noTranscriptMessage,
            );
          }
          final rawPcm = recordedAudioBytes.length > 44
              ? Uint8List.sublistView(recordedAudioBytes, 44)
              : recordedAudioBytes;
          rawTranscript = TranscriptionResultGuard.requireTranscript(
            await _whisperService.transcribeRawPcm(
              rawPcm,
              sampleRate: 16000,
              channels: 1,
              language: lang,
            ),
          );
        }
        if (effectiveTwoPassEnabled) {
          final refinementModelId = effectiveRefinementModelId;
          improvedText = await _cloudService.improveTranscription(
            rawTranscript,
            missionInstruction: effectiveInstruction,
            modelOverrideId: refinementModelId,
            thinkingLevelOverride:
                overrides.twoPassRefinementThinkingLevel ??
                overrides.thinkingLevel,
          );
          debugPrint('Whisper two-pass: refined with $refinementModelId');
        } else {
          improvedText = rawTranscript;
        }
      } else if (effectiveTwoPassEnabled) {
        // Phase 1: fixed transcription-only pass.
        final rawTranscript = await _cloudService.transcribeAudio(
          audioBytes!,
          'audio/wav',
          modelOverrideId: effectiveTranscriptionModelId,
        );
        // Phase 2: apply the selected mode to transcript text only.
        improvedText = await _cloudService.improveTranscription(
          rawTranscript,
          missionInstruction: effectiveInstruction,
          modelOverrideId: effectiveRefinementModelId,
          thinkingLevelOverride:
              overrides.twoPassRefinementThinkingLevel ??
              overrides.thinkingLevel,
        );
      } else {
        // Single-pass cloud mode: transcribe and apply the selected mode.
        improvedText = await _cloudService.transcribeAndImprove(
          audioBytes!,
          'audio/wav',
          missionInstruction: effectiveInstruction,
          modelOverrideId: overrides.modelId,
          thinkingLevelOverride: overrides.thinkingLevel,
        );
      }
      // If state changed (e.g. cancelled), don't paste
      if (_state != RecordingState.processing) return;

      await _copyToClipboardAndPaste(improvedText);
      await _settingsService.addClipboardEntry(improvedText);
      _retryRecordingDuration = null;
      _useCurrentSettingsForRetry = false;
      _returnToRetryAfterSettings = false;
      await _recordingService.deleteRecording();
      // Track usage stats (non-blocking — don't block the success state)
      _usageStatsService.recordTranscription(improvedText, recordingDuration);
      setState(() => _state = RecordingState.success);
      _hideAfterDelay(1);
    } catch (e, stackTrace) {
      final message = e is CloudTranscriptionException
          ? e.message
          : e.toString();
      debugPrint('Transcription failed: $message');
      if (kDebugMode) debugPrintStack(stackTrace: stackTrace);
      final retryableRecordingExists =
          currentAttemptIsRetryable && await _currentRecordingFileExists();
      if (retryableRecordingExists) {
        _retryRecordingDuration = recordingDuration;
        keepSessionForRetry = true;
      } else {
        _retryRecordingDuration = null;
        _useCurrentSettingsForRetry = false;
        _returnToRetryAfterSettings = false;
        await _recordingService.deleteRecording();
      }
      if (_state == RecordingState.processing) {
        setState(() {
          _lastErrorMessage = retryableRecordingExists
              ? '$message\nAudio saved. You can retry.'
              : message;
          _state = RecordingState.error;
        });
        if (!retryableRecordingExists) {
          _hideAfterDelay(4);
        }
      }
    } finally {
      _isLockActive = false;
      // Clear temporary prompt override after the session ends
      if (_temporaryPromptId != null && !keepSessionForRetry) {
        debugPrint(
          'Clearing temporary prompt override (was: $_temporaryPromptId)',
        );
        _temporaryPromptId = null;
      }
      // Restore cloud model if a per-prompt override was active
      if (_promptModelOverrideActive) {
        _promptModelOverrideActive = false;
        _cloudService.setModelById(_settingsService.selectedModelId);
        debugPrint('Restored default model after per-prompt override');
      }
      // Restore cloud provider if a per-prompt override was active
      if (_promptProviderOverrideActive) {
        _promptProviderOverrideActive = false;
        _cloudService.clearProviderOverride();
        debugPrint('Restored default provider after per-prompt override');
      }
    }
  }

  Future<void> _retryLastRecording() async {
    await _stopRecordingAndProcess(retryExisting: true);
  }

  Future<bool> _currentRecordingFileExists() async {
    final path = _recordingService.currentRecordingPath;
    return path != null && await File(path).exists();
  }

  Future<void> _clearRetryRecording() async {
    if (_retryRecordingDuration == null) return;
    _retryRecordingDuration = null;
    _useCurrentSettingsForRetry = false;
    _returnToRetryAfterSettings = false;
    await _recordingService.deleteRecording();
  }

  Future<void> _cancelRecording() async {
    if (_state != RecordingState.recording &&
        _state != RecordingState.processing) {
      return;
    }

    _recordingStopwatch
      ..stop()
      ..reset();

    if (_state == RecordingState.processing &&
        _settingsService.transcriptionBackend == TranscriptionBackend.whisper) {
      await _whisperService.cancelTranscription();
    }

    await _recordingService.stopRecording();
    await _recordingService.deleteRecording();
    await _hotkeyService.unregisterHotkey('cancel');
    await _hotkeyService.unregisterHotkey('commit');

    _pulseController.stop();
    _rotationController.stop();

    setState(() => _state = RecordingState.idle);
    await WindowHelper.hide();

    _temporaryPromptId = null;
    debugPrint('Recording cancelled');
  }

  Future<void> _copyToClipboardAndPaste(String text) async {
    final clipboard = SystemClipboard.instance;
    var didWriteClipboard = false;
    if (clipboard != null) {
      final item = DataWriterItem();
      item.add(Formats.plainText(text));
      await clipboard.write([item]);
      didWriteClipboard = true;
    }

    if (!_settingsService.autoPasteEnabled || !didWriteClipboard) {
      return;
    }

    await Future.delayed(const Duration(milliseconds: 150));

    try {
      final keyboardService = KeyboardService();
      await keyboardService.simulateCtrlV();
    } catch (e) {
      debugPrint('Auto-paste failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 100),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeInQuint,
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: Tween<double>(begin: 0.8, end: 1.0).animate(animation),
                child: child,
              ),
            );
          },
          child: _state == RecordingState.onboarding
              ? OnboardingWizard(
                  key: const ValueKey('onboarding'),
                  settingsService: _settingsService,
                  onVerifyCloudProvider: _verifyCloudProvider,
                  onHotkeyChanged: (hotkey) => _onHotkeyChanged(hotkey),
                  onComplete: _onOnboardingComplete,
                  onModelDownloaded: _onModelDownloaded,
                )
              : _state == RecordingState.settings
              ? SettingsWindow(
                  key: const ValueKey('settings'),
                  provider: _settingsProvider,
                  usageStatsService: _usageStatsService,
                  onClose: _onSettingsClose,
                  onRunOnboarding: () async {
                    // Close settings, then launch onboarding
                    await WindowHelper.hide();
                    await windowManager.setMinimumSize(const Size(740, 560));
                    await windowManager.setSize(const Size(740, 560));
                    await windowManager.center();
                    setState(() => _state = RecordingState.onboarding);
                    await WindowHelper.show();
                    // Wait for onboarding to finish
                    while (mounted && _state == RecordingState.onboarding) {
                      await Future.delayed(const Duration(milliseconds: 100));
                    }
                    // Reset window
                    await WindowHelper.hide();
                    await windowManager.setMinimumSize(const Size(150, 150));
                    await windowManager.setSize(const Size(150, 150));
                    // Re-init cloud service in case settings changed
                    _cloudService.attachSettings(_settingsService);
                    await _cloudService.initialize();
                    _cloudService.setModelById(
                      _settingsService.selectedModelId,
                    );
                    // Re-register hotkey in case it changed
                    await _registerMainHotkey(_settingsService.hotkey);
                    await _registerClipboardPopupHotkey(
                      _settingsService.clipboardPopupHotkey,
                    );
                    await _registerModeSelectionHotkey(
                      _settingsService.modeSelectionHotkey,
                    );
                    _trayService.updateContextMenu();
                  },
                  onModelChanged: (modelId) {
                    _cloudService.setModelById(modelId);
                    _trayService.updateContextMenu();
                    debugPrint(
                      'Model changed to: ${_cloudService.currentModel.name}',
                    );
                  },
                  onPromptChanged: (promptId) {
                    _trayService.updateContextMenu();
                    debugPrint('Prompt changed via settings to: $promptId');
                  },
                  onHotkeyChanged: (hotkey) =>
                      _onHotkeyChanged(hotkey as HotkeyConfig),
                  onModeSelectionHotkeyChanged: _onModeSelectionHotkeyChanged,
                  onRecordingModeChanged: (mode) =>
                      _onRecordingModeChanged(mode as RecordingMode),
                  onClipboardHotkeyChanged: _onClipboardHotkeyChanged,
                  onBackendChanged: (dynamic backend) =>
                      _onBackendChanged(backend as TranscriptionBackend),
                  onVerifyCloudProvider: _verifyCloudProvider,
                  onModelDownloaded: _onModelDownloaded,
                )
              : _state == RecordingState.modeSelection
              ? ModeSelectionPopup(
                  key: const ValueKey('modeSelection'),
                  settingsService: _settingsService,
                  selectedIndex: _modeSelectionIndex ?? 0,
                  onSelect: (promptId) {
                    final allPrompts = [
                      ...SystemPrompt.availablePrompts,
                      ..._settingsService.customPrompts,
                    ];
                    final idx = allPrompts.indexWhere((p) => p.id == promptId);
                    _selectModeByIndex(idx >= 0 ? idx : 0);
                  },
                  onCancel: _cancelModeSelection,
                )
              : _state == RecordingState.modeCloudConfirm
              ? ModeCloudConfirmPopup(
                  key: const ValueKey('modeCloudConfirm'),
                  settingsService: _settingsService,
                  promptName: _modeCloudConfirmPrompt?.name ?? '',
                  selectedIndex: _modeCloudConfirmIndex,
                  onSelect: _confirmModeCloudConfirm,
                  onOpenSettings: _openSettingsFromCloudConfirm,
                  onCancel: _cancelModeCloudConfirm,
                )
              : FrostedOrb(
                  key: ValueKey(_state),
                  state: _state,
                  errorMessage: _lastErrorMessage,
                  canRetry:
                      _state == RecordingState.error &&
                      _retryRecordingDuration != null,
                  onRetry: _retryLastRecording,
                  onAdjustSettings: _showRetrySettings,
                  glowAnimation: _pulseController,
                  rotationController: _rotationController,
                ),
        ),
      ),
    );
  }
}
