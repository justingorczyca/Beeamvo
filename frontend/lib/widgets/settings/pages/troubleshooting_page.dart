import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../providers/settings_provider.dart';
import '../../../services/keyboard_service.dart';
import '../../../services/recording_service.dart';
import '../../../services/settings_service.dart';
import '../../../services/whisper_service.dart';
import '../settings_shared.dart';

class TroubleshootingPage extends StatefulWidget {
  const TroubleshootingPage({super.key});

  @override
  State<TroubleshootingPage> createState() => _TroubleshootingPageState();
}

class _TroubleshootingPageState extends State<TroubleshootingPage> {
  bool? _accessibilityGranted;
  bool? _automationGranted;
  String _appVersion = '';
  bool _isResetting = false;
  bool _diagnosticsStarted = false;
  bool _diagnosticsLoading = false;
  DateTime? _diagnosticsUpdatedAt;
  List<_DiagnosticItem> _diagnostics = const [];

  @override
  void initState() {
    super.initState();
    _loadInfo();
    if (Platform.isMacOS) _checkPermissions();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_diagnosticsStarted) {
      _diagnosticsStarted = true;
      _runDiagnostics();
    }
  }

  Future<void> _loadInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() {
      _appVersion = '${info.version}+${info.buildNumber}';
    });
  }

  Future<void> _checkPermissions() async {
    final keyboardService = KeyboardService();
    final accessibility = await keyboardService.checkAccessibilityPermissions();
    final automation = await keyboardService.checkAutomationPermissions();
    if (mounted) {
      setState(() {
        _accessibilityGranted = accessibility;
        _automationGranted = automation;
      });
    }
  }

  Future<void> _runDiagnostics() async {
    final settings = SettingsProviderScope.of(context).settingsService;
    setState(() => _diagnosticsLoading = true);

    final items = <_DiagnosticItem>[
      _platformDiagnostic(),
      _backendDiagnostic(settings),
      _clipboardDiagnostic(settings),
    ];

    await _appendMacOSPermissionDiagnostics(items);
    await _appendMicrophoneDiagnostics(items);

    if (!mounted) return;
    setState(() {
      _diagnostics = items;
      _diagnosticsUpdatedAt = DateTime.now();
      _diagnosticsLoading = false;
    });
  }

  Future<void> _resetPermissions() async {
    if (!Platform.isMacOS) return;

    setState(() => _isResetting = true);
    try {
      await Process.run('tccutil', ['reset', 'Accessibility']);
      await Process.run('tccutil', ['reset', 'AppleEvents']);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Permissions reset. Restart Beeamvo to grant access again.',
            ),
            backgroundColor: beeSurfaceHighest(context),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kBeeRadiusMd),
            ),
          ),
        );
        await _checkPermissions();
        await _runDiagnostics();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reset failed: $e'),
            backgroundColor: beeError(context),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kBeeRadiusMd),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isResetting = false);
    }
  }

  Future<void> _confirmResetPermissions() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: beeSurfaceRaised(context),
        shape: beeDialogShape(),
        title: Text(
          'Reset macOS Permissions?',
          style: GoogleFonts.spaceGrotesk(
            color: beeText(context),
            fontWeight: FontWeight.w700,
            fontSize: 17,
          ),
        ),
        content: Text(
          'This revokes Accessibility and Automation permission for Beeamvo. '
          'You will need to restart the app and grant access again.',
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

    if (confirmed == true) {
      await _resetPermissions();
    }
  }

  _DiagnosticItem _platformDiagnostic() {
    return _DiagnosticItem(
      label: 'Platform',
      detail:
          '${_platformLabel()} - ${Platform.operatingSystemVersion.split('\n').first}',
      icon: Icons.computer_rounded,
      status: _DiagnosticStatus.good,
    );
  }

  _DiagnosticItem _backendDiagnostic(SettingsService settings) {
    if (settings.transcriptionBackend == TranscriptionBackend.whisper) {
      final modelId = settings.whisperModelId;
      final exists = WhisperService.modelExistsAtPath(modelId);
      return _DiagnosticItem(
        label: 'Offline model',
        detail: exists
            ? '$modelId is downloaded'
            : '$modelId is not downloaded',
        icon: Icons.graphic_eq_rounded,
        status: exists ? _DiagnosticStatus.good : _DiagnosticStatus.warning,
      );
    }

    final provider = settings.cloudProvider;
    final configured = provider == CloudProvider.geminiApiKey
        ? settings.hasGeminiApiKey
        : settings.vertexProjectId != null;
    return _DiagnosticItem(
      label: 'Cloud transcription',
      detail: configured
          ? '${provider.displayName} is configured'
          : '${provider.displayName} needs credentials',
      icon: Icons.cloud_queue_rounded,
      status: configured ? _DiagnosticStatus.good : _DiagnosticStatus.warning,
    );
  }

  _DiagnosticItem _clipboardDiagnostic(SettingsService settings) {
    if (!settings.clipboardHistoryEnabled) {
      return const _DiagnosticItem(
        label: 'Clipboard history',
        detail: 'History is disabled',
        icon: Icons.history_toggle_off_rounded,
        status: _DiagnosticStatus.warning,
      );
    }

    return _DiagnosticItem(
      label: 'Clipboard history',
      detail: settings.clipboardWatcherEnabled
          ? 'History and clipboard watcher are enabled'
          : 'History is enabled; system clipboard watcher is off',
      icon: Icons.content_paste_search_rounded,
      status: settings.clipboardWatcherEnabled
          ? _DiagnosticStatus.good
          : _DiagnosticStatus.neutral,
    );
  }

  Future<void> _appendMacOSPermissionDiagnostics(
    List<_DiagnosticItem> items,
  ) async {
    if (!Platform.isMacOS) return;

    final keyboardService = KeyboardService();
    final accessibility =
        _accessibilityGranted ??
        await keyboardService.checkAccessibilityPermissions();
    final automation =
        _automationGranted ??
        await keyboardService.checkAutomationPermissions();

    items.add(
      _DiagnosticItem(
        label: 'Accessibility permission',
        detail: accessibility ? 'Granted' : 'Required for global hotkeys',
        icon: accessibility
            ? Icons.check_circle_outline_rounded
            : Icons.warning_amber_rounded,
        status: accessibility
            ? _DiagnosticStatus.good
            : _DiagnosticStatus.error,
      ),
    );
    items.add(
      _DiagnosticItem(
        label: 'Automation permission',
        detail: automation ? 'Granted' : 'Required for automatic paste',
        icon: automation
            ? Icons.check_circle_outline_rounded
            : Icons.warning_amber_rounded,
        status: automation ? _DiagnosticStatus.good : _DiagnosticStatus.warning,
      ),
    );
  }

  Future<void> _appendMicrophoneDiagnostics(List<_DiagnosticItem> items) async {
    final recordingService = RecordingService();
    try {
      final hasPermission = await recordingService.hasPermission();
      final devices = await recordingService.listInputDevices();
      items.add(
        _DiagnosticItem(
          label: 'Microphone',
          detail: hasPermission
              ? '${devices.length} input ${devices.length == 1 ? 'device' : 'devices'} available'
              : 'Microphone permission is not granted',
          icon: hasPermission ? Icons.mic_none_rounded : Icons.mic_off_rounded,
          status: hasPermission
              ? _DiagnosticStatus.good
              : _DiagnosticStatus.error,
        ),
      );
    } catch (e) {
      items.add(
        _DiagnosticItem(
          label: 'Microphone',
          detail: 'Could not read recorder status: $e',
          icon: Icons.mic_off_rounded,
          status: _DiagnosticStatus.warning,
        ),
      );
    } finally {
      await recordingService.dispose();
    }
  }

  String _platformLabel() {
    final os = Platform.operatingSystem;
    if (os.isEmpty) return 'Unknown';
    return '${os[0].toUpperCase()}${os.substring(1)}';
  }

  String _updatedLabel() {
    final updatedAt = _diagnosticsUpdatedAt;
    if (updatedAt == null) return 'Not checked yet';
    final age = DateTime.now().difference(updatedAt);
    if (age.inMinutes < 1) return 'Updated just now';
    if (age.inHours < 1) return 'Updated ${age.inMinutes}m ago';
    return 'Updated ${age.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: Container(
            color: beeSurface(context),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(28, 24, 28, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Permissions (macOS only) ──────────────────
                  if (Platform.isMacOS) ...[
                    const BeeGroupLabel(label: 'Permissions'),
                    _buildPermRow(
                      'Accessibility',
                      'Required to detect global hotkeys',
                      _accessibilityGranted,
                      () => KeyboardService().openAccessibilitySettings(),
                    ),
                    _buildPermRow(
                      'Automation',
                      'Required to paste text automatically',
                      _automationGranted,
                      () => KeyboardService().openAutomationSettings(),
                      isLast: true,
                    ),
                    const SizedBox(height: 28),
                  ],

                  // ── Permissions (Windows) ─────────────────────
                  if (Platform.isWindows) ...[
                    const BeeGroupLabel(label: 'Permissions'),
                    _buildInfoBox(
                      icon: Icons.shield_outlined,
                      text:
                          'Beeamvo requires microphone access. When you first record, Windows will prompt you. '
                          'If recording fails, go to Settings > Privacy & security > Microphone and ensure '
                          '"Let desktop apps access your microphone" is enabled.',
                    ),
                    const SizedBox(height: 28),
                  ],

                  // ── Permissions (Linux) ──────────────────────
                  if (Platform.isLinux) ...[
                    const BeeGroupLabel(label: 'Requirements'),
                    _buildInfoBox(
                      icon: Icons.shield_outlined,
                      text:
                          'Beeamvo requires microphone access via PulseAudio/PipeWire. '
                          'For auto-paste, install xdotool (X11) or wtype (Wayland):\n'
                          '  sudo apt install xdotool\n'
                          'If auto-paste fails, text is still copied to your clipboard.',
                    ),
                    const SizedBox(height: 28),
                  ],

                  // ── Live Diagnostics ──────────────────────────
                  const BeeGroupLabel(label: 'Live Diagnostics'),
                  _buildDiagnosticsPanel(),
                  const SizedBox(height: 28),

                  // ── FAQ ───────────────────────────────────────
                  const BeeGroupLabel(label: 'Frequently Asked Questions'),
                  _buildFaq(
                    'How do I start recording?',
                    'Press your global hotkey (default: Ctrl + Shift + V). '
                        'In Toggle mode, press once to start and again to stop. '
                        'In Hold mode, hold the hotkey down and release when done.',
                  ),
                  _buildFaq(
                    'My hotkey is not working',
                    Platform.isWindows
                        ? 'Some apps (games, fullscreen apps, or apps with elevated privileges) may intercept '
                              'the hotkey before Beeamvo receives it. Try a different key combination in '
                              'Settings > General > Hotkey. If using an RDP or virtual machine, '
                              'global hotkeys may not pass through.'
                        : Platform.isLinux
                        ? 'On X11, global hotkeys should work out of the box. On Wayland, some compositors '
                              'may not support global hotkey capture. Try a different key combination in '
                              'Settings > General > Hotkey. If using a virtual machine, global hotkeys '
                              'may not pass through.'
                        : 'Grant Accessibility permission in System Settings > Privacy & Security > Accessibility. '
                              'If running from Terminal or VS Code, grant the permission to the parent app as well. '
                              'Try a different key combination in Settings > General > Hotkey.',
                  ),
                  _buildFaq(
                    'Text is not pasting into my app',
                    'Beeamvo copies text to your clipboard and simulates Ctrl+V (Cmd+V on macOS). '
                        'Some apps block simulated paste events. If paste fails, the text will still be '
                        'on your clipboard — just press Ctrl+V manually.\n\n'
                        'On macOS, ensure Automation permission is granted for the target application.',
                  ),
                  _buildFaq(
                    'Recording produces no transcription',
                    'Verify your microphone is working in your system sound settings. '
                        'If using Cloud backend, check that your API key is valid in Settings > AI Models. '
                        'If using Offline (Whisper), make sure the model has been downloaded — '
                        'go to Settings > AI Models and click Download next to the model.',
                  ),
                  _buildFaq(
                    'How does the offline (Whisper) backend work?',
                    'Beeamvo uses whisper.cpp for local, offline transcription. '
                        'It runs entirely on your device — no data is sent to the cloud. '
                        'You need to download a model file first (Settings > AI Models). '
                        'Larger models are more accurate but slower and use more RAM.',
                  ),
                  _buildFaq(
                    'Can I use Beeamvo with multiple monitors?',
                    'Yes. The recording orb appears at the bottom-center of whichever monitor '
                        'your active window is on. The orb uses a transparent, always-on-top window '
                        'so it stays visible over your workspace.',
                  ),
                  _buildFaq(
                    'How do I change the recording mode?',
                    'Go to Settings > General > Recording Mode. Toggle mode starts/stops '
                        'with a single press. Hold mode records while the key is held down.',
                  ),
                  _buildFaq(
                    'Where are my settings stored?',
                    'Settings are saved to a JSON file in your OS application data directory. '
                        'On Windows: %APPDATA%\\Beeamvo. On macOS: ~/Library/Application Support/Beeamvo. '
                        'On Linux: ~/.local/share/Beeamvo (or \$XDG_DATA_HOME/Beeamvo).',
                  ),

                  // ── Reset (macOS only) ────────────────────────
                  if (Platform.isMacOS) ...[
                    const SizedBox(height: 28),
                    const BeeGroupLabel(label: 'Reset'),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            size: 14,
                            color: beeYellow(context),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Resetting permissions will revoke all macOS access. You will need to re-grant them after restarting the app.',
                              style: GoogleFonts.inter(
                                fontSize: 11.5,
                                color: beeTextSub(context),
                                height: 1.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: BeeActionChip(
                        label: _isResetting
                            ? 'Resetting...'
                            : 'Reset All Permissions',
                        icon: _isResetting
                            ? null
                            : Icons.refresh_rounded,
                        color: beeError(context),
                        onTap: _isResetting ? null : _confirmResetPermissions,
                      ),
                    ),
                  ],

                                  // ── App Info moved to General → About ───────────
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  }

  void _copyDiagnostics() {
    final buffer = StringBuffer();
    buffer.writeln('Beeamvo Diagnostics');
    buffer.writeln('Generated: ${DateTime.now().toLocal()}');
    buffer.writeln('Version: $_appVersion');
    buffer.writeln(
      'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion.split('\n').first}',
    );
    buffer.writeln();
    for (final item in _diagnostics) {
      final statusLabel = switch (item.status) {
        _DiagnosticStatus.good => 'OK',
        _DiagnosticStatus.warning => 'WARNING',
        _DiagnosticStatus.error => 'ERROR',
        _DiagnosticStatus.neutral => 'INFO',
      };
      buffer.writeln('[$statusLabel] ${item.label}: ${item.detail}');
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Diagnostics copied to clipboard'),
        backgroundColor: beeSurfaceHighest(context),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kBeeRadiusMd),
        ),
      ),
    );
  }

  Widget _buildDiagnosticsPanel() {
    final items = _diagnostics;

    // Flat container — no bordered card. Header row + thin dividers between
    // diagnostic rows is enough visual structure on its own.
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _updatedLabel(),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: beeTextMuted(context),
                  ),
                ),
              ),
              if (_diagnostics.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: Tooltip(
                    message: 'Copy diagnostics to clipboard',
                    child: IconButton(
                      icon: Icon(
                        Icons.copy_rounded,
                        size: 15,
                        color: beeTextMuted(context),
                      ),
                      onPressed: _copyDiagnostics,
                      padding: EdgeInsets.zero,
                      splashRadius: 15,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                    ),
                  ),
                ),
              if (_diagnosticsLoading)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    valueColor: AlwaysStoppedAnimation(beeTextSub(context)),
                  ),
                )
              else
                Tooltip(
                  message: 'Refresh diagnostics',
                  child: IconButton(
                    icon: Icon(
                      Icons.refresh_rounded,
                      size: 15,
                      color: beeTextMuted(context),
                    ),
                    onPressed: _runDiagnostics,
                    padding: EdgeInsets.zero,
                    splashRadius: 15,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          if (items.isEmpty && _diagnosticsLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                'Checking current app status...',
                style: GoogleFonts.inter(fontSize: 12, color: beeTextSub(context)),
              ),
            )
          else
            ...items.map(_buildDiagnosticRow),
        ],
      ),
    );
  }

  Widget _buildDiagnosticRow(_DiagnosticItem item) {
    final color = _diagnosticColor(context, item.status);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 9),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: beeDivider(context).withValues(alpha: 0.55)),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status indicator — just a colored dot, no boxed icon.
          Padding(
            padding: const EdgeInsets.only(top: 5),
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: beeText(context),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.detail,
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: beeTextSub(context),
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _diagnosticColor(BuildContext context, _DiagnosticStatus status) {
    switch (status) {
      case _DiagnosticStatus.good:
        return beeSuccess(context);
      case _DiagnosticStatus.warning:
        return beeYellow(context);
      case _DiagnosticStatus.error:
        return beeError(context);
      case _DiagnosticStatus.neutral:
        return beeTextMuted(context);
    }
  }

  Widget _buildInfoBox({required IconData icon, required String text}) {
    // Plain text paragraph with a small leading icon — no bordered card.
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 13, color: beeTextMuted(context)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: GoogleFonts.inter(
                fontSize: 11.5,
                color: beeTextSub(context),
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermRow(
    String label,
    String description,
    bool? granted,
    VoidCallback onGrant, {
    bool isLast = false,
  }) {
    final color = granted == null
        ? beeTextMuted(context)
        : granted
        ? beeSuccess(context)
        : beeError(context);
    return BeeSettingsRow(
      icon: granted == null
          ? Icons.pending_outlined
          : granted
          ? Icons.check_circle_outline_rounded
          : Icons.warning_amber_rounded,
      label: label,
      description: description,
      showDivider: !isLast,
      trailing: granted == null
          ? SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                valueColor: AlwaysStoppedAnimation(beeTextMuted(context)),
              ),
            )
          : BeeActionChip(
              label: granted ? 'Granted' : 'Grant',
              icon: granted ? null : Icons.open_in_new_rounded,
              color: color,
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              onTap: granted ? null : onGrant,
            ),
    );
  }

  Widget _buildFaq(String question, String answer) {
    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        hoverColor: Colors.transparent,
      ),
      child: ExpansionTile(
        backgroundColor: Colors.transparent,
        collapsedBackgroundColor: Colors.transparent,
        tilePadding: const EdgeInsets.symmetric(horizontal: 4),
        childrenPadding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
        title: Text(
          question,
          style: GoogleFonts.inter(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: beeText(context),
          ),
        ),
        iconColor: beeTextMuted(context),
        collapsedIconColor: beeTextMuted(context),
        children: [
          // Flat answer text — no bordered card. Indented under the title.
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 4, 12),
            child: Text(
              answer,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: beeTextSub(context),
                height: 1.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _DiagnosticStatus { good, warning, error, neutral }

class _DiagnosticItem {
  final String label;
  final String detail;
  final IconData icon;
  final _DiagnosticStatus status;

  const _DiagnosticItem({
    required this.label,
    required this.detail,
    required this.icon,
    required this.status,
  });
}
