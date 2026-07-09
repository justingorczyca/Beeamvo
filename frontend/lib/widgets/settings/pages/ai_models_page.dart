import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../providers/settings_provider.dart';
import '../../../config.dart';
import '../../../models/system_prompt.dart';
import '../../../services/settings_service.dart';
import '../../../services/whisper_service.dart';
import '../../../services/whisper_model_download_service.dart';
import '../settings_shared.dart';
import '../bee_dropdown.dart';
import '../bee_input.dart';
import '../bee_page_header.dart';

class AiModelsPage extends StatefulWidget {
  final ValueChanged<String>? onModelChanged;
  final ValueChanged<dynamic>? onBackendChanged;
  final Future<void> Function(CloudProvider provider)? onVerifyCloudProvider;
  final VoidCallback? onModelDownloaded;

  const AiModelsPage({
    super.key,
    this.onModelChanged,
    this.onBackendChanged,
    this.onVerifyCloudProvider,
    this.onModelDownloaded,
  });

  @override
  State<AiModelsPage> createState() => _AiModelsPageState();
}

class _AiModelsPageState extends State<AiModelsPage> {
  String _selectedModelId = '';
  TranscriptionBackend _transcriptionBackend = TranscriptionBackend.cloud;
  CloudProvider _cloudProvider = CloudProvider.geminiApiKey;
  bool _twoPassEnabled = false;
  String _twoPassRefinementModelId = '';
  GeminiThinkingLevel? _selectedThinkingLevel; // null = model default
  GeminiThinkingLevel? _selectedRefinementThinkingLevel; // null = model default
  bool _settingsLoaded = false;
  bool _geminiApiKeyPresent = false;
  String? _vertexProjectId;
  bool _isVerifyingCloudProvider = false;
  String? _cloudStatusMessage;
  bool _cloudStatusIsError = false;
  bool _cloudStatusIsVerified = false;

  late WhisperModelDownloadService _downloadService;
  DownloadStatus _lastDownloadStatus = DownloadStatus.idle;
  bool _hasWhisper = false;
  bool _showModelSelector = false;
  List<String> _downloadedWhisperModelIds = const [];
  Set<String> _existingWhisperModelIds = const {};

  @override
  void initState() {
    super.initState();
    _downloadService = WhisperModelDownloadService();
    _downloadService.addListener(_onDownloadStateChanged);
  }

  @override
  void dispose() {
    // Whisper downloads belong to this page. Remove the page callback first,
    // then let cancellation delete any partial file before the notifier itself
    // is disposed. State.dispose cannot await this lifecycle future.
    _downloadService.removeListener(_onDownloadStateChanged);
    unawaited(_downloadService.cancelAndDispose());
    super.dispose();
  }

