import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config.dart';
import '../models/clipboard_history_entry.dart';
import '../models/system_prompt.dart';
import '../services/cloud_transcription_service.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import 'mobile_transcription_controller.dart';

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
  }

  @override
  void dispose() {
    controller.removeListener(_refresh);
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
    if (mounted) setState(() {});
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
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final state = controller.state;
    return Scaffold(
      backgroundColor: AppTheme.surfaceBase,
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
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const Spacer(),
                      Chip(
                        label: const Text('Cloud'),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: AppTheme.neutral200,
                        side: BorderSide.none,
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
                    _SetupCard(onSettings: _openSettings)
                  else
                    _RecordButton(
                      state: state,
                      duration: controller.duration,
                      amplitude: controller.amplitude,
                      onPressed: controller.toggleRecording,
                      onCancel: controller.isRecording
                          ? controller.cancel
                          : null,
                    ),
                  const SizedBox(height: 32),
                  _ResultCard(
                    state: state,
                    text: controller.resultText,
                    error: controller.errorMessage,
                    onCopy: controller.resultText == null
                        ? null
                        : () => Clipboard.setData(
                            ClipboardData(text: controller.resultText!),
                          ),
                    onClear: controller.clearResult,
                    onRetry: controller.retry,
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

class _SetupCard extends StatelessWidget {
  const _SetupCard({required this.onSettings});
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    color: AppTheme.neutral0,
    shape: RoundedRectangleBorder(
      side: const BorderSide(color: AppTheme.border),
      borderRadius: BorderRadius.circular(AppTheme.radiusLg),
    ),
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        children: [
          const Icon(Icons.key_outlined, size: 34),
          const SizedBox(height: 12),
          const Text(
            'Add a cloud API key to start',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          const Text(
            'Your key is stored securely on this device.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: onSettings,
            child: const Text('Open settings'),
          ),
        ],
      ),
    ),
  );
}

class _RecordButton extends StatelessWidget {
  const _RecordButton({
    required this.state,
    required this.duration,
    required this.amplitude,
    required this.onPressed,
    this.onCancel,
  });

  final MobileTranscriptionState state;
  final Duration duration;
  final double amplitude;
  final VoidCallback onPressed;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final recording = state == MobileTranscriptionState.recording;
    final processing = state == MobileTranscriptionState.processing;
    final success = state == MobileTranscriptionState.success;
    final icon = processing
        ? const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          )
        : Icon(
            success
                ? Icons.check
                : recording
                ? Icons.stop
                : Icons.mic_none,
            size: 34,
          );
    return Column(
      children: [
        SizedBox(
          width: 116,
          height: 116,
          child: Stack(
            alignment: Alignment.center,
            children: [
              if (recording)
                SizedBox(
                  width: 116 + amplitude * 12,
                  height: 116 + amplitude * 12,
                  child: CircularProgressIndicator(
                    value: null,
                    strokeWidth: 3,
                    color: AppTheme.neutral600,
                  ),
                ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: SizedBox(
                  key: ValueKey(state),
                  width: 96,
                  height: 96,
                  child: OutlinedButton(
                    onPressed: processing ? null : onPressed,
                    style: OutlinedButton.styleFrom(
                      shape: const CircleBorder(),
                      side: BorderSide(
                        color: recording
                            ? AppTheme.neutral900
                            : AppTheme.border,
                        width: 2,
                      ),
                      backgroundColor: recording
                          ? AppTheme.neutral900
                          : AppTheme.neutral0,
                      foregroundColor: recording
                          ? AppTheme.neutral0
                          : AppTheme.neutral900,
                    ),
                    child: icon,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (recording)
          Text(_formatDuration(duration))
        else if (processing)
          const Text('Transcribing…')
        else if (success)
          const Text('Copied to clipboard'),
        if (recording && onCancel != null)
          TextButton(onPressed: onCancel, child: const Text('Cancel')),
      ],
    );
  }

  String _formatDuration(Duration value) =>
      '${value.inMinutes.remainder(60).toString().padLeft(2, '0')}:'
      '${value.inSeconds.remainder(60).toString().padLeft(2, '0')}';
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
    required this.state,
    required this.text,
    required this.error,
    required this.onCopy,
    required this.onClear,
    required this.onRetry,
  });

  final MobileTranscriptionState state;
  final String? text;
  final String? error;
  final VoidCallback? onCopy;
  final VoidCallback onClear;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (text == null && error == null) {
      return const SizedBox(height: 100);
    }
    final isError = state == MobileTranscriptionState.error;
    return Card(
      elevation: 0,
      color: AppTheme.neutral0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: isError ? AppTheme.error : AppTheme.border),
        borderRadius: BorderRadius.circular(AppTheme.radiusLg),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isError ? error! : text!,
              maxLines: 7,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, height: 1.35),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: isError
                  ? [TextButton(onPressed: onRetry, child: const Text('Retry'))]
                  : [
                      TextButton(onPressed: onCopy, child: const Text('Copy')),
                      TextButton(
                        onPressed: onClear,
                        child: const Text('Clear'),
                      ),
                    ],
            ),
          ],
        ),
      ),
    );
  }
}

