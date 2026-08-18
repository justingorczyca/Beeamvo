const int maxRetryAfterDelayMilliseconds = Duration.secondsPerMinute * 1000;

int? retryAfterDelayMilliseconds(String? header) {
  final seconds = header == null ? null : int.tryParse(header.trim());
  if (seconds == null) return null;
  return (seconds * 1000).clamp(0, maxRetryAfterDelayMilliseconds).toInt();
}
