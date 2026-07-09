import 'package:flutter/material.dart';
import '../../models/hotkey_config.dart';
import '../../providers/settings_provider.dart';
import '../../services/settings_service.dart';
import '../../services/usage_stats_service.dart';
import 'pages/home_dashboard_page.dart';
import 'pages/general_settings_page.dart';
import 'pages/ai_models_page.dart';
import 'pages/prompts_page.dart';
import 'pages/clipboard_page.dart';
import 'pages/troubleshooting_page.dart';

/// Container that displays the appropriate settings page based on selected category
class SettingsPageContainer extends StatelessWidget {
  final UsageStatsService usageStatsService;
  final ValueChanged<String>? onModelChanged;
  final ValueChanged<String>? onPromptChanged;
  final ValueChanged<dynamic>? onHotkeyChanged;
  final ValueChanged<HotkeyConfig>? onModeSelectionHotkeyChanged;
  final ValueChanged<dynamic>? onRecordingModeChanged;
  final ValueChanged<String?>? onAudioDeviceChanged;
  final Future<void> Function()? onResetAllHotkeys;
  final ValueChanged<HotkeyConfig>? onClipboardHotkeyChanged;
  final ValueChanged<dynamic>? onBackendChanged;
  final Future<void> Function(CloudProvider provider)? onVerifyCloudProvider;
  final VoidCallback? onModelDownloaded;
  final VoidCallback? onRunOnboarding;

  const SettingsPageContainer({
    super.key,
    required this.usageStatsService,
    this.onModelChanged,
    this.onPromptChanged,
    this.onHotkeyChanged,
    this.onModeSelectionHotkeyChanged,
    this.onRecordingModeChanged,
    this.onAudioDeviceChanged,
    this.onResetAllHotkeys,
    this.onClipboardHotkeyChanged,
    this.onBackendChanged,
    this.onVerifyCloudProvider,
    this.onModelDownloaded,
    this.onRunOnboarding,
  });

  @override
  Widget build(BuildContext context) {
    final provider = SettingsProviderScope.of(context);

    return AnimatedBuilder(
      animation: provider,
      builder: (context, child) {
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 160),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          layoutBuilder: (currentChild, previousChildren) {
            return Stack(
              fit: StackFit.expand,
              alignment: Alignment.topLeft,
              children: [
                ...previousChildren,
                if (currentChild != null) currentChild,
              ],
            );
          },
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(opacity: animation, child: child);
          },
          child: _buildPage(provider.selectedCategory),
        );
      },
    );
  }

  Widget _buildPage(SettingsCategory category) {
    switch (category) {
      case SettingsCategory.home:
        return HomeDashboardPage(
          key: const ValueKey('home'),
          statsService: usageStatsService,
        );
      case SettingsCategory.general:
        return GeneralSettingsPage(
          key: const ValueKey('general'),
          onHotkeyChanged: onHotkeyChanged,
          onModeSelectionHotkeyChanged: onModeSelectionHotkeyChanged,
          onClipboardHotkeyChanged: onClipboardHotkeyChanged,
          onRecordingModeChanged: onRecordingModeChanged,
          onAudioDeviceChanged: onAudioDeviceChanged,
          onResetAllHotkeys: onResetAllHotkeys,
          onRunOnboarding: onRunOnboarding,
        );
      case SettingsCategory.aiModels:
        return AiModelsPage(
          key: const ValueKey('ai_models'),
          onModelChanged: onModelChanged,
          onBackendChanged: onBackendChanged,
          onVerifyCloudProvider: onVerifyCloudProvider,
          onModelDownloaded: onModelDownloaded,
        );
      case SettingsCategory.prompts:
        return PromptsPage(
          key: const ValueKey('prompts'),
          onPromptChanged: onPromptChanged,
        );
      case SettingsCategory.clipboard:
        return const ClipboardPage(key: ValueKey('clipboard'));
      case SettingsCategory.troubleshooting:
        return const TroubleshootingPage(key: ValueKey('troubleshooting'));
    }
  }
}
