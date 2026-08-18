/// Parses numeric `Retry-After` as delay-seconds per RFC 9110.
///
/// HTTP-date values deliberately fall back to jittered backoff. The 60-second
/// ceiling prevents hostile or absurd headers from stalling the UI.
const int maxRetryAfterDelayMilliseconds = 60 * 1000;

int? retryAfterDelayMilliseconds(String? header) {
  final seconds = header == null ? null : int.tryParse(header.trim());
  if (seconds == null) return null;
  return (seconds * 1000).clamp(0, maxRetryAfterDelayMilliseconds).toInt();
}
