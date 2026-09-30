import 'dart:async';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../config.dart';
import '../../services/codex_oauth_manager.dart';
import '../../widgets/settings/first_pass_settings.dart';
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
  bool _signingIn = false;
  CodexOAuthFlow? _codexFlow;
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
    unawaited(_codexFlow?.cancel() ?? Future<void>.value());
    _keyController.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final key = await _readCredential();
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
    final isVertex =
        widget.settingsService.cloudProvider == CloudProvider.vertexAi;
    if (isVertex) {
      await widget.settingsService.setVertexProjectId(value);
    } else {
      await widget.settingsService.setGeminiApiKey(value);
    }
    _keyController.clear();
    if (!mounted) return;
    setState(() {
      _storedKey = value;
      _message = isVertex ? 'Project ID saved.' : 'API key saved securely.';
    });
  }

  Future<void> _verify() async {
    setState(() {
      _verifying = true;
      _message = null;
    });
    try {
      await widget.cloudService.verifyTranscriptionSetup(
        widget.settingsService,
      );
      if (mounted) setState(() => _message = 'Setup verified.');
    } catch (error) {
      if (mounted) setState(() => _message = 'Verification failed: $error');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _signInCodex() async {
    setState(() {
      _signingIn = true;
      _message = null;
    });
    try {
      final flow = _codexFlow = await widget.settingsService.codexOAuth
          .startLogin();
      await flow.completion;
      await widget.settingsService.refreshCodexAuthState();
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Sign-in failed. Please try again.');
      }
    } finally {
      _codexFlow = null;
      if (mounted) setState(() => _signingIn = false);
    }
  }

  Future<void> _signOutCodex() async {
    await widget.settingsService.signOutCodex();
    if (mounted) setState(() => _message = 'Signed out of ChatGPT.');
  }

  /// OpenAI API-key and Grok providers are configured in the pass-2 section.
  Future<void> _removeKey() async {
    final s = widget.settingsService;
    if (s.cloudProvider == CloudProvider.vertexAi) {
      await s.clearVertexProjectId();
    } else {
      await s.clearGeminiApiKey();
    }
    if (mounted) setState(() => _storedKey = null);
  }

  Future<String?> _readCredential() async {
    final s = widget.settingsService;
    if (s.cloudProvider == CloudProvider.codexOAuth) return null;
    return s.cloudProvider == CloudProvider.vertexAi
        ? s.vertexProjectId
        : await s.readGeminiApiKey();
  }

  @override
  Widget build(BuildContext context) {
    if (_busy) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final settings = widget.settingsService;
    final isCodex = settings.cloudProvider == CloudProvider.codexOAuth;
    final firstModel = AppConfig.getModelById(settings.selectedModelId);
    final firstThinking = settings.getThinkingLevelForModel(firstModel.id);
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
            const _SectionTitle('Transcription account'),
            DropdownButtonFormField<CloudProvider>(
              initialValue: settings.cloudProvider,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Transcription provider',
                helperText: 'Receives your audio and turns it into text.',
              ),
              items: [
                for (final p in AppConfig.firstPassAudioProviders)
                  DropdownMenuItem(value: p, child: Text(p.displayName)),
              ],
              onChanged: _verifying
                  ? null
                  : (p) async {
                      if (p == null) return;
                      _keyController.clear();
                      await settings.setCloudProvider(p);
                      final key = await _readCredential();
                      if (mounted) {
                        setState(() {
                          _storedKey = key;
                          _message = null;
                        });
                      }
                    },
            ),
            if (isCodex)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('ChatGPT account'),
                subtitle: Text(
                  settings.hasCodexAuth ? 'Signed in' : 'Not signed in',
                ),
                trailing: _signingIn
                    ? TextButton(
                        onPressed: () => _codexFlow?.cancel(),
                        child: const Text('Cancel'),
                      )
                    : settings.hasCodexAuth
                    ? Wrap(
                        spacing: 4,
                        children: [
                          IconButton(
                            tooltip: 'Verify',
                            onPressed: _verifying ? null : _verify,
                            icon: _verifying
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.verified_outlined),
                          ),
                          IconButton(
                            tooltip: 'Sign out',
                            onPressed: _signOutCodex,
                            icon: const Icon(Icons.logout_rounded),
                          ),
                        ],
                      )
                    : TextButton(
                        onPressed: _signInCodex,
                        child: const Text('Sign in'),
                      ),
              )
            else if (_storedKey != null)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  '${settings.cloudProvider.displayName} credentials',
                ),
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
            if (!isCodex)
              TextField(
                controller: _keyController,
                obscureText: settings.cloudProvider != CloudProvider.vertexAi,
                decoration: InputDecoration(
                  labelText: settings.cloudProvider == CloudProvider.vertexAi
                      ? 'Vertex project ID (requires ADC)'
                      : '${settings.cloudProvider.displayName} API key',
                  suffixIcon: IconButton(
                    tooltip: 'Save',
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
            const _SectionTitle('Model'),
            DropdownButtonFormField<String>(
              key: ValueKey('model-${settings.selectedModelId}'),
              initialValue: settings.selectedModelId,
              isExpanded: true,
              items: [
                for (final model in settings.primaryModels)
                  DropdownMenuItem(
                    value: model.id,
                    child: Text(model.displayName),
                  ),
              ],
              onChanged: (value) {
                if (value != null) settings.setSelectedModelId(value);
              },
              decoration: InputDecoration(
                labelText: settings.twoPassTranscriptionEnabled
                    ? 'Pass 1 · Transcription model'
                    : 'Model',
                helperText:
                    firstModel.isTranscriptionOnly &&
                        !settings.twoPassTranscriptionEnabled
                    ? 'Speech-to-text only. Writing styles are not applied.'
                    : null,
              ),
            ),
            if (firstModel.hasSelectableThinkingLevel) ...[
              const SizedBox(height: 8),
              ThinkingLevelDropdown(
                key: ValueKey('model-thinking-${firstModel.id}'),
                label: 'Thinking',
                model: firstModel,
                value: firstModel.resolveThinkingLevel(
                  levelOverride: firstThinking,
                  forceMinimal:
                      firstThinking == null &&
                      settings.twoPassTranscriptionEnabled,
                ),
                onChanged: (level) =>
                    settings.setThinkingLevelForModel(firstModel.id, level),
              ),
            ],
            const SizedBox(height: 20),
            const _SectionTitle('Two-step refinement'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Refine in two steps'),
              subtitle: const Text(
                'Transcribe with the model above, then let any cloud AI polish the text.',
              ),
              value: settings.twoPassTranscriptionEnabled,
              onChanged: settings.setTwoPassTranscriptionEnabled,
            ),
            if (settings.twoPassTranscriptionEnabled)
              PolishStepSettings(settings: settings),
            const SizedBox(height: 20),
            const _SectionTitle('History'),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Save transcriptions on this device'),
              subtitle: const Text(
                'When off, results are only copied to the clipboard.',
              ),
              value: settings.clipboardHistoryEnabled,
              onChanged: settings.setClipboardHistoryEnabled,
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
              onChanged: settings.promptIsApplied
                  ? (value) {
                      if (value != null) settings.setSelectedPromptId(value);
                    }
                  : null,
              decoration: const InputDecoration(labelText: 'Prompt'),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<ToneRefinement>(
              initialValue: settings.toneRefinement,
              items: [
                for (final tone in ToneRefinement.values)
                  DropdownMenuItem(value: tone, child: Text(tone.displayName)),
              ],
              onChanged: settings.promptIsApplied
                  ? (tone) async {
                      if (tone == null) return;
                      await settings.setToneRefinement(tone);
                      if (mounted) setState(() {});
                    }
                  : null,
              decoration: InputDecoration(
                labelText: 'Tone refinement',
                helperText: settings.toneRefinement.description,
              ),
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
