import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:beeamvo/mobile/mobile_screens.dart';
import 'package:beeamvo/mobile/mobile_transcription_controller.dart';
import 'package:beeamvo/models/clipboard_history_entry.dart';
import 'package:beeamvo/models/system_prompt.dart';
import 'package:beeamvo/services/cloud_transcription_service.dart';
import 'package:beeamvo/services/settings_service.dart';
import 'package:beeamvo/services/usage_stats_service.dart';

class _Settings extends SettingsService {
  _Settings({required this.credentials});
  bool credentials;
  final history = <ClipboardHistoryEntry>[];

  @override
  bool get hasCloudCredentials => credentials;
  @override
  List<ClipboardHistoryEntry> get clipboardHistory => history;
  @override
  String get selectedModelId => 'gemini-3.5-flash-lite';
  @override
  String get selectedPromptId => 'standard';
  @override
  List<SystemPrompt> get customPrompts => const [];
  @override
  GeminiApiSurface get geminiApiSurface => GeminiApiSurface.generateContent;
  @override
  String get themeMode => 'system';
  @override
  Future<String?> readGeminiApiKey() async =>
      credentials ? 'secret-api-key-1234' : null;
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
    expect(find.text('Interactions'), findsOneWidget);
    expect(find.text('Legacy'), findsOneWidget);
  });
}
