import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'config.dart';
import 'services/cloud_transcription_service.dart';
import 'services/cloud_transcription_client.dart';
import 'services/hotkey_service.dart';
import 'services/recording_service.dart';
import 'services/keyboard_service.dart';
import 'services/macos_permission_service.dart';
import 'services/transcription_result_guard.dart';
import 'services/window_helper.dart';
import 'services/tray_service.dart';
import 'services/settings_service.dart';
import 'services/update_check_service.dart';
import 'services/usage_stats_service.dart';
import 'services/whisper_service.dart';
import 'models/system_prompt.dart';
import 'models/prompt_settings.dart';
import 'models/transcription_backend_resolver.dart';
import 'models/hotkey_config.dart';
import 'widgets/frosted_orb.dart';
import 'widgets/onboarding/onboarding_wizard.dart';
import 'widgets/onboarding/permission_onboarding_dialog.dart';
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
          // i18n foundation (H12): wire Flutter's localization delegates so the
          // framework + Material widgets honor the system locale. App-string
          // extraction to .arb is a tracked follow-up; English is the default.
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: const [Locale('en')],
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
  // True when the onboarding wizard ran during this launch. Used to avoid a
  // double Accessibility nudge (first-run users get the guided dialog at the
  // end of onboarding; returning users get the native prompt once at startup).
  bool _showedOnboardingThisRun = false;

  // Backend model transitions share one native Whisper instance. Serialize them
  // so a rapid settings change cannot initialize and unload the model at the
  // same time. A newer request supersedes queued work that has not started.
  Future<void> _backendTransitionQueue = Future<void>.value();
  int _backendTransitionRevision = 0;
  // The effective transcription backend captured at recording start. Pinned
  // for the whole session so a mid-session settings change cannot redirect the
  // captured audio to a different (wrong) transcription path at stop time.
  TranscriptionBackend? _activeRecordingBackend;
  // Bumped on superseding transitions (e.g. opening Settings while the record
  // hotkey is mid-start) so an in-flight [_startRecording] can detect that it
  // lost the race, stop the recorder it already started, and bail out instead
  // of clobbering the new state.
  int _sessionToken = 0;
  Completer<void>? _onboardingCompletion;
  bool _isShuttingDown = false;
  String? _hotkeyConfigurationError;

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
      unawaited(_scheduleBackendTransition(current));
    }
    _lastSeenBackend = current;
    // Clipboard settings are changed from several pages and tray flows. Keep
    // the monitor in sync immediately instead of waiting for Settings to close.
    _syncClipboardMonitor();
  }

  Future<void> _shutdownServices() async {
    if (_isShuttingDown) return;
    _isShuttingDown = true;
    final onboardingCompletion = _onboardingCompletion;
    if (onboardingCompletion != null && !onboardingCompletion.isCompleted) {
      onboardingCompletion.complete();
    }
    _onboardingCompletion = null;
    _holdTimer?.cancel();
    _holdTimer = null;
    _durationLimitTimer?.cancel();
    _durationLimitTimer = null;
    _clipboardMonitorTimer?.cancel();
    _clipboardMonitorTimer = null;
    await _unregisterModeSelectionHotkeys();
    await _unregisterModeCloudConfirmHotkeys();
    await _hotkeyService.unregisterHotkey('cancel');
    await _hotkeyService.unregisterHotkey('commit');
    await _recordingService.dispose();
    await _whisperService.dispose();
    await _hotkeyService.dispose();
    _cloudService.dispose();
    _trayService.dispose();
  }

  @override
  void dispose() {
    _settingsService.removeListener(_onSettingsChanged);
    windowManager.removeListener(this);
    _pulseController.dispose();
    _rotationController.dispose();
    unawaited(_shutdownServices());
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

      // Set the preferred audio input device from settings, then validate it
      // still exists so a stale saved id cannot produce empty captures later.
      final selectedDeviceId = _settingsService.selectedAudioDeviceId;
      _recordingService.setPreferredDevice(selectedDeviceId);
      debugPrint('Audio device set: ${selectedDeviceId ?? "System Default"}');
      try {
        final readiness = await _recordingService.assessMicReadiness();
        debugPrint(
          'Mic readiness: permission=${readiness.hasPermission}, '
          'devices=${readiness.devices.length}, '
          'resolved=${readiness.resolvedDeviceId ?? "System Default"}'
          '${readiness.fellBackToDefault ? " (stale selection cleared)" : ""}',
        );
        if (readiness.fellBackToDefault) {
          // Persist the fallback so Settings no longer shows "Device Not Found".
          await _settingsService.setSelectedAudioDeviceId(null);
        }
      } catch (e) {
        debugPrint('Mic readiness check failed (non-critical): $e');
      }

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
            await _shutdownServices();
            await windowManager.destroy();
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

      // macOS returning users: if Accessibility is still missing, surface the
      // native one-click prompt (it deep-links straight to the Accessibility
      // pane). First-run users already got the guided PermissionOnboardingDialog
      // at the end of the wizard, so we skip them to avoid a double nudge.
      if (Platform.isMacOS &&
          !_showedOnboardingThisRun &&
          mounted &&
          !await MacOsPermissionService.isGranted()) {
        await MacOsPermissionService.request();
      }

      await Future.delayed(const Duration(milliseconds: 200));
      await WindowHelper.hide();
      debugPrint('Window hidden');

      // ── Background update check ─────────────────────────────────────────
      // Fire-and-forget: rate-limited to once per 24h (see SettingsService),
      // never blocks startup or recording, and only surfaces a Settings badge
      // when a newer GitHub release exists. Every internal failure is swallowed
      // so this can never affect the rest of the app.
      if (_settingsService.shouldCheckForUpdates) {
        unawaited(_performBackgroundUpdateCheck());
      }
    } catch (e, stackTrace) {
      debugPrint('Initialization error: $e');
      if (kDebugMode) debugPrint('Stack trace: $stackTrace');
      setState(() => _state = RecordingState.error);
    }
  }

  /// Background GitHub-Releases update check. Fully best-effort — every
  /// failure path is swallowed so the app is never affected by a broken or
  /// offline check.
  Future<void> _performBackgroundUpdateCheck() async {
    try {
      final result = await UpdateCheckService().checkWithStatus();
      if (!result.succeeded) {
        debugPrint('Update check failed; it will be retried later.');
        return;
      }

      // Only a successfully parsed GitHub response consumes the 24-hour
      // rate-limit window. A transient failure should be retried.
      await _settingsService.recordUpdateCheck();
      final info = result.update;
      if (info != null) {
        await _settingsService.setAvailableUpdate(info);
        debugPrint('Update available: ${info.latestVersion}');
      } else {
        await _settingsService.clearAvailableUpdate();
      }
    } catch (e) {
      debugPrint('Update check failed (non-critical): $e');
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

  Future<void> _registerShortcut(
    String id,
    HotkeyConfig config,
    VoidCallback onPressed, {
    VoidCallback? onReleased,
  }) async {
    try {
      await _hotkeyService.registerHotkey(
        id: id,
        key: config.key,
        modifiers: config.modifiers.toList(),
        onPressed: onPressed,
        onReleased: onReleased,
      );
    } on HotkeyConflictException catch (error) {
      // A bad persisted shortcut should not prevent startup or recording. Keep
      // the already-working binding and surface a reset option in Settings.
      _hotkeyConfigurationError = error.message;
      debugPrint('Shortcut configuration conflict: ${error.message}');
    } catch (error) {
      // Platform registration failures (for example another app owns the OS
      // binding) are also non-fatal; the settings screen remains available.
      _hotkeyConfigurationError = 'Unable to register ${config.displayString}.';
      debugPrint('Shortcut registration failed for $id: $error');
    }
  }

  /// Register the main global hotkey with the given configuration.
  Future<void> _registerMainHotkey(HotkeyConfig config) {
    return _registerShortcut(
      'main',
      config,
      _onHotkeyPressed,
      onReleased: _onHotkeyReleased,
    );
  }

  Future<void> _registerClipboardPopupHotkey(HotkeyConfig config) {
    return _registerShortcut(
      'clipboard_popup',
      config,
      _openClipboardHistoryFromHotkey,
    );
  }

  Future<void> _registerModeSelectionHotkey(HotkeyConfig config) {
    return _registerShortcut('mode_selection', config, _openModeSelection);
  }

  Future<void> _resetShortcutDefaults() async {
    await _settingsService.resetHotkey();
    await _settingsService.resetClipboardPopupHotkey();
    await _settingsService.resetModeSelectionHotkey();
    // Remove all old bindings before registering defaults. Otherwise an old
    // secondary shortcut can block a default primary shortcut during the
    // conflict check.
    await _hotkeyService.unregisterHotkey('main');
    await _hotkeyService.unregisterHotkey('clipboard_popup');
    await _hotkeyService.unregisterHotkey('mode_selection');
    _hotkeyConfigurationError = null;
    await _registerMainHotkey(_settingsService.hotkey);
    await _registerClipboardPopupHotkey(_settingsService.clipboardPopupHotkey);
    await _registerModeSelectionHotkey(_settingsService.modeSelectionHotkey);
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

  /// Applies a settings-page device choice to the long-lived recorder now,
  /// rather than waiting for the next application launch.
  void _onAudioDeviceChanged(String? deviceId) {
    _recordingService.setPreferredDevice(deviceId);
    debugPrint('Audio input device changed: ${deviceId ?? 'System Default'}');
  }

  /// Serializes native Whisper transitions and discards queued stale requests.
  Future<void> _scheduleBackendTransition(TranscriptionBackend backend) {
    final revision = ++_backendTransitionRevision;
    final transition = _backendTransitionQueue.then((_) async {
      if (_isShuttingDown ||
          !mounted ||
          revision != _backendTransitionRevision) {
        return;
      }
      debugPrint('Transcription backend changed to: ${backend.name}');
      if (backend == TranscriptionBackend.whisper) {
        await _initWhisper();
      } else {
        // Release the native model but retain the shared ChangeNotifier so
        // a later switch back to Whisper can initialize the same service.
        await _whisperService.unloadModel();
      }
    });
    _backendTransitionQueue = transition.catchError((
      Object error,
      StackTrace _,
    ) {
      debugPrint('Whisper backend transition failed: $error');
    });
    return transition;
  }

  /// Called by settings widgets; queues instead of racing native operations.
  Future<void> _onBackendChanged(TranscriptionBackend backend) {
    _lastSeenBackend = backend;
    return _scheduleBackendTransition(backend);
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

  /// Resolve the transcription backend for [promptId], honoring a per-prompt
  /// override on top of the global default.
  ///
  /// Centralized so recording-start and recording-stop agree on the backend.
  /// A session pins the result at start time (see [_activeRecordingBackend]);
  /// callers must use that captured value rather than re-resolving at stop.
  TranscriptionBackend _resolveBackendForPrompt(String? promptId) {
    final effectivePromptId = promptId ?? _settingsService.selectedPromptId;
    final overrides =
        _settingsService.getPromptOverrides(effectivePromptId) ??
        const PromptSettings();
    return resolveSessionBackend(
      globalDefault: _settingsService.transcriptionBackend,
      promptBackendOverride: overrides.transcriptionBackend,
    );
  }

  /// Resolve the transcription backend that applies to a fresh (non-retry)
  /// session, honoring the active prompt's per-prompt override.
  ///
  /// This is captured into [_activeRecordingBackend] at recording start so the
  /// stop path uses the session decision rather than mutable settings.
  TranscriptionBackend _effectiveBackendForSession() {
    final promptId = _temporaryPromptId ?? _settingsService.selectedPromptId;
    return _resolveBackendForPrompt(promptId);
  }

  Future<void> _dismissModeInteractions() async {
    await _unregisterModeSelectionHotkeys();
    await _unregisterModeCloudConfirmHotkeys();
    _modeSelectionIndex = null;
    _modeCloudConfirmPrompt = null;
  }

  void _showSettings() async {
    // A recording may not survive a Settings transition. Opening Settings
    // (from the tray, a hotkey, or an in-app flow) while the orb is actively
    // recording would strand the native recorder — leaving a hot microphone,
    // unbounded stream memory, and session-scoped Enter/Escape/duration timers
    // that no longer fire. Discard the in-flight audio (the privacy-safe
    // choice) before proceeding.
    if (_state == RecordingState.recording) {
      await _cancelRecording();
    }
    // Invalidate any recording start that is racing concurrently (e.g. the
    // record hotkey was pressed moments before Settings opened). The in-flight
    // start checks this token before committing and abandons + stops the
    // recorder it may have just started.
    _sessionToken++;
    // Settings may be opened by the tray while a mode popup is visible. Tear
    // down its in-app navigation bindings first so stale handlers cannot act
    // on a hidden popup.
    await _dismissModeInteractions();
    // Resize to settings window size and center
    await windowManager.setMinimumSize(const Size(820, 560));
    await windowManager.setSize(const Size(980, 640));
    await windowManager.center();

    if (mounted) {
      setState(() => _state = RecordingState.settings);
    }

    await WindowHelper.show();
    final shortcutError = _hotkeyConfigurationError;
    if (shortcutError != null && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$shortcutError Reset shortcuts to recover.'),
            action: SnackBarAction(
              label: 'Reset',
              onPressed: () => unawaited(_resetShortcutDefaults()),
            ),
          ),
        );
      });
    }
  }

  void _showRetrySettings() {
    _returnToRetryAfterSettings = true;
    _useCurrentSettingsForRetry = true;
    _settingsProvider.selectCategory(SettingsCategory.aiModels);
    _showSettings();
  }

  Future<void> _showOnboarding() async {
    _showedOnboardingThisRun = true;
    await windowManager.setMinimumSize(const Size(740, 560));
    await windowManager.setSize(const Size(740, 560));
    await windowManager.center();
    await WindowHelper.show();

    if (!mounted) return;
    final completion = Completer<void>();
    _onboardingCompletion = completion;
    setState(() => _state = RecordingState.onboarding);

    // The wizard explicitly resolves this completer. Unlike state polling,
    // this cannot leave initialization spinning forever when a route is closed
    // or the app is disposed.
    await completion.future;
    if (!mounted) return;
    if (identical(_onboardingCompletion, completion)) {
      _onboardingCompletion = null;
    }

    // macOS: surface the single Accessibility permission for auto-paste right
    // after install, while the window is still at onboarding size.
    if (Platform.isMacOS) {
      await PermissionOnboardingDialog.show(context);
    }

    // Reset window to orb size.
    await WindowHelper.hide();
    await windowManager.setMinimumSize(const Size(150, 150));
    await windowManager.setSize(const Size(150, 150));
    debugPrint('Onboarding completed');
  }

  void _onOnboardingComplete() {
    final completion = _onboardingCompletion;
    if (completion != null && !completion.isCompleted) completion.complete();
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
    // Navigation is intentionally app-scoped instead of modifier-less global
    // shortcuts, so the popup must own focus while it is open.
    await WindowHelper.show();

    // Register focused-window keyboard navigation hotkeys
    await _hotkeyService.registerHotkey(
      id: 'mode_cancel',
      key: LogicalKeyboardKey.escape,
      scope: HotKeyScope.inapp,
      onPressed: _cancelModeSelection,
    );
    await _hotkeyService.registerHotkey(
      id: 'mode_up',
      key: LogicalKeyboardKey.arrowUp,
      scope: HotKeyScope.inapp,
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
      scope: HotKeyScope.inapp,
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
      scope: HotKeyScope.inapp,
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
  // Renders [ModeCloudConfirmPopup] inside the focused 320x360 popup. Its
  // Escape/arrow/Enter bindings are app-scoped, so no keys are captured while
  // the user is working in another application.

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
      scope: HotKeyScope.inapp,
      onPressed: _cancelModeCloudConfirm,
    );
    if (needsCloudSetup) {
      await _hotkeyService.registerHotkey(
        id: 'mode_cloud_enter',
        key: LogicalKeyboardKey.enter,
        scope: HotKeyScope.inapp,
        onPressed: _openSettingsFromCloudConfirm,
      );
      return;
    }
    await _hotkeyService.registerHotkey(
      id: 'mode_cloud_up',
      key: LogicalKeyboardKey.arrowUp,
      scope: HotKeyScope.inapp,
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
      scope: HotKeyScope.inapp,
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
      scope: HotKeyScope.inapp,
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
    await WindowHelper.show();

    // Re-register focused-window keyboard navigation hotkeys.
    await _hotkeyService.registerHotkey(
      id: 'mode_cancel',
      key: LogicalKeyboardKey.escape,
      scope: HotKeyScope.inapp,
      onPressed: _cancelModeSelection,
    );
    await _hotkeyService.registerHotkey(
      id: 'mode_up',
      key: LogicalKeyboardKey.arrowUp,
      scope: HotKeyScope.inapp,
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
      scope: HotKeyScope.inapp,
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
      scope: HotKeyScope.inapp,
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
    // Snapshot the transition generation. If Settings (or another superseding
    // transition) opens while we await async platform calls below, the token
    // will differ and we bail before committing a half-started recording.
    final sessionToken = _sessionToken;
    _activeRecordingBackend = null;
    _durationLimitTimer?.cancel();
    _durationLimitTimer = null;
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
      // Preflight: permission + stale-device cleanup. An empty device list is
      // only a warning (OS default may still work); denied permission is fatal.
      final readiness = await _recordingService.assessMicReadiness();
      if (readiness.fellBackToDefault) {
        await _settingsService.setSelectedAudioDeviceId(null);
      }
      if (!readiness.hasPermission) {
        debugPrint('Recording start blocked: microphone permission denied');
        setState(() {
          _lastErrorMessage =
              'Microphone permission is required. Enable it in system settings.';
          _state = RecordingState.error;
        });
        _hideAfterDelay(3);
        return;
      }
      if (!readiness.hasAnyDeviceListed) {
        // Still attempt start — some platforms report an empty list but allow
        // the default device — but log loudly for troubleshooting.
        debugPrint(
          'Warning: no input devices listed by the OS; attempting System Default',
        );
      }

      // Offline (Whisper) sessions record an in-memory PCM-16 stream that can be
      // passed straight to Whisper without a WAV container round-trip. Cloud
      // sessions (and offline sessions whose microphone won't stream) fall back
      // to a WAV file. The stop path in [_stopRecordingAndProcess] reads the
      // actual stream/file mode, so the WAV fallback stays correct regardless
      // of the pinned backend decision.
      //
      // The backend is resolved ONCE here and captured so a mid-session
      // settings change cannot redirect the captured audio to the wrong path.
      final sessionBackend = _effectiveBackendForSession();
      final isOffline = sessionBackend == TranscriptionBackend.whisper;
      // Explicit fallback flow: offline prefers the PCM stream and only falls
      // back to a WAV file when streaming is unavailable (driver/permission
      // edge case). Cloud always records to a WAV file.
      bool started;
      if (isOffline) {
        started = await _recordingService.startStreamRecording();
        if (!started) {
          debugPrint(
            'Stream recording unavailable; falling back to WAV file capture',
          );
          started = await _recordingService.startRecording();
        }
      } else {
        started = await _recordingService.startRecording();
      }

      if (sessionToken != _sessionToken) {
        // A superseding transition (e.g. Settings opened) won the race while
        // we were starting the recorder. Do not commit to RecordingState —
        // stop the recorder we just started so it cannot leave a hot mic, then
        // bail. The finally block releases the lock.
        debugPrint(
          'Recording start superseded by another transition; aborting.',
        );
        await _abortStartedRecorder();
        return;
      }

      if (started) {
        _activeRecordingBackend = sessionBackend;
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

        // Register the bare Enter and Escape keys for the active session:
        // Enter commits the recording (stop + process), Escape cancels it.
        //
        // These MUST be system/global scope, NOT inapp. The recording orb is
        // intentionally shown WITHOUT stealing OS keyboard focus
        // (positionAtActiveMonitorBottomCenter uses SW_SHOWNOACTIVATE) so the
        // user's foreground app keeps the caret for later paste. inapp-scope
        // hotkeys are delivered through HardwareKeyboard, which only receives
        // events while the Beeamvo window itself is focused — so an inapp
        // binding here would be inert for the entire recording. System scope
        // routes the keys through the OS keyboard hook regardless of which
        // window is focused, so Escape/Enter reliably drive the session while
        // the user is typing in another app. They are unregistered again in
        // _stopRecordingAndProcess / _cancelRecording / _abortStartedRecorder,
        // so the bindings only exist for the lifetime of an active recording.
        await _hotkeyService.registerHotkey(
          id: 'cancel',
          key: LogicalKeyboardKey.escape,
          scope: HotKeyScope.system,
          onPressed: _cancelRecording,
        );
        // Register Enter key to commit/finish recording
        await _hotkeyService.registerHotkey(
          id: 'commit',
          key: LogicalKeyboardKey.enter,
          scope: HotKeyScope.system,
          onPressed: _stopRecordingAndProcess,
        );
        } else {
          _activeRecordingBackend = null;
          _recordingStopwatch
            ..stop()
            ..reset();
          setState(() {
            _lastErrorMessage =
                'Could not start the microphone. Check the input device in '
                'Settings → General → Audio Input Device.';
            _state = RecordingState.error;
          });
          _hideAfterDelay(3);
        }
      } catch (e) {
        debugPrint('Recording start failed: $e');
        // A platform start may have succeeded before this exception (e.g. the
        // recorder is running but the subsequent cancel/commit hotkey
        // registration threw). Best-effort abort/stop it so a failed start can
        // never strand a hot microphone, and tear down the session-scoped
        // hotkeys/timers/backend pin captured so far. _abortStartedRecorder is
        // non-throwing, so it never masks the original error or leaves the mic on.
        await _abortStartedRecorder();
        _recordingStopwatch
          ..stop()
          ..reset();
        _holdTimer?.cancel();
        _holdTimer = null;
        _isHotkeyHeld = false;

        if (sessionToken == _sessionToken) {
          // We still own this session: surface a recoverable error state.
          setState(() {
            _lastErrorMessage =
                'Microphone failed to start. Try System Default in '
                'Settings → General → Audio Input Device.';
            _state = RecordingState.error;
          });
          _hideAfterDelay(3);
        }
      // If a superseding transition (e.g. Settings opened) won the race while
      // we were starting, leave the winning transition's UI state intact — it
      // already set the correct state and we must not overwrite it with error.
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
    }
    _durationLimitTimer?.cancel();
    _durationLimitTimer = null;
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

      // A session pins its backend at recording start. During a non-retry
      // stop we reuse that captured decision so a mid-session settings change
      // (e.g. switching Cloud↔Whisper) cannot redirect the already-captured
      // audio to a different — and for stream sessions incompatible — path.
      // Retry intentionally resolves fresh so the user can re-run with the
      // newly chosen settings.
      final backend = retryExisting
          ? _resolveBackendForPrompt(effectivePromptId)
          : (_activeRecordingBackend ??
                _resolveBackendForPrompt(effectivePromptId));
      final isOffline = backend == TranscriptionBackend.whisper;

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

      // Stop recording — decide stream vs. file from the ACTUAL capture mode
      // (not the pinned backend) so the WAV fallback path stays correct even
      // if the session's stream attempt failed over to a file at start time.
      Uint8List? pcmBytes;
      String? audioPath;
      if (retryExisting) {
        audioPath = _recordingService.currentRecordingPath;
      } else if (_recordingService.isStreamRecording) {
        pcmBytes = await _recordingService.stopStreamAndGetPcm();
      } else {
        audioPath = await _recordingService.stopRecording();
      }
      currentAttemptIsRetryable = !isOffline && audioPath != null;

      // A clip rejected locally for minimum duration can never become valid
      // when replayed. Never present it as a retryable cloud failure.
      if (recordingDuration <
          TranscriptionResultGuard.minimumRecordingDuration) {
        currentAttemptIsRetryable = false;
      }
      TranscriptionResultGuard.ensureRecordingLongEnough(recordingDuration);

      // For cloud paths, read audio bytes from the file.
      Uint8List? audioBytes;
      if (!isOffline) {
        if (audioPath == null) {
          debugPrint('Process aborted: recorder returned no file path');
          throw CloudTranscriptionException(
            'Recording failed — no audio was captured. Check that a '
            'microphone is selected and not in use by another app.',
          );
        }
        audioBytes = await _recordingService.getAudioBytes();
        if (audioBytes == null || audioBytes.isEmpty) {
          debugPrint(
            'Process aborted: empty audio file at $audioPath '
            '(duration=${recordingDuration.inMilliseconds}ms)',
          );
          throw CloudTranscriptionException(
            'No audio was captured. Check the microphone in '
            'Settings → General → Audio Input Device.',
          );
        }
      } else if (pcmBytes == null || pcmBytes.isEmpty) {
        // Stream fell back to file, or stream produced silence/empty buffer.
        if (audioPath == null) {
          debugPrint(
            'Process aborted: offline path has neither PCM nor file path',
          );
          throw CloudTranscriptionException(
            'Recording failed — no audio was captured. Check that a '
            'microphone is selected and not in use by another app.',
          );
        }
        audioBytes = await _recordingService.getAudioBytes();
        if (audioBytes == null || audioBytes.isEmpty) {
          debugPrint(
            'Process aborted: empty offline audio file at $audioPath '
            '(duration=${recordingDuration.inMilliseconds}ms)',
          );
          throw CloudTranscriptionException(
            'No audio was captured. Check the microphone in '
            'Settings → General → Audio Input Device.',
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
          // A WAV file may contain optional RIFF chunks, so parse its chunk
          // table instead of assuming a fixed 44-byte header.
          final recordedAudioBytes = audioBytes;
          if (recordedAudioBytes == null) {
            throw CloudTranscriptionException(
              TranscriptionResultGuard.noTranscriptMessage,
            );
          }
          final Uint8List rawPcm;
          try {
            rawPcm = RecordingService.extractMono16kPcmFromWav(
              recordedAudioBytes,
            );
          } on FormatException {
            throw CloudTranscriptionException(
              'Recorded audio is not valid mono 16 kHz PCM WAV data.',
            );
          }
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
      // Persist usage before signaling success so a tray Exit immediately
      // after a transcription cannot lose this completed activity record.
      await _usageStatsService.recordTranscription(
        improvedText,
        recordingDuration,
      );
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
      // Release the session-scoped global Enter/Escape handlers now that the
      // session has ended, so bare Enter/Escape are no longer captured
      // globally by Beeamvo. Idempotent — safe even if they were never
      // registered.
      await _hotkeyService.unregisterHotkey('cancel');
      await _hotkeyService.unregisterHotkey('commit');
      _activeRecordingBackend = null;
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

  /// Stops the native recorder and resets session recording flags/state after
  /// a recording start was superseded before it could commit to
  /// [RecordingState.recording] (e.g. Settings opened while the recorder was
  /// initializing). Unlike [_cancelRecording], it must not depend on the
  /// [_state] machine and must not touch the visible orb state — callers are
  /// transitioning elsewhere themselves.
  Future<void> _abortStartedRecorder() async {
    // Stop whichever mode is actually active. The stream path
    // (stopStreamAndGetPcm) already swallows internal failures; the file path
    // (stopRecording) does not, so both are guarded here. A platform stop
    // error must never propagate — this method must remain non-throwing so it
    // cannot clobber a superseding transition's UI state (e.g. Settings that
    // won the session-token race) or, when called from the _startRecording
    // catch, mask a real error with a cleanup failure.
    try {
      if (_recordingService.isStreamRecording) {
        await _recordingService.stopStreamAndGetPcm();
      } else {
        await _recordingService.stopRecording();
      }
    } catch (e) {
      debugPrint('Recorder stop during abort failed (best-effort): $e');
    }
    try {
      await _recordingService.deleteRecording();
    } catch (e) {
      debugPrint('Recording file cleanup during abort failed: $e');
    }
    _durationLimitTimer?.cancel();
    _durationLimitTimer = null;
    _activeRecordingBackend = null;
    // The session-scoped global Enter/Escape handlers are redundant here
    // (they are only registered after a start commits), but unregistering is
    // idempotent and keeps the hotkey set clean.
    await _hotkeyService.unregisterHotkey('cancel');
    await _hotkeyService.unregisterHotkey('commit');
  }

  Future<void> _cancelRecording() async {
    if (_state != RecordingState.recording &&
        _state != RecordingState.processing) {
      return;
    }

    _recordingStopwatch
      ..stop()
      ..reset();
    _durationLimitTimer?.cancel();
    _durationLimitTimer = null;
    _holdTimer?.cancel();
    _holdTimer = null;
    _isHotkeyHeld = false;

    // Use the backend resolved for this session, not the current global
    // setting. Prompts may temporarily override the backend.
    if (_state == RecordingState.processing &&
        _activeRecordingBackend == TranscriptionBackend.whisper) {
      await _whisperService.cancelTranscription();
    }

    // Release the session-scoped global Enter/Escape handlers.
    await _hotkeyService.unregisterHotkey('cancel');
    await _hotkeyService.unregisterHotkey('commit');

    await _recordingService.stopRecording();
    await _recordingService.deleteRecording();

    _pulseController.stop();
    _rotationController.stop();

    if (mounted) setState(() => _state = RecordingState.idle);
    await WindowHelper.hide();

    _temporaryPromptId = null;
    _activeRecordingBackend = null;
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
                    await _showOnboarding();
                    if (!mounted) return;
                    // Re-init cloud service in case onboarding changed its
                    // credentials, provider, or selected model.
                    _cloudService.attachSettings(_settingsService);
                    await _cloudService.initialize();
                    _cloudService.setModelById(
                      _settingsService.selectedModelId,
                    );
                    await _registerMainHotkey(_settingsService.hotkey);
                    await _registerClipboardPopupHotkey(
                      _settingsService.clipboardPopupHotkey,
                    );
                    await _registerModeSelectionHotkey(
                      _settingsService.modeSelectionHotkey,
                    );
                    await _trayService.updateContextMenu();
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
                  onAudioDeviceChanged: _onAudioDeviceChanged,
                  onResetAllHotkeys: _resetShortcutDefaults,
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
