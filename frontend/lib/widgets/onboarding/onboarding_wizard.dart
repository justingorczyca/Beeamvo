import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/hotkey_config.dart';
import '../../services/settings_service.dart';
import '../../theme/app_theme.dart';
import 'onboarding_shared.dart';
import 'onboarding_steps.dart';

/// Total number of onboarding steps (0-indexed: 0..8 = 9 steps).
const int _kTotalSteps = 9;

/// The onboarding wizard widget.
///
/// Displays a multi-step flow that walks the user through initial
/// configuration: API key, model, recording mode, and hotkey.
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

class _OnboardingWizardState extends State<OnboardingWizard>
    with TickerProviderStateMixin {
  int _currentStep = 0;

  late final PageController _pageController;
  late final AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
      value: 1.0,
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    if (step < 0 || step >= _kTotalSteps) return;
    _fadeController.reverse().then((_) {
      if (!mounted) return;
      setState(() => _currentStep = step);
      _pageController.animateToPage(
        step,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOutCubic,
      );
      _fadeController.forward();
    });
  }

  void _nextStep() => _goToStep(_currentStep + 1);

  void _prevStep() {
    // Skip over the API key step (2) for offline users — it auto-advances,
    // so landing on it would bounce back forward.
    if (_currentStep == 3 &&
        widget.settingsService.transcriptionBackend !=
            TranscriptionBackend.cloud) {
      _goToStep(1);
    } else {
      _goToStep(_currentStep - 1);
    }
  }

  void _skipProviderStep() {
    _nextStep();
  }

  Future<void> _finish() async {
    await widget.settingsService.setOnboardingComplete();
    widget.onComplete();
  }

  @override
  Widget build(BuildContext context) {
    final isCloud =
        widget.settingsService.transcriptionBackend ==
            TranscriptionBackend.cloud;

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 740,
        height: 560,
        decoration: BoxDecoration(
          color: AppTheme.chromeBlack,
          borderRadius: BorderRadius.circular(AppTheme.radiusXl),
          border: Border.all(
            color: AppTheme.border.withValues(alpha: 0.7),
          ),
          boxShadow: AppTheme.windowShadow,
        ),
        clipBehavior: Clip.antiAlias,
        child: OnboardingBackground(
          child: Column(
            children: [
              // Title bar
              _buildTitleBar(),

              // Progress
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 4),
                child: OnboardingProgress(
                  currentStep: _currentStep,
                  totalSteps: _kTotalSteps,
                ),
              ),

              // Step content
              Expanded(
                child: FadeTransition(
                  opacity: _fadeController,
                  child: PageView.builder(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _kTotalSteps,
                    itemBuilder: (context, index) {
                      return SingleChildScrollView(
                        child: _buildStep(index, isCloud),
                      );
                    },
                  ),
                ),
              ),

              // Navigation footer
              if (_currentStep > 0 && _currentStep < _kTotalSteps - 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(48, 0, 48, 16),
                  child: Row(
                    children: [
                      OnboardingSecondaryButton(
                        label: 'Back',
                        onTap: _prevStep,
                      ),
                      const Spacer(),
                      Text(
                        '${_currentStep + 1} of $_kTotalSteps',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: AppTheme.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_currentStep == 0)
                const SizedBox(height: 16),
              if (_currentStep == _kTotalSteps - 1)
                Padding(
                  padding: const EdgeInsets.fromLTRB(48, 0, 48, 20),
                  child: OnboardingPrimaryButton(
                    label: 'Start Using Beeamvo',
                    icon: Icons.rocket_launch_rounded,
                    onTap: _finish,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTitleBar() {
    return Container(
      height: 44,
      color: AppTheme.chromeBlack,
      child: Row(
        children: [
          const SizedBox(width: 16),
          // App brand
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.amber,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.amber.withValues(alpha: 0.5),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            'Beeamvo Setup',
            style: GoogleFonts.spaceGrotesk(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
              letterSpacing: -0.1,
            ),
          ),
          const Spacer(),
          if (_currentStep > 0 && _currentStep < _kTotalSteps - 1)
            OnboardingSecondaryButton(
              label: 'Skip All',
              onTap: _finish,
            ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  Widget _buildStep(int index, bool isCloud) {
    switch (index) {
      case 0:
        return Center(child: WelcomeStep(onNext: _nextStep));

      case 1:
        return Center(
          child: ProviderStep(
            onNext: _nextStep,
            settingsService: widget.settingsService,
          ),
        );

      case 2:
        // Only show API key step for cloud backend
        if (!isCloud) {
          // Skip this step for offline users — jump to model or finish
          // We render an empty step and auto-advance
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (_currentStep == 2) _nextStep();
          });
          return const SizedBox.shrink();
        }
        return Center(
          child: ApiKeyStep(
            onNext: _nextStep,
            onSkip: _skipProviderStep,
            settingsService: widget.settingsService,
            onVerifyCloudProvider: widget.onVerifyCloudProvider,
          ),
        );

      case 3:
        return Center(
          child: ModelStep(
            onNext: _nextStep,
            settingsService: widget.settingsService,
            onModelDownloaded: widget.onModelDownloaded,
          ),
        );

      case 4:
        return Center(
          child: TranscriptionModeStep(
            onNext: _nextStep,
            settingsService: widget.settingsService,
          ),
        );

      case 5:
        return Center(
          child: TwoPassRephraseStep(
            onNext: _nextStep,
            settingsService: widget.settingsService,
          ),
        );

      case 6:
        return Center(
          child: RecordingModeStep(
            onNext: _nextStep,
            settingsService: widget.settingsService,
          ),
        );

      case 7:
        return Center(
          child: HotkeyStep(
            onNext: _nextStep,
            settingsService: widget.settingsService,
            onHotkeyChanged: widget.onHotkeyChanged,
          ),
        );

      case 8:
        return Center(
          child: ReadyStep(
            onFinish: _finish,
            settingsService: widget.settingsService,
            onGoToApiKeyStep: () => _goToStep(2),
            onGoToModelStep: () => _goToStep(3),
          ),
        );

      default:
        return const SizedBox.shrink();
    }
  }
}
