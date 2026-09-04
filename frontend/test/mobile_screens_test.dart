import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:beeamvo/mobile/mobile_transcription_controller.dart';
import 'package:beeamvo/mobile/screens/mobile_history_screen.dart';
import 'package:beeamvo/mobile/screens/mobile_home_screen.dart';
import 'package:beeamvo/mobile/screens/mobile_settings_screen.dart';
import 'package:beeamvo/models/clipboard_history_entry.dart';
import 'package:beeamvo/models/system_prompt.dart';
import 'package:beeamvo/services/cloud_transcription_service.dart';
import 'package:beeamvo/services/settings_service.dart';
import 'package:beeamvo/services/usage_stats_service.dart';
import 'package:beeamvo/theme/app_theme.dart';

class _Settings extends SettingsService {
  _Settings({required this.credentials});
  bool credentials;
  final history = <ClipboardHistoryEntry>[];
  String promptId = 'standard';
  bool? clearKeepPinned;
  bool historyEnabled = true;

  @override
  bool get hasCloudCredentials => credentials;
  @override
  List<ClipboardHistoryEntry> get clipboardHistory => history;
  @override
  String get selectedModelId => 'gemini-3.5-flash-lite';
  @override
  String get selectedPromptId => promptId;
  @override
  List<SystemPrompt> get customPrompts => const [];
  @override
  String get themeMode => 'system';
  @override
  Future<String?> readGeminiApiKey() async =>
      credentials ? 'secret-api-key-1234' : null;

  @override
  bool get clipboardHistoryEnabled => historyEnabled;

  @override
  Future<void> setClipboardHistoryEnabled(bool value) async {
    historyEnabled = value;
    notifyListeners();
  }

  @override
  Future<void> setSelectedPromptId(String value) async {
    promptId = value;
    notifyListeners();
  }

  @override
  Future<void> clearClipboardHistory({bool keepPinned = true}) async {
    clearKeepPinned = keepPinned;
    history.clear();
    notifyListeners();
  }
}

class _Recorder implements MobileAudioRecorder {
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<bool> startRecording() async => true;
  @override
  Future<String?> stopRecording() async => null;
  @override
  Future<Uint8List?> getAudioBytes() async => null;
  @override
  Future<void> deleteRecording() async {}
  @override
  Stream<double> get amplitudeStream => const Stream.empty();
  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  MobileTranscriptionController controller(_Settings settings) =>
      MobileTranscriptionController(
        settingsService: settings,
        cloudService: CloudTranscriptionService(),
        usageStatsService: UsageStatsService(),
        recorder: _Recorder(),
      );

  testWidgets('home shows setup card without credentials', (tester) async {
    final settings = _Settings(credentials: false);
    await tester.pumpWidget(
      MaterialApp(
        home: MobileHomeScreen(
          controller: controller(settings),
          settingsService: settings,
          cloudService: CloudTranscriptionService(),
        ),
      ),
    );
    expect(find.text('Add a cloud API key to start'), findsOneWidget);
    expect(find.text('Open settings'), findsOneWidget);
  });

  testWidgets('home shows record button with credentials', (tester) async {
    final settings = _Settings(credentials: true);
    await tester.pumpWidget(
      MaterialApp(
        home: MobileHomeScreen(
          controller: controller(settings),
          settingsService: settings,
          cloudService: CloudTranscriptionService(),
        ),
      ),
    );
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
  });

  testWidgets('mode chip opens picker and updates after selection', (
    tester,
  ) async {
    final settings = _Settings(credentials: true);
    final nextPrompt = SystemPrompt.availablePrompts[1];
    await tester.pumpWidget(
      MaterialApp(
        home: MobileHomeScreen(
          controller: controller(settings),
          settingsService: settings,
          cloudService: CloudTranscriptionService(),
        ),
      ),
    );
    expect(find.text(SystemPrompt.availablePrompts.first.name), findsOneWidget);
    await tester.tap(find.byType(ActionChip));
    await tester.pumpAndSettle();
    expect(find.text(nextPrompt.name), findsOneWidget);
    await tester.tap(find.text(nextPrompt.name));
    await tester.pumpAndSettle();
    expect(find.text(nextPrompt.name), findsOneWidget);
  });

