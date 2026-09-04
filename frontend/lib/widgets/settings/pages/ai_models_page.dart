import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../providers/settings_provider.dart';
import '../../../config.dart';
import '../../../services/settings_service.dart';
import '../../../services/whisper_service.dart';
import '../../../services/whisper_model_download_service.dart';
import '../settings_shared.dart';
import '../bee_dropdown.dart';
import '../bee_input.dart';
import '../bee_page_header.dart';

class AiModelsPage extends StatefulWidget {
  final ValueChanged<String>? onModelChanged;
  final Future<void> Function(CloudProvider provider)? onVerifyCloudProvider;
  final VoidCallback? onModelDownloaded;

  const AiModelsPage({
    super.key,
    this.onModelChanged,
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
  String _twoPassTranscriptionModelId = '';
  GeminiThinkingLevel? _selectedThinkingLevel; // null = model default
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

  bool get _isOffline => _transcriptionBackend == TranscriptionBackend.whisper;
  bool get _isGemini => _cloudProvider == CloudProvider.geminiApiKey;

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
    if (status == _lastDownloadStatus) return;
    _lastDownloadStatus = status;
    if (status == DownloadStatus.completed) {
      _refreshDownloadedWhisperModels();
      widget.onModelDownloaded?.call();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // SettingsProviderScope is an InheritedNotifier, so any
    // SettingsService.notifyListeners() rebuilds this page; re-read the
    // values other surfaces (tray, prompts page) can change.
    if (!_settingsLoaded) {
      _settingsLoaded = true;
      _loadSettings();
    } else {
      _syncFromSettings();
    }
  }

  void _syncFromSettings() {
    final s = SettingsProviderScope.of(context).settingsService;
    final newBackend = s.transcriptionBackend;
    final newTwoPass = s.twoPassTranscriptionEnabled;
    final newStepOneModel = s.twoPassTranscriptionModelId;
    final newModel = s.selectedModelId;
    final newHasGeminiKey = s.hasGeminiApiKey;
    final newVertexProjectId = s.vertexProjectId;
    if (newBackend == _transcriptionBackend &&
        newTwoPass == _twoPassEnabled &&
        newStepOneModel == _twoPassTranscriptionModelId &&
        newModel == _selectedModelId &&
        newHasGeminiKey == _geminiApiKeyPresent &&
        newVertexProjectId == _vertexProjectId) {
      return;
    }
    setState(() {
      _transcriptionBackend = newBackend;
      _twoPassEnabled = newTwoPass;
      _twoPassTranscriptionModelId = newStepOneModel;
      _selectedModelId = newModel;
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
      _twoPassTranscriptionModelId = s.twoPassTranscriptionModelId;
      _selectedThinkingLevel = s.getThinkingLevelForModel(_selectedModelId);
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

  Future<void> _onModelSelected(String modelId) async {
    final settings = SettingsProviderScope.of(context).settingsService;
    await settings.setSelectedModelId(modelId);
    setState(() {
      _selectedModelId = modelId;
      _selectedThinkingLevel = settings.getThinkingLevelForModel(modelId);
    });
    widget.onModelChanged?.call(modelId);
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

    return Container(
      color: beeSurface(context),
      child: SingleChildScrollView(
        padding: BeePageHeader.contentPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const BeePageHeader(title: 'Transcription'),
            _buildEngineSection(),
            const SizedBox(height: BeePageHeader.groupGap),
            if (_isOffline) ...[
              _buildLocalWhisperModelsHeader(),
              _buildOfflineModelManagerFlat(),
            ] else ...[
              _buildCloudProviderSection(),
              const SizedBox(height: BeePageHeader.groupGap),
              _buildAiModelSection(),
            ],
            const SizedBox(height: BeePageHeader.groupGap),
            _buildTwoStepSection(),
            const SizedBox(height: BeePageHeader.groupGap),
            _buildSettingsLocalFootnote(),
          ],
        ),
      ),
    );
  }

  Widget _buildEngineSection() {
    final settings = SettingsProviderScope.of(context).settingsService;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BeeGroupLabel(label: 'Engine'),
        BeeSettingsRow(
          icon: Icons.settings_suggest_rounded,
          label: 'Where audio is transcribed',
          description: _isOffline
              ? 'On this device with Whisper. Works offline; nothing leaves your computer.'
              : 'Cloud AI transcribes and applies your writing style in one step.',
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
                  label: 'Offline',
                  icon: Icons.memory_rounded,
                ),
              ],
              onChanged: _onBackendSelected,
            ),
          ),
        ),
        BeeSettingsRow(
          icon: Icons.language_rounded,
          label: 'Spoken Language',
          description:
              'Auto-detect works well; pick a language to improve accuracy.',
          showDivider: false,
          trailing: BeeDropdown<String>(
            value: _safeLanguageId(settings.spokenLanguage),
            options: _languageOptions,
            onChanged: (v) async {
              await settings.setSpokenLanguage(v);
              setState(() {});
            },
          ),
        ),
      ],
    );
  }

  Widget _buildAiModelSection({bool showDivider = false}) {
    final model = AppConfig.getModelById(_selectedModelId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BeeGroupLabel(label: 'AI Model'),
        BeeSettingsRow(
          icon: Icons.auto_awesome_rounded,
          label: 'Model',
          description: 'Writes the final text and applies your writing style.',
          showDivider: model.hasSelectableThinkingLevel || showDivider,
          trailing: BeeDropdown<String>(
            value: _safeModelId(_selectedModelId),
            options: _mainModelOptions(),
            onChanged: _onModelSelected,
          ),
        ),
        if (model.hasSelectableThinkingLevel)
          _buildThinkingLevelRow(showDivider: showDivider),
      ],
    );
  }

  /// Two-step refinement, with both steps visible together so the pipeline
  /// reads top-to-bottom: raw transcript first, polished text second.
  Widget _buildTwoStepSection() {
    final settings = SettingsProviderScope.of(context).settingsService;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BeeGroupLabel(label: 'Two-Step Refinement'),
        BeeSettingsRow(
          icon: Icons.linear_scale_rounded,
          label: 'Refine in two steps',
          description: _isOffline
              ? 'Transcribe offline, then let a cloud AI model polish the text with your writing style.'
              : 'Use a dedicated speech model for the transcript, then polish it with your AI model.',
          showDivider: _twoPassEnabled,
          trailing: BeeToggle(
            value: _twoPassEnabled,
            semanticLabel: 'Two-step refinement',
            onChanged: (v) async {
              await settings.setTwoPassTranscriptionEnabled(v);
              setState(() => _twoPassEnabled = v);
            },
          ),
        ),
        AnimatedSize(
          duration: kBeeTransitionDuration,
          curve: kBeeTransitionCurve,
          alignment: Alignment.topCenter,
          child: _twoPassEnabled
              ? _buildTwoStepDetails(settings)
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }

  Widget _buildTwoStepDetails(SettingsService settings) {
    final whisperInfo = WhisperModelDownloadService.getModelInfo(
      settings.whisperModelId,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isOffline)
          BeeSettingsRow(
            icon: Icons.looks_one_rounded,
            label: 'Step 1 · Transcribe',
            description: whisperInfo?.name ?? settings.whisperModelId,
            trailing: beeBadge(context, 'Offline', BeeBadgeTone.neutral),
          )
        else if (_isGemini)
          BeeSettingsRow(
            icon: Icons.looks_one_rounded,
            label: 'Step 1 · Transcribe',
            description: 'Speech-to-text model for the raw transcript.',
            trailing: BeeDropdown<String>(
              value: _safeStepOneModelId(_twoPassTranscriptionModelId),
              options: _stepOneModelOptions(),
              onChanged: (v) async {
                await settings.setTwoPassTranscriptionModelId(v);
                setState(() => _twoPassTranscriptionModelId = v);
              },
            ),
          )
        else
          BeeSettingsRow(
            icon: Icons.looks_one_rounded,
            label: 'Step 1 · Transcribe',
            description: 'Your AI model writes the raw transcript.',
            trailing: beeBadge(context, 'Vertex AI', BeeBadgeTone.neutral),
          ),
        BeeSettingsRow(
          icon: Icons.looks_two_rounded,
          label: 'Step 2 · Polish',
          description: _isOffline
              ? 'A cloud AI model applies your writing style. Set it up below.'
              : '${AppConfig.getModelById(_selectedModelId).displayName} applies your writing style.',
          showDivider: _isOffline,
        ),
        if (_isOffline) ...[
          const SizedBox(height: BeePageHeader.groupGap),
          _buildCloudProviderSection(),
          const SizedBox(height: BeePageHeader.groupGap),
          _buildAiModelSection(),
        ],
      ],
    );
  }

  Widget _buildSettingsLocalFootnote() {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        'Preferences are saved in your OS application data folder. Cloud credentials are kept in secure storage, never in the settings file.',
        style: GoogleFonts.inter(
          fontSize: 11,
          color: beeTextMuted(context),
          height: 1.5,
          fontStyle: FontStyle.italic,
        ),
      ),
    );
  }

  Widget _buildCloudProviderSection() {
    final isGemini = _isGemini;
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

    String credentialDesc;
    if (isManagedByEnv) {
      credentialDesc = isGemini
          ? 'API key loaded from .env file (read-only).'
          : 'Project ID managed by .env file (read-only).';
    } else if (!isConfigured) {
      credentialDesc = isGemini
          ? 'Add your Gemini API key to enable cloud AI.'
          : 'Set your Google Cloud project ID. Vertex AI signs in with your local Application Default Credentials.';
    } else {
      credentialDesc = isGemini
          ? 'Stored in your OS secure storage.'
          : 'Project ID: ${_vertexProjectId ?? ''}. Signs in with your local Application Default Credentials.';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BeeGroupLabel(label: 'Cloud Account'),
        BeeSettingsRow(
          icon: Icons.cloud_outlined,
          label: 'Provider',
          description: isGemini
              ? 'Gemini with a personal API key.'
              : 'Google Cloud project via Vertex AI.',
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
          showDivider: isConfigured && !isManagedByEnv,
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
                _cloudStatusMessage ?? 'Check that your credentials work.',
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

  Widget _buildThinkingLevelRow({bool showDivider = false}) {
    final modelConfig = AppConfig.getModelById(_selectedModelId);
    final levels = modelConfig.supportedThinkingLevels;
    if (levels.isEmpty) return const SizedBox.shrink();

    final effective =
        modelConfig.resolveThinkingLevel(
          levelOverride: _selectedThinkingLevel,
        ) ??
        levels.first;
    final options = levels
        .map(
          (level) =>
              (val: level, label: level.displayLabel, icon: null as IconData?),
        )
        .toList();
    final rowDesc = _selectedThinkingLevel == null
        ? '${effective.description} (model default)'
        : effective.description;

    return BeeSettingsRow(
      icon: Icons.psychology_rounded,
      label: 'Thinking',
      description: rowDesc,
      showDivider: showDivider,
      trailing: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: BeeSegmented<GeminiThinkingLevel>(
          value: effective,
          onChanged: (level) async {
            final settings = SettingsProviderScope.of(context).settingsService;
            await settings.setThinkingLevelForModel(_selectedModelId, level);
            setState(() => _selectedThinkingLevel = level);
          },
          options: options,
        ),
      ),
    );
  }

  /// Prompt-capable models: the only valid choices for the AI model.
  List<BeeDropdownOption<String>> _mainModelOptions() {
    return [
      for (final m in AppConfig.mainModels)
        BeeDropdownOption(value: m.id, label: m.displayName),
    ];
  }

  /// Step 1 choices on Gemini: dedicated speech models plus any main model.
  List<BeeDropdownOption<String>> _stepOneModelOptions() {
    return [
      for (final m in AppConfig.transcriptionModels)
        BeeDropdownOption(value: m.id, label: m.displayName),
      for (final m in AppConfig.mainModels)
        BeeDropdownOption(value: m.id, label: m.displayName),
    ];
  }

  String _safeModelId(String id) => AppConfig.resolveRefinementModelId(id);

  String _safeStepOneModelId(String id) {
    return AppConfig.isOfferedModelId(id)
        ? id
        : AppConfig.defaultTranscriptionModelId;
  }

  static const List<BeeDropdownOption<String>> _languageOptions = [
    BeeDropdownOption(value: 'auto', label: 'Auto-Detect'),
    BeeDropdownOption(value: 'en', label: 'English'),
    BeeDropdownOption(value: 'de', label: 'German'),
    BeeDropdownOption(value: 'fr', label: 'French'),
    BeeDropdownOption(value: 'es', label: 'Spanish'),
  ];

  String _safeLanguageId(String id) {
    return _languageOptions.any((o) => o.value == id) ? id : 'auto';
  }
}
