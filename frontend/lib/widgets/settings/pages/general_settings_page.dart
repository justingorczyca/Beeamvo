import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../providers/settings_provider.dart';
import '../../../services/keyboard_service.dart';
import '../../../services/settings_service.dart';
import '../../../services/update_check_service.dart';
import '../../../services/recording_service.dart';
import '../../../models/hotkey_config.dart';
import '../../hotkey_recorder_widget.dart';
import '../../onboarding/permission_onboarding_dialog.dart';
import '../bee_input.dart';
import '../bee_page_header.dart';
import '../settings_shared.dart';
import 'package:record/record.dart';

class GeneralSettingsPage extends StatefulWidget {
  final ValueChanged<dynamic>? onHotkeyChanged;
  final ValueChanged<HotkeyConfig>? onModeSelectionHotkeyChanged;
  final ValueChanged<HotkeyConfig>? onClipboardHotkeyChanged;
  final ValueChanged<dynamic>? onRecordingModeChanged;
  final ValueChanged<String?>? onAudioDeviceChanged;
  final Future<void> Function()? onResetAllHotkeys;
  final VoidCallback? onRunOnboarding;

  const GeneralSettingsPage({
    super.key,
    this.onHotkeyChanged,
    this.onModeSelectionHotkeyChanged,
    this.onClipboardHotkeyChanged,
    this.onRecordingModeChanged,
    this.onAudioDeviceChanged,
    this.onResetAllHotkeys,
    this.onRunOnboarding,
  });

  @override
  State<GeneralSettingsPage> createState() => _GeneralSettingsPageState();
}

