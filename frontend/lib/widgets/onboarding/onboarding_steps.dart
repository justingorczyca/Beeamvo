import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../../config.dart';
import '../../models/hotkey_config.dart';
import '../../models/system_prompt.dart';
import '../../services/codex_oauth_manager.dart';
import '../../services/xai_oauth_manager.dart';
import '../../services/settings_service.dart';
import '../../services/whisper_model_download_service.dart';
import '../../services/whisper_service.dart';
import '../../theme/app_theme.dart';
import '../settings/cloud_provider_presentation.dart';
import '../settings/settings_shared.dart';
import 'onboarding_shared.dart';

// ═══════════════════════════════════════════════════════════════════════════
// STEP 1 — Welcome
// ═══════════════════════════════════════════════════════════════════════════

class WelcomeStep extends StatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onSkip;
  const WelcomeStep({super.key, required this.onNext, required this.onSkip});

  @override
  State<WelcomeStep> createState() => _WelcomeStepState();
}

class _WelcomeStepState extends State<WelcomeStep>
    with TickerProviderStateMixin {
  static const _sampleSentence = "Let's move the sync to Thursday at 3.";

  late final AnimationController _waveController = AnimationController(
    duration: const Duration(milliseconds: 1600),
    vsync: this,
  );
  late final AnimationController _typingController = AnimationController(
    duration: Duration(milliseconds: _sampleSentence.length * 90),
    vsync: this,
  );
  late final AnimationController _caretController = AnimationController(
    duration: const Duration(milliseconds: 550),
    vsync: this,
  );
  bool? _animationsDisabled;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disabled = MediaQuery.of(context).disableAnimations;
    if (_animationsDisabled == disabled) return;
    _animationsDisabled = disabled;
    if (disabled) {
      _waveController.stop();
      _typingController.stop();
      _caretController.stop();
    } else {
      _waveController.repeat();
      _typingController.repeat();
      _caretController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _waveController.dispose();
    _typingController.dispose();
    _caretController.dispose();
    super.dispose();
  }

  Widget _buildWaveform(
    BuildContext context, {
    required bool animationsDisabled,
  }) {
    return AnimatedBuilder(
      animation: _waveController,
      builder: (context, child) {
        final phase = _waveController.value * math.pi * 2;
        return SizedBox(
          height: 100,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: List.generate(24, (index) {
              final wave =
                  (math.sin(phase + index * 0.46) +
                          math.sin(phase * 0.72 + index * 0.19) * 0.45)
                      .abs();
              final height = animationsDisabled ? 20.0 : 12 + wave * 40;
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2.5),
                child: AnimatedContainer(
                  duration: animationsDisabled
                      ? Duration.zero
                      : const Duration(milliseconds: 100),
                  width: 4,
                  height: height,
                  decoration: BoxDecoration(
                    color: beeText(context).withValues(alpha: 0.85),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
        );
      },
    );
  }

  Widget _buildPreviewPanel(BuildContext context, bool animationsDisabled) {
    return Container(
      width: 300,
      height: 300,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: beeSurfaceRaised(context),
        borderRadius: BorderRadius.circular(AppTheme.radiusXl),
        border: Border.all(color: beeBorder(context).withValues(alpha: 0.6)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _buildWaveform(context, animationsDisabled: animationsDisabled),
          const SizedBox(height: 28),
          AnimatedBuilder(
            animation: _caretController,
            builder: (context, child) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: beeSurface(context),
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                border: Border.all(color: beeBorder(context)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(
                    opacity: animationsDisabled
                        ? 1
                        : 0.4 + _caretController.value * 0.6,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: beeText(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    'Listening…',
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: beeTextSub(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          AnimatedBuilder(
            animation: _typingController,
            builder: (context, child) {
              final charCount = animationsDisabled
                  ? _sampleSentence.length
                  : (_typingController.value * _sampleSentence.length)
                        .floor()
                        .clamp(0, _sampleSentence.length);
              return Text.rich(
                TextSpan(
                  children: [
                    TextSpan(
                      text: _sampleSentence.substring(0, charCount),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: beeText(context),
                        height: 1.4,
                      ),
                    ),
                    if (animationsDisabled || _caretController.value >= 0.5)
                      TextSpan(
                        text: '|',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          color: beeText(context),
                        ),
                      ),
                  ],
                ),
                textAlign: TextAlign.center,
              );
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final animationsDisabled = MediaQuery.of(context).disableAnimations;
    final contentWidth = MediaQuery.sizeOf(context).width;
    final horizontalPadding = contentWidth >= 700 ? 48.0 : 24.0;
    final leftContent = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: beeYellow(context),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(
                Icons.mic_rounded,
                size: 14,
                color: beeBlack(context),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              'Beeamvo',
              style: GoogleFonts.spaceGrotesk(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: beeText(context),
              ),
            ),
          ],
        ),
        const SizedBox(height: 26),
        Text(
          'Your voice,\ntyped anywhere.',
          style: GoogleFonts.spaceGrotesk(
            fontSize: contentWidth >= 700 ? 40 : 34,
            fontWeight: FontWeight.w700,
            letterSpacing: -1.6,
            height: 1.05,
            color: beeText(context),
          ),
        ),
        const SizedBox(height: 16),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 340),
          child: Text(
            "Press a shortcut, speak, and Beeamvo writes clean text into whatever app you're using. On-device with Whisper or in the cloud.",
            style: GoogleFonts.inter(
              fontSize: 14,
              color: beeTextSub(context),
              height: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OnboardingPrimaryButton(
              label: 'Get started',
              icon: Icons.arrow_forward_rounded,
              onTap: widget.onNext,
            ),
            OnboardingSecondaryButton(
              label: 'Skip setup',
              onTap: widget.onSkip,
            ),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          'Takes about a minute.',
          style: GoogleFonts.inter(fontSize: 12, color: beeTextMuted(context)),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        return Padding(
          padding: EdgeInsets.all(horizontalPadding),
          child: wide
              ? Row(
                  children: [
                    Expanded(child: Center(child: leftContent)),
                    const SizedBox(width: 32),
                    _buildPreviewPanel(context, animationsDisabled),
                  ],
                )
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      leftContent,
                      const SizedBox(height: 32),
                      Align(
                        alignment: Alignment.center,
                        child: _buildPreviewPanel(context, animationsDisabled),
                      ),
                    ],
                  ),
                ),
        );
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEP 2 — Choose Provider
// ═══════════════════════════════════════════════════════════════════════════

class ProviderStep extends StatefulWidget {
  final VoidCallback onNext;
  final SettingsService settingsService;
  const ProviderStep({
    super.key,
    required this.onNext,
    required this.settingsService,
  });

  @override
  State<ProviderStep> createState() => _ProviderStepState();
}

class _ProviderStepState extends State<ProviderStep>
    with AutomaticKeepAliveClientMixin {
  TranscriptionBackend _backend = TranscriptionBackend.cloud;
  CloudProvider _cloudProvider = CloudProvider.geminiApiKey;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _backend = widget.settingsService.transcriptionBackend;
    _cloudProvider = widget.settingsService.cloudProvider;
  }

  Widget _providerRow(CloudProvider provider) {
    final selected = _cloudProvider == provider;
    return OnboardingOptionTile(
      icon: provider.icon,
      title: provider.displayName,
      description: provider.tagline,
      selected: selected,
      compact: true,
      onTap: () => setState(() => _cloudProvider = provider),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return OnboardingStepScaffold(
      title: 'Choose your engine',
      subtitle:
          'Where your voice turns into text. You can change this any time in Settings.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: OnboardingOptionTile(
                    icon: Icons.cloud_outlined,
                    title: 'Cloud AI',
                    description:
                        'Fastest and most accurate. Applies your writing style.',
                    vertical: true,
                    selected: _backend == TranscriptionBackend.cloud,
                    onTap: () => setState(() {
                      _backend = TranscriptionBackend.cloud;
                    }),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OnboardingOptionTile(
                    icon: Icons.memory_rounded,
                    title: 'Offline',
                    description:
                        'Runs on this device with Whisper. Nothing leaves your device.',
                    vertical: true,
                    selected: _backend == TranscriptionBackend.whisper,
                    onTap: () => setState(() {
                      _backend = TranscriptionBackend.whisper;
                    }),
                  ),
                ),
              ],
            ),
          ),
          if (_backend == TranscriptionBackend.cloud) ...[
            const SizedBox(height: 24),
            Text(
              'PROVIDER',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: beeTextMuted(context),
              ),
            ),
            const SizedBox(height: 10),
            Column(
              children: [
                for (final (index, provider)
                    in AppConfig.firstPassAudioProviders.indexed) ...[
                  if (index > 0) const SizedBox(height: 8),
                  _providerRow(provider),
                ],
              ],
            ),
          ],
        ],
      ),
      primaryLabel: 'Continue',
      onPrimary: () async {
        await widget.settingsService.setTranscriptionBackend(_backend);
        await widget.settingsService.setCloudProvider(_cloudProvider);
        widget.onNext();
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEP 3 — API Key / Credentials
// ═══════════════════════════════════════════════════════════════════════════

class ApiKeyStep extends StatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onSkip;
  final SettingsService settingsService;
  final Future<void> Function(CloudProvider provider)? onVerifyCloudProvider;

  const ApiKeyStep({
    super.key,
    required this.onNext,
    required this.onSkip,
    required this.settingsService,
    this.onVerifyCloudProvider,
  });

  @override
  State<ApiKeyStep> createState() => _ApiKeyStepState();
}

class _ApiKeyStepState extends State<ApiKeyStep>
    with AutomaticKeepAliveClientMixin {
  final _apiKeyController = TextEditingController();
  final _projectIdController = TextEditingController();
  bool _obscureText = true;
  bool _isVerifying = false;
  String? _statusMessage;
  bool _statusIsError = false;
  CloudProvider? _hydratedProvider;
  bool _codexSigningIn = false;
  bool _codexSignedIn = false;
  CodexOAuthFlow? _codexFlow;
  bool _grokSigningIn = false;
  bool _grokSignedIn = false;
  XAiOAuthFlow? _grokFlow;

  @override
  bool get wantKeepAlive => true;

  CloudProvider get _provider => widget.settingsService.cloudProvider;
  bool get _isGemini => _provider == CloudProvider.geminiApiKey;
  bool get _isVertex => _provider == CloudProvider.vertexAi;
  bool get _isOpenAi => _provider == CloudProvider.openaiApiKey;
  bool get _isCodex => _provider == CloudProvider.codexOAuth;
  bool get _isGrok => _provider == CloudProvider.grokOAuth;

  /// True while a browser OAuth sign-in (Codex or Grok) is in flight.
  bool get _oauthSigningIn => _codexSigningIn || _grokSigningIn;

  /// True once the active OAuth provider has a completed sign-in.
  bool get _oauthSignedIn => _isCodex ? _codexSignedIn : _grokSignedIn;

  bool get _isFieldEmpty {
    if (_isCodex || _isGrok) return !_oauthSignedIn;
    if (_isGemini || _isOpenAi) {
      return _apiKeyController.text.trim().isEmpty;
    }
    return _projectIdController.text.trim().isEmpty;
  }

  bool get _hasSavedCredential => switch (_provider) {
    CloudProvider.geminiApiKey => widget.settingsService.hasGeminiApiKey,
    CloudProvider.vertexAi => widget.settingsService.vertexProjectId != null,
    CloudProvider.openaiApiKey => widget.settingsService.hasOpenAiApiKey,
    CloudProvider.codexOAuth => widget.settingsService.hasCodexAuth,
    CloudProvider.grokOAuth => widget.settingsService.hasGrokAuth,
  };

  /// Gemini API keys always start with "AIza".
  bool get _hasValidPrefix {
    final text = _apiKeyController.text.trim();
    if (text.isEmpty) return false;
    return text.startsWith('AIza');
  }

  /// Re-hydrates the fields when the user went back and switched providers;
  /// the keep-alive page would otherwise show the previous provider's input.
  void _syncProviderFields() {
    if (_provider == _hydratedProvider) return;
    _hydratedProvider = _provider;
    _statusMessage = null;
    _statusIsError = false;
    _codexSignedIn = widget.settingsService.hasCodexAuth;
    _grokSignedIn = widget.settingsService.hasGrokAuth;
    if (_isVertex) {
      _projectIdController.text = widget.settingsService.vertexProjectId ?? '';
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _projectIdController.dispose();
    _codexFlow?.cancel();
    _grokFlow?.cancel();
    super.dispose();
  }

  Future<void> _saveAndContinue() async {
    switch (_provider) {
      case CloudProvider.geminiApiKey:
        final key = _apiKeyController.text.trim();
        if (key.isNotEmpty) {
          await widget.settingsService.setGeminiApiKey(key);
        }
      case CloudProvider.openaiApiKey:
        final key = _apiKeyController.text.trim();
        if (key.isNotEmpty) {
          await widget.settingsService.setOpenAiApiKey(key);
        }
      case CloudProvider.vertexAi:
        final projectId = _projectIdController.text.trim();
        if (projectId.isNotEmpty) {
          await widget.settingsService.setVertexProjectId(projectId);
        }
      case CloudProvider.codexOAuth:
      case CloudProvider.grokOAuth:
        break; // sign-in already persisted the OAuth tokens
    }
    widget.onNext();
  }

  /// Starts the browser OAuth sign-in for the active OAuth provider
  /// (Codex or Grok) and waits for the loopback callback.
  Future<void> _startOAuthSignIn() async {
    final isCodex = _isCodex;
    setState(() {
      if (isCodex) {
        _codexSigningIn = true;
      } else {
        _grokSigningIn = true;
      }
      _statusMessage = isCodex
          ? 'Complete the ChatGPT sign-in in your browser…'
          : 'Complete the xAI sign-in in your browser…';
      _statusIsError = false;
    });
    try {
      if (isCodex) {
        final flow = await widget.settingsService.codexOAuth.startLogin();
        _codexFlow = flow;
        await flow.completion;
        await widget.settingsService.refreshCodexAuthState();
      } else {
        final flow = await widget.settingsService.xaiOAuth.startLogin();
        _grokFlow = flow;
        await flow.completion;
        await widget.settingsService.refreshGrokAuthState();
      }
      if (!mounted) return;
      setState(() {
        _codexSignedIn = widget.settingsService.hasCodexAuth;
        _grokSignedIn = widget.settingsService.hasGrokAuth;
        _statusMessage = isCodex
            ? 'Signed in with ChatGPT!'
            : 'Signed in with xAI!';
        _statusIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = e.toString();
        _statusIsError = true;
      });
    } finally {
      if (isCodex) {
        _codexFlow = null;
      } else {
        _grokFlow = null;
      }
      if (mounted) {
        setState(() {
          _codexSigningIn = false;
          _grokSigningIn = false;
        });
      }
    }
  }

  Future<void> _verifyConnection() async {
    if (widget.onVerifyCloudProvider == null) return;
    setState(() {
      _isVerifying = true;
      _statusMessage = null;
    });
    try {
      await widget.onVerifyCloudProvider!(_provider);
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _statusMessage = switch (_provider) {
          CloudProvider.geminiApiKey => 'API key verified!',
          CloudProvider.vertexAi => 'Vertex AI configuration verified!',
          CloudProvider.openaiApiKey => 'API key verified!',
          CloudProvider.codexOAuth => 'ChatGPT Codex verified!',
          CloudProvider.grokOAuth => 'xAI Grok verified!',
        };
        _statusIsError = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isVerifying = false;
        _statusMessage = e.toString();
        _statusIsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    _syncProviderFields();
    final isGemini = _isGemini;
    final showPrefixWarning =
        isGemini &&
        _apiKeyController.text.trim().isNotEmpty &&
        !_hasValidPrefix;

    final (title, subtitle) = switch (_provider) {
      CloudProvider.geminiApiKey => (
        'API Key',
        'Your Gemini API key is stored locally and never leaves your device.',
      ),
      CloudProvider.vertexAi => (
        'Vertex Project',
        'Enter your Google Cloud project ID. ADC credentials are resolved at runtime.',
      ),
      CloudProvider.openaiApiKey => (
        'OpenAI API Key',
        'Your API key is stored locally and never leaves your device. Custom endpoints can be set later in Settings.',
      ),
      CloudProvider.codexOAuth => (
        'ChatGPT Sign-In',
        'Sign in with your ChatGPT account — no API key needed. ChatGPT Transcribe turns speech into text on your ChatGPT plan.',
      ),
      CloudProvider.grokOAuth => (
        'xAI Sign-In',
        'Sign in with your xAI account — no API key needed. Grok models polish text; pair them with Offline for speech-to-text.',
      ),
    };

    final Widget oauthTrailing = _oauthSigningIn
        ? OnboardingSecondaryButton(
            label: 'Cancel',
            small: true,
            onTap: () {
              if (_isCodex) {
                _codexFlow?.cancel();
              } else {
                _grokFlow?.cancel();
              }
            },
          )
        : _oauthSignedIn
        ? Icon(Icons.check_circle_rounded, size: 18, color: beeSuccess(context))
        : OnboardingPrimaryButton(
            label: 'Sign in',
            small: true,
            icon: null,
            onTap: _startOAuthSignIn,
          );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isCodex || _isGrok)
          OnboardingOptionTile(
            icon: _provider.icon,
            title: _isCodex ? 'ChatGPT account' : 'xAI account',
            description: _oauthSigningIn
                ? 'Waiting for browser sign-in…'
                : _oauthSignedIn
                ? 'Signed in'
                : 'Not signed in',
            trailing: oauthTrailing,
          )
        else ...[
          Text(
            isGemini || _isOpenAi ? 'API KEY' : 'PROJECT ID',
            style: GoogleFonts.inter(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: beeTextMuted(context),
            ),
          ),
          const SizedBox(height: 8),
          if (isGemini || _isOpenAi)
            OnboardingTextField(
              controller: _apiKeyController,
              hintText: isGemini ? 'AIza...' : 'sk-...',
              obscureText: _obscureText,
              onChanged: (_) => setState(() {
                _statusMessage = null;
              }),
              suffixIcon: BeeInteractive(
                onTap: () => setState(() => _obscureText = !_obscureText),
                semanticLabel: _obscureText ? 'Show API key' : 'Hide API key',
                builder: (context, focused) => Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    _obscureText
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 18,
                    color: focused
                        ? beeTextSub(context)
                        : beeTextMuted(context),
                  ),
                ),
              ),
            )
          else
            OnboardingTextField(
              controller: _projectIdController,
              hintText: 'your-google-cloud-project-id',
              onChanged: (_) => setState(() {
                _statusMessage = null;
              }),
            ),
        ],
        if (showPrefixWarning) ...[
          const SizedBox(height: 10),
          OnboardingStatusBadge(
            label: 'Gemini API keys start with "AIza" — double-check your key',
            isError: false,
            isSuccess: false,
          ),
        ],
        if (_hasSavedCredential && _isFieldEmpty) ...[
          const SizedBox(height: 10),
          OnboardingStatusBadge(
            label: _isCodex || _isGrok
                ? _isCodex
                      ? 'You are already signed in with ChatGPT.'
                      : 'You are already signed in with xAI.'
                : isGemini || _isOpenAi
                ? 'An API key is already saved — leave blank to keep it.'
                : 'Your project ID is already saved — leave blank to keep it.',
            isSuccess: true,
          ),
        ],
        if (_statusMessage != null) ...[
          const SizedBox(height: 10),
          OnboardingStatusBadge(
            label: _statusMessage!,
            isError: _statusIsError,
            isSuccess: !_statusIsError,
          ),
        ],
      ],
    );

    return OnboardingStepScaffold(
      title: title,
      subtitle: subtitle,
      body: body,
      primaryLabel: 'Continue',
      onPrimary: (_isFieldEmpty && !_hasSavedCredential)
          ? null
          : _saveAndContinue,
      primaryLoading: false,
      secondaryActions: [
        OnboardingSecondaryButton(label: 'Set up later', onTap: widget.onSkip),
        if (widget.onVerifyCloudProvider != null)
          OnboardingSecondaryButton(
            label: _isVerifying ? 'Verifying…' : 'Verify',
            onTap: _isVerifying ? null : _verifyConnection,
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEP 4 — Model Selection
// ═══════════════════════════════════════════════════════════════════════════

class ModelStep extends StatefulWidget {
  final VoidCallback onNext;
  final SettingsService settingsService;
  final VoidCallback? onModelDownloaded;

  const ModelStep({
    super.key,
    required this.onNext,
    required this.settingsService,
    this.onModelDownloaded,
  });

  @override
  State<ModelStep> createState() => _ModelStepState();
}

class _ModelStepState extends State<ModelStep>
    with AutomaticKeepAliveClientMixin {
  late String _selectedModelId;
  late String _selectedWhisperModelId;
  late String _selectedPromptId;

  // Whisper download state
  final WhisperModelDownloadService _downloadService =
      WhisperModelDownloadService();
  List<String> _downloadedModels = [];
  String? _downloadingModelId;
  double _downloadProgress = 0.0;
  bool _downloadError = false;
  String? _downloadErrorMessage;

  @override
  bool get wantKeepAlive => true;

  bool get _isWhisper =>
      widget.settingsService.transcriptionBackend ==
      TranscriptionBackend.whisper;

  @override
  void initState() {
    super.initState();
    _selectedModelId = widget.settingsService.selectedModelId;
    _selectedWhisperModelId = widget.settingsService.whisperModelId;
    _selectedPromptId = widget.settingsService.selectedPromptId;
    if (_isWhisper) {
      _refreshDownloadedModels();
    }
  }

  @override
  void dispose() {
    _downloadService.dispose();
    super.dispose();
  }

  void _refreshDownloadedModels() {
    _downloadedModels = WhisperService.listDownloadedModels();
    // Auto-select the first downloaded model when the configured one is absent
    if (!_downloadedModels.contains(_selectedWhisperModelId) &&
        _downloadedModels.isNotEmpty) {
      _selectedWhisperModelId = _downloadedModels.first;
    }
  }

  Future<void> _startDownload(WhisperModelInfo model) async {
    setState(() {
      _downloadingModelId = model.id;
      _downloadProgress = 0.0;
      _downloadError = false;
      _downloadErrorMessage = null;
    });

    final success = await _downloadService.downloadModel(
      model,
      onProgress: (progress, downloaded, total) {
        if (mounted) {
          setState(() => _downloadProgress = progress);
        }
      },
    );

    if (!mounted) return;

    if (success) {
      setState(() {
        _downloadingModelId = null;
        _downloadProgress = 0.0;
      });
      _refreshDownloadedModels();
      // Auto-select the newly downloaded model
      _selectedWhisperModelId = model.id;
      await widget.settingsService.setWhisperModelId(model.id);
      widget.onModelDownloaded?.call();
    } else {
      setState(() {
        _downloadError = true;
        _downloadErrorMessage =
            _downloadService.errorMessage ?? 'Download failed';
        _downloadingModelId = null;
        _downloadProgress = 0.0;
      });
    }
  }

  // ── Cloud model helpers ──────────────────────────────────────────────

  String _modelDescription(GeminiModelConfig model) {
    if (model.isTranscriptionOnly) {
      return AppConfig.transcriptionOnlyStyleNotice;
    }
    return model.description.isNotEmpty
        ? model.description
        : 'High-quality AI model.';
  }

  /// One-line summary for each built-in writing style.
  String _styleDescription(String promptId) {
    switch (promptId) {
      case 'concise':
        return 'The shortest clear version';
      case 'smart':
        return 'Detects emails, lists and notes';
      case 'professional':
        return 'Polished business wording';
      default:
        return 'Clean text, close to your words';
    }
  }

  String _speedLabel(GeminiModelConfig model) {
    if (model.id.contains('lite') ||
        model.id.contains('mini') ||
        model.id.contains('fast')) {
      return 'Ultra fast';
    }
    return 'Balanced';
  }

  Widget _buildStyleTile(SystemPrompt prompt) {
    final isSelected = _selectedPromptId == prompt.id;
    return Semantics(
      selected: isSelected,
      button: true,
      child: BeeInteractive(
        onTap: () => setState(() => _selectedPromptId = prompt.id),
        semanticLabel: prompt.name,
        selected: isSelected,
        toggled: isSelected,
        builder: (context, focused) => AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: isSelected
                ? beeYellow(context).withValues(alpha: 0.035)
                : beeSurfaceRaised(context),
            borderRadius: BorderRadius.circular(AppTheme.radiusLg),
            border: Border.all(
              color: isSelected
                  ? beeYellow(context)
                  : focused
                  ? beeTextMuted(context).withValues(alpha: 0.5)
                  : beeBorder(context).withValues(alpha: 0.6),
              width: isSelected ? 1.5 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                prompt.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: beeText(context),
                ),
              ),
              const SizedBox(height: 3),
              Text(
                _styleDescription(prompt.id),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  color: beeTextMuted(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (_isWhisper) return _buildWhisperModelStep();
    return _buildCloudModelStep();
  }

  // ── Cloud Model Step ─────────────────────────────────────────────────

  Widget _buildCloudModelStep() {
    final selectedModel = AppConfig.getModelById(_selectedModelId);
    // Dedicated speech models cannot follow a writing style — offering one
    // would be meaningless, so the picker stays hidden for that selection.
    final showStylePicker = !selectedModel.isTranscriptionOnly;

    return OnboardingStepScaffold(
      title: 'Choose your model',
      subtitle:
          'Pick the AI model that transcribes your voice, then choose how the text reads.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final model in widget.settingsService.primaryModels) ...[
            OnboardingOptionTile(
              icon: Icons.auto_awesome_rounded,
              title: model.displayName,
              description: _modelDescription(model),
              badge: _speedLabel(model),
              selected: _selectedModelId == model.id,
              onTap: () => setState(() => _selectedModelId = model.id),
            ),
            const SizedBox(height: 8),
          ],
          if (showStylePicker) ...[
            const SizedBox(height: 16),
            Text(
              'WRITING STYLE',
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: beeTextMuted(context),
              ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) => Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final prompt in SystemPrompt.availablePrompts)
                    SizedBox(
                      width: (constraints.maxWidth - 8) / 2,
                      height: 68,
                      child: _buildStyleTile(prompt),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Prefer OpenAI, ChatGPT or Grok for polishing? Turn on two-step '
            'refinement later in Settings › Transcription.',
            style: GoogleFonts.inter(
              fontSize: 12,
              color: beeTextMuted(context),
              height: 1.4,
            ),
          ),
        ],
      ),
      primaryLabel: 'Continue',
      onPrimary: () async {
        await widget.settingsService.setSelectedModelId(_selectedModelId);
        if (showStylePicker) {
          await widget.settingsService.setSelectedPromptId(_selectedPromptId);
        }
        widget.onNext();
      },
    );
  }

  // ── Whisper Model Step ───────────────────────────────────────────────

  Widget _buildWhisperModelStep() {
    final hasDownloadedModel = _downloadedModels.contains(
      _selectedWhisperModelId,
    );

    return OnboardingStepScaffold(
      title: 'Choose your offline model',
      subtitle:
          'Download a model for offline transcription. Tiny is recommended for most users.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final model in WhisperModelDownloadService.availableModels)
            Builder(
              builder: (context) {
                final isDownloaded = _downloadedModels.contains(model.id);
                final isDownloading = _downloadingModelId == model.id;
                final isSelected = _selectedWhisperModelId == model.id;
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: OnboardingOptionTile(
                    icon: Icons.memory_rounded,
                    title: model.name,
                    description: model.id == 'tiny'
                        ? 'Recommended for most users'
                        : 'Offline speech recognition',
                    badge: isDownloaded
                        ? 'Downloaded · ${model.sizeDisplay}'
                        : model.sizeDisplay,
                    selected: isDownloaded && isSelected,
                    onTap: isDownloaded
                        ? () =>
                              setState(() => _selectedWhisperModelId = model.id)
                        : null,
                    trailing: isDownloading
                        ? SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              value: _downloadProgress > 0
                                  ? _downloadProgress
                                  : null,
                              color: beeYellow(context),
                            ),
                          )
                        : isDownloaded
                        ? null
                        : OnboardingSecondaryButton(
                            label: 'Download',
                            small: true,
                            onTap: _downloadingModelId == null
                                ? () => _startDownload(model)
                                : null,
                          ),
                    footer: isDownloading
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(3),
                                child: LinearProgressIndicator(
                                  value: _downloadProgress,
                                  backgroundColor: beeSurfaceHighest(context),
                                  valueColor: AlwaysStoppedAnimation(
                                    beeYellow(context),
                                  ),
                                  minHeight: 2,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${WhisperModelDownloadService.formatBytes((_downloadProgress * model.sizeBytes).round())} / ${model.sizeDisplay}',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: beeTextMuted(context),
                                ),
                              ),
                            ],
                          )
                        : null,
                  ),
                );
              },
            ),
          if (_downloadError && _downloadErrorMessage != null) ...[
            const SizedBox(height: 8),
            OnboardingStatusBadge(label: _downloadErrorMessage!, isError: true),
          ],
        ],
      ),
      primaryLabel: hasDownloadedModel ? 'Continue' : 'Skip for now',
      onPrimary: () async {
        if (hasDownloadedModel) {
          await widget.settingsService.setWhisperModelId(
            _selectedWhisperModelId,
          );
        }
        widget.onNext();
      },
    );
  }

  // ── Shared ───────────────────────────────────────────────────────────
}

