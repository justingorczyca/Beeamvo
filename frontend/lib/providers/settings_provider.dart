import 'package:flutter/material.dart';
import '../services/settings_service.dart';

/// Categories available in the settings sidebar
enum SettingsCategory {
  home,
  general,
  aiModels,
  prompts,
  clipboard,
  troubleshooting,
}

/// Extension for category metadata
extension SettingsCategoryExtension on SettingsCategory {
  String get displayName {
    switch (this) {
      case SettingsCategory.home:
        return 'Home';
      case SettingsCategory.general:
        return 'General';
      case SettingsCategory.aiModels:
        return 'Transcription';
      case SettingsCategory.prompts:
        return 'Prompts';
      case SettingsCategory.clipboard:
        return 'Clipboard';
      case SettingsCategory.troubleshooting:
        return 'Help';
    }
  }

  IconData get icon {
    switch (this) {
      case SettingsCategory.home:
        return Icons.home_rounded;
      case SettingsCategory.general:
        return Icons.settings_rounded;
      case SettingsCategory.aiModels:
        return Icons.graphic_eq_rounded;
      case SettingsCategory.prompts:
        return Icons.chat_rounded;
      case SettingsCategory.clipboard:
        return Icons.content_paste_rounded;
      case SettingsCategory.troubleshooting:
        return Icons.help_outline_rounded;
    }
  }

  /// Semantic group for visual separation in the sidebar.
  /// Items with a different group than their predecessor get a gap.
  int get group {
    switch (this) {
      case SettingsCategory.home:
        return 0;
      case SettingsCategory.troubleshooting:
        return 1;
      default:
        return 0;
    }
  }

  bool get isEnabled => true;
}

/// Provider for managing settings UI state
class SettingsProvider extends ChangeNotifier {
  final SettingsService settingsService;

  SettingsProvider({required this.settingsService}) {
    // Relay notifications from the underlying service so that dependents of
    // SettingsProviderScope (an InheritedNotifier over this provider) rebuild
    // when persisted settings change anywhere. Without this forwarding the
    // provider is effectively a snapshot and never reflects mutations made
    // through SettingsService (hotkey/model/theme switches, tray actions…).
    settingsService.addListener(notifyListeners);
    _loadInitialState();
  }

  @override
  void dispose() {
    settingsService.removeListener(notifyListeners);
    super.dispose();
  }

  // Current selected category
  SettingsCategory _selectedCategory = SettingsCategory.home;
  SettingsCategory get selectedCategory => _selectedCategory;

  void selectCategory(SettingsCategory category) {
    if (_selectedCategory != category && category.isEnabled) {
      _selectedCategory = category;
      notifyListeners();
    }
  }

  // Window state
  bool _isDragging = false;
  bool get isDragging => _isDragging;

  void setDragging(bool value) {
    _isDragging = value;
    notifyListeners();
  }

  // Permissions state
  bool? _accessibilityGranted;
  bool? get accessibilityGranted => _accessibilityGranted;

  bool? _automationGranted;
  bool? get automationGranted => _automationGranted;

  Future<void> checkPermissions() async {
    // Will be populated by the UI using KeyboardService
    notifyListeners();
  }

  void updatePermissions({bool? accessibility, bool? automation}) {
    _accessibilityGranted = accessibility ?? _accessibilityGranted;
    _automationGranted = automation ?? _automationGranted;
    notifyListeners();
  }

  // Hotkey recording state
  bool _isRecordingHotkey = false;
  bool get isRecordingHotkey => _isRecordingHotkey;

  void setRecordingHotkey(bool value) {
    _isRecordingHotkey = value;
    notifyListeners();
  }

  void _loadInitialState() {
    // Initial state is already set
    notifyListeners();
  }

  // Available categories
  List<SettingsCategory> get availableCategories => SettingsCategory.values;
}

/// Global provider instance holder for easy access
class SettingsProviderScope extends InheritedNotifier<SettingsProvider> {
  const SettingsProviderScope({
    super.key,
    required SettingsProvider provider,
    required super.child,
  }) : super(notifier: provider);

  static SettingsProvider of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<SettingsProviderScope>();
    assert(scope != null, 'SettingsProviderScope not found in context');
    return scope!.notifier!;
  }

  static SettingsProvider? maybeOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<SettingsProviderScope>();
    return scope?.notifier;
  }
}
