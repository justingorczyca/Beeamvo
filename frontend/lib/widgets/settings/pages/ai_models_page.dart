import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../providers/settings_provider.dart';
import '../../../config.dart';
import '../../../services/codex_oauth_manager.dart';
import '../../../services/openai_compatible_service.dart';
import '../../../services/settings_service.dart';
import '../../../services/whisper_service.dart';
import '../../../services/whisper_model_download_service.dart';
import '../../../services/xai_oauth_manager.dart';
import '../settings_shared.dart';
import '../cloud_provider_presentation.dart';
import '../bee_dropdown.dart';
import '../bee_input.dart';
import '../bee_page_header.dart';

class AiModelsPage extends StatefulWidget {
  final Future<void> Function(CloudProvider provider)? onVerifyCloudProvider;
  final VoidCallback? onModelDownloaded;

  const AiModelsPage({
    super.key,
    this.onVerifyCloudProvider,
    this.onModelDownloaded,
  });

  @override
  State<AiModelsPage> createState() => _AiModelsPageState();
}

/// Connection feedback for one provider account. Kept per provider because
/// the transcription and polish accounts can be on screen at the same time.
typedef _ProviderStatus = ({String message, bool isError, bool isVerified});

class _AiModelsPageState extends State<AiModelsPage> {
  String _selectedModelId = '';
  TranscriptionBackend _transcriptionBackend = TranscriptionBackend.cloud;
  CloudProvider _cloudProvider = CloudProvider.geminiApiKey;
  CloudProvider _refinementProvider = CloudProvider.geminiApiKey;
  bool _twoPassEnabled = false;
  String _twoPassRefinementModelId = '';
  GeminiThinkingLevel? _selectedThinkingLevel; // null = pass default
  bool _settingsLoaded = false;
  bool _geminiApiKeyPresent = false;
  String? _vertexProjectId;
  bool _openAiApiKeyPresent = false;
  String? _openAiBaseUrl;
  bool _codexSignedIn = false;
  bool _codexSignInInProgress = false;
  CodexOAuthFlow? _codexFlow;
  bool _grokSignedIn = false;
  bool _grokSignInInProgress = false;
  XAiOAuthFlow? _grokFlow;
  final Set<CloudProvider> _verifyingProviders = {};
  final Map<CloudProvider, _ProviderStatus> _providerStatus = {};

  late WhisperModelDownloadService _downloadService;
  DownloadStatus _lastDownloadStatus = DownloadStatus.idle;
  bool _hasWhisper = false;
  bool _showModelSelector = false;
  List<String> _downloadedWhisperModelIds = const [];
  Set<String> _existingWhisperModelIds = const {};

  bool get _isOffline => _transcriptionBackend == TranscriptionBackend.whisper;

