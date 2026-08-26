import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/system_prompt.dart';
import '../../services/cloud_transcription_service.dart';
import '../../services/settings_service.dart';
import '../mobile_transcription_controller.dart';
import '../widgets/mobile_mode_picker_sheet.dart';
import '../widgets/mobile_record_button.dart';
import '../widgets/mobile_result_card.dart';
import '../widgets/mobile_setup_card.dart';
import 'mobile_history_screen.dart';
import 'mobile_settings_screen.dart';

class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({
    super.key,
    required this.controller,
    required this.settingsService,
    required this.cloudService,
  });

  final MobileTranscriptionController controller;
  final SettingsService settingsService;
  final CloudTranscriptionService cloudService;

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen> {
  MobileTranscriptionController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_refresh);
    widget.settingsService.addListener(_refresh);
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
    widget.settingsService.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _openHistory() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            MobileHistoryScreen(settingsService: widget.settingsService),
      ),
    );
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MobileSettingsScreen(
          settingsService: widget.settingsService,
          cloudService: widget.cloudService,
        ),
      ),
    );
  }

  Future<void> _openModePicker() async {
    final prompts = [
      ...SystemPrompt.availablePrompts,
      ...widget.settingsService.customPrompts,
    ];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => MobileModePickerSheet(
        prompts: prompts,
        selectedPromptId: widget.settingsService.selectedPromptId,
        onSelected: (prompt) =>
            widget.settingsService.setSelectedPromptId(prompt.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final prompt = SystemPrompt.getById(
      widget.settingsService.selectedPromptId,
      customPrompts: widget.settingsService.customPrompts,
    );
    final state = controller.state;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 36,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        'Beeamvo',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const Spacer(),
                      ActionChip(
                        label: Text(prompt.name),
                        onPressed: _openModePicker,
                        avatar: Icon(
                          Icons.tune,
                          size: 16,
                          color: colors.onSurfaceVariant,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      IconButton(
                        tooltip: 'History',
                        onPressed: _openHistory,
                        icon: const Icon(Icons.history),
                      ),
                      IconButton(
                        tooltip: 'Settings',
                        onPressed: _openSettings,
                        icon: const Icon(Icons.settings_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  if (!widget.settingsService.hasCloudCredentials)
                    MobileSetupCard(onSettings: _openSettings)
                  else
                    MobileRecordButton(
                      state: state,
                      duration: controller.duration,
                      amplitude: controller.amplitude,
                      onPressed: controller.toggleRecording,
                      onCancel: controller.isRecording
                          ? controller.cancel
                          : null,
                    ),
                  const SizedBox(height: 32),
                  MobileResultCard(
                    state: state,
                    text: controller.resultText,
                    error: controller.errorMessage,
                    canRetry: controller.canRetry,
                    errorAction: controller.errorAction,
                    onCopy: controller.resultText == null
                        ? null
                        : () => Clipboard.setData(
                            ClipboardData(text: controller.resultText!),
                          ),
                    onClear: controller.clearResult,
                    onRetry: controller.retry,
                    onOpenSettings: _openSettings,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
