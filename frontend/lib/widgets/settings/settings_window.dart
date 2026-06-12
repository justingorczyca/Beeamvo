import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';
import '../../models/hotkey_config.dart';
import '../../providers/settings_provider.dart';
import '../../services/settings_service.dart';
import '../../services/usage_stats_service.dart';
import '../../theme/app_theme.dart';
import 'settings_sidebar.dart';
import 'settings_page_container.dart';
import 'settings_shared.dart';

/// Main settings window for Beeamvo.
class SettingsWindow extends StatefulWidget {
  final SettingsProvider provider;
  final UsageStatsService usageStatsService;
  final VoidCallback onClose;
  final ValueChanged<String>? onModelChanged;
  final ValueChanged<String>? onPromptChanged;
  final ValueChanged<dynamic>? onHotkeyChanged;
  final ValueChanged<HotkeyConfig>? onModeSelectionHotkeyChanged;
  final ValueChanged<dynamic>? onRecordingModeChanged;
  final ValueChanged<HotkeyConfig>? onClipboardHotkeyChanged;
  final ValueChanged<dynamic>? onBackendChanged;
  final Future<void> Function(CloudProvider provider)? onVerifyCloudProvider;
  final VoidCallback? onModelDownloaded;
  final VoidCallback? onRunOnboarding;

  const SettingsWindow({
    super.key,
    required this.provider,
    required this.usageStatsService,
    required this.onClose,
    this.onModelChanged,
    this.onPromptChanged,
    this.onHotkeyChanged,
    this.onModeSelectionHotkeyChanged,
    this.onRecordingModeChanged,
    this.onClipboardHotkeyChanged,
    this.onBackendChanged,
    this.onVerifyCloudProvider,
    this.onModelDownloaded,
    this.onRunOnboarding,
  });

  @override
  State<SettingsWindow> createState() => _SettingsWindowState();
}

class _SettingsWindowState extends State<SettingsWindow> {
  @override
  Widget build(BuildContext context) {
    return SettingsProviderScope(
      provider: widget.provider,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? constraints.maxWidth.clamp(760.0, 1040.0)
              : 980.0;
          final height = constraints.maxHeight.isFinite
              ? constraints.maxHeight.clamp(540.0, 720.0)
              : 640.0;

          return SizedBox(
            width: width,
            height: height,
            child: Material(
              color: Colors.transparent,
                child: Container(
                decoration: beePanelDecoration(
                  color: beeSurface(context),
                  radius: kBeeRadiusXl,
                  borderOpacity: 0.8,
                  shadows: AppTheme.windowShadow,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(kBeeRadiusXl),
                  child: Column(
                    children: [
                      _buildTitleBar(),
                      Expanded(
                        child: Row(
                          children: [
                            const SettingsSidebar(),
                            Expanded(
                              child: SettingsPageContainer(
                                usageStatsService: widget.usageStatsService,
                                onModelChanged: widget.onModelChanged,
                                onPromptChanged: widget.onPromptChanged,
                                onHotkeyChanged: widget.onHotkeyChanged,
                                onModeSelectionHotkeyChanged:
                                    widget.onModeSelectionHotkeyChanged,
                                onRecordingModeChanged:
                                    widget.onRecordingModeChanged,
                                onClipboardHotkeyChanged:
                                    widget.onClipboardHotkeyChanged,
                                onBackendChanged: widget.onBackendChanged,
                                onVerifyCloudProvider:
                                    widget.onVerifyCloudProvider,
                                onModelDownloaded: widget.onModelDownloaded,
                                onRunOnboarding: widget.onRunOnboarding,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildTitleBar() {
    return Container(
      height: 42,
      decoration: BoxDecoration(
        // Title bar is chrome — same tier as the sidebar (one step
        // above content surface). Using the runtime token ensures dark
        // mode renders the title bar in dark graphite instead of the
        // always-light AppTheme.surfaceContainerHigh constant.
        color: beeSidebar(context),
        border: Border(bottom: BorderSide(color: beeDivider(context))),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final showTitle = constraints.maxWidth >= 190;
          final showDragHint = constraints.maxWidth >= 240;
          final sideGap = constraints.maxWidth < 90 ? 8.0 : 14.0;

          return Row(
            children: [
              SizedBox(width: sideGap),
              _buildCloseButton(),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onPanStart: (_) => widget.provider.setDragging(true),
                  onPanEnd: (_) => widget.provider.setDragging(false),
                  onPanCancel: () => widget.provider.setDragging(false),
                  onPanUpdate: (_) async => await windowManager.startDragging(),
                  child: Row(
                    children: [
                      if (showTitle) ...[
                        const SizedBox(width: 16),
                        Container(width: 1, height: 14, color: beeBorder(context)),
                        const SizedBox(width: 14),
                        Flexible(
                          child: Text(
                            'Preferences',
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.spaceGrotesk(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: beeTextSub(context),
                              letterSpacing: -0.1,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: beeYellow(context),
                            boxShadow: [
                              BoxShadow(
                                color: beeYellow(context).withValues(alpha: 0.32),
                                blurRadius: 5,
                              ),
                            ],
                          ),
                        ),
                      ],
                      const Spacer(),
                      if (showDragHint) ...[
                        Row(
                          children: List.generate(
                            6,
                            (_) => Container(
                              width: 2,
                              height: 2,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
  decoration: BoxDecoration(
      shape: BoxShape.circle,
      color: beeTextMuted(context),
    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 14),
                      ] else
                        SizedBox(width: sideGap),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

        Widget _buildCloseButton() {
          return _CloseButton(onClose: widget.onClose);
        }
      }

    /// Close button with proper desktop hover feedback.
    class _CloseButton extends StatefulWidget {
      final VoidCallback onClose;

      const _CloseButton({required this.onClose});

      @override
      State<_CloseButton> createState() => _CloseButtonState();
    }

    class _CloseButtonState extends State<_CloseButton> {
      bool _isHovered = false;

      @override
      Widget build(BuildContext context) {
        return Tooltip(
          message: 'Close preferences',
          child: Semantics(
            button: true,
            label: 'Close preferences',
            onTap: widget.onClose,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              onEnter: (_) => setState(() => _isHovered = true),
              onExit: (_) => setState(() => _isHovered = false),
              child: Focus(
                child: Shortcuts(
                  shortcuts: const <ShortcutActivator, Intent>{
                    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
                  },
                  child: Actions(
                    actions: <Type, Action<Intent>>{
                      ActivateIntent: CallbackAction<ActivateIntent>(
                        onInvoke: (_) {
                          widget.onClose();
                          return null;
                        },
                      ),
                    },
                    child: GestureDetector(
                      excludeFromSemantics: true,
                      behavior: HitTestBehavior.opaque,
                      onTap: widget.onClose,
                      child: SizedBox(
                        width: 32,
                        height: 32,
                        child: Center(
                          child: AnimatedContainer(
                            duration: kBeeTransitionDuration,
                            curve: kBeeTransitionCurve,
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: _isHovered
                                  ? beeError(context).withValues(alpha: 0.10)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(kBeeRadiusXs),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.close_rounded,
                                size: 13,
                                color: _isHovered ? beeError(context) : beeTextMuted(context),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