  /// Records connection feedback for [provider]; a null [message] clears it.
  void _setStatus(
    CloudProvider provider,
    String? message, {
    bool isError = false,
    bool isVerified = false,
  }) {
    if (message == null) {
      _providerStatus.remove(provider);
    } else {
      _providerStatus[provider] = (
        message: message,
        isError: isError,
        isVerified: isVerified,
      );
    }
  }

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
    unawaited(_codexFlow?.cancel() ?? Future<void>.value());
    unawaited(_grokFlow?.cancel() ?? Future<void>.value());
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
    final newProvider = s.cloudProvider;
    final newRefinementProvider = s.refinementProvider;
    final newThinking = s.getThinkingLevelForModel(s.selectedModelId);
    final newTwoPass = s.twoPassTranscriptionEnabled;
    final newRefinementModel = s.twoPassRefinementModelId;
    final newModel = s.selectedModelId;
    final newHasGeminiKey = s.hasGeminiApiKey;
    final newVertexProjectId = s.vertexProjectId;
    final newHasOpenAiKey = s.hasOpenAiApiKey;
    final newOpenAiBaseUrl = s.openAiBaseUrl;
    final newCodexSignedIn = s.hasCodexAuth;
    final newGrokSignedIn = s.hasGrokAuth;
    if (newBackend == _transcriptionBackend &&
        newProvider == _cloudProvider &&
        newRefinementProvider == _refinementProvider &&
        newThinking == _selectedThinkingLevel &&
        newTwoPass == _twoPassEnabled &&
        newRefinementModel == _twoPassRefinementModelId &&
        newModel == _selectedModelId &&
        newHasGeminiKey == _geminiApiKeyPresent &&
        newVertexProjectId == _vertexProjectId &&
        newHasOpenAiKey == _openAiApiKeyPresent &&
        newOpenAiBaseUrl == _openAiBaseUrl &&
        newCodexSignedIn == _codexSignedIn &&
        newGrokSignedIn == _grokSignedIn) {
      return;
    }
    setState(() {
      _transcriptionBackend = newBackend;
      _cloudProvider = newProvider;
      _refinementProvider = newRefinementProvider;
      _selectedThinkingLevel = newThinking;
      _twoPassEnabled = newTwoPass;
      _twoPassRefinementModelId = newRefinementModel;
      _selectedModelId = newModel;
      _geminiApiKeyPresent = newHasGeminiKey;
      _vertexProjectId = newVertexProjectId;
      _openAiApiKeyPresent = newHasOpenAiKey;
      _openAiBaseUrl = newOpenAiBaseUrl;
      _codexSignedIn = newCodexSignedIn;
      _grokSignedIn = newGrokSignedIn;
    });
  }

  void _loadSettings() {
    final s = SettingsProviderScope.of(context).settingsService;
    final downloadedWhisperModels = WhisperService.listDownloadedModels();
    setState(() {
      _selectedModelId = s.selectedModelId;
      _transcriptionBackend = s.transcriptionBackend;
      _cloudProvider = s.cloudProvider;
      _refinementProvider = s.refinementProvider;
      _twoPassEnabled = s.twoPassTranscriptionEnabled;
      _twoPassRefinementModelId = s.twoPassRefinementModelId;
      _selectedThinkingLevel = s.getThinkingLevelForModel(_selectedModelId);
      _cacheDownloadedWhisperModels(downloadedWhisperModels);
      _geminiApiKeyPresent = s.hasGeminiApiKey;
      _vertexProjectId = s.vertexProjectId;
      _openAiApiKeyPresent = s.hasOpenAiApiKey;
      _openAiBaseUrl = s.openAiBaseUrl;
      _codexSignedIn = s.hasCodexAuth;
      _grokSignedIn = s.hasGrokAuth;
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
      _refinementProvider = settings.refinementProvider;
      _twoPassRefinementModelId = settings.twoPassRefinementModelId;
    });
  }

  Future<void> _onRefinementProviderSelected(CloudProvider provider) async {
    final settings = SettingsProviderScope.of(context).settingsService;
    await settings.setRefinementProvider(provider);
    setState(() {
      _refinementProvider = provider;
      _twoPassRefinementModelId = settings.twoPassRefinementModelId;
    });
  }

  Future<void> _onModelSelected(String modelId) async {
    final settings = SettingsProviderScope.of(context).settingsService;
    await settings.setSelectedModelId(modelId);
    setState(() {
      _selectedModelId = settings.selectedModelId;
      _selectedThinkingLevel = settings.getThinkingLevelForModel(
        _selectedModelId,
      );
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
      _setStatus(
        CloudProvider.geminiApiKey,
        _geminiApiKeyPresent
            ? 'Gemini API key saved locally.'
            : 'No Gemini API key saved.',
        isError: !_geminiApiKeyPresent,
      );
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
      _setStatus(
        CloudProvider.vertexAi,
        _vertexProjectId == null
            ? 'Vertex project ID cleared.'
            : 'Vertex project ID saved.',
        isError: _vertexProjectId == null,
      );
    });
  }

  Future<void> _clearVertexProjectId() async {
    final settings = SettingsProviderScope.of(context).settingsService;
    await settings.clearVertexProjectId();
    setState(() {
      _vertexProjectId = null;
      _setStatus(CloudProvider.vertexAi, 'Vertex project ID removed.');
    });
  }

  Future<void> _clearApiKey() async {
    final settings = SettingsProviderScope.of(context).settingsService;
    await settings.clearGeminiApiKey();
    setState(() {
      _geminiApiKeyPresent = false;
      _setStatus(CloudProvider.geminiApiKey, 'Gemini API key removed.');
    });
  }

  String? _validateOpenAiApiKey(String value) {
    if (value.isEmpty) {
      return 'Enter an API key or use Remove to clear the saved key.';
    }
    if (RegExp(r'\s').hasMatch(value)) {
      return 'API keys cannot contain spaces.';
    }
    return null;
  }

  Future<void> _showOpenAiApiKeyDialog() async {
    final settings = SettingsProviderScope.of(context).settingsService;
    final apiKey = await _showTextInputDialog(
      title: 'OpenAI API Key',
      hintText: 'sk-...',
      obscureText: true,
      helperText: 'Stored locally. Use the eye button to reveal while editing.',
      validator: _validateOpenAiApiKey,
    );
    if (apiKey == null) return;

    await settings.setOpenAiApiKey(apiKey);
    setState(() {
      _openAiApiKeyPresent = settings.hasOpenAiApiKey;
      _setStatus(
        CloudProvider.openaiApiKey,
        _openAiApiKeyPresent
            ? 'OpenAI API key saved locally.'
            : 'No OpenAI API key saved.',
        isError: !_openAiApiKeyPresent,
      );
    });
  }

  Future<void> _clearOpenAiApiKey() async {
    final settings = SettingsProviderScope.of(context).settingsService;
    await settings.clearOpenAiApiKey();
    setState(() {
      _openAiApiKeyPresent = false;
      _setStatus(CloudProvider.openaiApiKey, 'OpenAI API key removed.');
    });
  }

  String? _validateOpenAiBaseUrl(String value) {
    if (value.isEmpty) {
      return 'Enter a base URL, or use Reset to return to api.openai.com.';
    }
    try {
      OpenAiCompatibleService.normalizeBaseUrl(value);
    } catch (e) {
      return e.toString();
    }
    return null;
  }

  Future<void> _showOpenAiBaseUrlDialog() async {
    final settings = SettingsProviderScope.of(context).settingsService;
    final baseUrl = await _showTextInputDialog(
      title: 'OpenAI-Compatible Base URL',
      hintText: 'https://api.openai.com/v1',
      initialValue: _openAiBaseUrl ?? AppConfig.openAiDefaultBaseUrl,
      helperText:
          'HTTPS only (HTTP allowed for localhost). Polish requests go to '
          '<base>/chat/completions.',
      validator: _validateOpenAiBaseUrl,
    );
    if (baseUrl == null) return;

    final normalized = OpenAiCompatibleService.normalizeBaseUrl(baseUrl);
    await settings.setOpenAiBaseUrl(normalized);
    setState(() {
      _openAiBaseUrl = settings.openAiBaseUrl;
      _setStatus(
        CloudProvider.openaiApiKey,
        'OpenAI-compatible endpoint saved.',
      );
    });
  }

  Future<void> _resetOpenAiBaseUrl() async {
    final settings = SettingsProviderScope.of(context).settingsService;
    await settings.setOpenAiBaseUrl(null);
    setState(() {
      _openAiBaseUrl = null;
      _setStatus(
        CloudProvider.openaiApiKey,
        'OpenAI endpoint reset to api.openai.com.',
      );
    });
  }

  Future<void> _startCodexSignIn() async {
    final settings = SettingsProviderScope.of(context).settingsService;
    setState(() {
      _codexSignInInProgress = true;
      _setStatus(
        CloudProvider.codexOAuth,
        'Complete the ChatGPT sign-in in your browser…',
      );
    });
    try {
      final flow = await settings.codexOAuth.startLogin();
      _codexFlow = flow;
      await flow.completion;
      await settings.refreshCodexAuthState();
      if (!mounted) return;
      setState(() {
        _codexSignedIn = settings.hasCodexAuth;
        _setStatus(
          CloudProvider.codexOAuth,
          'Signed in with ChatGPT.',
          isVerified: true,
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _setStatus(
          CloudProvider.codexOAuth,
          error.toString(),
          isError: true,
        ),
      );
    } finally {
      _codexFlow = null;
      if (mounted) {
        setState(() => _codexSignInInProgress = false);
      }
    }
  }

  Future<void> _signOutCodex() async {
    final settings = SettingsProviderScope.of(context).settingsService;
    await _codexFlow?.cancel();
    await settings.signOutCodex();
    setState(() {
      _codexSignedIn = false;
      _setStatus(CloudProvider.codexOAuth, 'Signed out of ChatGPT Codex.');
    });
  }

  Future<void> _startGrokSignIn() async {
    final settings = SettingsProviderScope.of(context).settingsService;
    setState(() {
      _grokSignInInProgress = true;
      _setStatus(
        CloudProvider.grokOAuth,
        'Complete the xAI sign-in in your browser…',
      );
    });
    try {
      final flow = await settings.xaiOAuth.startLogin();
      _grokFlow = flow;
      await flow.completion;
      await settings.refreshGrokAuthState();
      if (!mounted) return;
      setState(() {
        _grokSignedIn = settings.hasGrokAuth;
        _setStatus(
          CloudProvider.grokOAuth,
          'Signed in with xAI.',
          isVerified: true,
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(
        () => _setStatus(
          CloudProvider.grokOAuth,
          error.toString(),
          isError: true,
        ),
      );
    } finally {
      _grokFlow = null;
      if (mounted) {
        setState(() => _grokSignInInProgress = false);
      }
    }
  }

  Future<void> _signOutGrok() async {
    final settings = SettingsProviderScope.of(context).settingsService;
    await _grokFlow?.cancel();
    await settings.signOutGrok();
    setState(() {
      _grokSignedIn = false;
      _setStatus(CloudProvider.grokOAuth, 'Signed out of xAI Grok.');
    });
  }

  Future<void> _verifyCloudProvider(CloudProvider provider) async {
    if (widget.onVerifyCloudProvider == null) return;

    setState(() {
      _verifyingProviders.add(provider);
      _setStatus(provider, null);
    });

    try {
      await widget.onVerifyCloudProvider!.call(provider);
      if (!mounted) return;
      setState(
        () => _setStatus(
          provider,
          '${provider.displayName} connection verified.',
          isVerified: true,
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() => _setStatus(provider, error.toString(), isError: true));
    } finally {
      if (mounted) {
        setState(() => _verifyingProviders.remove(provider));
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
              _buildTranscriptionAccountSection(),
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
    final selectedModelIsTranscriptionOnly = AppConfig.getModelById(
      settings.selectedModelId,
    ).isTranscriptionOnly;
    final transcriptionDescription =
        '${_cloudProvider.displayName} transcribes your audio in the cloud';
    final cloudDescription = switch ((
      selectedModelIsTranscriptionOnly,
      _twoPassEnabled,
    )) {
      (true, false) =>
        '$transcriptionDescription. Turn on two-step refinement to apply your writing style.',
      (true, true) =>
        '$transcriptionDescription; the polish step applies your writing style.',
      _ => '$transcriptionDescription and applies your writing style.',
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BeeGroupLabel(label: 'Engine'),
        BeeSettingsRow(
          icon: Icons.settings_suggest_rounded,
          label: 'Where audio is transcribed',
          description: _isOffline
              ? 'On this device with Whisper. Works offline; nothing leaves your computer.'
              : cloudDescription,
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

  Widget _buildAiModelSection() {
    final model = AppConfig.getModelById(_safeModelId(_selectedModelId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BeeGroupLabel(label: 'AI Model'),
        BeeSettingsRow(
          icon: Icons.auto_awesome_rounded,
          label: 'Model',
          description: _twoPassEnabled
              ? 'Transcribes your audio word for word in step 1.'
              : model.isTranscriptionOnly
              ? AppConfig.transcriptionOnlyStyleNotice
              : 'Writes the final text and applies your writing style.',
          showDivider: model.hasSelectableThinkingLevel,
          trailing: BeeDropdown<String>(
            value: _safeModelId(_selectedModelId),
            options: _mainModelOptions(),
            onChanged: _onModelSelected,
          ),
        ),
        if (model.hasSelectableThinkingLevel) _buildThinkingLevelRow(),
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
              ? 'Transcribe offline, then let any cloud AI polish the text with your writing style.'
              : 'Transcribe with the model above, then let any cloud AI polish the text.',
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
        BeeSettingsRow(
          icon: Icons.looks_one_rounded,
          label: 'Step 1 · Transcribe',
          description: _isOffline
              ? '${whisperInfo?.name ?? settings.whisperModelId} transcribes '
                    'on this device.'
              : '${_cloudProvider.displayName} · '
                    '${AppConfig.getModelById(_safeModelId(_selectedModelId)).displayName} '
                    'transcribes the audio. Change it above.',
          trailing: beeBadge(
            context,
            _isOffline ? 'Offline' : 'Audio',
            BeeBadgeTone.neutral,
          ),
        ),
        _buildStepTwoPolishSection(settings),
      ],
    );
  }

  /// Step 2 · Polish: any provider and any prompt-capable model. It only
  /// receives the step-1 transcript, never audio.
  Widget _buildStepTwoPolishSection(SettingsService settings) {
    final provider = _refinementProvider;
    final models = settings.refinementModels;
    final modelId = settings.twoPassRefinementModelId;
    final model = AppConfig.getModelById(modelId);
    final sharesStepOneAccount = !_isOffline && provider == _cloudProvider;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        BeeSettingsRow(
          icon: Icons.looks_two_rounded,
          label: 'Step 2 · Polish',
          description: sharesStepOneAccount
              ? 'Uses the ${provider.displayName} account above. Receives only '
                    'the transcript, never audio.'
              : '${provider.displayName} polishes the transcript. It never '
                    'receives audio.',
          trailing: BeeDropdown<CloudProvider>(
            key: const ValueKey('two-pass-refinement-provider'),
            value: provider,
            semanticLabel: 'Polish provider',
            options: [
              for (final p in CloudProvider.values)
                BeeDropdownOption(value: p, label: p.displayName, icon: p.icon),
            ],
            onChanged: _onRefinementProviderSelected,
          ),
        ),
        if (!sharesStepOneAccount)
          ..._buildAccountRows(provider, followedByMore: true),
        BeeSettingsRow(
          icon: Icons.edit_note_rounded,
          label: 'Polish model',
          description: model.description.isEmpty
              ? 'Applies your writing style to the transcript.'
              : model.description,
          showDivider: model.hasSelectableThinkingLevel,
          trailing: BeeDropdown<String>(
            key: const ValueKey('two-pass-refinement-model'),
            value: modelId,
            menuMaxWidth: 320,
            options: [
              for (final m in models)
                BeeDropdownOption(value: m.id, label: m.displayName),
            ],
            onChanged: (id) async {
              await settings.setTwoPassRefinementModelId(id);
              setState(() => _twoPassRefinementModelId = id);
            },
          ),
        ),
        if (model.hasSelectableThinkingLevel)
          _buildRefinementThinkingRow(model),
      ],
    );
  }

  Widget _buildRefinementThinkingRow(GeminiModelConfig model) {
    final settings = SettingsProviderScope.of(context).settingsService;
    final saved = settings.getRefinementThinkingLevel(model.id);
    return _thinkingRow(
      key: const ValueKey('two-pass-refinement-thinking'),
      label: 'Polish thinking',
      model: model,
      effective: model.resolveThinkingLevel(levelOverride: saved),
      isDefault: saved == null,
      defaultNote: 'model default',
      onChanged: (level) async {
        await settings.setRefinementThinkingLevel(model.id, level);
        setState(() {});
      },
    );
  }

  /// Shared thinking-level row. Each pass stores its own level, so the first
  /// pass and the polish step never change each other.
  Widget _thinkingRow({
    Key? key,
    required String label,
    required GeminiModelConfig model,
    required GeminiThinkingLevel? effective,
    required bool isDefault,
    required String defaultNote,
    required ValueChanged<GeminiThinkingLevel> onChanged,
  }) {
    final levels = model.supportedThinkingLevels;
    final value = effective ?? levels.first;
    return BeeSettingsRow(
      key: key,
      icon: Icons.psychology_rounded,
      label: label,
      description: isDefault
          ? '${value.description} ($defaultNote)'
          : value.description,
      showDivider: false,
      trailing: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: levels.length > 4 ? 440 : 360),
        child: BeeSegmented<GeminiThinkingLevel>(
          value: value,
          onChanged: onChanged,
          options: [
            for (final level in levels)
              (val: level, label: level.displayLabel, icon: null),
          ],
        ),
      ),
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

  bool _isManagedByEnv(CloudProvider provider) {
    final env = dotenv.isInitialized ? dotenv.env : const <String, String>{};
    bool has(String key) => (env[key]?.trim() ?? '').isNotEmpty;
    return switch (provider) {
      CloudProvider.geminiApiKey => has('GEMINI_API_KEY'),
      CloudProvider.vertexAi => has('VERTEX_PROJECT_ID'),
      CloudProvider.openaiApiKey => has('OPENAI_API_KEY'),
      CloudProvider.codexOAuth || CloudProvider.grokOAuth => false,
    };
  }

  bool get _openAiBaseUrlManagedByEnv =>
      dotenv.isInitialized &&
      (dotenv.env['OPENAI_BASE_URL']?.trim() ?? '').isNotEmpty;

  bool _isConfigured(CloudProvider provider) =>
      _isManagedByEnv(provider) ||
      switch (provider) {
        CloudProvider.geminiApiKey => _geminiApiKeyPresent,
        CloudProvider.vertexAi => _vertexProjectId != null,
        CloudProvider.openaiApiKey => _openAiApiKeyPresent,
        CloudProvider.codexOAuth => _codexSignedIn,
        CloudProvider.grokOAuth => _grokSignedIn,
      };

  /// Step-1 cloud account. Only providers that accept audio are offered;
  /// OpenAI API-key and Grok providers are chosen for the polish step instead.
  Widget _buildTranscriptionAccountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const BeeGroupLabel(label: 'Transcription Account'),
        BeeSettingsRow(
          icon: Icons.cloud_outlined,
          label: 'Provider',
          description: _cloudProvider.description,
          trailing: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: BeeSegmented<CloudProvider>(
              key: const ValueKey('transcription-provider'),
              value: _cloudProvider,
              options: [
                for (final p in AppConfig.firstPassAudioProviders)
                  (val: p, label: p.displayName, icon: p.icon),
              ],
              onChanged: _onCloudProviderSelected,
            ),
          ),
        ),
        ..._buildAccountRows(_cloudProvider),
      ],
    );
  }

  /// Credential rows plus the connection check for [provider]. Set
  /// [followedByMore] when further rows follow in the same group.
  List<Widget> _buildAccountRows(
    CloudProvider provider, {
    bool followedByMore = false,
  }) {
    final isConfigured = _isConfigured(provider);
    final isManagedByEnv = _isManagedByEnv(provider);
    final showConnection = isConfigured && !isManagedByEnv;
    final status = _providerStatus[provider];
    final verifying = _verifyingProviders.contains(provider);
    return [
      ..._buildCredentialRows(
        provider,
        isConfigured: isConfigured,
        isManagedByEnv: isManagedByEnv,
        lastDivider: showConnection || followedByMore,
      ),
      if (showConnection)
        BeeSettingsRow(
          icon: status?.isVerified == true
              ? Icons.verified_rounded
              : status?.isError == true
              ? Icons.error_outline_rounded
              : Icons.verified_outlined,
          label: 'Connection',
          description: status?.message ?? 'Check that your credentials work.',
          showDivider: followedByMore,
          trailing: BeeActionChip(
            label: verifying ? 'Verifying…' : 'Verify',
            onTap: verifying ? null : () => _verifyCloudProvider(provider),
          ),
        ),
    ];
  }

  /// Credential row(s) for [provider] — one per provider except OpenAI,
  /// which adds an endpoint row for OpenAI-compatible base URLs.
  List<Widget> _buildCredentialRows(
    CloudProvider provider, {
    required bool isConfigured,
    required bool isManagedByEnv,
    required bool lastDivider,
  }) {
    switch (provider) {
      case CloudProvider.geminiApiKey:
        return [
          BeeSettingsRow(
            icon: Icons.key_rounded,
            label: 'API Key',
            description: isManagedByEnv
                ? 'API key loaded from .env file (read-only).'
                : !isConfigured
                ? 'Add your Gemini API key to enable cloud AI.'
                : 'Stored in your OS secure storage.',
            showDivider: lastDivider,
            trailing: _buildCredentialTrailing(
              isManagedByEnv: isManagedByEnv,
              isConfigured: isConfigured,
              addLabel: 'Add API Key',
              onEdit: _showApiKeyDialog,
              onRemove: _clearApiKey,
            ),
          ),
        ];
      case CloudProvider.vertexAi:
        return [
          BeeSettingsRow(
            icon: Icons.hub_rounded,
            label: 'Project ID',
            description: isManagedByEnv
                ? 'Project ID managed by .env file (read-only).'
                : !isConfigured
                ? 'Set your Google Cloud project ID. Vertex AI signs in with your local Application Default Credentials.'
                : 'Project ID: ${_vertexProjectId ?? ''}. Signs in with your local Application Default Credentials.',
            showDivider: lastDivider,
            trailing: _buildCredentialTrailing(
              isManagedByEnv: isManagedByEnv,
              isConfigured: isConfigured,
              addLabel: 'Set Project ID',
              onEdit: _showVertexProjectIdDialog,
              onRemove: _clearVertexProjectId,
            ),
          ),
        ];
      case CloudProvider.openaiApiKey:
        final baseUrlManagedByEnv = _openAiBaseUrlManagedByEnv;
        final baseUrlDesc = baseUrlManagedByEnv
            ? 'Endpoint managed by .env file (read-only).'
            : _openAiBaseUrl != null
            ? 'Endpoint: $_openAiBaseUrl'
            : 'Endpoint: ${AppConfig.openAiDefaultBaseUrl} (default).';
        return [
          BeeSettingsRow(
            icon: Icons.key_rounded,
            label: 'API Key',
            description: isManagedByEnv
                ? 'API key loaded from .env file (read-only).'
                : !isConfigured
                ? 'Add an OpenAI API key, or a key for your OpenAI-compatible endpoint.'
                : 'Stored in your OS secure storage.',
            trailing: _buildCredentialTrailing(
              isManagedByEnv: isManagedByEnv,
              isConfigured: isConfigured,
              addLabel: 'Add API Key',
              onEdit: _showOpenAiApiKeyDialog,
              onRemove: _clearOpenAiApiKey,
            ),
          ),
          BeeSettingsRow(
            icon: Icons.link_rounded,
            label: 'Endpoint',
            description: baseUrlDesc,
            showDivider: lastDivider,
            trailing: baseUrlManagedByEnv
                ? beeBadge(context, '.env', BeeBadgeTone.success)
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BeeActionChip(
                        label: 'Edit',
                        onTap: _showOpenAiBaseUrlDialog,
                      ),
                      if (_openAiBaseUrl != null) ...[
                        const SizedBox(width: 6),
                        BeeActionChip(
                          label: 'Reset',
                          onTap: _resetOpenAiBaseUrl,
                        ),
                      ],
                    ],
                  ),
          ),
        ];
      case CloudProvider.codexOAuth:
        return [
          BeeSettingsRow(
            icon: Icons.login_rounded,
            label: 'ChatGPT Sign-In',
            description: _codexSignInInProgress
                ? 'Complete the sign-in in your browser, then return here.'
                : isConfigured
                ? 'Signed in. Tokens refresh automatically and stay in OS secure storage.'
                : 'Sign in with your ChatGPT account to transcribe and polish with your ChatGPT plan.',
            showDivider: lastDivider,
            trailing: _codexSignInInProgress
                ? BeeActionChip(
                    label: 'Cancel',
                    onTap: () => _codexFlow?.cancel(),
                  )
                : isConfigured
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      beeBadge(context, 'Signed In', BeeBadgeTone.success),
                      const SizedBox(width: 6),
                      BeeActionChip(
                        label: 'Sign Out',
                        color: beeError(context),
                        onTap: _signOutCodex,
                      ),
                    ],
                  )
                : BeeActionChip(label: 'Sign In', onTap: _startCodexSignIn),
          ),
        ];
      case CloudProvider.grokOAuth:
        return [
          BeeSettingsRow(
            icon: Icons.login_rounded,
            label: 'xAI Sign-In',
            description: _grokSignInInProgress
                ? 'Complete the sign-in in your browser, then return here.'
                : isConfigured
                ? 'Signed in. Tokens refresh automatically and stay in OS secure storage.'
                : 'Sign in with your xAI account to use Grok models for polish.',
            showDivider: lastDivider,
            trailing: _grokSignInInProgress
                ? BeeActionChip(
                    label: 'Cancel',
                    onTap: () => _grokFlow?.cancel(),
                  )
                : isConfigured
                ? Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      beeBadge(context, 'Signed In', BeeBadgeTone.success),
                      const SizedBox(width: 6),
                      BeeActionChip(
                        label: 'Sign Out',
                        color: beeError(context),
                        onTap: _signOutGrok,
                      ),
                    ],
                  )
                : BeeActionChip(label: 'Sign In', onTap: _startGrokSignIn),
          ),
        ];
    }
  }

  Widget _buildCredentialTrailing({
    required bool isManagedByEnv,
    required bool isConfigured,
    required String addLabel,
    required VoidCallback onEdit,
    required VoidCallback onRemove,
  }) {
    if (isManagedByEnv) {
      return beeBadge(context, '.env', BeeBadgeTone.success);
    }
    if (!isConfigured) {
      return BeeActionChip(label: addLabel, onTap: onEdit);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        beeBadge(context, 'Ready', BeeBadgeTone.success),
        const SizedBox(width: 6),
        BeeActionChip(label: 'Edit', onTap: onEdit),
        const SizedBox(width: 6),
        BeeActionChip(
          label: 'Remove',
          color: beeError(context),
          onTap: onRemove,
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

  /// First-pass thinking. In two-step mode an unset level defaults to the
  /// fastest one, because step 1 only transcribes word for word.
  Widget _buildThinkingLevelRow() {
    final modelId = _safeModelId(_selectedModelId);
    final model = AppConfig.getModelById(modelId);
    final saved = _selectedThinkingLevel;
    return _thinkingRow(
      key: const ValueKey('first-pass-thinking'),
      label: 'Thinking',
      model: model,
      effective: model.resolveThinkingLevel(
        levelOverride: saved,
        forceMinimal: saved == null && _twoPassEnabled,
      ),
      isDefault: saved == null,
      defaultNote: _twoPassEnabled ? 'step 1 default' : 'model default',
      onChanged: (level) async {
        final settings = SettingsProviderScope.of(context).settingsService;
        await settings.setThinkingLevelForModel(modelId, level);
        setState(() => _selectedThinkingLevel = level);
      },
    );
  }

  /// Primary choices allowed by the current provider and transcription pipeline.
  List<BeeDropdownOption<String>> _mainModelOptions() {
    final settings = SettingsProviderScope.of(context).settingsService;
    return [
      for (final m in settings.primaryModels)
        BeeDropdownOption(value: m.id, label: m.displayName),
    ];
  }

  String _safeModelId(String id) => SettingsProviderScope.of(
    context,
  ).settingsService.resolvePrimaryModelId(id);

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