  testWidgets('home and settings use dark theme surfaces', (tester) async {
    final settings = _Settings(credentials: true);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: MobileHomeScreen(
          controller: controller(settings),
          settingsService: settings,
          cloudService: CloudTranscriptionService(),
        ),
      ),
    );
    final homeScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(
      homeScaffold.backgroundColor,
      AppTheme.darkTheme.colorScheme.surface,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.dark,
        home: MobileSettingsScreen(
          settingsService: settings,
          cloudService: CloudTranscriptionService(),
          packageInfoLoader: () async => PackageInfo(
            appName: 'Beeamvo',
            packageName: 'com.beeamvo.app',
            version: '1.2.3',
            buildNumber: '1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final settingsScaffold = tester.widget<Scaffold>(find.byType(Scaffold));
    expect(
      settingsScaffold.backgroundColor,
      AppTheme.darkTheme.colorScheme.surface,
    );
    expect(
      Theme.of(tester.element(find.byType(MobileSettingsScreen))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('history renders empty and populated states', (tester) async {
    final settings = _Settings(credentials: true);
    await tester.pumpWidget(
      MaterialApp(home: MobileHistoryScreen(settingsService: settings)),
    );
    expect(find.text('No transcriptions yet'), findsOneWidget);

    settings.history.add(
      ClipboardHistoryEntry(
        id: '1',
        text: 'A saved transcript',
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        isPinned: false,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(home: MobileHistoryScreen(settingsService: settings)),
    );
    expect(find.text('A saved transcript'), findsOneWidget);
  });

  testWidgets('settings renders and masks API key', (tester) async {
    final settings = _Settings(credentials: true);
    await tester.pumpWidget(
      MaterialApp(
        home: MobileSettingsScreen(
          settingsService: settings,
          cloudService: CloudTranscriptionService(),
          packageInfoLoader: () async => PackageInfo(
            appName: 'Beeamvo',
            packageName: 'com.beeamvo.app',
            version: '1.2.3',
            buildNumber: '1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('••••••••1234'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -1000));
    await tester.pump();
    expect(find.text('1.2.3'), findsOneWidget);
  });

  testWidgets('settings history switch can disable local history', (
    tester,
  ) async {
    final settings = _Settings(credentials: true);
    await tester.pumpWidget(
      MaterialApp(
        home: MobileSettingsScreen(
          settingsService: settings,
          cloudService: CloudTranscriptionService(),
          packageInfoLoader: () async => PackageInfo(
            appName: 'Beeamvo',
            packageName: 'com.beeamvo.app',
            version: '1.2.3',
            buildNumber: '1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(settings.historyEnabled, isTrue);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(settings.historyEnabled, isFalse);
    expect(
      find.text('When off, results are only copied to the clipboard.'),
      findsOneWidget,
    );
  });

  testWidgets('history clear all confirms and removes pinned entries', (
    tester,
  ) async {
    final settings = _Settings(credentials: true)
      ..history.add(
        ClipboardHistoryEntry(
          id: '1',
          text: 'Pinned transcript',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          isPinned: true,
        ),
      );
    await tester.pumpWidget(
      MaterialApp(home: MobileHistoryScreen(settingsService: settings)),
    );
    await tester.tap(find.byTooltip('Clear all'));
    await tester.pumpAndSettle();
    expect(find.text('Clear all history?'), findsOneWidget);
    await tester.tap(find.text('Clear all').last);
    await tester.pumpAndSettle();
    expect(settings.clearKeepPinned, isFalse);
    expect(find.text('Pinned transcript'), findsNothing);
  });
}