// ═══════════════════════════════════════════════════════════════════════════
// STEP 5 — Recording Mode
// ═══════════════════════════════════════════════════════════════════════════

class RecordingModeStep extends StatefulWidget {
  final VoidCallback onNext;
  final SettingsService settingsService;

  const RecordingModeStep({
    super.key,
    required this.onNext,
    required this.settingsService,
  });

  @override
  State<RecordingModeStep> createState() => _RecordingModeStepState();
}

class _RecordingModeStepState extends State<RecordingModeStep>
    with AutomaticKeepAliveClientMixin {
  late RecordingMode _mode;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _mode = widget.settingsService.recordingMode;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final mainHotkeyLabel = widget.settingsService.hotkey.displayString
        .split(' + ')
        .last;
    return OnboardingStepScaffold(
      title: 'How do you want to record?',
      subtitle: 'Choose how your shortcut starts and stops dictation.',
      body: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: OnboardingOptionTile(
                vertical: true,
                icon: Icons.touch_app_rounded,
                title: 'Toggle',
                description: 'Press once to start, again to stop.',
                badge: 'Best for long dictation',
                selected: _mode == RecordingMode.toggle,
                footer: Row(
                  children: [
                    OnboardingKeycap(label: mainHotkeyLabel, small: true),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        '· · ·',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: beeTextMuted(context)),
                      ),
                    ),
                    const SizedBox(width: 8),
                    OnboardingKeycap(label: mainHotkeyLabel, small: true),
                  ],
                ),
                onTap: () => setState(() => _mode = RecordingMode.toggle),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OnboardingOptionTile(
                vertical: true,
                icon: Icons.back_hand_rounded,
                title: 'Hold',
                description:
                    'Hold the hotkey while you talk, release to finish.',
                badge: 'Quick and natural',
                selected: _mode == RecordingMode.hold,
                footer: Row(
                  children: [
                    OnboardingKeycap(label: mainHotkeyLabel, small: true),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          color: beeBorder(context),
                          borderRadius: BorderRadius.circular(1),
                        ),
                      ),
                    ),
                  ],
                ),
                onTap: () => setState(() => _mode = RecordingMode.hold),
              ),
            ),
          ],
        ),
      ),
      primaryLabel: 'Continue',
      onPrimary: () async {
        await widget.settingsService.setRecordingMode(_mode);
        widget.onNext();
      },
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEP 6 — Hotkey
// ═══════════════════════════════════════════════════════════════════════════

