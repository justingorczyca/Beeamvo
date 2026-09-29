import 'package:flutter/material.dart';
import '../../models/enums.dart';

/// UI-only presentation for [CloudProvider]: icon plus the short copy used by
/// the settings selector and the onboarding provider step.
extension CloudProviderPresentation on CloudProvider {
  IconData get icon => switch (this) {
    CloudProvider.geminiApiKey => Icons.key_rounded,
    CloudProvider.vertexAi => Icons.hub_rounded,
    CloudProvider.openaiApiKey => Icons.bolt_rounded,
    CloudProvider.codexOAuth => Icons.chat_bubble_rounded,
    CloudProvider.grokOAuth => Icons.rocket_launch_rounded,
  };

  /// Two-to-four word tagline for compact tiles.
  String get tagline => switch (this) {
    CloudProvider.geminiApiKey => 'Personal API key',
    CloudProvider.vertexAi => 'Google Cloud project',
    CloudProvider.openaiApiKey => 'API key or endpoint',
    CloudProvider.codexOAuth => 'Browser sign-in · no API key',
    CloudProvider.grokOAuth => 'Browser sign-in · polish only',
  };
}