  void _onDownloadStateChanged() {
    if (!mounted) return;

    final status = _downloadService.status;
    if (status == _lastDownloadStatus) {
      return;
    }

    _lastDownloadStatus = status;
    if (status == DownloadStatus.completed) {
      _refreshDownloadedWhisperModels();
      widget.onModelDownloaded?.call();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Always re-read settings on rebuild so changes from other pages
    // (e.g. the prompts-page rephraser popover flipping the backend
    // to cloud) are reflected here. SettingsProviderScope is an
    // InheritedNotifier, so any SettingsService.notifyListeners()
    // triggers a rebuild of this page; we piggyback on that to
    // refresh our cached state.
    //
    // We skip the initial build's mounting frame to avoid a setState
    // during build — _settingsLoaded is set on first load and then
    // kept in sync on subsequent dependency changes.
    if (!_settingsLoaded) {
      _settingsLoaded = true;
      _loadSettings();
    } else {
      _syncFromSettings();
    }
  }

  /// Lightweight version of [_loadSettings] that only refreshes
  /// the values that can change from outside this page (backend,
  /// two-pass, API-key presence, etc.). Called on every rebuild
  /// after the initial load. The Whisper-model list is NOT re-read
  /// here because it's only mutated by user actions on this page.
  void _syncFromSettings() {
    final s = SettingsProviderScope.of(context).settingsService;
    final newBackend = s.transcriptionBackend;
    final newTwoPass = s.twoPassTranscriptionEnabled;
    final newTwoPassModel = s.twoPassRefinementModelId;
    final newHasGeminiKey = s.hasGeminiApiKey;
    final newVertexProjectId = s.vertexProjectId;
    // Avoid setState if nothing changed (keeps no-op rebuilds cheap).
    if (newBackend == _transcriptionBackend &&
        newTwoPass == _twoPassEnabled &&
        newTwoPassModel == _twoPassRefinementModelId &&
        newHasGeminiKey == _geminiApiKeyPresent &&
        newVertexProjectId == _vertexProjectId) {
      return;
    }
    setState(() {
      _transcriptionBackend = newBackend;
      _twoPassEnabled = newTwoPass;
      _twoPassRefinementModelId = newTwoPassModel;
      _geminiApiKeyPresent = newHasGeminiKey;
      _vertexProjectId = newVertexProjectId;
    });
  }

  void _loadSettings() {
    final s = SettingsProviderScope.of(context).settingsService;
    final downloadedWhisperModels = WhisperService.listDownloadedModels();
    setState(() {
      _selectedModelId = s.selectedModelId;
      _transcriptionBackend = s.transcriptionBackend;
      _cloudProvider = s.cloudProvider;
      _twoPassEnabled = s.twoPassTranscriptionEnabled;
      _twoPassRefinementModelId = s.twoPassRefinementModelId;
      // Load persisted thinking level for the currently selected model
      _selectedThinkingLevel = s.getThinkingLevelForModel(_selectedModelId);
      _selectedRefinementThinkingLevel = s.getThinkingLevelForModel(
        _twoPassRefinementModelId,
      );
      _cacheDownloadedWhisperModels(downloadedWhisperModels);
      _geminiApiKeyPresent = s.hasGeminiApiKey;
      _vertexProjectId = s.vertexProjectId;
    });
  }

  void _cacheDownloadedWhisperModels(List<String> modelIds) {
    final sortedModelIds = List<String>.from(modelIds)..sort();
    _downloadedWhisperModelIds = List.unmodifiable(sortedModelIds);
    _existingWhisperModelIds = Set.unmodifiable(sortedModelIds);
    _hasWhisper = sortedModelIds.isNotEmpty;
  }

  void _refreshDownloadedWhisperModels() {
    final downloadedWhisperModels = WhisperService.listDownloadedModels();
    if (!mounted) return;
    setState(() => _cacheDownloadedWhisperModels(downloadedWhisperModels));
  }

  Future<void> _onBackendSelected(TranscriptionBackend backend) async {
    final settings = SettingsProviderScope.of(context).settingsService;
    await settings.setTranscriptionBackend(backend);
    // The SettingsService.notifyListeners() call from
    // setTranscriptionBackend now propagates to _BeamVoHomeState's
    // listener, which calls _onBackendChanged (Whisper init/teardown).
    // No need to fire widget.onBackendChanged manually here — it
    // would just double-trigger the handler.
    //
    // When the user switches BACK to Whisper, reset the rephraser to
    // Off. The rephraser is a cloud-only feature; leaving it on
    // Medium/High while on Whisper is silently ineffective (the
    // transcription pipeline has no LLM to apply it). The prompts
    // page would route the next pick through the local→cloud
    // confirmation popover anyway, but the persisted level should
    // not lie about intent between sessions either.
    if (backend == TranscriptionBackend.whisper &&
        settings.rephraseLevel != RephraseLevel.off) {
      await settings.setRephraseLevel(RephraseLevel.off);
    }
    setState(() => _transcriptionBackend = backend);
  }

  Future<void> _onCloudProviderSelected(CloudProvider provider) async {
    final settings = SettingsProviderScope.of(context).settingsService;
    await settings.setCloudProvider(provider);
    setState(() {
      _cloudProvider = provider;
      _cloudStatusMessage = null;
      _cloudStatusIsError = false;
      _cloudStatusIsVerified = false;
    });
  }

  Future<String?> _showTextInputDialog({
    required String title,
    required String hintText,
    String initialValue = '',
    bool obscureText = false,
    String? helperText,
    String? Function(String value)? validator,
  }) async {
    final controller = TextEditingController(text: initialValue);
    String? errorText;
    bool hideText = obscureText;

    return showDialog<String>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            void submit() {
              final value = controller.text.trim();
              final validationError = validator?.call(value);
              if (validationError != null) {
                setDialogState(() => errorText = validationError);
                return;
              }
              Navigator.of(context).pop(value);
            }

            return AlertDialog(
              backgroundColor: beeSurfaceRaised(context),
              shape: beeDialogShape(),
              title: Text(
                title,
                style: GoogleFonts.spaceGrotesk(
                  color: beeText(context),
                  fontWeight: FontWeight.w700,
                  fontSize: 17,
                ),
              ),
              content: SizedBox(
                width: 420,
                child: TextField(
                  controller: controller,
                  autofocus: true,
                  obscureText: hideText,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => submit(),
                  onChanged: (_) {
                    if (errorText != null) {
                      setDialogState(() => errorText = null);
                    }
                  },
                  decoration:
                      beeInputDecoration(
                        context,
                        hint: hintText,
                        suffix: obscureText
                            ? IconButton(
                                tooltip: hideText ? 'Show key' : 'Hide key',
                                icon: Icon(
                                  hideText
                                      ? Icons.visibility_rounded
                                      : Icons.visibility_off_rounded,
                                  size: 18,
                                  color: beeTextMuted(context),
                                ),
                                onPressed: () =>
                                    setDialogState(() => hideText = !hideText),
                              )
                            : null,
                      ).copyWith(
                        helperText: helperText,
                        errorText: errorText,
                        hintStyle: GoogleFonts.inter(
                          color: beeTextMuted(context),
                          fontSize: 13,
                        ),
                        helperStyle: GoogleFonts.inter(
                          color: beeTextMuted(context),
                          fontSize: 11,
                          height: 1.35,
                        ),
                        errorStyle: GoogleFonts.inter(
                          color: beeError(context),
                          fontSize: 11,
                        ),
                        errorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(kBeeRadiusMd),
                          borderSide: BorderSide(color: beeError(context)),
                        ),
                        focusedErrorBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(kBeeRadiusMd),
                          borderSide: BorderSide(color: beeError(context)),
                        ),
                      ),
                  style: GoogleFonts.inter(
                    color: beeText(context),
                    fontSize: 14,
                  ),
                ),
              ),
              actions: [
                TextButton(
                  style: beeSecondaryButtonStyle(context),
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'Cancel',
                    style: GoogleFonts.inter(
                      color: beeTextSub(context),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: beePrimaryButtonStyle(context),
                  onPressed: submit,
                  child: Text(
                    'Save',
                    style: GoogleFonts.inter(
                      color: beeBlack(context),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  String? _validateGeminiApiKey(String value) {
    if (value.isEmpty) {
      return 'Enter an API key or use Remove to clear the saved key.';
    }
    if (RegExp(r'\s').hasMatch(value)) {
      return 'API keys cannot contain spaces.';
    }
    if (value.length < 20) {
      return 'This API key looks too short.';
    }
    return null;
  }

  String? _validateVertexProjectId(String value) {
    if (value.isEmpty) {
      return 'Enter a Google Cloud project ID or use Clear to remove it.';
    }
    final projectIdPattern = RegExp(r'^[a-z][a-z0-9-]{4,28}[a-z0-9]$');
    if (!projectIdPattern.hasMatch(value)) {
      return 'Use 6-30 lowercase letters, numbers, or hyphens. Start with a letter and do not end with a hyphen.';
    }
    return null;
  }

  Future<bool> _confirmDeleteModel(String modelId) async {
    final info = WhisperModelDownloadService.getModelInfo(modelId);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: beeSurfaceRaised(context),
          shape: beeDialogShape(),
          title: Text(
            'Delete Whisper Model?',
            style: GoogleFonts.spaceGrotesk(
              color: beeText(context),
              fontWeight: FontWeight.w700,
              fontSize: 17,
            ),
          ),
          content: SizedBox(
            width: 420,
            child: Text(
              'Remove ${info?.name ?? modelId} from this device? You can download it again later.',
              style: GoogleFonts.inter(
                color: beeTextSub(context),
                fontSize: 13,
                height: 1.45,
              ),
            ),
          ),
          actions: [
            TextButton(
              style: beeSecondaryButtonStyle(context),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Cancel',
                style: GoogleFonts.inter(
                  color: beeTextSub(context),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            ElevatedButton(
              style: beePrimaryButtonStyle(
                context,
                backgroundColor: beeError(context),
                foregroundColor: beeBlack(context),
              ),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                'Delete',
                style: GoogleFonts.inter(
                  color: beeBlack(context),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        );
      },
    );

    return confirmed ?? false;
  }

  Future<void> _showApiKeyDialog() async {
    final settings = SettingsProviderScope.of(context).settingsService;
    final apiKey = await _showTextInputDialog(
      title: 'Gemini API Key',
      hintText: 'AIza...',
      obscureText: true,
      helperText: 'Stored locally. Use the eye button to reveal while editing.',
      validator: _validateGeminiApiKey,
    );
    if (apiKey == null) return;

    await settings.setGeminiApiKey(apiKey);
    setState(() {
      _geminiApiKeyPresent = settings.hasGeminiApiKey;
      _cloudStatusMessage = _geminiApiKeyPresent
          ? 'Gemini API key saved locally.'
          : 'No Gemini API key saved.';
      _cloudStatusIsError = !_geminiApiKeyPresent;
      _cloudStatusIsVerified = false;
    });
  }

  Future<void> _showVertexProjectIdDialog() async {
    final settings = SettingsProviderScope.of(context).settingsService;
    final projectId = await _showTextInputDialog(
      title: 'Vertex Project ID',
      hintText: 'your-google-cloud-project',
      initialValue: _vertexProjectId ?? '',
      helperText:
          'Use the stable Google Cloud project ID, not the display name.',
      validator: _validateVertexProjectId,
    );
    if (projectId == null) return;

    await settings.setVertexProjectId(projectId);
    setState(() {
      _vertexProjectId = settings.vertexProjectId;
      _cloudStatusMessage = _vertexProjectId == null
          ? 'Vertex project ID cleared.'
          : 'Vertex project ID saved.';
      _cloudStatusIsError = _vertexProjectId == null;
      _cloudStatusIsVerified = false;
    });
  }

  Future<void> _clearVertexProjectId() async {
    final settings = SettingsProviderScope.of(context).settingsService;
    await settings.clearVertexProjectId();
    setState(() {
      _vertexProjectId = null;
      _cloudStatusMessage = 'Vertex project ID removed.';
      _cloudStatusIsError = false;
      _cloudStatusIsVerified = false;
    });
  }

  Future<void> _clearApiKey() async {
    final settings = SettingsProviderScope.of(context).settingsService;
    await settings.clearGeminiApiKey();
    setState(() {
      _geminiApiKeyPresent = false;
      _cloudStatusMessage = 'Gemini API key removed.';
      _cloudStatusIsError = false;
      _cloudStatusIsVerified = false;
    });
  }

  Future<void> _verifyCloudProvider() async {
    if (widget.onVerifyCloudProvider == null) return;

    setState(() {
      _isVerifyingCloudProvider = true;
      _cloudStatusMessage = null;
      _cloudStatusIsError = false;
      _cloudStatusIsVerified = false;
    });

    try {
      await widget.onVerifyCloudProvider!.call(_cloudProvider);
      setState(() {
        _cloudStatusMessage = _cloudProvider == CloudProvider.geminiApiKey
            ? 'Gemini API key verified successfully.'
            : 'Vertex AI configuration verified successfully.';
        _cloudStatusIsError = false;
        _cloudStatusIsVerified = true;
      });
    } catch (error) {
      setState(() {
        _cloudStatusMessage = error.toString();
        _cloudStatusIsError = true;
        _cloudStatusIsVerified = false;
      });
    } finally {
      if (mounted) {
        setState(() => _isVerifyingCloudProvider = false);
      }
    }
  }

  Future<void> _startDownload(WhisperModelInfo model) async {
    setState(() => _showModelSelector = false);
    await _downloadService.downloadModel(model);
  }

  Future<void> _cancelDownload() async {
    await _downloadService.cancelDownload();
  }

  Future<void> _deleteModel(String modelId) async {
    final confirmed = await _confirmDeleteModel(modelId);
    if (!confirmed) return;

    final deleted = await _downloadService.deleteModel(modelId);
    if (deleted) {
      _refreshDownloadedWhisperModels();
    }
  }

  String _whisperModelTradeoff(WhisperModelInfo model) {
    switch (model.id) {
      case 'ggml-tiny-q5_1.bin':
        return 'smallest download, lowest memory';
      case 'ggml-tiny.en.bin':
        return 'fast English-only transcription';
      case 'ggml-tiny.bin':
        return 'fastest multilingual baseline';
      case 'ggml-base.bin':
        return 'better accuracy, modest CPU use';
      case 'ggml-small.bin':
        return 'best local accuracy, slower and larger';
      default:
        return 'offline transcription model';
    }
  }

  Widget _buildLoadingState() {
    return Container(
      color: beeSurface(context),
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(beeTextMuted(context)),
              backgroundColor: beeText(context).withValues(alpha: 0.08),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Loading AI settings',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: beeTextSub(context),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_settingsLoaded) return _buildLoadingState();

    return Column(
      children: [
        Expanded(
          child: Container(
            color: beeSurface(context),
            child: SingleChildScrollView(
              padding: BeePageHeader.contentPadding,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const BeePageHeader(title: 'AI Models'),
                  // ── PROCESSING ENGINE ──────────────────────────────
                  const BeeGroupLabel(label: 'Processing Engine'),
                  BeeSettingsRow(
                    icon: Icons.settings_suggest_rounded,
                    label: 'Transcription Backend',
                    description:
                        _transcriptionBackend == TranscriptionBackend.cloud
                        ? 'Using cloud AI for fast transcription and formatting.'
                        : 'Using local Whisper for offline, on-device transcription.',
                    trailing: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 360),
                      child: BeeSegmented<TranscriptionBackend>(
                        value: _transcriptionBackend,
                        options: const [
                          (
                            val: TranscriptionBackend.cloud,
                            label: 'Cloud AI',
                            icon: Icons.cloud_done_rounded,
                          ),
                          (
                            val: TranscriptionBackend.whisper,
                            label: 'Local Whisper',
                            icon: Icons.memory_rounded,
                          ),
                        ],
                        onChanged: _onBackendSelected,
                      ),
                    ),
                  ),

                  const SizedBox(height: BeePageHeader.groupGap),

                  if (_transcriptionBackend == TranscriptionBackend.cloud) ...[
                    // ── CLOUD SETTINGS ────────────────────────────────
                    _buildCloudProviderSection(),

                    const SizedBox(height: BeePageHeader.groupGap),

                    // ── MODEL SETTINGS ────────────────────────────────
                    const BeeGroupLabel(label: 'Model Settings'),
                    BeeSettingsRow(
                      icon: Icons.cloud_outlined,
                      label: 'Primary Cloud Model',
                      description:
                          'The AI model used for high-speed cloud transcription and formatting.',
                      showDivider: !AppConfig.getModelById(
                        _selectedModelId,
                      ).hasSelectableThinkingLevel,
                      trailing: BeeDropdown<String>(
                        value: _safeModelId(_selectedModelId),
                        options: _cloudModelOptions(),
                        onChanged: (v) async {
                          final settings = SettingsProviderScope.of(
                            context,
                          ).settingsService;
                          await settings.setSelectedModelId(v);
                          setState(() {
                            _selectedModelId = v;
                            // Load any saved level for the newly selected model
                            _selectedThinkingLevel = settings
                                .getThinkingLevelForModel(v);
                          });
                          widget.onModelChanged?.call(v);
                        },
                      ),
                    ),

                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 280),
                      crossFadeState:
                          AppConfig.getModelById(
                            _selectedModelId,
                          ).hasSelectableThinkingLevel
                          ? CrossFadeState.showFirst
                          : CrossFadeState.showSecond,
                      firstChild: _buildThinkingLevelRow(),
                      secondChild: const SizedBox(width: double.infinity),
                    ),

                    const SizedBox(height: BeePageHeader.groupGap),
                  ] else ...[
                    // ── LOCAL SETTINGS ─────────────────────────────────
                    const BeeGroupLabel(label: 'Local Settings'),
                    BeeSettingsRow(
                      icon: Icons.memory_rounded,
                      label: 'Whisper Engine',
                      description:
                          'Offline speech recognition running entirely on your device.',
                      trailing: beeBadge(
                        context,
                        '${_downloadedWhisperModelIds.length} ${_downloadedWhisperModelIds.length == 1 ? 'model' : 'models'}',
                        _hasWhisper
                            ? BeeBadgeTone.success
                            : BeeBadgeTone.neutral,
                      ),
                    ),
                    Builder(
                      builder: (context) {
                        final settings = SettingsProviderScope.of(
                          context,
                        ).settingsService;
                        return BeeSettingsRow(
                          icon: Icons.language_rounded,
                          label: 'Spoken Language',
                          description:
                              'The language Whisper should expect in the audio.',
                          trailing: BeeDropdown<String>(
                            value: _safeLanguageId(settings.whisperLanguage),
                            options: _languageOptions,
                            onChanged: (v) async {
                              await settings.setWhisperLanguage(v);
                              setState(() {});
                            },
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: BeePageHeader.groupGap),
                    _buildLocalWhisperModelsHeader(),
                    _buildOfflineModelManagerFlat(),
                    const SizedBox(height: BeePageHeader.groupGap),
                  ],

                  // ── TRANSCRIPTION PIPELINE ────────────────────────
                  _buildPipelineSection(),

                  const SizedBox(height: BeePageHeader.groupGap),

                  // ── FOOTNOTE ──────────────────────────────────────
                  _buildSettingsLocalFootnote(),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Plain text footnote — no bordered container.
  Widget _buildSettingsLocalFootnote() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        'Preferences are saved in your OS application data folder. Cloud credentials are not written into the settings JSON.',
        style: GoogleFonts.inter(
          fontSize: 11,
          color: beeTextMuted(context),
          height: 1.5,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  /// Eyebrow section header used by the always-visible Pipeline area.
  /// Always-visible Two-Pass Refinement section. Promoted out of the
  /// collapsed Advanced block because it is one of the most consequential
  /// workflow choices on this page and should be reachable without a tap.
  Widget _buildPipelineSection() {
    final settings = SettingsProviderScope.of(context).settingsService;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BeeGroupLabel(label: 'Transcription Pipeline'),
        BeeSettingsRow(
          icon: Icons.linear_scale_rounded,
          label: 'Two-Pass Refinement',
          warningBadge: beeBadge(context, 'BETA', BeeBadgeTone.neutral),
          description:
              'Pipeline your audio through a raw transcription pass, followed by an AI refinement pass.',
          trailing: BeeToggle(
            value: _twoPassEnabled,
            semanticLabel: 'Two-pass refinement',
            onChanged: (v) async {
              await settings.setTwoPassTranscriptionEnabled(v);
              if (v) {
                await settings.setTwoPassRefinementModelId(_selectedModelId);
                _twoPassRefinementModelId = _selectedModelId;
                _selectedRefinementThinkingLevel = settings
                    .getThinkingLevelForModel(_selectedModelId);
              }
              setState(() => _twoPassEnabled = v);
            },
          ),
        ),
        if (_twoPassEnabled) ...[
          BeeSettingsRow(
            icon: Icons.looks_one_rounded,
            label: 'Pass 1 · Raw Transcription',
            description: _transcriptionBackend == TranscriptionBackend.cloud
                ? 'Uses ${AppConfig.getModelById(_selectedModelId).displayName} (primary cloud model).'
                : 'Uses the selected local Whisper model.',
            trailing: beeBadge(
              context,
              _transcriptionBackend == TranscriptionBackend.cloud
                  ? 'Cloud'
                  : 'Local',
              BeeBadgeTone.neutral,
            ),
          ),
          BeeSettingsRow(
            icon: Icons.looks_two_rounded,
            label: 'Pass 2 · AI Refinement',
            description:
                'Cloud model that formats, corrects, and structures the raw transcript.',
            trailing: BeeDropdown<String>(
              value: _safeModelId(_twoPassRefinementModelId),
              options: _cloudModelOptions(),
              onChanged: (v) async {
                await settings.setTwoPassRefinementModelId(v);
                setState(() {
                  _twoPassRefinementModelId = v;
                  _selectedRefinementThinkingLevel = settings
                      .getThinkingLevelForModel(v);
                });
              },
            ),
          ),
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 240),
            crossFadeState:
                AppConfig.getModelById(
                  _twoPassRefinementModelId,
                ).hasSelectableThinkingLevel
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: _buildThinkingLevelControl(
              title: 'Refinement Thinking',
              description: 'Reasoning effort for the refinement pass.',
              modelId: _twoPassRefinementModelId,
              selectedLevel: _selectedRefinementThinkingLevel,
              onChanged: (level) =>
                  setState(() => _selectedRefinementThinkingLevel = level),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
          if (_transcriptionBackend == TranscriptionBackend.whisper)
            _buildCloudFallbackRow(),
        ],
      ],
    );
  }

  /// Shows whether the cloud provider is configured for two-pass when on local backend.
  Widget _buildCloudFallbackRow() {
    final isGemini = _cloudProvider == CloudProvider.geminiApiKey;
    final env = dotenv.isInitialized ? dotenv.env : const <String, String>{};
    final geminiEnvKey = env['GEMINI_API_KEY']?.trim() ?? '';
    final vertexEnvProjectId = env['VERTEX_PROJECT_ID']?.trim() ?? '';
    final cloudConfigured = isGemini
        ? (geminiEnvKey.isNotEmpty || _geminiApiKeyPresent)
        : (vertexEnvProjectId.isNotEmpty || _vertexProjectId != null);
    final providerLabel = isGemini ? 'Gemini API Key' : 'Vertex AI';

    return BeeSettingsRow(
      icon: cloudConfigured
          ? Icons.cloud_done_outlined
          : Icons.cloud_off_outlined,
      label: 'Cloud Fallback',
      description:
          '$providerLabel · ${cloudConfigured ? 'Ready' : 'Not configured'}',
      showDivider: false,
      trailing: !cloudConfigured
          ? BeeActionChip(
              label: 'Configure',
              onTap: () => _onBackendSelected(TranscriptionBackend.cloud),
            )
          : beeBadge(context, 'Ready', BeeBadgeTone.success),
    );
  }

  Widget _buildCloudProviderSection() {
    final isGemini = _cloudProvider == CloudProvider.geminiApiKey;
    final env = dotenv.isInitialized ? dotenv.env : const <String, String>{};
    final geminiEnvKey = env['GEMINI_API_KEY']?.trim() ?? '';
    final vertexEnvProjectId = env['VERTEX_PROJECT_ID']?.trim() ?? '';
    final geminiManagedByEnv = geminiEnvKey.isNotEmpty;
    final vertexProjectManagedByEnv = vertexEnvProjectId.isNotEmpty;
    final isConfigured = isGemini
        ? (geminiManagedByEnv || _geminiApiKeyPresent)
        : (vertexProjectManagedByEnv || _vertexProjectId != null);
    final isManagedByEnv =
        (isGemini && geminiManagedByEnv) ||
        (!isGemini && vertexProjectManagedByEnv);

    // Credential status label for the row description
    String credentialDesc;
    if (isManagedByEnv) {
      credentialDesc = isGemini
          ? 'API key loaded from .env file (read-only).'
          : 'Project ID managed by .env file (read-only).';
    } else if (!isConfigured) {
      credentialDesc = isGemini
          ? 'No API key configured. Add one to enable cloud transcription.'
          : 'No project ID set. Configure one for Vertex AI access.';
    } else {
      credentialDesc = isGemini
          ? 'API key stored locally in secure storage.'
          : 'Project ID: ${_vertexProjectId ?? ''}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BeeGroupLabel(label: 'Cloud Provider'),
        BeeSettingsRow(
          icon: Icons.cloud_outlined,
          label: 'Provider',
          description: isGemini
              ? 'Direct API key setup for individual use.'
              : 'Google Cloud project with Application Default Credentials.',
          trailing: BeeSegmented<CloudProvider>(
            value: _cloudProvider,
            onChanged: _onCloudProviderSelected,
            options: const [
              (
                val: CloudProvider.geminiApiKey,
                label: 'Gemini',
                icon: Icons.key_rounded,
              ),
              (
                val: CloudProvider.vertexAi,
                label: 'Vertex AI',
                icon: Icons.hub_rounded,
              ),
            ],
          ),
        ),
        BeeSettingsRow(
          icon: isGemini ? Icons.key_rounded : Icons.hub_rounded,
          label: isGemini ? 'API Key' : 'Project ID',
          description: credentialDesc,
          trailing: _buildCredentialTrailing(
            isGemini: isGemini,
            isManagedByEnv: isManagedByEnv,
            isConfigured: isConfigured,
          ),
        ),
        if (isConfigured && !isManagedByEnv)
          BeeSettingsRow(
            icon: _cloudStatusIsVerified
                ? Icons.verified_rounded
                : _cloudStatusIsError
                ? Icons.error_outline_rounded
                : Icons.verified_outlined,
            label: 'Connection',
            description:
                _cloudStatusMessage ??
                'Verify that your credentials work correctly.',
            showDivider: false,
            trailing: BeeActionChip(
              label: _isVerifyingCloudProvider ? 'Verifying…' : 'Verify',
              onTap: !_isVerifyingCloudProvider ? _verifyCloudProvider : null,
            ),
          ),
      ],
    );
  }

  Widget _buildCredentialTrailing({
    required bool isGemini,
    required bool isManagedByEnv,
    required bool isConfigured,
  }) {
    if (isManagedByEnv) {
      return beeBadge(context, '.env', BeeBadgeTone.success);
    }
    if (!isConfigured) {
      return BeeActionChip(
        label: isGemini ? 'Add API Key' : 'Set Project ID',
        onTap: isGemini ? _showApiKeyDialog : _showVertexProjectIdDialog,
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        beeBadge(context, 'Ready', BeeBadgeTone.success),
        const SizedBox(width: 6),
        BeeActionChip(
          label: 'Edit',
          onTap: isGemini ? _showApiKeyDialog : _showVertexProjectIdDialog,
        ),
        const SizedBox(width: 6),
        BeeActionChip(
          label: 'Remove',
          color: beeError(context),
          onTap: isGemini ? _clearApiKey : _clearVertexProjectId,
        ),
      ],
    );
  }

  Widget _buildLocalWhisperModelsHeader() {
    final isDownloading = _downloadService.status == DownloadStatus.downloading;
    final hasError = _downloadService.status == DownloadStatus.error;

    return Row(
      children: [
        const Expanded(child: BeeGroupLabel(label: 'Local Whisper Models')),
        if (!_showModelSelector && _hasWhisper && !isDownloading && !hasError)
          BeeActionChip(
            label: 'Add Model',
            icon: Icons.add_rounded,
            onTap: () => setState(() => _showModelSelector = true),
          ),
      ],
    );
  }

  Widget _buildOfflineModelManagerFlat() {
    return AnimatedBuilder(
      animation: _downloadService,
      builder: (context, _) {
        final isDownloading =
            _downloadService.status == DownloadStatus.downloading;
        final hasError = _downloadService.status == DownloadStatus.error;

        if (isDownloading) {
          return _buildFlatDownloadProgress();
        }
        if (hasError) {
          return _buildFlatErrorState();
        }
        if (_showModelSelector || !_hasWhisper) {
          return _buildFlatModelSelector();
        }
        return _buildFlatModelList();
      },
    );
  }

  Widget _buildFlatDownloadProgress() {
    final progress = _downloadService.progress;
    final downloaded = WhisperModelDownloadService.formatBytes(
      _downloadService.bytesDownloaded,
    );
    final total = WhisperModelDownloadService.formatBytes(
      _downloadService.totalBytes,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BeeSettingsRow(
          icon: Icons.downloading_rounded,
          label: 'Downloading ${_downloadService.currentModelId}',
          description: '${(progress * 100).toInt()}% · $downloaded of $total',
          showDivider: false,
          trailing: BeeActionChip(label: 'Cancel', onTap: _cancelDownload),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(1.5),
            child: LinearProgressIndicator(
              value: progress,
              backgroundColor: beeText(context).withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(beeTextSub(context)),
              minHeight: 3,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFlatErrorState() {
    return BeeSettingsRow(
      icon: Icons.error_outline_rounded,
      label: 'Download Failed',
      description: _downloadService.errorMessage ?? 'Network error.',
      showDivider: false,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BeeActionChip(
            label: 'Retry',
            onTap: () {
              _downloadService.resetState();
              setState(() {});
            },
          ),
          const SizedBox(width: 8),
          BeeActionChip(
            label: 'Cancel',
            onTap: () {
              _downloadService.resetState();
              setState(() => _showModelSelector = false);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFlatModelList() {
    final settings = SettingsProviderScope.of(context).settingsService;
    final activeModelId = settings.whisperModelId;
    final entries = _downloadedWhisperModelIds.toList();

    return Column(
      children: [
        for (final modelId in entries)
          _buildFlatModelRow(modelId, activeModelId),
      ],
    );
  }

  Widget _buildFlatModelRow(String modelId, String activeModelId) {
    final isActive = modelId == activeModelId;
    final info = WhisperModelDownloadService.getModelInfo(modelId);

    return BeeRadioTile(
      isSelected: isActive,
      label: info?.name ?? modelId,
      subtitle: info == null
          ? 'Unknown size'
          : '${info.sizeDisplay} · ${_whisperModelTradeoff(info)}',
      showDivider: false,
      badge: BeeInteractive(
        onTap: () => _deleteModel(modelId),
        semanticLabel: 'Delete ${info?.name ?? modelId}',
        builder: (context, focused) => Padding(
          padding: const EdgeInsets.all(4),
          child: Icon(
            Icons.delete_outline_rounded,
            size: 14,
            color: beeError(context).withValues(alpha: 0.8),
          ),
        ),
      ),
      onTap: () async {
        final settings = SettingsProviderScope.of(context).settingsService;
        await settings.setWhisperModelId(modelId);
        setState(() {});
        widget.onModelDownloaded?.call();
      },
    );
  }

  Widget _buildFlatModelSelector() {
    final models = WhisperModelDownloadService.availableModels;
    return Column(
      children: [
        for (final model in models) _buildFlatSelectorRow(model),
        if (_hasWhisper) ...[
          const SizedBox(height: 8),
          BeeSettingsRow(
            icon: Icons.arrow_back_rounded,
            label: 'Back to Installed Models',
            showDivider: false,
            trailing: BeeActionChip(
              label: 'Back',
              onTap: () => setState(() => _showModelSelector = false),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFlatSelectorRow(WhisperModelInfo model) {
    final exists = _existingWhisperModelIds.contains(model.id);
    return BeeSettingsRow(
      icon: exists
          ? Icons.download_done_rounded
          : Icons.cloud_download_outlined,
      label: model.name,
      description: '${model.sizeDisplay} · ${_whisperModelTradeoff(model)}',
      showDivider: false,
      trailing: exists
          ? beeBadge(context, 'Installed', BeeBadgeTone.success)
          : BeeActionChip(
              label: 'Download',
              onTap: () => _startDownload(model),
            ),
    );
  }

  Widget _buildThinkingLevelRow() {
    return _buildThinkingLevelControl(
      title: 'Thinking Level',
      description:
          'Control how much internal reasoning the model performs. '
          'Higher levels improve accuracy for complex tasks; lower levels '
          'reduce latency and token cost.',
      modelId: _selectedModelId,
      selectedLevel: _selectedThinkingLevel,
      onChanged: (level) => setState(() => _selectedThinkingLevel = level),
    );
  }

  Widget _buildThinkingLevelControl({
    required String title,
    required String description,
    required String modelId,
    required GeminiThinkingLevel? selectedLevel,
    required ValueChanged<GeminiThinkingLevel> onChanged,
  }) {
    final modelConfig = AppConfig.getModelById(modelId);
    final levels = modelConfig.supportedThinkingLevels;
    if (levels.isEmpty) {
      return const SizedBox.shrink();
    }

    final effective =
        selectedLevel ?? modelConfig.thinkingLevel ?? levels.first;

    final options = levels
        .map(
          (level) =>
              (val: level, label: level.displayLabel, icon: null as IconData?),
        )
        .toList();

    String rowDesc = effective.description;
    if (selectedLevel == null) {
      rowDesc = '$rowDesc (Using model default)';
    }

    return BeeSettingsRow(
      icon: Icons.psychology_rounded,
      label: title,
      description: rowDesc,
      showDivider: false,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: BeeSegmented<GeminiThinkingLevel>(
          value: effective,
          onChanged: (level) async {
            final settings = SettingsProviderScope.of(context).settingsService;
            await settings.setThinkingLevelForModel(modelId, level);
            onChanged(level);
          },
          options: options,
        ),
      ),
    );
  }

  /// Dropdown options for every available cloud model. Shared by the
  /// primary-model and two-pass refinement [BeeDropdown] triggers.
  List<BeeDropdownOption<String>> _cloudModelOptions() {
    return [
      for (final m in AppConfig.availableModels)
        BeeDropdownOption(value: m.id, label: m.displayName),
    ];
  }

  /// Resolves a (possibly stale) persisted model id to one that still
  /// exists in [AppConfig.availableModels], falling back to the default so
  /// the [BeeDropdown] trigger always renders a label rather than blanking.
  String _safeModelId(String id) {
    return AppConfig.availableModels.any((m) => m.id == id)
        ? id
        : AppConfig.availableModels.first.id;
  }

  /// Spoken-language choices for the Whisper engine dropdown.
  static const List<BeeDropdownOption<String>> _languageOptions = [
    BeeDropdownOption(value: 'auto', label: 'Auto-Detect'),
    BeeDropdownOption(value: 'en', label: 'English'),
    BeeDropdownOption(value: 'de', label: 'German'),
    BeeDropdownOption(value: 'fr', label: 'French'),
    BeeDropdownOption(value: 'es', label: 'Spanish'),
  ];

  /// Resolves a (possibly stale) persisted language code to one present in
  /// [_languageOptions], falling back to auto-detect.
  String _safeLanguageId(String id) {
    return _languageOptions.any((o) => o.value == id) ? id : 'auto';
  }
}
