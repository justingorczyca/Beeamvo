import 'enums.dart';

/// Resolves the transcription backend for a single recording session.
///
/// A non-null per-prompt override (the [promptBackendOverride] value as stored
/// in [PromptSettings.transcriptionBackend]) takes precedence over the global
/// default so that, e.g., a "this prompt uses offline Whisper" choice is
/// honoured even when Cloud is the global backend.
///
/// This is centralized so the recording-start and recording-stop paths cannot
/// drift: a session must stop with exactly the backend it started with, even if
/// the user changes the global selection mid-session.
TranscriptionBackend resolveSessionBackend({
  required TranscriptionBackend globalDefault,
  String? promptBackendOverride,
}) {
  if (promptBackendOverride != null) {
    return TranscriptionBackendExtension.fromValue(promptBackendOverride);
  }
  return globalDefault;
}
