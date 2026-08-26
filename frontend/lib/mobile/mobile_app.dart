import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../config.dart';
import '../services/cloud_transcription_service.dart';
import '../services/settings_service.dart';
import '../services/usage_stats_service.dart';
import '../theme/app_theme.dart';
import 'mobile_screens.dart';
import 'mobile_transcription_controller.dart';

class BeeamvoMobileApp extends StatefulWidget {
  const BeeamvoMobileApp({
    super.key,
    required this.settingsService,
    this.cloudService,
    this.usageStatsService,
    this.recorder,
  });

  final SettingsService settingsService;
  final CloudTranscriptionService? cloudService;
  final UsageStatsService? usageStatsService;
  final MobileAudioRecorder? recorder;

  @override
  State<BeeamvoMobileApp> createState() => _BeeamvoMobileAppState();
}

class _BeeamvoMobileAppState extends State<BeeamvoMobileApp> {
  late final Future<void> _ready;
  late final CloudTranscriptionService _cloudService;
  late final UsageStatsService _usageStatsService;
  MobileTranscriptionController? _controller;

  @override
  void initState() {
    super.initState();
    _cloudService = widget.cloudService ?? CloudTranscriptionService();
    _usageStatsService = widget.usageStatsService ?? UsageStatsService();
    _ready = _initialize();
  }

  Future<void> _initialize() async {
    await widget.settingsService.initialize();
    await widget.settingsService.applyMobileDefaults();
    await _usageStatsService.initialize();
    _controller = MobileTranscriptionController(
      settingsService: widget.settingsService,
      cloudService: _cloudService,
      usageStatsService: _usageStatsService,
      recorder: widget.recorder ?? RecordingServiceMobileAudioRecorder(),
    );
  }

  @override
  void dispose() {
    _controller?.dispose();
    _cloudService.dispose();
    _usageStatsService.dispose();
    widget.settingsService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.settingsService,
      builder: (context, _) => MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: widget.settingsService.themeModeEnum,
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en')],
        home: FutureBuilder<void>(
          future: _ready,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done ||
                _controller == null) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            return MobileHomeScreen(
              controller: _controller!,
              settingsService: widget.settingsService,
              cloudService: _cloudService,
            );
          },
        ),
      ),
    );
  }
}