class HotkeyStep extends StatefulWidget {
  final VoidCallback onNext;
  final SettingsService settingsService;
  final Future<void> Function(HotkeyConfig)? onHotkeyChanged;

  const HotkeyStep({
    super.key,
    required this.onNext,
    required this.settingsService,
    this.onHotkeyChanged,
  });

  @override
  State<HotkeyStep> createState() => _HotkeyStepState();
}

class _HotkeyStepState extends State<HotkeyStep>
    with SingleTickerProviderStateMixin, AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  late HotkeyConfig _currentHotkey;
  bool _isRecording = false;
  String? _errorMessage;
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _currentHotkey = widget.settingsService.hotkey;
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _startRecording() {
    setState(() {
      _isRecording = true;
      _errorMessage = null;
    });
    _pulseController.repeat(reverse: true);
    _focusNode.requestFocus();
  }

  void _stopRecording() {
    setState(() => _isRecording = false);
    _pulseController.stop();
    _pulseController.reset();
  }

  void _handleKeyEvent(KeyEvent event) {
    if (!_isRecording) return;
    if (event is! KeyDownEvent) return;

    final key = event.logicalKey;
    if (_isModifierKey(key)) return;

    final modifiers = <HotKeyModifier>{};
    if (HardwareKeyboard.instance.isControlPressed) {
      modifiers.add(HotKeyModifier.control);
    }
    if (HardwareKeyboard.instance.isAltPressed) {
      modifiers.add(HotKeyModifier.alt);
    }
    if (HardwareKeyboard.instance.isShiftPressed) {
      modifiers.add(HotKeyModifier.shift);
    }
    if (HardwareKeyboard.instance.isMetaPressed) {
      modifiers.add(HotKeyModifier.meta);
    }

    if (key == LogicalKeyboardKey.escape) {
      _stopRecording();
      return;
    }

    if (modifiers.isEmpty) {
      setState(() {
        _errorMessage =
            'Include at least one modifier (Ctrl, Alt, Shift, or Win)';
      });
      return;
    }

    final newConfig = HotkeyConfig(key: key, modifiers: modifiers);
    _stopRecording();
    setState(() {
      _currentHotkey = newConfig;
      _errorMessage = null;
    });
    widget.settingsService.setHotkey(newConfig);
    widget.onHotkeyChanged?.call(newConfig);
  }

  bool _isModifierKey(LogicalKeyboardKey key) {
    return key == LogicalKeyboardKey.controlLeft ||
        key == LogicalKeyboardKey.controlRight ||
        key == LogicalKeyboardKey.altLeft ||
        key == LogicalKeyboardKey.altRight ||
        key == LogicalKeyboardKey.shiftLeft ||
        key == LogicalKeyboardKey.shiftRight ||
        key == LogicalKeyboardKey.metaLeft ||
        key == LogicalKeyboardKey.metaRight;
  }

  /// A captured hotkey is saved the moment the keys land, so restoring the
  /// default must write it back — a "keep default" label would lie.
  Future<void> _resetToDefault() async {
    _stopRecording();
    setState(() => _currentHotkey = HotkeyConfig.defaultHotkey);
    await widget.settingsService.resetHotkey();
    widget.onHotkeyChanged?.call(HotkeyConfig.defaultHotkey);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final hotkeyLabels = _currentHotkey.displayString.split(' + ');
    return OnboardingStepScaffold(
      title: 'Pick your shortcut',
      subtitle:
          'Choose a keyboard shortcut to trigger voice recording from anywhere.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          KeyboardListener(
            focusNode: _focusNode,
            onKeyEvent: _handleKeyEvent,
            child: BeeInteractive(
              onTap: _isRecording ? _stopRecording : _startRecording,
              semanticLabel: _isRecording
                  ? 'Stop capturing hotkey'
                  : 'Capture a new hotkey. Current: ${_currentHotkey.displayString}',
              builder: (context, focused) => AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) => Container(
                  height: 150,
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: beeSurfaceRaised(context),
                    borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                    border: Border.all(
                      color: _isRecording
                          ? beeYellow(
                              context,
                            ).withValues(alpha: _pulseAnimation.value)
                          : focused
                          ? beeYellow(context)
                          : beeBorder(context),
                      width: 1.5,
                    ),
                  ),
                  child: Center(
                    child: _isRecording
                        ? Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                'Press your shortcut…',
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: beeText(context),
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Esc to cancel',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: beeTextMuted(context),
                                ),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    for (
                                      var index = 0;
                                      index < hotkeyLabels.length;
                                      index++
                                    ) ...[
                                      if (index > 0) ...[
                                        const SizedBox(width: 8),
                                        Text(
                                          '+',
                                          style: GoogleFonts.inter(
                                            fontSize: 14,
                                            color: beeTextMuted(context),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                      ],
                                      OnboardingKeycap(
                                        label: hotkeyLabels[index],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'Click to change',
                                style: GoogleFonts.inter(
                                  fontSize: 12,
                                  color: beeTextMuted(context),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
            ),
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: 8),
            OnboardingStatusBadge(label: _errorMessage!, isError: true),
          ],
        ],
      ),
      primaryLabel: 'Continue',
      onPrimary: widget.onNext,
      secondaryActions: [
        if (_currentHotkey != HotkeyConfig.defaultHotkey)
          OnboardingSecondaryButton(
            label: 'Reset to default',
            onTap: _resetToDefault,
          ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEP 7 — Ready / Finish
// ═══════════════════════════════════════════════════════════════════════════

class ReadyStep extends StatefulWidget {
  final VoidCallback onFinish;
  final SettingsService settingsService;
  final VoidCallback? onGoToApiKeyStep;
  final VoidCallback? onGoToModelStep;
  final VoidCallback? onGoToProviderStep;
  final VoidCallback? onGoToRecordingStep;
  final VoidCallback? onGoToHotkeyStep;

  const ReadyStep({
    super.key,
    required this.onFinish,
    required this.settingsService,
    this.onGoToApiKeyStep,
    this.onGoToModelStep,
    this.onGoToProviderStep,
    this.onGoToRecordingStep,
    this.onGoToHotkeyStep,
  });

  @override
  State<ReadyStep> createState() => _ReadyStepState();
}

class _ReadyStepState extends State<ReadyStep> {
  @override
  Widget build(BuildContext context) {
    final s = widget.settingsService;
    final isWhisper = s.transcriptionBackend == TranscriptionBackend.whisper;

    // Readiness tracks the ACTIVE backend and the SELECTED provider — the
    // same check SettingsService exposes, so a leftover Gemini key can never
    // make a Vertex (or Whisper) setup look "ready".
    final bool isReady =
        s.isTranscriptionReady &&
        (!isWhisper ||
            WhisperService.listDownloadedModels().contains(s.whisperModelId));

    final cloudModel = AppConfig.getModelById(s.selectedModelId);
    final styleNotApplied = !s.promptIsApplied;
    final whisperModelInfo = WhisperModelDownloadService.getModelInfo(
      s.whisperModelId,
    );
    final prompt = SystemPrompt.getById(s.selectedPromptId);
    final hotkeyLabels = s.hotkey.displayString.split(' + ');

    return OnboardingStepScaffold(
      title: isReady ? "You're all set" : 'Almost there',
      subtitle: isReady
          ? 'Beeamvo is configured and ready to use.'
          : 'Configure a transcription backend to start using Beeamvo.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isReady) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: beeSurfaceRaised(context),
                borderRadius: BorderRadius.circular(AppTheme.radiusLg),
                border: Border.all(color: beeBorder(context)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        size: 18,
                        color: beeYellow(context),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'No transcription backend configured',
                              style: GoogleFonts.inter(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: beeText(context),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isWhisper
                                  ? 'Download a Whisper model to enable offline transcription, or switch to Cloud AI.'
                                  : 'Choose compatible models and configure credentials for every active step.',
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: beeTextMuted(context),
                                height: 1.4,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    alignment: WrapAlignment.end,
                    children: [
                      if (widget.onGoToProviderStep != null)
                        OnboardingSecondaryButton(
                          label: 'Change engine',
                          small: true,
                          onTap: widget.onGoToProviderStep,
                        ),
                      if (!isWhisper && widget.onGoToApiKeyStep != null)
                        OnboardingSecondaryButton(
                          label: s.cloudProvider == CloudProvider.vertexAi
                              ? 'Set up Vertex AI'
                              : 'Set up account',
                          small: true,
                          onTap: widget.onGoToApiKeyStep,
                        ),
                      if (isWhisper && widget.onGoToModelStep != null)
                        OnboardingSecondaryButton(
                          label: 'Download model',
                          small: true,
                          onTap: widget.onGoToModelStep,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: beeSurfaceRaised(context),
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              border: Border.all(color: beeDivider(context)),
            ),
            child: Column(
              children: [
                _summaryRow(
                  'Engine',
                  s.transcriptionBackend == TranscriptionBackend.cloud
                      ? 'Cloud'
                      : 'Offline (Whisper)',
                  widget.onGoToProviderStep,
                ),
                Divider(color: beeDivider(context), height: 12),
                _summaryRow(
                  'Model',
                  isWhisper
                      ? (whisperModelInfo?.name ?? s.whisperModelId)
                      : cloudModel.displayName,
                  widget.onGoToModelStep,
                ),
                Divider(color: beeDivider(context), height: 12),
                _summaryRow(
                  'Style',
                  styleNotApplied ? 'Not applied' : prompt.name,
                  cloudModel.isTranscriptionOnly
                      ? null
                      : widget.onGoToModelStep,
                  valueMuted: styleNotApplied,
                ),
                Divider(color: beeDivider(context), height: 12),
                _summaryRow(
                  'Recording',
                  s.recordingMode == RecordingMode.toggle ? 'Toggle' : 'Hold',
                  widget.onGoToRecordingStep,
                ),
                Divider(color: beeDivider(context), height: 12),
                _summaryRow(
                  'Hotkey',
                  s.hotkey.displayString,
                  widget.onGoToHotkeyStep,
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: beeSurfaceRaised(context),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
              border: Border.all(color: beeBorder(context)),
            ),
            child: Row(
              children: [
                Text(
                  'Try it',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: beeText(context),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Wrap(
                    spacing: 5,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      const Text('Press'),
                      for (
                        var index = 0;
                        index < hotkeyLabels.length;
                        index++
                      ) ...[
                        if (index > 0) const Text('+'),
                        OnboardingKeycap(
                          label: hotkeyLabels[index],
                          small: true,
                        ),
                      ],
                      const Text('anywhere to start dictating.'),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      primaryLabel: 'Start using Beeamvo',
      primaryIcon: null,
      onPrimary: widget.onFinish,
    );
  }

  Widget _summaryRow(
    String label,
    String value,
    VoidCallback? onEdit, {
    bool valueMuted = false,
  }) {
    return SizedBox(
      height: 44,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 12,
                color: beeTextMuted(context),
              ),
            ),
          ),
          Expanded(
            flex: 6,
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: valueMuted ? FontWeight.w500 : FontWeight.w600,
                color: valueMuted ? beeTextMuted(context) : beeText(context),
              ),
            ),
          ),
          SizedBox(
            width: 44,
            child: onEdit == null
                ? null
                : OnboardingSecondaryButton(
                    label: 'Edit',
                    small: true,
                    onTap: onEdit,
                  ),
          ),
        ],
      ),
    );
  }
}

// ─── local tokens ───────────────────────────────────────────────────────