class _GeneralSettingsPageState extends State<GeneralSettingsPage> {
  bool? _accessibilityGranted;
  bool _launchAtStartup = false;
  bool _durationLimitEnabled = false;
  int _durationLimit = 300;
  HotkeyConfig _currentHotkey = HotkeyConfig.defaultHotkey;
  HotkeyConfig _modeSelectionHotkey = HotkeyConfig.defaultModeSelectionHotkey;
  HotkeyConfig _clipboardPopupHotkey = HotkeyConfig.defaultClipboardPopupHotkey;
  RecordingMode _recordingMode = RecordingMode.toggle;
  List<InputDevice> _availableDevices = [];
  String? _selectedDeviceId;
  bool _isLoadingDevices = false;
  bool _settingsLoaded = false;
  bool _isCheckingUpdate = false;
  String _appVersion = '';
  String _themeMode = 'system';

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _loadAudioDevices();
    _loadAppVersion();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_settingsLoaded) {
      _settingsLoaded = true;
      _loadSettings();
    }
  }

  void _loadSettings() {
    final s = SettingsProviderScope.of(context).settingsService;
    // Use setState so the loaded values are reflected in the UI immediately.
    setState(() {
      _launchAtStartup = s.launchAtStartupEnabled;
      _currentHotkey = s.hotkey;
      _modeSelectionHotkey = s.modeSelectionHotkey;
      _clipboardPopupHotkey = s.clipboardPopupHotkey;
      _durationLimitEnabled = s.durationLimitEnabled;
      _durationLimit = s.durationLimit;
      _recordingMode = s.recordingMode;
      _selectedDeviceId = s.selectedAudioDeviceId;
      _themeMode = s.themeMode;
    });
  }

  Future<void> _loadAppVersion() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _appVersion = '${info.version}+${info.buildNumber}';
    });
  }

  // ── Update checking ──────────────────────────────────────────────────────

  /// Manually triggered update check. Always performs a fresh fetch and shows
  /// a result dialog. Fully UI-driven so the user always gets feedback.
  Future<void> _checkForUpdates() async {
    final settings = SettingsProviderScope.of(context).settingsService;
    setState(() => _isCheckingUpdate = true);
    try {
      final result = await UpdateCheckService().checkWithStatus(force: true);
      if (!result.succeeded) {
        if (!mounted) return;
        _showUpdateCheckFailedDialog();
        return;
      }

      await settings.recordUpdateCheck();
      final info = result.update;
      if (info != null) {
        await settings.setAvailableUpdate(info);
        if (!mounted) return;
        _showUpdateDialog(info);
      } else {
        await settings.clearAvailableUpdate();
        if (!mounted) return;
        _showUpToDateDialog();
      }
    } catch (_) {
      // Persistence failures must not be presented as a successful check.
      if (!mounted) return;
      _showUpdateCheckFailedDialog();
    } finally {
      if (mounted) setState(() => _isCheckingUpdate = false);
    }
  }

  void _showUpdateDialog(UpdateInfo info) {
    final notes = info.releaseNotes.trim();
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: beeSurfaceRaised(dialogContext),
        shape: beeDialogShape(),
        title: Row(
          children: [
            Icon(
              Icons.system_update_rounded,
              color: beeSuccess(dialogContext),
              size: 20,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Update available — v${info.latestVersion}',
                style: GoogleFonts.spaceGrotesk(
                  color: beeText(dialogContext),
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'A new version of Beeamvo is ready to download.',
                style: GoogleFonts.inter(
                  color: beeTextSub(dialogContext),
                  fontSize: 13,
                ),
              ),
              if (notes.isNotEmpty) ...[
                const SizedBox(height: 12),
                Flexible(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: SingleChildScrollView(
                      child: Text(
                        notes,
                        style: GoogleFonts.inter(
                          color: beeText(dialogContext),
                          fontSize: 12.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            style: beeSecondaryButtonStyle(dialogContext),
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Later'),
          ),
          ElevatedButton(
            style: beePrimaryButtonStyle(dialogContext),
            onPressed: () async {
              final uri = Uri.tryParse(info.releaseUrl);
              if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
                if (dialogContext.mounted) Navigator.pop(dialogContext);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('The saved release link is invalid.'),
                    ),
                  );
                }
                return;
              }
              Navigator.pop(dialogContext);
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
            child: const Text('Download'),
          ),
        ],
      ),
    );
  }

  void _showUpdateCheckFailedDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: beeSurfaceRaised(dialogContext),
        shape: beeDialogShape(),
        title: Text(
          'Unable to check for updates',
          style: GoogleFonts.spaceGrotesk(
            color: beeText(dialogContext),
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        content: Text(
          'Please check your connection and try again later.',
          style: GoogleFonts.inter(
            color: beeTextSub(dialogContext),
            fontSize: 14,
          ),
        ),
        actions: [
          ElevatedButton(
            style: beePrimaryButtonStyle(dialogContext),
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _showUpToDateDialog() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: beeSurfaceRaised(dialogContext),
        shape: beeDialogShape(),
        title: Text(
          "You're up to date",
          style: GoogleFonts.spaceGrotesk(
            color: beeText(dialogContext),
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        content: Text(
          'Beeamvo v$_appVersion is the latest version.',
          style: GoogleFonts.inter(
            color: beeTextSub(dialogContext),
            fontSize: 14,
          ),
        ),
        actions: [
          ElevatedButton(
            style: beePrimaryButtonStyle(dialogContext),
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  /// Compact tappable "Update available" chip shown inline on the Version row.
  Widget _buildUpdateAvailableChip() {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        final update = SettingsProviderScope.of(
          context,
        ).settingsService.availableUpdate;
        if (update != null) _showUpdateDialog(update);
      },
      child: beeBadge(context, 'Update available', BeeBadgeTone.success),
    );
  }

  Future<void> _loadAudioDevices() async {
    setState(() => _isLoadingDevices = true);
    final recorder = RecordingService();
    try {
      final devices = await recorder.listInputDevices();
      // If the saved selection no longer exists, clear it so recording uses the
      // OS default instead of a dead id that captures silence/crashes start.
      var selectedId = _selectedDeviceId;
      if (selectedId != null &&
          selectedId.isNotEmpty &&
          !devices.any((d) => d.id == selectedId)) {
        if (!mounted) return;
        await SettingsProviderScope.of(
          context,
        ).settingsService.setSelectedAudioDeviceId(null);
        widget.onAudioDeviceChanged?.call(null);
        selectedId = null;
      }
      if (mounted) {
        setState(() {
          _availableDevices = devices;
          _selectedDeviceId = selectedId;
          _isLoadingDevices = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingDevices = false);
    } finally {
      await recorder.dispose();
    }
  }

  Future<void> _checkPermissions() async {
    final ks = KeyboardService();
    final a = await ks.checkAccessibilityPermissions();
    if (mounted) {
      setState(() => _accessibilityGranted = a);
      SettingsProviderScope.of(context).updatePermissions(accessibility: a);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsProviderScope.of(context).settingsService;
    return Column(
      children: [
        Expanded(
          child: Container(
            color: beeSurface(context),
            child: SingleChildScrollView(
              padding: BeePageHeader.contentPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  BeePageHeader(title: 'General'),
                  // ── APPEARANCE ──────────────────────────────────
                  // Top-most group: theme mode follows OS or pinned to
                  // light/dark. Kept up here because it affects every frame
                  // the user sees, not just specific workflows.
                  const BeeGroupLabel(label: 'Appearance'),
                  BeeSettingsRow(
                    icon: Icons.brightness_6_rounded,
                    label: 'Appearance',
                    description:
                        'Choose how the app looks. System follows your OS preference.',
                    trailing: BeeSegmented<String>(
                      value: _themeMode,
                      onChanged: (mode) async {
                        await settings.setThemeMode(mode);
                        setState(() => _themeMode = mode);
                      },
                      options: const [
                        (val: 'system', label: 'System', icon: null),
                        (val: 'light', label: 'Light', icon: null),
                        (val: 'dark', label: 'Dark', icon: null),
                      ],
                    ),
                  ),

                  const SizedBox(height: BeePageHeader.groupGap),

                  // ── RECORDING ───────────────────────────────────
                  // Audio device + recording mode + auto-stop + duration.
                  // All four are conceptually about how recording works —
                  // unified into one group for better information hierarchy.
                  const BeeGroupLabel(label: 'Recording'),
                  BeeSettingsRow(
                    icon: Icons.mic_rounded,
                    label: 'Audio Input Device',
                    description: 'Microphone used for recording',
                    trailing: BeeChip(
                      displayValue: Text(
                        _selectedDeviceId == null
                            ? 'System Default'
                            : _getDeviceLabel(),
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color:
                              _selectedDeviceId != null &&
                                  _getDeviceLabel() == 'Device Not Found'
                              ? beeError(context)
                              : beeText(context),
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => _isLoadingDevices
                          ? null
                          : _showAudioDeviceDialog(settings),
                      isLoading: _isLoadingDevices,
                    ),
                  ),
                  BeeSettingsRow(
                    icon: Icons.fiber_manual_record_rounded,
                    label: 'Recording Mode',
                    description: _recordingMode == RecordingMode.toggle
                        ? 'Press once to start. Press again to stop.'
                        : 'Hold to record. Release to transcribe.',
                    trailing: BeeSegmented<RecordingMode>(
                      value: _recordingMode,
                      onChanged: (mode) async {
                        await settings.setRecordingMode(mode);
                        setState(() => _recordingMode = mode);
                        widget.onRecordingModeChanged?.call(mode);
                      },
                      options: const [
                        (
                          val: RecordingMode.toggle,
                          label: 'Toggle',
                          icon: Icons.keyboard_command_key_rounded,
                        ),
                        (
                          val: RecordingMode.hold,
                          label: 'Hold',
                          icon: Icons.touch_app_rounded,
                        ),
                      ],
                    ),
                  ),
                  BeeSettingsRow(
                    icon: Icons.timer_rounded,
                    label: 'Auto-stop Recording',
                    description: 'Limit maximum recording duration',
                    showDivider: _durationLimitEnabled,
                    trailing: BeeToggle(
                      value: _durationLimitEnabled,
                      semanticLabel: 'Auto-stop recording',
                      onChanged: (v) async {
                        await settings.setDurationLimitEnabled(v);
                        setState(() => _durationLimitEnabled = v);
                      },
                    ),
                  ),
                  if (_durationLimitEnabled)
                    BeeSettingsRow(
                      icon: Icons.hourglass_bottom_rounded,
                      label: 'Duration Limit',
                      showDivider: false,
                      trailing: BeeChip(
                        displayValue: Text(
                          _formatDuration(_durationLimit),
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: beeText(context),
                          ),
                        ),
                        onTap: () => _showDurationDialog(settings),
                      ),
                    ),

                  const SizedBox(height: BeePageHeader.groupGap),

                  // ── SHORTCUTS ──────────────────────────────────
                  const BeeGroupLabel(label: 'Shortcuts'),
                  BeeSettingsRow(
                    icon: Icons.graphic_eq_rounded,
                    label: 'Record and Transcribe',
                    description:
                        'Start, stop, or hold-to-record from anywhere on your desktop',
                    trailing: _hotkeyChip(
                      _currentHotkey,
                      () => _showHotkeyDialog(
                        title: 'Recording Hotkey',
                        current: _currentHotkey,
                        onSave: (hotkey) async {
                          await settings.setHotkey(hotkey);
                          setState(() => _currentHotkey = hotkey);
                          widget.onHotkeyChanged?.call(hotkey);
                        },
                        onReset: () async {
                          await settings.resetHotkey();
                          final hotkey = settings.hotkey;
                          setState(() => _currentHotkey = hotkey);
                          widget.onHotkeyChanged?.call(hotkey);
                        },
                      ),
                    ),
                  ),
                  BeeSettingsRow(
                    icon: Icons.view_carousel_rounded,
                    label: 'Mode Selection Popup',
                    description:
                        'Open the prompt/mode picker without visiting settings',
                    trailing: _hotkeyChip(
                      _modeSelectionHotkey,
                      () => _showHotkeyDialog(
                        title: 'Mode Selection Hotkey',
                        current: _modeSelectionHotkey,
                        onSave: (hotkey) async {
                          await settings.setModeSelectionHotkey(hotkey);
                          setState(() => _modeSelectionHotkey = hotkey);
                          widget.onModeSelectionHotkeyChanged?.call(hotkey);
                        },
                        onReset: () async {
                          await settings.resetModeSelectionHotkey();
                          final hotkey = settings.modeSelectionHotkey;
                          setState(() => _modeSelectionHotkey = hotkey);
                          widget.onModeSelectionHotkeyChanged?.call(hotkey);
                        },
                      ),
                    ),
                  ),
                  BeeSettingsRow(
                    icon: Icons.content_paste_search_rounded,
                    label: 'Clipboard History Popup',
                    description:
                        'Open saved and pinned clipboard entries from anywhere',
                    showDivider: false,
                    trailing: _hotkeyChip(
                      _clipboardPopupHotkey,
                      () => _showHotkeyDialog(
                        title: 'Clipboard Popup Hotkey',
                        current: _clipboardPopupHotkey,
                        onSave: (hotkey) async {
                          await settings.setClipboardPopupHotkey(hotkey);
                          setState(() => _clipboardPopupHotkey = hotkey);
                          widget.onClipboardHotkeyChanged?.call(hotkey);
                        },
                        onReset: () async {
                          await settings.resetClipboardPopupHotkey();
                          final hotkey = settings.clipboardPopupHotkey;
                          setState(() => _clipboardPopupHotkey = hotkey);
                          widget.onClipboardHotkeyChanged?.call(hotkey);
                        },
                      ),
                    ),
                  ),

                  const SizedBox(height: BeePageHeader.groupGap),

                  // ── SYSTEM ─────────────────────────────────────
                  // Truly system-level: launch at login, onboarding,
                  // permissions, reset, about metadata.
                  const BeeGroupLabel(label: 'System'),
                  BeeSettingsRow(
                    icon: Icons.launch_rounded,
                    label: 'Launch at Login',
                    description: 'Automatically start when you log in',
                    trailing: BeeToggle(
                      value: _launchAtStartup,
                      semanticLabel: 'Launch at login',
                      onChanged: (v) async {
                        await settings.setLaunchAtStartup(v);
                        setState(() => _launchAtStartup = v);
                      },
                    ),
                  ),
                  if (widget.onRunOnboarding != null)
                    BeeSettingsRow(
                      icon: Icons.auto_awesome_rounded,
                      label: 'Re-run Setup Wizard',
                      description:
                          'Reconfigure your API key, model, and preferences',
                      onTap: widget.onRunOnboarding,
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        size: 14,
                        color: beeTextMuted(context),
                      ),
                    ),
                  if (Platform.isMacOS && _accessibilityGranted == false)
                    BeeSettingsRow(
                      icon: Icons.warning_amber_rounded,
                      label: 'Enable Auto-Paste (Accessibility)',
                      description:
                          'One permission to paste & detect shortcuts. Takes a few seconds.',
                      showDivider: false,
                      trailing: BeeActionChip(
                        label: 'Enable',
                        icon: Icons.open_in_new_rounded,
                        color: beeError(context),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 4,
                        ),
                        onTap: () async {
                          await PermissionOnboardingDialog.show(context);
                          _checkPermissions();
                        },
                      ),
                    ),
                  BeeSettingsRow(
                    icon: Icons.refresh_rounded,
                    label: 'Reset General Settings',
                    description:
                        'Restore hotkey, recording mode, audio device and other preferences to defaults',
                    showDivider: false,
                    onTap: () => _showResetDefaultsDialog(settings),
                    trailing: Icon(
                      Icons.chevron_right_rounded,
                      size: 14,
                      color: beeTextMuted(context),
                    ),
                  ),

                  const SizedBox(height: BeePageHeader.groupGap),

                  // ── ABOUT ──────────────────────────────────────
                  const BeeGroupLabel(label: 'About'),
                  BeeSettingsRow(
                    label: 'Version',
                    icon: Icons.tag_rounded,
                    trailing: AnimatedBuilder(
                      animation: settings,
                      builder: (context, _) {
                        final update = settings.availableUpdate;
                        return Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (update != null) ...[
                              _buildUpdateAvailableChip(),
                              const SizedBox(width: 8),
                            ],
                            Text(
                              _appVersion.isEmpty ? '-' : _appVersion,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: beeText(context),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  BeeSettingsRow(
                    icon: Icons.system_update_rounded,
                    label: 'Check for Updates',
                    description: 'Get the latest version from GitHub',
                    trailing: _isCheckingUpdate
                        ? SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                beeTextMuted(context),
                              ),
                            ),
                          )
                        : Icon(
                            Icons.chevron_right_rounded,
                            size: 14,
                            color: beeTextMuted(context),
                          ),
                    onTap: _isCheckingUpdate ? null : () => _checkForUpdates(),
                  ),
                  BeeSettingsRow(
                    label: 'Platform',
                    icon: Icons.computer_rounded,
                    trailing: Text(
                      '${Platform.operatingSystem[0].toUpperCase()}${Platform.operatingSystem.substring(1)}',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: beeText(context),
                      ),
                    ),
                  ),
                  BeeSettingsRow(
                    label: 'OS Version',
                    icon: Icons.info_outline_rounded,
                    showDivider: false,
                    trailing: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                        Platform.operatingSystemVersion,
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: beeTextSub(context),
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Helpers moved from former hotkeys_page ─────────────────────────

  Widget _hotkeyChip(HotkeyConfig hotkey, VoidCallback onTap) {
    final display = hotkey.displayString;
    if (display.isEmpty) {
      return BeeChip(
        displayValue: Text(
          'Not Set',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: beeTextMuted(context),
            fontStyle: FontStyle.italic,
          ),
        ),
        onTap: onTap,
      );
    }
    return BeeChip(
      displayValue: Row(children: renderKeycaps(display)),
      onTap: onTap,
    );
  }

  void _showHotkeyDialog({
    required String title,
    required HotkeyConfig current,
    required Future<void> Function(HotkeyConfig hotkey) onSave,
    required Future<void> Function() onReset,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: beeSurfaceRaised(context),
        shape: beeDialogShape(),
        title: Text(
          title,
          style: GoogleFonts.spaceGrotesk(
            color: beeText(context),
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        content: SizedBox(
          width: 360,
          child: HotkeyRecorderWidget(
            currentHotkey: current,
            onHotkeyChanged: (hotkey) async {
              await onSave(hotkey);
              if (context.mounted) Navigator.of(context).pop();
            },
            onReset: () async {
              await onReset();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ),
      ),
    );
  }

  String _getDeviceLabel() {
    if (_selectedDeviceId == null) return 'System Default';
    final device = _availableDevices.firstWhere(
      (d) => d.id == _selectedDeviceId,
      orElse: () => InputDevice(id: '', label: ''),
    );
    return device.label.isNotEmpty ? device.label : 'Device Not Found';
  }

  String _formatDuration(int s) {
    final m = s ~/ 60;
    final r = s % 60;
    return m > 0 ? '${m}m ${r}s' : '${s}s';
  }

  void _showResetDefaultsDialog(dynamic settings) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: beeSurfaceRaised(context),
        shape: beeDialogShape(),
        title: Text(
          'Reset General Settings?',
          style: GoogleFonts.spaceGrotesk(
            color: beeText(context),
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        content: Text(
          'This will revert hotkey, recording mode, audio device, '
          'launch-at-login, and duration settings to their defaults.',
          style: GoogleFonts.inter(color: beeTextSub(context), fontSize: 14),
        ),
        actions: [
          TextButton(
            style: beeSecondaryButtonStyle(context),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: beePrimaryButtonStyle(
              context,
              backgroundColor: beeError(context),
              foregroundColor: beeText(context),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    // Reset every shortcut advertised by this dialog, then notify the live
    // registrations so no old secondary binding survives the reset.
    await settings.resetHotkey();
    await settings.resetClipboardPopupHotkey();
    await settings.resetModeSelectionHotkey();
    await settings.setRecordingMode(RecordingMode.toggle);
    await settings.setSelectedAudioDeviceId(null);
    await settings.setLaunchAtStartup(false);
    await settings.setDurationLimitEnabled(false);
    await settings.setDurationLimit(300);

    setState(() {
      _recordingMode = RecordingMode.toggle;
      _selectedDeviceId = null;
      _launchAtStartup = false;
      _durationLimitEnabled = false;
      _durationLimit = 300;
    });

    final resetAllHotkeys = widget.onResetAllHotkeys;
    if (resetAllHotkeys != null) {
      await resetAllHotkeys();
    } else {
      widget.onHotkeyChanged?.call(settings.hotkey);
      widget.onClipboardHotkeyChanged?.call(settings.clipboardPopupHotkey);
      widget.onModeSelectionHotkeyChanged?.call(settings.modeSelectionHotkey);
    }
    widget.onRecordingModeChanged?.call(_recordingMode);
    widget.onAudioDeviceChanged?.call(null);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('General settings reset to defaults'),
          backgroundColor: beeSurfaceHighest(context),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kBeeRadiusMd),
          ),
        ),
      );
    }
  }

  void _showAudioDeviceDialog(dynamic settings) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        backgroundColor: beeSurfaceRaised(context),
        shape: beeDialogShape(),
        title: Text(
          'Audio Input Device',
          style: GoogleFonts.spaceGrotesk(
            color: beeText(context),
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildDeviceOption(
                'System Default',
                null,
                showDivider: _availableDevices.isNotEmpty,
              ),
              if (_availableDevices.isNotEmpty)
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _availableDevices.length,
                    itemBuilder: (_, i) {
                      final d = _availableDevices[i];
                      return _buildDeviceOption(
                        d.label.isNotEmpty ? d.label : 'Device ${i + 1}',
                        d.id,
                        showDivider: i < _availableDevices.length - 1,
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            style: beeSecondaryButtonStyle(context),
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceOption(
    String label,
    String? id, {
    bool showDivider = true,
  }) {
    return BeeRadioTile(
      isSelected: id == _selectedDeviceId,
      label: label,
      onTap: () async {
        await SettingsProviderScope.of(
          context,
        ).settingsService.setSelectedAudioDeviceId(id);
        widget.onAudioDeviceChanged?.call(id);
        if (!mounted) return;
        setState(() => _selectedDeviceId = id);
        Navigator.of(context).pop();
      },
      showDivider: showDivider,
    );
  }

  void _showDurationDialog(dynamic settings) {
    final ctrl = TextEditingController(text: _durationLimit.toString());
    String? error;
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: beeSurfaceRaised(context),
          shape: beeDialogShape(),
          title: Text(
            'Duration Limit',
            style: GoogleFonts.spaceGrotesk(
              color: beeText(context),
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                autofocus: true,
                style: GoogleFonts.inter(color: beeText(context), fontSize: 14),
                decoration: beeInputDecoration(context, label: 'Seconds')
                    .copyWith(
                      suffixText: 'seconds',
                      errorText: error,
                      errorStyle: GoogleFonts.inter(
                        color: beeError(context),
                        fontSize: 12,
                      ),
                    ),
              ),
            ],
          ),
          actions: [
            TextButton(
              style: beeSecondaryButtonStyle(context),
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: beePrimaryButtonStyle(context),
              onPressed: () {
                final v = int.tryParse(ctrl.text);
                if (v == null) {
                  setDialogState(() => error = 'Enter a valid number');
                } else if (v < 5) {
                  setDialogState(() => error = 'Minimum is 5 seconds');
                } else if (v > 3600) {
                  setDialogState(() => error = 'Maximum is 3600 seconds');
                } else {
                  settings.setDurationLimit(v);
                  setState(() => _durationLimit = v);
                  Navigator.of(context).pop();
                }
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
