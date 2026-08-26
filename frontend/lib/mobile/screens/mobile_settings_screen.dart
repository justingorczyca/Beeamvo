import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../config.dart';
import '../../models/system_prompt.dart';
import '../../services/cloud_transcription_service.dart';
import '../../services/settings_service.dart';

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
    widget.settingsService.addListener(_refresh);
    _load();
  }

  @override
  void dispose() {
    widget.settingsService.removeListener(_refresh);
    _keyController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
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
    if (!mounted) return;
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
      backgroundColor: Theme.of(context).colorScheme.surface,
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
      style: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    ),
  );
}