class MobileHistoryScreen extends StatefulWidget {
  const MobileHistoryScreen({super.key, required this.settingsService});
  final SettingsService settingsService;

  @override
  State<MobileHistoryScreen> createState() => _MobileHistoryScreenState();
}

class _MobileHistoryScreenState extends State<MobileHistoryScreen> {
  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Copied to clipboard')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.settingsService.clipboardHistory;
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: [
          if (entries.isNotEmpty)
            PopupMenuButton<String>(
              onSelected: (_) async {
                await widget.settingsService.clearClipboardHistory();
                if (mounted) setState(() {});
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'clear', child: Text('Clear all')),
              ],
            ),
        ],
      ),
      body: entries.isEmpty
          ? const Center(child: Text('No transcriptions yet'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final entry = entries[index];
                return _HistoryTile(
                  entry: entry,
                  onCopy: () => _copy(entry.text),
                  onPin: () async {
                    await widget.settingsService.setClipboardEntryPinned(
                      entry.id,
                      !entry.isPinned,
                    );
                    if (mounted) setState(() {});
                  },
                  onDelete: () async {
                    await widget.settingsService.removeClipboardEntry(entry.id);
                    if (mounted) setState(() {});
                  },
                );
              },
            ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.entry,
    required this.onCopy,
    required this.onPin,
    required this.onDelete,
  });
  final ClipboardHistoryEntry entry;
  final VoidCallback onCopy;
  final VoidCallback onPin;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: ListTile(
      onTap: onCopy,
      title: Text(entry.text, maxLines: 3, overflow: TextOverflow.ellipsis),
      subtitle: Text('${entry.createdAt.toLocal()}'.split('.').first),
      trailing: PopupMenuButton<String>(
        onSelected: (value) {
          if (value == 'pin') onPin();
          if (value == 'delete') onDelete();
        },
        itemBuilder: (_) => [
          PopupMenuItem(
            value: 'pin',
            child: Text(entry.isPinned ? 'Unpin' : 'Pin'),
          ),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    ),
  );
}

class MobileSettingsScreen extends StatefulWidget {
  const MobileSettingsScreen({
    super.key,
    required this.settingsService,
    required this.cloudService,
    this.packageInfoLoader,
  });
  final SettingsService settingsService;
  final CloudTranscriptionService cloudService;
  final Future<PackageInfo> Function()? packageInfoLoader;

  @override
  State<MobileSettingsScreen> createState() => _MobileSettingsScreenState();
}

