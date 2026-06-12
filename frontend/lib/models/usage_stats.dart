/// Aggregated usage statistics persisted to disk.
///
/// All fields are stored as simple JSON-serializable types so the service can
/// read/write them without code-gen.
class UsageStats {
  final int totalWords;
  final int totalRecordings;
  final int totalRecordingDurationSeconds;
  final int longestRecordingSeconds;
  final int currentStreak;
  final int longestStreak;

  /// ISO-8601 date string of the most recent recording (e.g. "2025-01-15").
  final String? lastRecordingDate;

  /// ISO-8601 date string of the very first recording.
  final String? firstRecordingDate;

  /// Map of ISO date → word count for that day.
  final Map<String, int> dailyWordCount;

  const UsageStats({
    this.totalWords = 0,
    this.totalRecordings = 0,
    this.totalRecordingDurationSeconds = 0,
    this.longestRecordingSeconds = 0,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.lastRecordingDate,
    this.firstRecordingDate,
    this.dailyWordCount = const {},
  });

  // ── Computed helpers ──────────────────────────────────────────────────────

  /// Estimated typing time saved in **minutes**, assuming 40 WPM average.
  double get totalTypingTimeSavedMinutes => totalWords / 40.0;

  /// Average words per recording (0 when no recordings yet).
  double get averageWordsPerRecording =>
      totalRecordings == 0 ? 0 : totalWords / totalRecordings;

  /// Number of unique days the user has made at least one recording.
  int get totalSessionDays => dailyWordCount.length;

  /// Whether the user has made at least one recording.
  bool get hasAnyRecording => totalRecordings > 0;

  // ── Serialization ─────────────────────────────────────────────────────────

  Map<String, dynamic> toMap() {
    return {
      'totalWords': totalWords,
      'totalRecordings': totalRecordings,
      'totalRecordingDurationSeconds': totalRecordingDurationSeconds,
      'longestRecordingSeconds': longestRecordingSeconds,
      'currentStreak': currentStreak,
      'longestStreak': longestStreak,
      'lastRecordingDate': lastRecordingDate,
      'firstRecordingDate': firstRecordingDate,
      'dailyWordCount': dailyWordCount,
    };
  }

  factory UsageStats.fromMap(Map<String, dynamic> map) {
    final dailyRaw = map['dailyWordCount'];
    final Map<String, int> daily = {};
    if (dailyRaw is Map) {
      for (final entry in dailyRaw.entries) {
        daily[entry.key.toString()] = (entry.value as num?)?.toInt() ?? 0;
      }
    }
    return UsageStats(
      totalWords: (map['totalWords'] as num?)?.toInt() ?? 0,
      totalRecordings: (map['totalRecordings'] as num?)?.toInt() ?? 0,
      totalRecordingDurationSeconds:
          (map['totalRecordingDurationSeconds'] as num?)?.toInt() ?? 0,
      longestRecordingSeconds:
          (map['longestRecordingSeconds'] as num?)?.toInt() ?? 0,
      currentStreak: (map['currentStreak'] as num?)?.toInt() ?? 0,
      longestStreak: (map['longestStreak'] as num?)?.toInt() ?? 0,
      lastRecordingDate: map['lastRecordingDate'] as String?,
      firstRecordingDate: map['firstRecordingDate'] as String?,
      dailyWordCount: daily,
    );
  }

  /// Create a copy with optional field overrides.
  UsageStats copyWith({
    int? totalWords,
    int? totalRecordings,
    int? totalRecordingDurationSeconds,
    int? longestRecordingSeconds,
    int? currentStreak,
    int? longestStreak,
    String? lastRecordingDate,
    String? firstRecordingDate,
    Map<String, int>? dailyWordCount,
  }) {
    return UsageStats(
      totalWords: totalWords ?? this.totalWords,
      totalRecordings: totalRecordings ?? this.totalRecordings,
      totalRecordingDurationSeconds:
          totalRecordingDurationSeconds ?? this.totalRecordingDurationSeconds,
      longestRecordingSeconds:
          longestRecordingSeconds ?? this.longestRecordingSeconds,
      currentStreak: currentStreak ?? this.currentStreak,
      longestStreak: longestStreak ?? this.longestStreak,
      lastRecordingDate: lastRecordingDate ?? this.lastRecordingDate,
      firstRecordingDate: firstRecordingDate ?? this.firstRecordingDate,
      dailyWordCount: dailyWordCount ?? this.dailyWordCount,
    );
  }
}
