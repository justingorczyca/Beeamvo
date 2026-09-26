import 'dart:async';

import 'package:flutter/material.dart';

import '../../config.dart';
import '../../services/codex_oauth_manager.dart';
import '../../services/settings_service.dart';
import '../../services/xai_oauth_manager.dart';

/// Material (mobile) settings for pass 2 of two-step refinement: any
/// provider, its prompt-capable model, the polish thinking level, and the
/// provider's credentials when they differ from the transcription account.
/// Pass 2 only ever receives the validated transcript, never audio.
class PolishStepSettings extends StatefulWidget {
  const PolishStepSettings({super.key, required this.settings});
  final SettingsService settings;

  @override
  State<PolishStepSettings> createState() => _PolishStepSettingsState();
}

class _PolishStepSettingsState extends State<PolishStepSettings> {
  final _credential = TextEditingController();
  bool _busy = false;
  String? _message;
  CodexOAuthFlow? _codexFlow;
  XAiOAuthFlow? _grokFlow;

  @override
  void dispose() {
    unawaited(_codexFlow?.cancel() ?? Future<void>.value());
    unawaited(_grokFlow?.cancel() ?? Future<void>.value());
    _credential.dispose();
    super.dispose();
  }

  Future<void> _save(CloudProvider provider) async {
    final value = _credential.text.trim();
    if (value.isEmpty) return;
    try {
      switch (provider) {
        case CloudProvider.geminiApiKey:
          await widget.settings.setGeminiApiKey(value);
        case CloudProvider.openaiApiKey:
          await widget.settings.setOpenAiApiKey(value);
        case CloudProvider.vertexAi:
          await widget.settings.setVertexProjectId(value);
        case CloudProvider.codexOAuth:
        case CloudProvider.grokOAuth:
          return;
      }
      _credential.clear();
      if (mounted) setState(() => _message = 'Polish credentials saved.');
    } catch (_) {
      if (mounted) setState(() => _message = 'Could not save credentials.');
    }
  }

  Future<void> _signIn(CloudProvider provider) async {
    final s = widget.settings;
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      if (provider == CloudProvider.codexOAuth) {
        final flow = _codexFlow = await s.codexOAuth.startLogin();
        await flow.completion;
        await s.refreshCodexAuthState();
      } else {
        final flow = _grokFlow = await s.xaiOAuth.startLogin();
        await flow.completion;
        await s.refreshGrokAuthState();
      }
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'Sign-in failed. Please try again.');
      }
    } finally {
      _codexFlow = null;
      _grokFlow = null;
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _signOut(CloudProvider provider) =>
      provider == CloudProvider.codexOAuth
      ? widget.settings.signOutCodex()
      : widget.settings.signOutGrok();

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.settings,
    builder: (context, _) {
      final settings = widget.settings;
      final provider = settings.refinementProvider;
      final modelId = settings.twoPassRefinementModelId;
      final model = AppConfig.getModelById(modelId);
      final sharesStepOneAccount =
          settings.transcriptionBackend == TranscriptionBackend.cloud &&
          provider == settings.cloudProvider;
      final isOAuth =
          provider == CloudProvider.codexOAuth ||
          provider == CloudProvider.grokOAuth;
      final configured = settings.hasRefinementCredentials;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<CloudProvider>(
            key: ValueKey('polish-provider-$provider'),
            initialValue: provider,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Pass 2 · Polish provider',
              helperText: sharesStepOneAccount
                  ? 'Uses the account above. Receives only the transcript.'
                  : '${provider.description} Receives only the transcript, '
                        'never audio.',
              helperMaxLines: 3,
            ),
            items: [
              for (final p in CloudProvider.values)
                DropdownMenuItem(value: p, child: Text(p.displayName)),
            ],
            onChanged: _busy
                ? null
                : (p) async {
                    if (p == null) return;
                    _credential.clear();
                    setState(() => _message = null);
                    await settings.setRefinementProvider(p);
                  },
          ),
          if (!sharesStepOneAccount) ...[
            const SizedBox(height: 8),
            if (isOAuth)
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                children: [
                  Text(
                    configured
                        ? 'Signed in to ${provider.displayName}'
                        : '${provider.displayName} sign-in required',
                  ),
                  if (configured)
                    TextButton(
                      onPressed: _busy ? null : () => _signOut(provider),
                      child: const Text('Sign out'),
                    )
                  else
                    TextButton(
                      onPressed: _busy ? null : () => _signIn(provider),
                      child: Text(_busy ? 'Signing in…' : 'Sign in'),
                    ),
                ],
              )
            else
              TextField(
                controller: _credential,
                obscureText: provider != CloudProvider.vertexAi,
                enableSuggestions: false,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: provider == CloudProvider.vertexAi
                      ? 'Vertex project ID (requires ADC)'
                      : '${provider.displayName} API key',
                  helperText: configured
                      ? 'Credentials saved securely. Enter a new value to replace them.'
                      : 'Stored in secure storage on this device.',
                  helperMaxLines: 2,
                  suffixIcon: IconButton(
                    tooltip: 'Save polish credentials',
                    icon: const Icon(Icons.save_outlined),
                    onPressed: () => _save(provider),
                  ),
                ),
                onSubmitted: (_) => _save(provider),
              ),
          ],
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            key: ValueKey('polish-model-$provider-$modelId'),
            initialValue: modelId,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Pass 2 · Polish model',
            ),
            items: [
              for (final m in settings.refinementModels)
                DropdownMenuItem(value: m.id, child: Text(m.displayName)),
            ],
            onChanged: (id) {
              if (id != null) settings.setTwoPassRefinementModelId(id);
            },
          ),
          if (model.hasSelectableThinkingLevel) ...[
            const SizedBox(height: 8),
            ThinkingLevelDropdown(
              key: ValueKey('polish-thinking-$modelId'),
              label: 'Polish thinking',
              model: model,
              value: model.resolveThinkingLevel(
                levelOverride: settings.getRefinementThinkingLevel(modelId),
              ),
              onChanged: (level) =>
                  settings.setRefinementThinkingLevel(modelId, level),
            ),
          ],
          if (_message != null) ...[const SizedBox(height: 8), Text(_message!)],
        ],
      );
    },
  );
}

/// Material dropdown over a model's supported thinking levels.
class ThinkingLevelDropdown extends StatelessWidget {
  const ThinkingLevelDropdown({
    super.key,
    required this.label,
    required this.model,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final GeminiModelConfig model;
  final GeminiThinkingLevel? value;
  final ValueChanged<GeminiThinkingLevel> onChanged;

  @override
  Widget build(BuildContext context) {
    final levels = model.supportedThinkingLevels;
    return DropdownButtonFormField<GeminiThinkingLevel>(
      initialValue: levels.contains(value) ? value : levels.first,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final level in levels)
          DropdownMenuItem(value: level, child: Text(level.displayLabel)),
      ],
      onChanged: (level) {
        if (level != null) onChanged(level);
      },
    );
  }
}
