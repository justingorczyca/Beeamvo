import 'cloud_transcription_client.dart';

class TranscriptionResultGuard {
  static const String noTranscriptMessage = 'Nothing was transcribed.';
  static const String noTranscriptMarker = '[NO_TRANSCRIPT]';
  static const String noTranscriptPromptInstruction =
      'If the audio contains no discernible speech, only silence or noise, '
      'or is too short or too quiet to transcribe reliably, return exactly '
      '$noTranscriptMarker.';
  static const Duration minimumRecordingDuration = Duration(milliseconds: 350);

  static void ensureRecordingLongEnough(Duration duration) {
    if (duration < minimumRecordingDuration) {
      throw CloudTranscriptionException(noTranscriptMessage);
    }
  }

  static String requireTranscript(String text) {
    final normalized = text.trim();
    final marker = normalized.toUpperCase();
    if (normalized.isEmpty ||
        marker == noTranscriptMarker ||
        marker == 'NO_TRANSCRIPT') {
      throw CloudTranscriptionException(noTranscriptMessage);
    }
    return normalized;
  }
}
