import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../models/usage_stats.dart';
import 'file_permissions.dart';

/// Service that tracks local usage statistics (word counts, streaks, etc.)
/// and persists them to a JSON file in the app-support directory.
///
/// Extends [ChangeNotifier] so the UI can react to stat updates.
class UsageStatsService extends ChangeNotifier {
  UsageStats _stats = const UsageStats();
  late File _file;

  /// Serializes [recordTranscription] so concurrent calls (e.g. back-to-back
  /// recording completions) run strictly one at a time. The `await _save()`
  /// inside the body is an interleaving point on the event loop: without this
  /// mutex, two near-simultaneous calls both read the same pre-update [_stats]
  /// snapshot and the loser's increment is silently lost — the lost-update
  /// race (see `BACKEND_SERVICES_AUDIT.md`, finding H-2). This is a simple
  /// chained-future lock; the chain is shielded with [Future.catchError] so a
  /// failed recording still surfaces its error to the caller while never
  /// leaving this future in an error state that would permanently block later
  /// recordings.
  Future<void> _recordLock = Future<void>.value();

  /// The current aggregated stats (read-only).
  UsageStats get stats => _stats;

  // ── Init ──────────────────────────────────────────────────────────────────

  Future<void> initialize() async {
    final dir = await getApplicationSupportDirectory();
    final folder = Directory('${dir.path}${Platform.pathSeparator}Beeamvo');
    if (!folder.existsSync()) {
      folder.createSync(recursive: true);
    }
    await setPosixPermissions(folder.path, '700');
    _file = File('${folder.path}${Platform.pathSeparator}usage_stats.json');
    if (_file.existsSync()) {
      await setPosixPermissions(_file.path, '600');
    }
    await _load();
    debugPrint('[UsageStatsService] initialized');
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> _load() async {
    // Crash-safe load: try the live file, then `.bak`, then the leftover
    // `.tmp`, before resetting — the read-side counterpart to the atomic
    // write in `_save()` below.
    final map =
        await _readJsonMap(_file) ??
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
      final encoded = const JsonEncoder.withIndent(
        '  ',
      ).convert(_stats.toMap());
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
    await setPosixPermissions(tmp.path, '600');
    if (target.existsSync()) {
      if (backup.existsSync()) {
        await backup.delete();
      }
      await target.rename(backup.path);
      await setPosixPermissions(backup.path, '600');
    }
    await tmp.rename(target.path);
    await setPosixPermissions(target.path, '600');
  }

  // ── Public API ────────────────────────────────────────────────────────────

  /// Call after a successful transcription.
  ///
  /// Serialized via [_recordLock]: concurrent invocations are queued onto a
  /// single chained future and never interleave across the `await _save()`
  /// inside the body — the interleaving that previously caused a lost update
  /// of [_stats], streaks, and achievement thresholds.
  Future<void> recordTranscription(String text, Duration recordingDuration) {
    // Chain onto the lock so this call only runs once the previous recording
    // has fully completed its read-modify-write + persist. The returned `run`
    // future still surfaces any error to the caller; we feed `_recordLock`
    // from `run.catchError(...)` instead so a single failure never leaves the
    // chain in an error state that would permanently block later recordings.
    final run = _recordLock
        .then((_) => _recordTranscriptionInternal(text, recordingDuration));
    _recordLock = run.catchError((Object _) {});
    return run;
  }

  /// The actual read-modify-write of [_stats] + persist + notify, executed
  /// exclusively from [recordTranscription] under the [_recordLock] mutex.
  Future<void> _recordTranscriptionInternal(
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
    final newLongest = newStreak > _stats.longestStreak
        ? newStreak
        : _stats.longestStreak;

    _stats = _stats.copyWith(
      totalWords: _stats.totalWords + wordCount,
      totalRecordings: _stats.totalRecordings + 1,
      totalRecordingDurationSeconds:
          _stats.totalRecordingDurationSeconds + seconds,
      longestRecordingSeconds: seconds > _stats.longestRecordingSeconds
          ? seconds
          : _stats.longestRecordingSeconds,
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
  /// Splits on whitespace for Latin/Cyrillic scripts, and counts each CJK
  /// ideograph as a separate 'word' for unsegmented scripts.
  int _countWords(String text) {
    const cjkPattern =
        r'[\u3400-\u9FFF\uF900-\uFAFF\u3040-\u30FF\uAC00-\uD7AF]';
    final cjkCount = RegExp(cjkPattern).allMatches(text).length;
    // Split on whitespace AND CJK ranges to separate Latin words from CJK runs.
    final spaced = text
        .split(RegExp(
            r'[\s\u3400-\u9FFF\uF900-\uFAFF\u3040-\u30FF\uAC00-\uD7AF]+'))
        .where((t) => t.isNotEmpty)
        .length;
    return spaced + cjkCount;
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
