import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';
import '../../config.dart';
import '../../models/hotkey_config.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import '../settings/settings_shared.dart';
import 'onboarding_shared.dart';
import 'onboarding_steps.dart';

const int _kTotalSteps = 6;

class OnboardingWizard extends StatefulWidget {
  final SettingsService settingsService;
  final Future<void> Function(CloudProvider provider)? onVerifyCloudProvider;
  final Future<void> Function(HotkeyConfig)? onHotkeyChanged;
  final VoidCallback onComplete;
  final VoidCallback? onModelDownloaded;

  const OnboardingWizard({
    super.key,
    required this.settingsService,
    this.onVerifyCloudProvider,
    this.onHotkeyChanged,
    required this.onComplete,
    this.onModelDownloaded,
  });

  @override
  State<OnboardingWizard> createState() => _OnboardingWizardState();
}

class _OnboardingWizardState extends State<OnboardingWizard> {
  int _currentStep = 0;
  int _maxStepReached = 0;
  late final PageController _pageController = PageController();

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    if (step < 0 || step > _kTotalSteps || step == _currentStep) return;
    setState(() {
      _currentStep = step;
      if (step > _maxStepReached) _maxStepReached = step;
    });
    if (step == 0) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.animateToPage(
        step - 1,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _nextStep() => _goToStep(_currentStep + 1);

  void _prevStep() {
    if (_currentStep == 3 &&
        widget.settingsService.transcriptionBackend !=
            TranscriptionBackend.cloud) {
      _goToStep(1);
    } else {
      _goToStep(_currentStep - 1);
    }
  }

  void _skipAccountStep() => _nextStep();

  Future<void> _finish() async {
    await widget.settingsService.setOnboardingComplete();
    widget.onComplete();
  }

  String _railSummary(int step) {
    final settings = widget.settingsService;
    switch (step) {
      case 1:
        return settings.transcriptionBackend == TranscriptionBackend.cloud
            ? 'Cloud · ${settings.cloudProvider.displayName}'
            : 'Offline · Whisper';
      case 2:
        if (settings.transcriptionBackend != TranscriptionBackend.cloud) {
          return 'Not needed';
        }
        if (!settings.hasCloudCredentials) return 'Set up later';
        return switch (settings.cloudProvider) {
          CloudProvider.vertexAi => 'Project saved',
          CloudProvider.geminiApiKey ||
          CloudProvider.openaiApiKey => 'Key saved',
          CloudProvider.codexOAuth || CloudProvider.grokOAuth => 'Signed in',
        };
      case 3:
        if (settings.transcriptionBackend == TranscriptionBackend.cloud) {
          return AppConfig.getModelById(settings.selectedModelId).displayName;
        }
        return 'Whisper · ${settings.whisperModelId.replaceFirst('ggml-', '').replaceAll('.bin', '')}';
      case 4:
        return settings.recordingMode == RecordingMode.toggle
            ? 'Toggle'
            : 'Hold';
      case 5:
        return settings.hotkey.displayString;
      case 6:
        return 'Ready';
      default:
        return '';
    }
  }

  bool get _accountNotNeeded =>
      widget.settingsService.transcriptionBackend != TranscriptionBackend.cloud;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 860,
        height: 580,
        decoration: BoxDecoration(
          color: beeSurfaceHighest(context),
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
          border: Border.all(color: beeBorder(context).withValues(alpha: 0.7)),
          boxShadow: AppTheme.windowShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: _currentStep == 0
            ? WelcomeStep(onNext: _nextStep, onSkip: _finish)
            : Row(
                children: [
                  _buildRail(context),
                  Expanded(
                    child: ColoredBox(
                      color: beeSurface(context),
                      child: Stack(
                        children: [
                          OnboardingNav(
                            stepNumber: _currentStep,
                            totalSteps: _kTotalSteps,
                            onBack: _prevStep,
                            child: PageView.builder(
                              controller: _pageController,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _kTotalSteps,
                              itemBuilder: (context, index) =>
                                  _buildStep(index + 1),
                            ),
                          ),
                          Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            height: 36,
                            child: _dragHandle(child: const SizedBox.expand()),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _dragHandle({required Widget child}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onPanStart: (_) => windowManager.startDragging(),
      child: child,
    );
  }

  Widget _buildRail(BuildContext context) {
    return Container(
      width: 232,
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
      decoration: BoxDecoration(
        color: beeSidebar(context),
        border: Border(right: BorderSide(color: beeDivider(context))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _dragHandle(
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: beeYellow(context),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(
                    Icons.mic_rounded,
                    size: 13,
                    color: beeBlack(context),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Beeamvo',
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: beeText(context),
                      ),
                    ),
                    Text(
                      'Setup',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: beeTextMuted(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 30),
          Expanded(
            child: Column(
              children: [
                for (var step = 1; step <= _kTotalSteps; step++)
                  _buildRailStep(context, step),
              ],
            ),
          ),
          if (_currentStep < _kTotalSteps)
            Align(
              alignment: Alignment.centerLeft,
              child: OnboardingSecondaryButton(
                label: 'Skip setup',
                onTap: _finish,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRailStep(BuildContext context, int step) {
    const labels = [
      'Engine',
      'Account',
      'Model',
      'Recording',
      'Hotkey',
      'Finish',
    ];
    final label = labels[step - 1];
    final isCurrent = step == _currentStep;
    final isNotNeeded = step == 2 && _accountNotNeeded;
    final isCompleted =
        !isNotNeeded &&
        !isCurrent &&
        (step < _currentStep || step <= _maxStepReached);
    final canVisit = !isNotNeeded && !isCurrent && step <= _maxStepReached;
    final summary = isNotNeeded
        ? 'Not needed'
        : isCompleted
        ? _railSummary(step)
        : null;

    return SizedBox(
      height: 48,
      child: Opacity(
        opacity: isNotNeeded ? 0.5 : 1,
        child: BeeInteractive(
          onTap: canVisit ? () => _goToStep(step) : null,
          semanticLabel: 'Step $step: $label',
          selected: isCurrent,
          builder: (context, focused) => AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              color: focused
                  ? beeText(context).withValues(alpha: 0.04)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 22,
                  height: 48,
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: Alignment.center,
                    children: [
                      if (step < _kTotalSteps)
                        Positioned(
                          top: 35,
                          left: 10,
                          child: Container(
                            width: 1,
                            height: 26,
                            color: beeDivider(context),
                          ),
                        ),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isCompleted
                              ? beeYellow(context)
                              : Colors.transparent,
                          border: isCompleted
                              ? null
                              : Border.all(
                                  color: isCurrent
                                      ? beeYellow(context)
                                      : beeBorder(context),
                                  width: isCurrent ? 1.5 : 1,
                                ),
                        ),
                        child: isCompleted
                            ? Icon(
                                Icons.check_rounded,
                                size: 14,
                                color: beeBlack(context),
                              )
                            : isCurrent
                            ? Center(
                                child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: beeYellow(context),
                                  ),
                                ),
                              )
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: isCurrent || isCompleted
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: isCurrent
                              ? beeText(context)
                              : isCompleted
                              ? beeTextSub(context)
                              : beeTextMuted(context),
                        ),
                      ),
                      if (summary != null)
                        Text(
                          summary,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            fontSize: 11,
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
      ),
    );
  }

  Widget _buildStep(int step) {
    final settingsService = widget.settingsService;
    switch (step) {
      case 1:
        return ProviderStep(
          onNext: _nextStep,
          settingsService: settingsService,
        );
      case 2:
        if (_accountNotNeeded) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_currentStep == 2) _nextStep();
          });
          return const SizedBox.shrink();
        }
        return ApiKeyStep(
          onNext: _nextStep,
          onSkip: _skipAccountStep,
          settingsService: settingsService,
          onVerifyCloudProvider: widget.onVerifyCloudProvider,
        );
      case 3:
        return ModelStep(
          onNext: _nextStep,
          settingsService: settingsService,
          onModelDownloaded: widget.onModelDownloaded,
        );
      case 4:
        return RecordingModeStep(
          onNext: _nextStep,
          settingsService: settingsService,
        );
      case 5:
        return HotkeyStep(
          onNext: _nextStep,
          settingsService: settingsService,
          onHotkeyChanged: widget.onHotkeyChanged,
        );
      case 6:
        return ReadyStep(
          onFinish: _finish,
          settingsService: settingsService,
          onGoToApiKeyStep: () => _goToStep(2),
          onGoToModelStep: () => _goToStep(3),
          onGoToProviderStep: () => _goToStep(1),
          onGoToRecordingStep: () => _goToStep(4),
          onGoToHotkeyStep: () => _goToStep(5),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
