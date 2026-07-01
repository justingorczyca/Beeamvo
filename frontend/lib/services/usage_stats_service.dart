import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/usage_stats.dart';

/// Service that tracks local usage statistics (word counts, streaks, etc.)
/// and persists them to a JSON file in the app-support directory.
///
/// Extends [ChangeNotifier] so the UI can react to stat updates.
class UsageStatsService extends ChangeNotifier {
  UsageStats _stats = const UsageStats();
  late File _file;

  /// The current aggregated stats (read-only).
  UsageStats get stats => _stats;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    final dir = await getApplicationSupportDirectory();
    final folder = Directory('${dir.path}${Platform.pathSeparator}Beeamvo');
    if (!folder.existsSync()) {
      folder.createSync(recursive: true);
    }
    _file = File('${folder.path}${Platform.pathSeparator}usage_stats.json');
    await _load();
    debugPrint('[UsageStatsService] initialized');
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> _load() async {
    // Crash-safe load: try the live file, then `.bak`, then the leftover
    // `.tmp`, before resetting — the read-side counterpart to the atomic
    // write in `_save()` below.
    final map = await _readJsonMap(_file) ??
        await _readJsonMap(File('${_file.path}.bak')) ??
        await _readJsonMap(File('${_file.path}.tmp'));
    if (map != null) {
      _stats = UsageStats.fromMap(map);
    } else {
      _stats = const UsageStats();
    }
    // Recalculate streak on startup (handles missed days)
    _stats = _stats.copyWith(currentStreak: _calculateStreak());
  }

  Future<Map<String, dynamic>?> _readJsonMap(File f) async {
    try {
      if (!f.existsSync()) return null;
      final raw = (await f.readAsString()).trim();
      if (raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } catch (e) {
      debugPrint('[UsageStatsService] load error from ${f.path}: $e');
      return null;
    }
  }

  Future<void> _save() async {
    try {
      final encoded =
          const JsonEncoder.withIndent('  ').convert(_stats.toMap());
      await _writeAtomic(_file, encoded);
    } catch (e) {
      debugPrint('[UsageStatsService] save error: $e');
    }
  }

  /// Atomically persist [content] to [target], keeping a `.bak` of the
  /// previous-good file (renames always target a non-existent path, so they
  /// are atomic and cross-platform safe). If a crash lands between the two
  /// renames, `_load()` recovers from the `.bak`.
  Future<void> _writeAtomic(File target, String content) async {
    final tmp = File('${target.path}.tmp');
    final backup = File('${target.path}.bak');
    await tmp.writeAsString(content, flush: true);
    if (target.existsSync()) {
      if (backup.existsSync()) {
        await backup.delete();
      }
      await target.rename(backup.path);
    }
    await tmp.rename(target.path);
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Call after a successful transcription.
  Future<void> recordTranscription(
    String text,
    Duration recordingDuration,
  ) async {
    final wordCount = _countWords(text);
    final today = _todayKey();
    final seconds = recordingDuration.inSeconds;

    // Update daily word count
    final newDaily = Map<String, int>.from(_stats.dailyWordCount);
    newDaily[today] = (newDaily[today] ?? 0) + wordCount;

    // Recalculate streak
    final newStreak = _calculateStreak(todayKey: today, daily: newDaily);
    final newLongest =
        newStreak > _stats.longestStreak ? newStreak : _stats.longestStreak;

    _stats = _stats.copyWith(
      totalWords: _stats.totalWords + wordCount,
      totalRecordings: _stats.totalRecordings + 1,
      totalRecordingDurationSeconds:
          _stats.totalRecordingDurationSeconds + seconds,
      longestRecordingSeconds:
          seconds > _stats.longestRecordingSeconds ? seconds : _stats.longestRecordingSeconds,
      currentStreak: newStreak,
      longestStreak: newLongest,
      lastRecordingDate: today,
      firstRecordingDate: _stats.firstRecordingDate ?? today,
      dailyWordCount: newDaily,
    );

    await _save();
    notifyListeners();
  }

  /// Returns word counts for the last 7 days (Mon–Sun of current week).
  List<int> getWeeklyData() {
    final now = DateTime.now();
    // Find Monday of the current week
    final monday = now.subtract(Duration(days: now.weekday - 1));
    return List.generate(7, (i) {
      final day = monday.add(Duration(days: i));
      final key = _dateKey(day);
      return _stats.dailyWordCount[key] ?? 0;
    });
  }

  /// Returns activity data for the last [count] days.
  /// Each entry is an int (words spoken that day, 0 if empty).
  List<int> getRecentDays(int count) {
    return List.generate(count, (i) {
      final day = DateTime.now().subtract(Duration(days: count - 1 - i));
      return _stats.dailyWordCount[_dateKey(day)] ?? 0;
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Count words in a transcription string.
  /// Splits on whitespace, filters empty tokens.
  int _countWords(String text) {
    return text.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).length;
  }

  /// Today's date as "YYYY-MM-DD".
  String _todayKey() => _dateKey(DateTime.now());

  String _dateKey(DateTime dt) {
    return '${dt.year.toString().padLeft(4, '0')}'
        '-${dt.month.toString().padLeft(2, '0')}'
        '-${dt.day.toString().padLeft(2, '0')}';
  }

  /// Calculate current streak (consecutive days with activity ending today
  /// or yesterday).
  int _calculateStreak({String? todayKey, Map<String, int>? daily}) {
    todayKey ??= _todayKey();
    daily ??= _stats.dailyWordCount;

    final today = DateTime.parse(todayKey);
    int streak = 0;

    for (int i = 0; i < 365; i++) {
      final day = today.subtract(Duration(days: i));
      final key = _dateKey(day);
      if (daily.containsKey(key) && daily[key]! > 0) {
        streak++;
      } else if (i == 0) {
        // Today has no activity yet — that's OK, check yesterday.
        continue;
      } else {
        break;
      }
    }
    return streak;
  }
}
