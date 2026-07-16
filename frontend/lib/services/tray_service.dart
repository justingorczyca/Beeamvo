import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:tray_manager/tray_manager.dart';

import '../config.dart';
import '../models/system_prompt.dart';
import 'settings_service.dart';

class TrayService with TrayListener {
  late SettingsService _settingsService;
  late VoidCallback _onShowSettings;
  late VoidCallback _onExit;
  late VoidCallback _onPromptChanged;
  late VoidCallback _onModelChanged;

  Future<void> initialize({
    required SettingsService settingsService,
    required VoidCallback onShowSettings,
    required VoidCallback onExit,
    required VoidCallback onPromptChanged,
    required VoidCallback onModelChanged,
  }) async {
    _settingsService = settingsService;
    _onShowSettings = onShowSettings;
    _onExit = onExit;
    _onPromptChanged = onPromptChanged;
    _onModelChanged = onModelChanged;

    try {
      if (Platform.isWindows) {
        // On Windows, tray_manager requires an absolute path to an .ico file.
        final exePath = Platform.resolvedExecutable;
        final exeDir = path.dirname(exePath);
        final icoPath = path.join(
          exeDir,
          'data',
          'flutter_assets',
          'assets',
          'app_icon.ico',
        );
        debugPrint('Setting tray icon path: $icoPath');

        if (await File(icoPath).exists()) {
          await trayManager.setIcon(icoPath);
          debugPrint('Tray icon set successfully');
        } else {
          debugPrint('Tray icon file not found at: $icoPath');
          await trayManager.setIcon('assets/app_icon.ico');
        }
      } else if (Platform.isMacOS) {
        // On macOS, use the monochrome microphone as a template icon so the
        // menu bar renders it natively in light and dark appearances.
        await trayManager.setIcon(
          'assets/tray_icon_macos.png',
          isTemplate: true,
        );
      } else if (Platform.isLinux) {
        // On Linux, tray_manager needs an absolute path to the icon file.
        final exePath = Platform.resolvedExecutable;
        final exeDir = path.dirname(exePath);
        final pngPath = path.join(
          exeDir,
          'data',
          'flutter_assets',
          'assets',
          'app_icon.png',
        );
        if (await File(pngPath).exists()) {
          await trayManager.setIcon(pngPath);
        } else {
          await trayManager.setIcon('assets/app_icon.png');
        }
      }
    } catch (e) {
      debugPrint('Tray icon error: $e');
    }

    await updateContextMenu();
    trayManager.addListener(this);
  }

  Future<void> updateContextMenu() async {
    final currentPromptId = _settingsService.selectedPromptId;
    final currentModelId = _settingsService.selectedModelId;

    final allPrompts = [
      ...SystemPrompt.availablePrompts,
      ..._settingsService.customPrompts,
    ];

    // On the local-only backend, non-default prompts have no effect until a
    // cloud model is in the pipeline. Gray those entries out (disabled) so
    // they can't be silently selected, and offer the switch actions that
    // make prompts work — full cloud, or keep local + cloud two-pass refine.
    final promptsNeedCloud = allPrompts.any(
      (p) => _settingsService.isPromptInactiveOnLocalBackend(p.id),
    );

    final promptItems = <MenuItem>[];
    if (promptsNeedCloud) {
      if (_settingsService.hasCloudCredentials) {
        promptItems.add(
          MenuItem(key: 'prompt_switch_cloud', label: 'Use cloud for prompts'),
        );
        promptItems.add(
          MenuItem(
            key: 'prompt_switch_twopass',
            label: 'Keep local + cloud refine (two-pass)',
          ),
        );
      } else {
        promptItems.add(
          MenuItem(
            key: 'prompt_setup_cloud',
            label: 'Set up cloud for prompts\u2026',
          ),
        );
      }
      promptItems.add(MenuItem.separator());
    }
    for (final prompt in allPrompts) {
      final blocked = _settingsService.isPromptInactiveOnLocalBackend(
        prompt.id,
      );
      promptItems.add(
        MenuItem(
          key: 'prompt_${prompt.id}',
          label: blocked ? '${prompt.name}  (needs cloud)' : prompt.name,
          checked: currentPromptId == prompt.id,
          disabled: blocked,
        ),
      );
    }

    final modelItems = AppConfig.availableModels
        .map(
          (model) => MenuItem(
            key: 'model_${model.id}',
            label: model.displayName,
            checked: currentModelId == model.id,
          ),
        )
        .toList();

    // The rephraser is a global cloud feature: it only takes effect when a
    // cloud model is in the pipeline (full cloud, or local + cloud two-pass
    // refine). On the local-only backend, levels above Off silently resolve
    // to Path A and the rephraser fragment is dropped at record time. Gate the
    // Medium/High items exactly like the prompt section does above, while
    // keeping Off selectable as the local-safe default.
    final currentRephraseLevel = _settingsService.rephraseLevel;
    final rephraserNeedsCloud = !_settingsService.isCloudRefinementInPipeline;

    final rephraserItems = <MenuItem>[];
    if (rephraserNeedsCloud) {
      if (_settingsService.hasCloudCredentials) {
        rephraserItems.add(
          MenuItem(
            key: 'rephrase_switch_cloud',
            label: 'Use cloud for rephraser',
          ),
        );
        rephraserItems.add(
          MenuItem(
            key: 'rephrase_switch_twopass',
            label: 'Keep local + cloud refine (two-pass)',
          ),
        );
      } else {
        rephraserItems.add(
          MenuItem(
            key: 'rephrase_setup_cloud',
            label: 'Set up cloud for rephraser\u2026',
          ),
        );
      }
      rephraserItems.add(MenuItem.separator());
    }
    for (final level in RephraseLevel.values) {
      final blocked = rephraserNeedsCloud && level != RephraseLevel.off;
      rephraserItems.add(
        MenuItem(
          key: 'rephrase_${level.name}',
          label: blocked
              ? '${level.displayName}  (needs cloud)'
              : level.displayName,
          checked: currentRephraseLevel == level,
          disabled: blocked,
        ),
      );
    }

    final items = <MenuItem>[
      MenuItem(key: 'settings', label: 'Settings'),
      MenuItem.submenu(
        key: 'prompts',
        label: 'System Prompt',
        submenu: Menu(items: promptItems),
      ),
      MenuItem.submenu(
        key: 'rephraser',
        label: 'Rephraser',
        submenu: Menu(items: rephraserItems),
      ),
      MenuItem.submenu(
        key: 'models',
        label: 'AI Model',
        submenu: Menu(items: modelItems),
      ),
      MenuItem.separator(),
      MenuItem(key: 'exit', label: 'Exit'),
    ];
    await trayManager.setContextMenu(Menu(items: items));
  }