class _MobileSettingsScreenState extends State<MobileSettingsScreen> {
  final _keyController = TextEditingController();
  String? _storedKey;
  String? _message;
  bool _busy = true;
  bool _verifying = false;
  String? _version;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final key = await widget.settingsService.readGeminiApiKey();
    final packageInfo = widget.packageInfoLoader == null
        ? await PackageInfo.fromPlatform()
        : await widget.packageInfoLoader!();
    if (!mounted) return;
    setState(() {
      _storedKey = key;
      _version = packageInfo.version;
      _busy = false;
    });
  }

  Future<void> _saveKey() async {
    final value = _keyController.text.trim();
    if (value.isEmpty) return;
    setState(() => _message = null);
    await widget.settingsService.setGeminiApiKey(value);
    _keyController.clear();
    setState(() {
      _storedKey = value;
      _message = 'API key saved securely.';
    });
  }

  Future<void> _verify() async {
    setState(() {
      _verifying = true;
      _message = null;
    });
    try {
      await widget.cloudService.verifyProvider(CloudProvider.geminiApiKey);
      if (mounted) setState(() => _message = 'API key verified.');
    } catch (error) {
      if (mounted) setState(() => _message = 'Verification failed: $error');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _removeKey() async {
    await widget.settingsService.clearGeminiApiKey();
    if (mounted) setState(() => _storedKey = null);
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final settings = widget.settingsService;
    final prompts = [
      ...SystemPrompt.availablePrompts,
      ...settings.customPrompts,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const _SectionTitle('Cloud access'),
            if (_storedKey != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Gemini API key'),
                subtitle: Text(_mask(_storedKey!)),
                trailing: Wrap(
                  children: [
                    IconButton(
                      tooltip: 'Verify',
                      onPressed: _verifying ? null : _verify,
                      icon: _verifying
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.verified_outlined),
                    ),
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: _removeKey,
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: _keyController,
              obscureText: true,
              decoration: InputDecoration(
                labelText: _storedKey == null
                    ? 'Gemini API key'
                    : 'Replace API key',
                suffixIcon: IconButton(
                  onPressed: _saveKey,
                  icon: const Icon(Icons.save_outlined),
                ),
              ),
              onSubmitted: (_) => _saveKey(),
            ),
            if (_message != null) ...[
              const SizedBox(height: 8),
              Text(_message!),
            ],
            const SizedBox(height: 20),
            const _SectionTitle('Gemini API surface'),
            SegmentedButton<GeminiApiSurface>(
              segments: GeminiApiSurface.values
                  .map(
                    (surface) => ButtonSegment(
                      value: surface,
                      label: Text(
                        surface == GeminiApiSurface.interactions
                            ? 'Interactions'
                            : 'Legacy',
                      ),
                    ),
                  )
                  .toList(),
              selected: {settings.geminiApiSurface},
              onSelectionChanged: (selected) =>
                  settings.setGeminiApiSurface(selected.first),
            ),
            const SizedBox(height: 20),
            const _SectionTitle('Model'),
            DropdownButtonFormField<String>(
              initialValue: settings.selectedModelId,
              items: AppConfig.availableModels
                  .map(
                    (model) => DropdownMenuItem(
                      value: model.id,
                      child: Text(model.displayName),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) settings.setSelectedModelId(value);
              },
              decoration: const InputDecoration(labelText: 'Model'),
            ),
            const SizedBox(height: 20),
            const _SectionTitle('Mode'),
            DropdownButtonFormField<String>(
              initialValue: settings.selectedPromptId,
              items: prompts
                  .map(
                    (prompt) => DropdownMenuItem(
                      value: prompt.id,
                      child: Text(prompt.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                if (value != null) settings.setSelectedPromptId(value);
              },
              decoration: const InputDecoration(labelText: 'Prompt'),
            ),
            const SizedBox(height: 20),
            const _SectionTitle('Appearance'),
            DropdownButtonFormField<String>(
              initialValue: settings.themeMode,
              items: const [
                DropdownMenuItem(value: 'system', child: Text('System')),
                DropdownMenuItem(value: 'light', child: Text('Light')),
                DropdownMenuItem(value: 'dark', child: Text('Dark')),
              ],
              onChanged: (value) {
                if (value != null) settings.setThemeMode(value);
              },
              decoration: const InputDecoration(labelText: 'Theme'),
            ),
            const SizedBox(height: 20),
            const _SectionTitle('About'),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Beeamvo'),
              subtitle: Text(_version ?? 'unknown'),
            ),
            const Text(
              'Offline Whisper transcription is available on desktop only.',
            ),
          ],
        ),
      ),
    );
  }

  String _mask(String value) => value.length <= 4
      ? '••••'
      : '••••••••${value.substring(value.length - 4)}';
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
    ),
  );
}
