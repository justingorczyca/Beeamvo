import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../../config.dart';
import '../../models/hotkey_config.dart';
import '../../models/system_prompt.dart';
import '../../services/settings_service.dart';
import '../../services/whisper_model_download_service.dart';
import '../../services/whisper_service.dart';
import '../../theme/app_theme.dart';
import '../settings/settings_shared.dart';
import 'onboarding_shared.dart';

// ═══════════════════════════════════════════════════════════════════════════
// STEP 1 — Welcome
// ═══════════════════════════════════════════════════════════════════════════

class WelcomeStep extends StatefulWidget {
  final VoidCallback onNext;
  const WelcomeStep({super.key, required this.onNext});

  @override
  State<WelcomeStep> createState() => _WelcomeStepState();
}

class _WelcomeStepState extends State<WelcomeStep>
    with SingleTickerProviderStateMixin {
  late AnimationController _glowController;

  @override
  void initState() {
    super.initState();
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 12),
        // Animated logo orb
        AnimatedBuilder(
          animation: _glowController,
          builder: (context, child) {
            final t = _glowController.value;
            return Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    beeYellow(context).withValues(alpha: 0.25 + 0.10 * t),
                    beeYellow(context).withValues(alpha: 0.05),
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: beeYellow(context).withValues(alpha: 0.15 + 0.10 * t),
                    blurRadius: 40,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Center(
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [beeYellow(context), beeYellowDim(context)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: beeYellow(context).withValues(alpha: 0.4 + 0.2 * t),
                        blurRadius: 16,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.mic_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 20),
        Text(
          'Welcome to Beeamvo',
          textAlign: TextAlign.center,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: beeText(context),
            letterSpacing: -0.8,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Your voice, instantly everywhere.\nTransform speech to text with AI-powered precision.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(
            fontSize: 13,
            color: beeTextSub(context),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),
        OnboardingPrimaryButton(
          label: "Let's Get Started",
          icon: Icons.arrow_forward_rounded,
          onTap: widget.onNext,
        ),
        const SizedBox(height: 12),
        OnboardingSecondaryButton(label: 'Skip Setup', onTap: widget.onNext),
      ],
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

class _ProviderStepState extends State<ProviderStep> {
  TranscriptionBackend _backend = TranscriptionBackend.cloud;
  CloudProvider _cloudProvider = CloudProvider.geminiApiKey;

  @override
  void initState() {
    super.initState();
    _backend = widget.settingsService.transcriptionBackend;
    _cloudProvider = widget.settingsService.cloudProvider;
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingStepShell(
      icon: Icons.dns_rounded,
      title: 'Processing Engine',
      subtitle:
          'Choose where your voice is transcribed. Cloud is faster; Local ensures complete privacy.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Cloud vs Offline
          Row(
            children: [
              Expanded(
                child: OnboardingGlowCard(
                  isSelected: _backend == TranscriptionBackend.cloud,
                  onTap: () => setState(() {
                    _backend = TranscriptionBackend.cloud;
                  }),
                  child: Column(
                    children: [
                      Icon(
                        Icons.cloud_outlined,
                        size: 24,
                        color: _backend == TranscriptionBackend.cloud
                            ? beeYellow(context)
                            : beeTextMuted(context),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Cloud',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _backend == TranscriptionBackend.cloud
                              ? beeText(context)
                              : beeTextSub(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Fast, accurate, AI-powered',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: beeTextMuted(context),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OnboardingGlowCard(
                  isSelected: _backend == TranscriptionBackend.whisper,
                  onTap: () => setState(() {
                    _backend = TranscriptionBackend.whisper;
                  }),
                  child: Column(
                    children: [
                      Icon(
                        Icons.memory_rounded,
                        size: 24,
                        color: _backend == TranscriptionBackend.whisper
                            ? beeYellow(context)
                            : beeTextMuted(context),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Offline (Whisper)',
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: _backend == TranscriptionBackend.whisper
                              ? beeText(context)
                              : beeTextSub(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '100% private, runs locally',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: beeTextMuted(context),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Cloud provider sub-choice
          if (_backend == TranscriptionBackend.cloud) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OnboardingGlowCard(
                    isSelected: _cloudProvider == CloudProvider.geminiApiKey,
                    onTap: () => setState(() {
                      _cloudProvider = CloudProvider.geminiApiKey;
                    }),
                    child: Row(
                      children: [
                        Icon(
                          Icons.key_rounded,
                          size: 18,
                          color: _cloudProvider == CloudProvider.geminiApiKey
                              ? beeYellow(context)
                              : beeTextMuted(context),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Gemini API Key',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      _cloudProvider ==
                                          CloudProvider.geminiApiKey
                                      ? beeText(context)
                                      : beeTextSub(context),
                                ),
                              ),
                              Text(
                                'Quick setup with a personal key',
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  color: beeTextMuted(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OnboardingGlowCard(
                    isSelected: _cloudProvider == CloudProvider.vertexAi,
                    onTap: () => setState(() {
                      _cloudProvider = CloudProvider.vertexAi;
                    }),
                    child: Row(
                      children: [
                        Icon(
                          Icons.hub_rounded,
                          size: 18,
                          color: _cloudProvider == CloudProvider.vertexAi
                              ? beeYellow(context)
                              : beeTextMuted(context),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Vertex AI',
                                style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color:
                                      _cloudProvider == CloudProvider.vertexAi
                                      ? beeText(context)
                                      : beeTextSub(context),
                                ),
                              ),
                              Text(
                                'Google Cloud project required',
                                style: GoogleFonts.inter(
                                  fontSize: 9,
                                  color: beeTextMuted(context),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],

          const SizedBox(height: 18),
          OnboardingPrimaryButton(
            label: 'Continue',
            icon: Icons.arrow_forward_rounded,
            onTap: () async {
              await widget.settingsService.setTranscriptionBackend(_backend);
              await widget.settingsService.setCloudProvider(_cloudProvider);
              widget.onNext();
            },
          ),
        ],
      ),
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

class _ApiKeyStepState extends State<ApiKeyStep> {
  final _apiKeyController = TextEditingController();
  final _projectIdController = TextEditingController();
  bool _obscureText = true;
  bool _isVerifying = false;
  String? _statusMessage;
  bool _statusIsError = false;

  CloudProvider get _provider => widget.settingsService.cloudProvider;

  bool get _isFieldEmpty {
    if (_provider == CloudProvider.geminiApiKey) {
      return _apiKeyController.text.trim().isEmpty;
    }
    return _projectIdController.text.trim().isEmpty;
  }

  /// Gemini API keys always start with "AIza".
  bool get _hasValidPrefix {
    final text = _apiKeyController.text.trim();
    if (text.isEmpty) return false;
    return text.startsWith('AIza');
  }

  @override
  void initState() {
    super.initState();
    if (_provider == CloudProvider.vertexAi) {
      _projectIdController.text = widget.settingsService.vertexProjectId ?? '';
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _projectIdController.dispose();
    super.dispose();
  }

  Future<void> _saveAndContinue() async {
    if (_provider == CloudProvider.geminiApiKey) {
      final key = _apiKeyController.text.trim();
      if (key.isNotEmpty) {
        await widget.settingsService.setGeminiApiKey(key);
      }
    } else {
      final projectId = _projectIdController.text.trim();
      if (projectId.isNotEmpty) {
        await widget.settingsService.setVertexProjectId(projectId);
      }
    }
    widget.onNext();
  }

  Future<void> _verifyConnection() async {
    if (widget.onVerifyCloudProvider == null) return;
    setState(() {
      _isVerifying = true;
      _statusMessage = null;
    });
    try {
      await widget.onVerifyCloudProvider!(_provider);
      setState(() {
        _isVerifying = false;
        _statusMessage = _provider == CloudProvider.geminiApiKey
            ? 'API key verified!'
            : 'Vertex AI configuration verified!';
        _statusIsError = false;
      });
    } catch (e) {
      setState(() {
        _isVerifying = false;
        _statusMessage = e.toString();
        _statusIsError = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isGemini = _provider == CloudProvider.geminiApiKey;
    final showPrefixWarning = isGemini &&
        _apiKeyController.text.trim().isNotEmpty &&
        !_hasValidPrefix;

    return OnboardingStepShell(
      icon: isGemini ? Icons.key_rounded : Icons.hub_rounded,
      title: isGemini ? 'API Key' : 'Vertex Project',
      subtitle: isGemini
          ? 'Your Gemini API key is stored locally and never leaves your device.'
          : 'Enter your Google Cloud project ID. ADC credentials are resolved at runtime.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isGemini) ...[
            // API Key field
            OnboardingTextField(
              controller: _apiKeyController,
              hintText: 'AIza...',
              obscureText: _obscureText,
              onChanged: (_) => setState(() {
                _statusMessage = null;
              }),
              suffixIcon: GestureDetector(
                onTap: () => setState(() => _obscureText = !_obscureText),
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Icon(
                    _obscureText
                        ? Icons.visibility_off_rounded
                        : Icons.visibility_rounded,
                    size: 18,
                    color: beeTextMuted(context),
                  ),
                ),
              ),
            ),
          ] else ...[
            // Vertex Project ID field
            OnboardingTextField(
              controller: _projectIdController,
              hintText: 'your-google-cloud-project-id',
              onChanged: (_) => setState(() {
                _statusMessage = null;
              }),
            ),
          ],

          // Prefix validation warning for Gemini keys
          if (showPrefixWarning) ...[
            const SizedBox(height: 8),
            OnboardingStatusBadge(
              label: 'Gemini API keys start with "AIza" — double-check your key',
              isError: false,
              isSuccess: false,
            ),
          ],

          // Status
          if (_statusMessage != null) ...[
            const SizedBox(height: 8),
            OnboardingStatusBadge(
              label: _statusMessage!,
              isError: _statusIsError,
              isSuccess: !_statusIsError,
            ),
          ],

          const SizedBox(height: 14),

          // Verify + Continue row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OnboardingPrimaryButton(
                label: 'Continue',
                icon: Icons.arrow_forward_rounded,
                onTap: _isFieldEmpty ? null : _saveAndContinue,
              ),
              // Only show Verify button when a handler is available
              if (widget.onVerifyCloudProvider != null) ...[
                const SizedBox(width: 10),
                OnboardingSecondaryButton(
                  label: 'Verify',
                  onTap: _isVerifying ? null : _verifyConnection,
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          OnboardingSecondaryButton(
            label: 'Set up later',
            onTap: widget.onSkip,
          ),
        ],
      ),
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

class _ModelStepState extends State<ModelStep> {
  late String _selectedModelId;
  late String _selectedWhisperModelId;

  // Whisper download state
  final WhisperModelDownloadService _downloadService =
      WhisperModelDownloadService();
  List<String> _downloadedModels = [];
  String? _downloadingModelId;
  double _downloadProgress = 0.0;
  bool _downloadError = false;
  String? _downloadErrorMessage;

  bool get _isWhisper =>
      widget.settingsService.transcriptionBackend ==
      TranscriptionBackend.whisper;

  @override
  void initState() {
    super.initState();
    _selectedModelId = widget.settingsService.selectedModelId;
    _selectedWhisperModelId = widget.settingsService.whisperModelId;
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
    // Auto-select if the configured model is downloaded
    if (_downloadedModels.contains(_selectedWhisperModelId)) {
      // Already selected
    } else if (_downloadedModels.isNotEmpty) {
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
    switch (model.id) {
      case 'gemini-2.5-flash':
        return 'Best balance of speed and quality. Recommended default.';
      case 'gemini-2.5-flash-lite':
        return 'Ultra-fast responses, lighter reasoning.';
      case 'gemini-3-flash':
        return 'Newest generation. Advanced reasoning (Preview).';
      case 'gemini-3.5-flash':
        return 'Latest stable Flash. Strong reasoning with high speed.';
      case 'gemini-3.1-flash-lite':
        return 'Next-gen lightweight. Fast with upgraded reasoning.';
      default:
        return 'High-quality AI model.';
    }
  }

  String _speedLabel(GeminiModelConfig model) {
    if (model.id.contains('lite')) return '⚡ Ultra Fast';
    return '🚀 Balanced';
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isWhisper) return _buildWhisperModelStep();
    return _buildCloudModelStep();
  }

  // ── Cloud Model Step ─────────────────────────────────────────────────

  Widget _buildCloudModelStep() {
    return OnboardingStepShell(
      icon: Icons.auto_awesome_rounded,
      title: 'Choose Your Model',
      subtitle: 'Select the AI model that powers your voice transcription.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 220),
            child: SingleChildScrollView(
              child: Column(
                children: AppConfig.availableModels.map((model) {
                  final isSelected = _selectedModelId == model.id;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: OnboardingGlowCard(
                      isSelected: isSelected,
                      onTap: () => setState(() => _selectedModelId = model.id),
                      child: Row(
                        children: [
                          _buildRadioIndicator(isSelected),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      model.displayName,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: isSelected
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: isSelected
                                            ? beeText(context)
                                            : beeTextSub(context),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: beeSurfaceHighest(context)
                                            .withValues(alpha: 0.6),
                                        borderRadius: BorderRadius.circular(
                                          AppTheme.radiusXs,
                                        ),
                                      ),
                                      child: Text(
                                        _speedLabel(model),
                                        style: GoogleFonts.inter(
                                          fontSize: 9,
                                          color: beeTextMuted(context),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  _modelDescription(model),
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: beeTextMuted(context),
                                    height: 1.3,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 14),
          OnboardingPrimaryButton(
            label: 'Continue',
            icon: Icons.arrow_forward_rounded,
            onTap: () async {
              await widget.settingsService.setSelectedModelId(_selectedModelId);
              widget.onNext();
            },
          ),
        ],
      ),
    );
  }

  // ── Whisper Model Step ───────────────────────────────────────────────

  Widget _buildWhisperModelStep() {
    final hasDownloadedModel = _downloadedModels.contains(
      _selectedWhisperModelId,
    );

    return OnboardingStepShell(
      icon: Icons.memory_rounded,
      title: 'Download Whisper Model',
      subtitle:
          'Download a model for offline transcription. Tiny is recommended for most users.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
              child: Column(
                children: WhisperModelDownloadService.availableModels.map((
                  model,
                ) {
                  final isDownloaded = _downloadedModels.contains(model.id);
                  final isDownloading = _downloadingModelId == model.id;
                  final isSelected = _selectedWhisperModelId == model.id;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 5),
                    child: OnboardingGlowCard(
                      isSelected: isDownloaded && isSelected,
                      onTap: isDownloaded
                          ? () => setState(() {
                              _selectedWhisperModelId = model.id;
                            })
                          : null,
                      child: Row(
                        children: [
                          // Status icon
                          if (isDownloading)
                            SizedBox(
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
                          else if (isDownloaded)
                            _buildRadioIndicator(isSelected)
                          else
                            Container(
                              width: 18,
                              height: 18,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: beeBorder(context),
                                  width: 1.5,
                                ),
                              ),
                            ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      model.name,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        fontWeight: isDownloaded
                                            ? FontWeight.w700
                                            : FontWeight.w500,
                                        color: isDownloaded
                                            ? beeText(context)
                                            : beeTextSub(context),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: beeSurfaceHighest(context)
                                            .withValues(alpha: 0.6),
                                        borderRadius: BorderRadius.circular(
                                          AppTheme.radiusXs,
                                        ),
                                      ),
                                      child: Text(
                                        model.sizeDisplay,
                                        style: GoogleFonts.inter(
                                          fontSize: 9,
                                          color: beeTextMuted(context),
                                        ),
                                      ),
                                    ),
                                    if (isDownloaded) ...[
                                      const SizedBox(width: 6),
                                      Icon(
                                        Icons.check_circle_rounded,
                                        size: 14,
                                        color: beeSuccess(context),
                                      ),
                                    ],
                                  ],
                                ),
                                // Download progress bar
                                if (isDownloading) ...[
                                  const SizedBox(height: 4),
                                  ClipRRect(
                                    borderRadius: BorderRadius.circular(3),
                                    child: LinearProgressIndicator(
                                      value: _downloadProgress,
                                      backgroundColor:
                                          beeSurfaceHighest(context),
                                      valueColor: AlwaysStoppedAnimation(
                                        beeYellow(context),
                                      ),
                                      minHeight: 4,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${WhisperModelDownloadService.formatBytes((_downloadProgress * model.sizeBytes).round())} / ${model.sizeDisplay}',
                                    style: GoogleFonts.inter(
                                      fontSize: 9,
                                      color: beeTextMuted(context),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          // Download button for non-downloaded models
                          if (!isDownloaded && !isDownloading)
                            GestureDetector(
                              onTap: _downloadingModelId == null
                                  ? () => _startDownload(model)
                                  : null,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: _downloadingModelId == null
                                      ? beeYellow(context).withValues(alpha: 0.12)
                                      : beeSurfaceHighest(context).withValues(
                                          alpha: 0.3,
                                        ),
                                  borderRadius: BorderRadius.circular(
                                    AppTheme.radiusSm,
                                  ),
                                  border: Border.all(
                                    color: _downloadingModelId == null
                                        ? beeYellow(context).withValues(alpha: 0.65)
                                        : beeBorder(context),
                                  ),
                                ),
                                child: Text(
                                  'Download',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                    color: _downloadingModelId == null
                                        ? beeYellow(context)
                                        : beeTextMuted(context),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Error message
          if (_downloadError && _downloadErrorMessage != null) ...[
            const SizedBox(height: 6),
            OnboardingStatusBadge(label: _downloadErrorMessage!, isError: true),
          ],

          const SizedBox(height: 14),
          OnboardingPrimaryButton(
            label: hasDownloadedModel ? 'Continue' : 'Skip for Now',
            icon: hasDownloadedModel
                ? Icons.arrow_forward_rounded
                : Icons.arrow_forward_rounded,
            onTap: () async {
              if (hasDownloadedModel) {
                await widget.settingsService.setWhisperModelId(
                  _selectedWhisperModelId,
                );
              }
              widget.onNext();
            },
          ),
        ],
      ),
    );
  }

  // ── Shared ───────────────────────────────────────────────────────────

  Widget _buildRadioIndicator(bool isSelected) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected ? beeYellow(context) : Colors.transparent,
        border: Border.all(
          color: isSelected ? beeYellow(context) : beeBorder(context),
          width: 1.5,
        ),
      ),
      child: isSelected
          ? Center(
              child: Container(
                width: 7,
                height: 7,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
              ),
            )
          : null,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEP 5 — Transcription Mode (Default / Concise / Smart Mode)
// ═══════════════════════════════════════════════════════════════════════════

class TranscriptionModeStep extends StatefulWidget {
  final VoidCallback onNext;
  final SettingsService settingsService;

  const TranscriptionModeStep({
    super.key,
    required this.onNext,
    required this.settingsService,
  });

  @override
  State<TranscriptionModeStep> createState() => _TranscriptionModeStepState();
}

class _TranscriptionModeStepState extends State<TranscriptionModeStep> {
  late String _selectedPromptId;

  @override
  void initState() {
    super.initState();
    _selectedPromptId = widget.settingsService.selectedPromptId;
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingStepShell(
      icon: Icons.tune_rounded,
      title: 'Transcription Style',
      subtitle:
          'Choose how your voice is processed. You can always change this later.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...SystemPrompt.availablePrompts.map((prompt) {
            final isSelected = _selectedPromptId == prompt.id;
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: OnboardingGlowCard(
                isSelected: isSelected,
                onTap: () => setState(() => _selectedPromptId = prompt.id),
                child: Row(
                  children: [
                    // Icon per mode
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? beeYellow(context).withValues(alpha: 0.12)
                            : beeSurfaceHighest(context).withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      ),
                      child: Icon(
                        prompt.id == 'standard'
                            ? Icons.text_fields_rounded
                            : prompt.id == 'concise'
                            ? Icons.compress_rounded
                            : Icons.auto_awesome_rounded,
                        size: 18,
                        color: isSelected
                            ? beeYellow(context)
                            : beeTextMuted(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            prompt.name,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isSelected
                                  ? beeText(context)
                                  : beeTextSub(context),
                            ),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            _promptDescription(prompt.id),
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: beeTextMuted(context),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Radio indicator
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 16,
                      height: 16,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected ? beeYellow(context) : Colors.transparent,
                        border: Border.all(
                          color: isSelected ? beeYellow(context) : beeBorder(context),
                          width: 1.5,
                        ),
                      ),
                      child: isSelected
                          ? Center(
                              child: Container(
                                width: 6,
                                height: 6,
                                decoration: const BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: Colors.white,
                                ),
                              ),
                            )
                          : null,
                    ),
                  ],
                ),
              ),
            );
          }),

          const SizedBox(height: 14),
          OnboardingPrimaryButton(
            label: 'Continue',
            icon: Icons.arrow_forward_rounded,
            onTap: () async {
              await widget.settingsService.setSelectedPromptId(
                _selectedPromptId,
              );
              widget.onNext();
            },
          ),
        ],
      ),
    );
  }

  String _promptDescription(String id) {
    switch (id) {
      case 'standard':
        return 'Clean, accurate transcription with grammar fixes. Best for most use cases.';
      case 'concise':
        return 'Condensed output — removes filler, keeps only essential information.';
      case 'smart':
        return 'Restructured with formatting, headings & bullet points. Great for notes & docs.';
      default:
        return 'Custom transcription mode.';
    }
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEP 6 — Two-Pass Transcription & Rephrase
// ═══════════════════════════════════════════════════════════════════════════

class TwoPassRephraseStep extends StatefulWidget {
  final VoidCallback onNext;
  final SettingsService settingsService;

  const TwoPassRephraseStep({
    super.key,
    required this.onNext,
    required this.settingsService,
  });

  @override
  State<TwoPassRephraseStep> createState() => _TwoPassRephraseStepState();
}

class _TwoPassRephraseStepState extends State<TwoPassRephraseStep> {
  bool _twoPassEnabled = false;
  RephraseLevel _rephraseLevel = RephraseLevel.off;

  @override
  void initState() {
    super.initState();
    _twoPassEnabled = widget.settingsService.twoPassTranscriptionEnabled;
    _rephraseLevel = widget.settingsService.rephraseLevel;
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingStepShell(
      icon: Icons.layers_rounded,
      title: 'Refinement Options',
      subtitle: 'Add extra processing passes for higher-quality output.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Two-Pass Toggle ──────────────────────────────────────────
          OnboardingGlowCard(
            isSelected: _twoPassEnabled,
            onTap: () => setState(() => _twoPassEnabled = !_twoPassEnabled),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: _twoPassEnabled
                        ? beeYellow(context).withValues(alpha: 0.12)
                        : beeSurfaceHighest(context).withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  ),
                  child: Icon(
                    Icons.merge_type_rounded,
                    size: 16,
                    color: _twoPassEnabled
                        ? beeYellow(context)
                        : beeTextMuted(context),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Two-Pass Transcription',
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: _twoPassEnabled
                                  ? beeText(context)
                                  : beeTextSub(context),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: beeYellow(context).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(
                                AppTheme.radiusXs,
                              ),
                            ),
                            child: Text(
                              'BETA',
                              style: GoogleFonts.inter(
                                fontSize: 8,
                                fontWeight: FontWeight.w700,
                                color: beeYellow(context),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'First pass transcribes, second pass refines with AI for higher accuracy.',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: beeTextMuted(context),
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                // Toggle switch
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 40,
                  height: 22,
                  decoration: BoxDecoration(
                    color: _twoPassEnabled
                        ? beeYellow(context)
                        : beeSurfaceHighest(context),
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(
                      color: _twoPassEnabled ? beeYellow(context) : beeBorder(context),
                    ),
                  ),
                  child: AnimatedAlign(
                    duration: const Duration(milliseconds: 200),
                    alignment: _twoPassEnabled
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _twoPassEnabled
                            ? Colors.white
                            : beeTextMuted(context),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          // ── Rephrase Level ───────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: beeSurfaceRaised(context),
              borderRadius: BorderRadius.circular(AppTheme.radiusLg),
              border: Border.all(color: beeBorder(context).withValues(alpha: 0.6)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.auto_fix_high_rounded,
                      size: 16,
                      color: beeYellow(context),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Professional Rephrasing',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: beeText(context),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Padding(
                  padding: const EdgeInsets.only(left: 24),
                  child: Text(
                    'Add a professional polish layer on top of your transcription.',
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: beeTextMuted(context),
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: RephraseLevel.values.map((level) {
                    final isSelected = _rephraseLevel == level;
                    return Expanded(
                      child: GestureDetector(
                        onTap: () => setState(() => _rephraseLevel = level),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? beeYellow(context).withValues(alpha: 0.10)
                                : beeSurfaceHighest(context),
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusMd,
                            ),
                            border: Border.all(
                              color: isSelected
                                  ? beeYellow(context).withValues(alpha: 0.65)
                                  : beeBorder(context).withValues(alpha: 0.6),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              level.displayName,
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isSelected
                                    ? beeText(context)
                                    : beeTextMuted(context),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 0),
                  child: Text(
                    _rephraseLevel.description,
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      color: beeTextMuted(context),
                      height: 1.3,
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),
          OnboardingPrimaryButton(
            label: 'Continue',
            icon: Icons.arrow_forward_rounded,
            onTap: () async {
              final s = widget.settingsService;
              await s.setTwoPassTranscriptionEnabled(_twoPassEnabled);
              if (_twoPassEnabled) {
                // Initialize two-pass model IDs with the current model
                await s.setTwoPassTranscriptionModelId(s.selectedModelId);
                await s.setTwoPassRefinementModelId(s.selectedModelId);
              }
              await s.setRephraseLevel(_rephraseLevel);
              widget.onNext();
            },
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEP 7 — Recording Mode
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

class _RecordingModeStepState extends State<RecordingModeStep> {
  late RecordingMode _mode;

  @override
  void initState() {
    super.initState();
    _mode = widget.settingsService.recordingMode;
  }

  @override
  Widget build(BuildContext context) {
    return OnboardingStepShell(
      icon: Icons.fiber_manual_record_rounded,
      title: 'Recording Mode',
      subtitle: 'How do you want to trigger voice recording?',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: OnboardingGlowCard(
                  isSelected: _mode == RecordingMode.toggle,
                  onTap: () => setState(() => _mode = RecordingMode.toggle),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.touch_app_rounded,
                            size: 20,
                            color: _mode == RecordingMode.toggle
                                ? beeYellow(context)
                                : beeTextMuted(context),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Toggle',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _mode == RecordingMode.toggle
                                  ? beeText(context)
                                  : beeTextSub(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Press once to start, press again to stop and process.',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: beeTextMuted(context),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: beeSurfaceHighest(context).withValues(
                            alpha: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusXs,
                          ),
                        ),
                        child: Text(
                          'Great for longer recordings',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: beeYellow(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OnboardingGlowCard(
                  isSelected: _mode == RecordingMode.hold,
                  onTap: () => setState(() => _mode = RecordingMode.hold),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.back_hand_rounded,
                            size: 20,
                            color: _mode == RecordingMode.hold
                                ? beeYellow(context)
                                : beeTextMuted(context),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Hold',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: _mode == RecordingMode.hold
                                  ? beeText(context)
                                  : beeTextSub(context),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Hold the hotkey to record. Release to stop and process.',
                        style: GoogleFonts.inter(
                          fontSize: 10,
                          color: beeTextMuted(context),
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: beeSurfaceHighest(context).withValues(
                            alpha: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusXs,
                          ),
                        ),
                        child: Text(
                          'Fast and intuitive',
                          style: GoogleFonts.inter(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: beeYellow(context),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),
          OnboardingPrimaryButton(
            label: 'Continue',
            icon: Icons.arrow_forward_rounded,
            onTap: () async {
              await widget.settingsService.setRecordingMode(_mode);
              widget.onNext();
            },
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEP 8 — Hotkey
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
    with SingleTickerProviderStateMixin {
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

    if (modifiers.isEmpty) {
      setState(() {
        _errorMessage =
            'Include at least one modifier (Ctrl, Alt, Shift, or Win)';
      });
      return;
    }

    if (key == LogicalKeyboardKey.escape) {
      _stopRecording();
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

  @override
  Widget build(BuildContext context) {
    return OnboardingStepShell(
      icon: Icons.keyboard_command_key_rounded,
      title: 'Set Your Hotkey',
      subtitle:
          'Choose a keyboard shortcut to trigger voice recording from anywhere.',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Hotkey recorder
          KeyboardListener(
            focusNode: _focusNode,
            onKeyEvent: _handleKeyEvent,
            child: GestureDetector(
              onTap: _isRecording ? _stopRecording : _startRecording,
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 14,
                    ),
                    decoration: BoxDecoration(
                      color: _isRecording
                          ? beeYellow(context).withValues(alpha: 0.06)
                          : beeSurfaceRaised(context),
                      borderRadius: BorderRadius.circular(_kRadiusMd),
                      border: Border.all(
                        color: _isRecording ? beeYellow(context) : beeBorder(context),
                        width: 1.5,
                      ),
                      boxShadow: _isRecording
                          ? [
                              BoxShadow(
                                color: beeYellow(context).withValues(
                                  alpha: 0.08 * _pulseAnimation.value,
                                ),
                                blurRadius: 16,
                              ),
                            ]
                          : [],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _isRecording
                              ? Icons.keyboard_rounded
                              : Icons.keyboard_command_key_rounded,
                          color: _isRecording
                              ? beeYellow(context)
                              : beeTextSub(context),
                          size: 24,
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isRecording
                                  ? 'Press your hotkey...'
                                  : _currentHotkey.displayString,
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                                color: _isRecording
                                    ? beeYellow(context)
                                    : beeText(context),
                              ),
                            ),
                            Text(
                              _isRecording
                                  ? 'Press Esc to cancel'
                                  : 'Tap to change',
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: beeTextMuted(context),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),

          // Error
          if (_errorMessage != null) ...[
            const SizedBox(height: 6),
            OnboardingStatusBadge(label: _errorMessage!, isError: true),
          ],

          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              OnboardingPrimaryButton(
                label: 'Continue',
                icon: Icons.arrow_forward_rounded,
                onTap: widget.onNext,
              ),
              const SizedBox(width: 10),
              OnboardingSecondaryButton(
                label: 'Keep Default',
                onTap: widget.onNext,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// STEP 9 — Ready / Finish
// ═══════════════════════════════════════════════════════════════════════════

class ReadyStep extends StatefulWidget {
  final VoidCallback onFinish;
  final SettingsService settingsService;
  final VoidCallback? onGoToApiKeyStep;
  final VoidCallback? onGoToModelStep;

  const ReadyStep({
    super.key,
    required this.onFinish,
    required this.settingsService,
    this.onGoToApiKeyStep,
    this.onGoToModelStep,
  });

  @override
  State<ReadyStep> createState() => _ReadyStepState();
}

class _ReadyStepState extends State<ReadyStep>
    with SingleTickerProviderStateMixin {
  late AnimationController _successController;

  @override
  void initState() {
    super.initState();
    _successController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..forward();
  }

  @override
  void dispose() {
    _successController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settingsService;
    final isWhisper = s.transcriptionBackend == TranscriptionBackend.whisper;

    // Determine readiness based on the ACTIVE backend only — not OR logic.
    // A leftover Gemini key shouldn't make a Whisper user look "ready".
    bool isReady;
    if (isWhisper) {
      isReady = WhisperService.listDownloadedModels().isNotEmpty;
    } else {
      isReady = s.hasGeminiApiKey ||
          (s.cloudProvider == CloudProvider.vertexAi &&
              s.vertexProjectId != null);
    }

    final cloudModel = AppConfig.getModelById(s.selectedModelId);
    final whisperModelInfo = WhisperModelDownloadService.getModelInfo(
      s.whisperModelId,
    );
    final prompt = SystemPrompt.getById(s.selectedPromptId);
    final rephraseLevel = s.rephraseLevel;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const SizedBox(height: 8),

        // Animated orb — amber checkmark when ready, amber warning when not
        AnimatedBuilder(
          animation: _successController,
          builder: (context, child) {
            final t = Curves.easeOutBack.transform(
              _successController.value.clamp(0.0, 1.0),
            );
            return Transform.scale(
              scale: t,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isReady
                      ? LinearGradient(
                          colors: [beeYellow(context), beeYellowDim(context)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : LinearGradient(
                          colors: [
                            beeYellow(context).withValues(alpha: 0.7),
                            beeYellowDim(context),
                          ],
                        ),
                  boxShadow: [
                    BoxShadow(
                      color: beeYellow(context).withValues(alpha: 0.3),
                      blurRadius: 20,
                      spreadRadius: 3,
                    ),
                  ],
                ),
                child: Icon(
                  isReady
                      ? Icons.check_rounded
                      : Icons.warning_amber_rounded,
                  color: Colors.white,
                  size: 28,
                ),
              ),
            );
          },
        ),

        const SizedBox(height: 16),
        Text(
          isReady ? "You're All Set!" : 'Almost There',
          textAlign: TextAlign.center,
          style: GoogleFonts.spaceGrotesk(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: beeText(context),
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          isReady
              ? 'Beeamvo is configured and ready to use.'
              : 'Configure a transcription backend to start using Beeamvo.',
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 12, color: beeTextSub(context)),
        ),

        // Warning banner when no backend is configured
        if (!isReady) ...[
          const SizedBox(height: 14),
          Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: beeYellow(context).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(_kRadiusMd),
              border: Border.all(
                color: beeYellow(context).withValues(alpha: 0.30),
              ),
            ),
            child: Column(
              children: [
                Row(
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
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: beeYellow(context),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isWhisper
                                ? 'Download a Whisper model to enable offline transcription, or switch to Cloud mode.'
                                : 'Enter a valid API key to enable cloud transcription, or switch to Offline mode.',
                            style: GoogleFonts.inter(
                              fontSize: 10,
                              color: beeTextSub(context),
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    if (!isWhisper && widget.onGoToApiKeyStep != null)
                      OnboardingSecondaryButton(
                        label: 'Set Up API Key',
                        onTap: widget.onGoToApiKeyStep,
                      ),
                    if (isWhisper && widget.onGoToModelStep != null) ...[
                      OnboardingSecondaryButton(
                        label: 'Download Model',
                        onTap: widget.onGoToModelStep,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 16),

        // Summary card
        Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: beeSurfaceRaised(context),
              borderRadius: BorderRadius.circular(_kRadiusLg),
              border: Border.all(color: beeDivider(context)),
            ),
            child: Column(
              children: [
                _summaryRow(
                  Icons.graphic_eq_rounded,
                  'Engine',
                  s.transcriptionBackend == TranscriptionBackend.cloud
                      ? 'Cloud'
                      : 'Offline (Whisper)',
                ),
                Divider(color: beeDivider(context), height: 16),
                _summaryRow(
                  Icons.auto_awesome_rounded,
                  'Model',
                  isWhisper
                      ? (whisperModelInfo?.name ?? s.whisperModelId)
                      : cloudModel.displayName,
                ),
                Divider(color: beeDivider(context), height: 16),
                _summaryRow(Icons.tune_rounded, 'Mode', prompt.name),
                Divider(color: beeDivider(context), height: 16),
                _summaryRow(
                  Icons.layers_rounded,
                  'Two-Pass',
                  s.twoPassTranscriptionEnabled ? 'Enabled' : 'Off',
                ),
                Divider(color: beeDivider(context), height: 16),
                _summaryRow(
                  Icons.auto_fix_high_rounded,
                  'Rephrase',
                  rephraseLevel.displayName,
                ),
                Divider(color: beeDivider(context), height: 16),
                _summaryRow(
                  Icons.fiber_manual_record_rounded,
                  'Recording',
                  s.recordingMode == RecordingMode.toggle ? 'Toggle' : 'Hold',
                ),
                Divider(color: beeDivider(context), height: 16),
                _summaryRow(
                  Icons.keyboard_command_key_rounded,
                  'Hotkey',
                  s.hotkey.displayString,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 4),
      ],
    );
  }

  Widget _summaryRow(IconData icon, String label, String value) {
    return Row(
      children: [
        Icon(icon, size: 16, color: beeYellow(context)),
        const SizedBox(width: 10),
        Text(
          label,
          style: GoogleFonts.inter(fontSize: 12, color: beeTextMuted(context)),
        ),
        const Spacer(),
        Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: beeText(context),
          ),
        ),
      ],
    );
  }
}

// ─── local tokens ───────────────────────────────────────────────────────
const double _kRadiusMd = AppTheme.radiusMd;
const double _kRadiusLg = AppTheme.radiusLg;