  @override
  void onTrayIconMouseDown() {
    _onShowSettings();
  }

  @override
  void onTrayIconRightMouseDown() {
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    if (menuItem.key == 'settings') {
      _onShowSettings();
    } else if (menuItem.key == 'exit') {
      _onExit();
    } else if (menuItem.key == 'prompt_switch_cloud') {
      // Switch fully to cloud so prompts take effect.
      _settingsService.switchToCloudTranscription().then((_) {
        updateContextMenu();
        _onPromptChanged();
      });
    } else if (menuItem.key == 'prompt_switch_twopass') {
      // Keep local Whisper transcription but refine with a cloud pass so
      // prompts take effect.
      _settingsService.enableLocalTwoPassRefinement().then((_) {
        updateContextMenu();
        _onPromptChanged();
      });
    } else if (menuItem.key == 'prompt_setup_cloud') {
      // No cloud provider configured — send the user to settings.
      _onShowSettings();
    } else if (menuItem.key!.startsWith('prompt_')) {
      final promptId = menuItem.key!.replaceFirst('prompt_', '');
      _settingsService.setSelectedPromptId(promptId).then((_) {
        updateContextMenu();
        _onPromptChanged();
      });
    } else if (menuItem.key == 'rephrase_switch_cloud') {
      // Switch fully to cloud so the rephraser takes effect.
      _settingsService.switchToCloudTranscription().then((_) {
        updateContextMenu();
      });
    } else if (menuItem.key == 'rephrase_switch_twopass') {
      // Keep local Whisper transcription but refine with a cloud pass so
      // the rephraser takes effect.
      _settingsService.enableLocalTwoPassRefinement().then((_) {
        updateContextMenu();
      });
    } else if (menuItem.key == 'rephrase_setup_cloud') {
      // No cloud provider configured — send the user to settings.
      _onShowSettings();
    } else if (menuItem.key!.startsWith('rephrase_')) {
      final levelName = menuItem.key!.replaceFirst('rephrase_', '');
      final level = RephraseLevel.values.firstWhere(
        (l) => l.name == levelName,
        orElse: () => RephraseLevel.off,
      );
      _settingsService.setRephraseLevel(level).then((_) {
        updateContextMenu();
      });
    } else if (menuItem.key!.startsWith('model_')) {
      final modelId = menuItem.key!.replaceFirst('model_', '');
      _settingsService.setSelectedModelId(modelId).then((_) {
        updateContextMenu();
        _onModelChanged();
      });
    }
  }

  Future<void> setStatus(String status) async {
    await trayManager.setToolTip('Beeamvo: $status');
  }

  void dispose() {
    trayManager.removeListener(this);
  }
}
