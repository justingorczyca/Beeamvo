import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import 'package:tray_manager/tray_manager.dart';

import '../models/system_prompt.dart';
import 'settings_service.dart';

class TrayService with TrayListener {
  late SettingsService _settingsService;
  late VoidCallback _onShowSettings;
  late VoidCallback _onExit;
  late VoidCallback _onPromptChanged;

  Future<void> initialize({
    required SettingsService settingsService,
    required VoidCallback onShowSettings,
    required VoidCallback onExit,
    required VoidCallback onPromptChanged,
  }) async {
    _settingsService = settingsService;
    _onShowSettings = onShowSettings;
    _onExit = onExit;
    _onPromptChanged = onPromptChanged;

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
    final allPrompts = [
      ...SystemPrompt.availablePrompts,
      ..._settingsService.customPrompts,
    ];

    // Prompts only shape the output when a cloud model is in the pipeline.
    final promptsApply = _settingsService.promptIsApplied;
    final promptItems = <MenuItem>[
      for (final prompt in allPrompts)
        MenuItem(
          key: 'prompt_${prompt.id}',
          label: prompt.name,
          checked: currentPromptId == prompt.id,
          disabled: !promptsApply && prompt.id != SystemPrompt.defaultId,
        ),
    ];

    final items = <MenuItem>[
      MenuItem(key: 'settings', label: 'Settings'),
      MenuItem.submenu(
        key: 'prompts',
        label: 'Writing Style',
        submenu: Menu(items: promptItems),
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
  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    final key = menuItem.key;
    if (key == 'settings') {
      _onShowSettings();
    } else if (key == 'exit') {
      _onExit();
    } else if (key != null && key.startsWith('prompt_')) {
      final promptId = key.replaceFirst('prompt_', '');
      _settingsService.setSelectedPromptId(promptId).then((_) {
        updateContextMenu();
        _onPromptChanged();
      });
    }
  }

  Future<void> setStatus(String status) async {
    await trayManager.setToolTip('Beeamvo: $status');
  }

  Future<void> dispose() async {
    try {
      await trayManager.destroy();
    } catch (e) {
      debugPrint('[TrayService] Failed to destroy tray: $e');
    } finally {
      trayManager.removeListener(this);
    }
  }
}
