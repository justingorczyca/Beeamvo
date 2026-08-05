import 'cloud_transcription_client.dart';

class TranscriptionResultGuard {
  static const String noTranscriptMessage = 'Nothing was transcribed.';
    static const String recordingTooShortMessage =
        'Recording was too short. Hold the hotkey a bit longer, then release.';
    static const String noTranscriptMarker = '[NO_TRANSCRIPT]';
    static const String noTranscriptPromptInstruction =
        'If the audio contains no discernible speech, only silence or noise, '
        'or is too short or too quiet to transcribe reliably, return exactly '
        '$noTranscriptMarker.';
    static const Duration minimumRecordingDuration = Duration(milliseconds: 350);

    static void ensureRecordingLongEnough(Duration duration) {
      if (duration < minimumRecordingDuration) {
        throw CloudTranscriptionException(recordingTooShortMessage);
      }
    }

  /// Maximum characters allowed in a transcription result.
  static const int maxTranscriptLength = 10000;

  /// Unicode ranges considered unsafe for direct paste:
  /// - BiDi control characters (U+202A–U+202E, U+2066–U+2069)
  /// - BiDi marks (U+200E, U+200F)
  /// - Zero-width / join characters (U+200B–U+200D, U+FEFF)
  static final RegExp _unsafeChars = RegExp(
    '[\u200B-\u200F\u202A-\u202E\u2066-\u2069\uFEFF]',
  );

  static String requireTranscript(String text) {
    // Strip BiDi / invisible control characters that could be used to
    // disguise text direction or interfere with the paste target.
    final cleaned = text.replaceAll(_unsafeChars, '');
    final normalized = cleaned.trim();
    final marker = normalized.toUpperCase();
    if (normalized.isEmpty ||
        marker == noTranscriptMarker ||
        marker == 'NO_TRANSCRIPT') {
      throw CloudTranscriptionException(noTranscriptMessage);
    }
    // Enforce a length cap to protect against runaway/hallucinated output.
    if (normalized.length > maxTranscriptLength) {
      return normalized.substring(0, maxTranscriptLength);
    }
    return normalized;
  }
}
