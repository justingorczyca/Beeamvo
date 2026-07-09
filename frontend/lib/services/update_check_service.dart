/// Lightweight GitHub-Releases-based update check for Beeamvo.
///
/// We never replace the running binary — we simply compare the installed
/// version (from [PackageInfo]) against the latest published GitHub release
/// and, when newer, surface the release page so the user can download it.
///
/// Every failure path is silent: network errors, non-200 responses, and
/// unparseable payloads all collapse to a `null` result so this can never
/// block startup, recording, or transcription.
library;

import 'dart:async';
import 'dart:convert';

import 'package:package_info_plus/package_info_plus.dart';

import 'pinned_http_client.dart';

/// Describes a published release that is newer than the running build.
class UpdateInfo {
  /// Latest version as `MAJOR.MINOR.PATCH` (leading `v` stripped).
  final String latestVersion;

  /// Browser URL of the release page (opened when the user taps "Download").
  final String releaseUrl;

  /// Markdown release notes body (may be empty).
  final String releaseNotes;

  /// ISO-8601 timestamp string of when the release was published (may be empty
  /// if the API did not provide one).
  final String publishedAt;

  const UpdateInfo({
    required this.latestVersion,
    required this.releaseUrl,
    required this.releaseNotes,
    required this.publishedAt,
  });

  factory UpdateInfo.fromMap(Map<String, dynamic> map) {
    return UpdateInfo(
      latestVersion: (map['version'] as String?) ?? '',
      releaseUrl: (map['url'] as String?) ?? '',
      releaseNotes: (map['notes'] as String?) ?? '',
      publishedAt: (map['publishedAt'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
    'version': latestVersion,
    'url': releaseUrl,
    'notes': releaseNotes,
    'publishedAt': publishedAt,
  };
}

/// Result of a GitHub release lookup.
///
/// A successful lookup may legitimately have no [update] when the installed
/// version is current. [succeeded] is therefore kept separate from [update] so
/// callers do not rate-limit transient network or parsing failures as if they
/// had successfully checked for updates.
class UpdateCheckResult {
  final bool succeeded;
  final UpdateInfo? update;

  const UpdateCheckResult._({required this.succeeded, this.update});

  const UpdateCheckResult.success([UpdateInfo? update])
    : this._(succeeded: true, update: update);

  const UpdateCheckResult.failure() : this._(succeeded: false);
}

class UpdateCheckService {
  /// GitHub endpoint for the single most recent non-prerelease release.
  static const _api =
      'https://api.github.com/repos/justingorczyca/Beeamvo/releases/latest';

  /// GitHub rejects requests without a `User-Agent` header (HTTP 403).
  static const _userAgent = 'Beeamvo-Update-Check';

  /// Compares the installed version against the latest GitHub release.
  ///
  /// Unlike [check], this preserves whether the lookup itself succeeded. This
  /// lets background callers retry a failed network request instead of treating
  /// it as a successful up-to-date result for the next 24 hours.
  Future<UpdateCheckResult> checkWithStatus({bool force = false}) async {
    // api.github.com has no configured pins in the shipped configuration, so
    // this currently uses normal OS certificate trust. The client is scoped to
    // a single request and always closed below.
    final client = createPinnedHttpClient();
    try {
      final installed = (await PackageInfo.fromPlatform()).version;
      final res = await client
          .get(Uri.parse(_api), headers: {'User-Agent': _userAgent})
          .timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) return const UpdateCheckResult.failure();

      final decoded = jsonDecode(res.body);
      if (decoded is! Map<String, dynamic>) {
        return const UpdateCheckResult.failure();
      }

      final tag = (decoded['tag_name'] as String?)?.trim();
      final url = decoded['html_url'] as String?;
      if (tag == null || url == null || url.isEmpty) {
        return const UpdateCheckResult.failure();
      }

      final latest = _normalizeVersion(tag);
      if (latest.isEmpty) return const UpdateCheckResult.failure();
      if (!_isVersionNewer(installed, latest)) {
        return const UpdateCheckResult.success();
      }

      return UpdateCheckResult.success(
        UpdateInfo(
          latestVersion: latest,
          releaseUrl: url,
          releaseNotes: (decoded['body'] as String?) ?? '',
          publishedAt: (decoded['published_at'] as String?) ?? '',
        ),
      );
    } catch (_) {
      // Best-effort: never propagate failures to the caller.
      return const UpdateCheckResult.failure();
    } finally {
      client.close();
    }
  }

  /// Compatibility wrapper for UI paths that only need an available update.
  /// Use [checkWithStatus] when retry/rate-limit decisions depend on success.
  Future<UpdateInfo?> check({bool force = false}) async {
    return (await checkWithStatus(force: force)).update;
  }

  /// Strips a leading `v`/`V` and any build/pre-release suffix, returning the
  /// bare `MAJOR.MINOR.PATCH` portion (may be a subset such as `1.0`).
  String _normalizeVersion(String raw) {
    var v = raw;
    if (v.startsWith('v') || v.startsWith('V')) v = v.substring(1);
    final dash = v.indexOf('-');
    if (dash != -1) v = v.substring(0, dash);
    final plus = v.indexOf('+');
    if (plus != -1) v = v.substring(0, plus);
    return v.trim();
  }

  /// Returns the first 3 numeric components of [version] (defaulting missing
  /// parts to 0), e.g. `'1.2'` → `[1, 2, 0]`.
  List<int> _components(String version) {
    final clean = _normalizeVersion(version);
    final parts = clean.split('.');
    final nums = <int>[];
    for (var i = 0; i < 3; i++) {
      nums.add(i < parts.length ? (int.tryParse(parts[i]) ?? 0) : 0);
    }
    return nums;
  }

  /// Splits both versions into `[major, minor, patch]` and compares element by
  /// element. Returns `true` only if [latest] is strictly greater than
  /// [installed].
  bool _isVersionNewer(String installed, String latest) {
    final a = _components(installed);
    final b = _components(latest);
    for (var i = 0; i < 3; i++) {
      if (b[i] != a[i]) return b[i] > a[i];
    }
    return false;
  }
}
