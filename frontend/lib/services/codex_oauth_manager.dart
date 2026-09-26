import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'pinned_http_client.dart';
import 'secure_credential_store.dart';

/// Thrown when the user must (re-)sign-in with their ChatGPT account before
/// Codex requests can run.
class CodexSignInRequiredException implements Exception {
  const CodexSignInRequiredException([this.message]);

  final String? message;

  @override
  String toString() =>
      message ??
      'ChatGPT Codex sign-in required. Sign in with ChatGPT and try again.';
}

/// Generic Codex OAuth failure (token exchange, refresh, device login).
class CodexOAuthException implements Exception {
  const CodexOAuthException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// Thrown when OpenAI Codex bespoke device-code login is not available for
/// this client/account; callers should fall back to the loopback flow.
class CodexDeviceLoginUnavailableException implements Exception {
  const CodexDeviceLoginUnavailableException([this.message]);

  final String? message;

  @override
  String toString() => message ?? 'Codex device-code login is not available.';
}

/// OAuth credentials for the ChatGPT Codex backend.
///
/// The layout intentionally matches what the OpenAI Codex CLI writes to
/// `~/.codex/auth.json` so an existing CLI sign-in can be imported
/// transparently.
class CodexCredentials {
  const CodexCredentials({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.idToken,
    this.tokenType = 'Bearer',
    this.accountId,
    required this.createdAt,
    required this.updatedAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String? idToken;
  final String tokenType;
  final String? accountId;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool expiresWithin(Duration buffer, DateTime now) =>
      !expiresAt.isAfter(now.add(buffer));

  CodexCredentials copyWith({
    String? accessToken,
    String? refreshToken,
    DateTime? expiresAt,
    String? idToken,
    String? tokenType,
    String? accountId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return CodexCredentials(
      accessToken: accessToken ?? this.accessToken,
      refreshToken: refreshToken ?? this.refreshToken,
      expiresAt: expiresAt ?? this.expiresAt,
      idToken: idToken ?? this.idToken,
      tokenType: tokenType ?? this.tokenType,
      accountId: accountId ?? this.accountId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'expiresAt': expiresAt.toUtc().toIso8601String(),
      if (idToken != null && idToken!.isNotEmpty) 'idToken': idToken,
      'tokenType': tokenType,
      if (accountId != null && accountId!.isNotEmpty) 'accountId': accountId,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  /// Decodes both the native shape and the Codex CLI's nested
  /// `{ tokens: { access_token, ... }, last_refresh: ... }` shape.
  static CodexCredentials? fromJson(Map<String, dynamic> json) {
    final nestedTokens = json['tokens'];
    if (nestedTokens is Map) {
      final merged = <String, dynamic>{
        ...json,
        ...Map<String, dynamic>.from(nestedTokens),
      }..remove('tokens');
      merged['createdAt'] ??= json['last_refresh'];
      merged['updatedAt'] ??= json['last_refresh'];
      return fromJson(merged);
    }

    final accessToken =
        json['accessToken']?.toString() ??
        json['access_token']?.toString() ??
        '';
    final refreshToken =
        json['refreshToken']?.toString() ??
        json['refresh_token']?.toString() ??
        '';
    if (accessToken.isEmpty || refreshToken.isEmpty) return null;

    final expiresAt =
        CodexOAuthManager.parseDateTime(json['expiresAt']) ??
        CodexOAuthManager.parseDateTime(json['expires_at']) ??
        CodexOAuthManager.expiresAtFromJwt(accessToken) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);

    final now = DateTime.now().toUtc();
    return CodexCredentials(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt,
      idToken: json['idToken']?.toString() ?? json['id_token']?.toString(),
      tokenType:
          json['tokenType']?.toString() ??
          json['token_type']?.toString() ??
          'Bearer',
      accountId:
          json['accountId']?.toString() ??
          json['account_id']?.toString() ??
          CodexOAuthManager.extractAccountIdFromClaims(
            CodexOAuthManager.decodeJwtClaims(accessToken) ??
                const <String, dynamic>{},
          ),
      createdAt:
          CodexOAuthManager.parseDateTime(json['createdAt']) ??
          CodexOAuthManager.parseDateTime(json['created_at']) ??
          now,
      updatedAt:
          CodexOAuthManager.parseDateTime(json['updatedAt']) ??
          CodexOAuthManager.parseDateTime(json['updated_at']) ??
          now,
    );
  }
}

/// Snapshot of the current Codex sign-in state.
class CodexAuthStatus {
  const CodexAuthStatus({
    required this.isSignedIn,
    this.accountId,
    this.expiresAt,
  });

  final bool isSignedIn;
  final String? accountId;
  final DateTime? expiresAt;
}

/// Handle for an in-progress loopback OAuth login.
class CodexOAuthFlow {
  const CodexOAuthFlow({
    required this.authorizationUrl,
    required this.completion,
    required Future<void> Function() cancelAction,
  }) : _cancel = cancelAction;

  /// The authorization URL the user's browser was sent to.
  final String authorizationUrl;

  /// Resolves once the loopback callback has been exchanged for credentials.
  final Future<CodexCredentials> completion;

  final Future<void> Function() _cancel;

  Future<void> cancel() => _cancel();
}

/// In-progress "paste the redirect URL" login for environments where a
/// loopback callback cannot be received.
class CodexManualLoginSession {
  const CodexManualLoginSession({
    required this.authorizationUrl,
    required this.state,
    required this.codeVerifier,
    required this.codeChallenge,
    required this.createdAt,
  });

  final String authorizationUrl;
  final String state;
  final String codeVerifier;
  final String codeChallenge;
  final DateTime createdAt;
}

/// State for an in-progress Codex device-code login
/// (`codex login --device-auth`). The user visits [verificationUrl] and
/// enters [userCode]; polling completes via [CodexOAuthManager].
class CodexDeviceCodeSession {
  const CodexDeviceCodeSession({
    required this.deviceAuthId,
    required this.userCode,
    required this.verificationUrl,
    required this.pollInterval,
    required this.expiresAt,
  });

  final String deviceAuthId;
  final String userCode;
  final String verificationUrl;
  final Duration pollInterval;
  final DateTime expiresAt;
}

/// OAuth manager for OpenAI Codex (ChatGPT-account sign-in).
///
/// Adapted from the codgine `OpenAICodexOAuthManager`:
///
/// * Loopback redirect + PKCE on `localhost:1455/auth/callback`.
/// * Token requests are JSON-encoded (not form-urlencoded).
/// * Credentials persist in the OS secure store via [SecureCredentialStore].
/// * Credentials can be transparently imported from the Codex CLI's
///   `~/.codex/auth.json`; a persisted "import disabled" flag keeps the user
///   signed out across launches after an explicit sign-out.
/// * Refresh failures caused by a rejected refresh token attempt one
///   re-import before forcing sign-in.
class CodexOAuthManager {
  CodexOAuthManager({
    SecureCredentialStore? credentialStore,
    http.Client? client,
    this.codexDirOverride,
    DateTime Function()? now,
    FutureOr<bool> Function()? isCliImportDisabled,
    FutureOr<void> Function(bool disabled)? setCliImportDisabled,
    Future<void> Function(String url)? openUrl,
  }) : _credentialStore =
           credentialStore ?? const FlutterSecureCredentialStore(),
       _client = client ?? createSecureHttpClient(),
       _now = now ?? (() => DateTime.now().toUtc()),
       _isCliImportDisabled = isCliImportDisabled ?? (() => false),
       _setCliImportDisabled = setCliImportDisabled ?? ((_) async {}),
       _openUrl = openUrl ?? _defaultOpenUrl;

  // ── Static configuration ───────────────────────────────────────────────

  static const String credentialsAccount = 'codex_oauth_credentials';
  static const String codexAuthFileName = 'auth.json';
  static const String clientId = 'app_EMoamEEZ73f0CkXaXp7hrann';
  static const String authorizationEndpoint =
      'https://auth.openai.com/oauth/authorize';
  static const String tokenEndpoint = 'https://auth.openai.com/oauth/token';
  static const String redirectUri = 'http://localhost:1455/auth/callback';
  static const String defaultScope = 'openid profile email offline_access';
  static const int callbackPort = 1455;
  static const String callbackPath = '/auth/callback';
  static const Duration refreshBuffer = Duration(minutes: 5);

  /// Device-auth usercode endpoint (`codex login --device-auth`).
  static const String deviceAuthUsercodeEndpoint =
      'https://auth.openai.com/api/accounts/deviceauth/usercode';

  /// Device-auth token poll endpoint.
  static const String deviceAuthTokenPollEndpoint =
      'https://auth.openai.com/api/accounts/deviceauth/token';

  /// The page the user must visit to approve a device login.
  static const String deviceAuthVerificationUrl =
      'https://auth.openai.com/codex/device';

  /// Redirect URI sent on the authorization-code exchange that closes the
  /// device flow.
  static const String deviceAuthCallbackRedirectUri =
      'https://auth.openai.com/deviceauth/callback';

  /// How long a device-code session is considered live.
  static const Duration deviceAuthSessionLifetime = Duration(minutes: 15);

  final SecureCredentialStore _credentialStore;
  final http.Client _client;
  final DateTime Function() _now;

  /// Optional override for the directory containing the Codex CLI
  /// `auth.json`. Tests use this to point at a temp directory.
  final String? codexDirOverride;

  /// Callbacks that persist the "Codex CLI import disabled" flag.
  /// [SettingsService] wires these to a settings key; the defaults keep
  /// import always allowed (used by tests and standalone callers).
  final FutureOr<bool> Function() _isCliImportDisabled;
  final FutureOr<void> Function(bool disabled) _setCliImportDisabled;
  final Future<void> Function(String url) _openUrl;

  Future<CodexCredentials>? _refreshFuture;

  DateTime currentTime() => _now();

  static Future<void> _defaultOpenUrl(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  // ── PKCE / JWT helpers ─────────────────────────────────────────────────

  static const String _verifierAlphabet =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';

  /// Generates a high-entropy PKCE `code_verifier` per RFC 7636.
  static String generateCodeVerifier({int length = 64}) {
    final random = Random.secure();
    return List<String>.generate(
      length,
      (_) => _verifierAlphabet[random.nextInt(_verifierAlphabet.length)],
    ).join();
  }

  /// base64url-encoded SHA-256 challenge for [verifier].
  static String codeChallengeForVerifier(String verifier) {
    final digest = sha256.convert(utf8.encode(verifier));
    return base64Url.encode(digest.bytes).replaceAll('=', '');
  }

  /// Generates a fresh `state` parameter (base64url, no padding).
  static String generateState({int byteLength = 32}) =>
      base64Url.encode(_randomBytes(byteLength)).replaceAll('=', '');

  static List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  /// Decodes the JWT payload of [token] without verifying its signature.
  static Map<String, dynamic>? decodeJwtClaims(String token) {
    final parts = token.split('.');
    if (parts.length < 2) return null;
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Reads the `exp` claim from [token] as a UTC [DateTime], or null.
  static DateTime? expiresAtFromJwt(String token) {
    final exp = decodeJwtClaims(token)?['exp'];
    if (exp is num) {
      return DateTime.fromMillisecondsSinceEpoch(
        exp.toInt() * 1000,
        isUtc: true,
      );
    }
    return null;
  }

  /// Parses a date that may be an ISO-8601 string, milliseconds since epoch,
  /// or seconds since epoch. Returns null when unparseable.
  static DateTime? parseDateTime(Object? raw) {
    if (raw == null) return null;
    if (raw is num) {
      final value = raw.toInt();
      if (value > 100000000000) {
        return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
      }
      return DateTime.fromMillisecondsSinceEpoch(value * 1000, isUtc: true);
    }
    return DateTime.tryParse(raw.toString())?.toUtc();
  }

  /// Extracts a ChatGPT account id from JWT claims.
  static String? extractAccountIdFromClaims(Map<String, dynamic> claims) {
    const directKeys = <String>[
      'account_id',
      'chatgpt_account_id',
      'https://api.openai.com/auth/account_id',
      'https://api.openai.com/auth/chatgpt_account_id',
    ];
    for (final key in directKeys) {
      final value = claims[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }

    final authClaim = claims['https://api.openai.com/auth'];
    if (authClaim is Map) {
      final accountId =
          authClaim['account_id']?.toString().trim() ??
          authClaim['chatgpt_account_id']?.toString().trim();
      if (accountId != null && accountId.isNotEmpty) return accountId;
    }

    final accounts = claims['accounts'];
    if (accounts is List) {
      for (final account in accounts) {
        if (account is Map) {
          final id =
              account['id']?.toString().trim() ??
              account['account_id']?.toString().trim();
          if (id != null && id.isNotEmpty) return id;
        }
      }
    }
    return null;
  }

  /// Builds the OpenAI Codex authorization URL. Static for tests and for
  /// callers that want the URL without starting a login.
  static Uri buildAuthorizationUri({
    required String codeChallenge,
    required String state,
    String redirectUri = redirectUri,
    String scope = defaultScope,
  }) {
    return Uri.parse(authorizationEndpoint).replace(
      queryParameters: <String, String>{
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'scope': scope,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'state': state,
      },
    );
  }

  // ── Persistence ────────────────────────────────────────────────────────

  Future<bool> _importDisabled() => Future.value(_isCliImportDisabled());

  Future<void> _setImportDisabled(bool disabled) =>
      Future.value(_setCliImportDisabled(disabled));

  /// Loads stored credentials, transparently importing from the Codex CLI's
  /// `auth.json` when allowed.
  Future<CodexCredentials?> loadCredentials() async {
    final stored = await _readStoredCredentials();
    final importDisabled = await _importDisabled();

    if (stored != null) {
      if (!importDisabled) {
        final imported = await loadCodexHomeCredentials();
        if (imported != null && _preferExternal(stored, imported)) {
          await saveCredentials(imported);
          return imported;
        }
      }
      return stored;
    }

    if (importDisabled) return null;
    final imported = await loadCodexHomeCredentials();
    if (imported == null) return null;
    await saveCredentials(imported);
    return imported;
  }

  Future<CodexCredentials?> _readStoredCredentials() async {
    final raw = await _credentialStore.readApiKey(credentialsAccount);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return CodexCredentials.fromJson(decoded);
      }
      if (decoded is Map) {
        return CodexCredentials.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  /// Whether the imported credentials should replace [stored]. Keeps the
  /// stored set unless the import is strictly newer and actually different.
  bool _preferExternal(CodexCredentials stored, CodexCredentials imported) {
    if (imported.refreshToken == stored.refreshToken &&
        imported.accessToken == stored.accessToken) {
      return false;
    }
    return !imported.updatedAt.isBefore(stored.updatedAt);
  }

  /// Persists [credentials] and clears the import-disabled flag (a fresh
  /// sign-in always re-enables CLI import).
  Future<void> saveCredentials(CodexCredentials credentials) async {
    await _credentialStore.writeApiKey(
      credentialsAccount,
      jsonEncode(credentials.toJson()),
    );
    await _setImportDisabled(false);
  }

  /// Removes the stored credentials and persists the import-disabled flag so
  /// the user stays signed out across launches.
  Future<void> signOut() async {
    await _credentialStore.deleteApiKey(credentialsAccount);
    await _setImportDisabled(true);
  }

  /// Current sign-in status without triggering a refresh.
  Future<CodexAuthStatus> status() async {
    final credentials = await loadCredentials();
    return CodexAuthStatus(
      isSignedIn: credentials != null,
      accountId: credentials?.accountId,
      expiresAt: credentials?.expiresAt,
    );
  }

  // ── Codex CLI auth.json import ─────────────────────────────────────────

  /// Reads the Codex CLI's `auth.json`, honouring [codexDirOverride],
  /// `$CODEX_HOME`, then `~/.codex/`.
  Future<CodexCredentials?> loadCodexHomeCredentials() async {
    final file = File(_codexAuthFilePath());
    if (!await file.exists()) return null;
    try {
      final modifiedAt = (await file.stat()).modified.toUtc();
      final decoded = jsonDecode(await file.readAsString());
      final map = decoded is Map<String, dynamic>
          ? decoded
          : decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : null;
      if (map == null) return null;
      final credentials = CodexCredentials.fromJson(map);
      if (credentials == null) return null;
      if (_hasCredentialTimestamp(map)) return credentials;
      return credentials.copyWith(createdAt: modifiedAt, updatedAt: modifiedAt);
    } catch (_) {
      return null;
    }
  }

  String _codexAuthFilePath() {
    final explicit = codexDirOverride?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      return '$explicit${Platform.pathSeparator}$codexAuthFileName';
    }
    final env = Platform.environment;
    final home = env['CODEX_HOME'] ?? env['HOME'] ?? env['USERPROFILE'] ?? '.';
    final separator = Platform.pathSeparator;
    if (home.endsWith('$separator.codex')) {
      return '$home$separator$codexAuthFileName';
    }
    return '$home$separator.codex$separator$codexAuthFileName';
  }

  bool _hasCredentialTimestamp(Map<String, dynamic> json) {
    if (_hasTimestampField(json)) return true;
    final tokens = json['tokens'];
    return tokens is Map && _hasTimestampField(tokens);
  }

  bool _hasTimestampField(Map<dynamic, dynamic> json) {
    return json['createdAt'] != null ||
        json['created_at'] != null ||
        json['updatedAt'] != null ||
        json['updated_at'] != null ||
        json['last_refresh'] != null;
  }

  // ── Token exchange & refresh ───────────────────────────────────────────

  CodexCredentials _credentialsFromTokenResponse(
    Map<String, dynamic> response, {
    CodexCredentials? previous,
  }) {
    final accessToken =
        response['access_token']?.toString() ??
        response['accessToken']?.toString() ??
        '';
    if (accessToken.isEmpty) {
      throw const CodexOAuthException(
        'Codex token response did not include an access token.',
      );
    }

    final refreshToken =
        response['refresh_token']?.toString() ??
        response['refreshToken']?.toString() ??
        previous?.refreshToken ??
        '';
    if (refreshToken.isEmpty) {
      throw const CodexOAuthException(
        'Codex token response did not include a refresh token.',
      );
    }

    final now = _now();
    final idToken =
        response['id_token']?.toString() ?? response['idToken']?.toString();
    final claims =
        decodeJwtClaims(accessToken) ??
        (idToken == null ? null : decodeJwtClaims(idToken)) ??
        const <String, dynamic>{};
    final accountId = extractAccountIdFromClaims(claims) ?? previous?.accountId;
    final expiresAt = _expiresAtFromTokenResponse(response, accessToken, now);

    return CodexCredentials(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt,
      idToken: idToken ?? previous?.idToken,
      tokenType:
          response['token_type']?.toString() ??
          response['tokenType']?.toString() ??
          previous?.tokenType ??
          'Bearer',
      accountId: accountId,
      createdAt: previous?.createdAt ?? now,
      updatedAt: now,
    );
  }

  DateTime _expiresAtFromTokenResponse(
    Map<String, dynamic> response,
    String accessToken,
    DateTime now,
  ) {
    final expiresAt = parseDateTime(
      response['expires_at'] ?? response['expiresAt'],
    );
    if (expiresAt != null) return expiresAt;

    final expiresIn = response['expires_in'] ?? response['expiresIn'];
    final seconds = expiresIn is num
        ? expiresIn.toInt()
        : int.tryParse(expiresIn?.toString() ?? '');
    if (seconds != null) return now.add(Duration(seconds: seconds));

    return expiresAtFromJwt(accessToken) ?? now.add(const Duration(hours: 1));
  }

  Future<Map<String, dynamic>> _postTokenRequest(
    Map<String, String> body,
  ) async {
    final response = await _client.post(
      Uri.parse(tokenEndpoint),
      headers: const <String, String>{
        HttpHeaders.contentTypeHeader: 'application/json',
        HttpHeaders.acceptHeader: 'application/json',
      },
      body: jsonEncode(body),
    );
    final decoded = _decodeJson(response.body);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw _CodexTokenHttpError(response.statusCode, decoded);
    }
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw CodexOAuthException(
      'Codex token response was not a JSON object.',
      statusCode: response.statusCode,
    );
  }

  /// Exchanges an authorization [code] for credentials at the token
  /// endpoint. [redirectUriOverride] is used by the device-code flow, whose
  /// callback URL differs from the loopback URI.
  Future<CodexCredentials> exchangeAuthorizationCode({
    required String code,
    required String codeVerifier,
    String? codeChallenge,
    String? redirectUriOverride,
  }) async {
    final body = <String, String>{
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUriOverride ?? redirectUri,
      'client_id': clientId,
      'code_verifier': codeVerifier,
    };
    if (codeChallenge != null && codeChallenge.isNotEmpty) {
      body['code_challenge'] = codeChallenge;
      body['code_challenge_method'] = 'S256';
    }
    final response = await _postTokenRequest(body);
    return _credentialsFromTokenResponse(response);
  }

  /// Returns a valid access token, refreshing when expiry is within
  /// [refreshBuffer].
  Future<String> getAccessToken() async {
    final credentials = await loadCredentials();
    if (credentials == null) {
      throw const CodexSignInRequiredException();
    }
    if (!credentials.expiresWithin(refreshBuffer, _now())) {
      return credentials.accessToken;
    }
    return (await refreshCredentials(credentials)).accessToken;
  }

  /// Forces a refresh regardless of expiry.
  Future<String> forceRefreshAccessToken() async {
    final credentials = await loadCredentials();
    if (credentials == null) {
      throw const CodexSignInRequiredException();
    }
    return (await refreshCredentials(credentials)).accessToken;
  }

  /// De-duplicated refresh: concurrent callers share one in-flight future.
  Future<CodexCredentials> refreshCredentials(
    CodexCredentials credentials,
  ) async {
    final existing = _refreshFuture;
    if (existing != null) return existing;
    final future = _performRefresh(credentials);
    _refreshFuture = future;
    try {
      return await future;
    } finally {
      if (identical(_refreshFuture, future)) _refreshFuture = null;
    }
  }

  Future<CodexCredentials> _performRefresh(CodexCredentials credentials) async {
    if (credentials.refreshToken.isEmpty) {
      await signOut();
      throw const CodexSignInRequiredException();
    }
    Map<String, dynamic> response;
    try {
      response = await _postTokenRequest(<String, String>{
        'grant_type': 'refresh_token',
        'client_id': clientId,
        'refresh_token': credentials.refreshToken,
      });
    } on _CodexTokenHttpError catch (error) {
      if (_isRefreshTokenRejection(error)) {
        final replacement = await _findReplacementForRejectedRefresh(
          credentials,
        );
        if (replacement != null) {
          await saveCredentials(replacement);
          if (!replacement.expiresWithin(refreshBuffer, _now())) {
            return replacement;
          }
          return _performRefresh(replacement);
        }
        await _clearCredentialsIfCurrent(credentials);
        throw const CodexSignInRequiredException(
          'ChatGPT Codex session expired. Sign in again.',
        );
      }
      throw CodexOAuthException(
        'Codex token refresh failed with HTTP ${error.statusCode}.',
        statusCode: error.statusCode,
      );
    }
    final refreshed = _credentialsFromTokenResponse(
      response,
      previous: credentials,
    );
    await saveCredentials(refreshed);
    return refreshed;
  }

  bool _isRefreshTokenRejection(_CodexTokenHttpError error) {
    final decoded = error.decoded;
    String? code;
    String? message;
    if (decoded is Map) {
      final rawError = decoded['error'];
      if (rawError is Map) {
        code =
            rawError['code']?.toString() ??
            rawError['error']?.toString() ??
            rawError['type']?.toString();
        message = rawError['message']?.toString();
      } else {
        code = rawError?.toString() ?? decoded['code']?.toString();
        message =
            decoded['error_description']?.toString() ??
            decoded['message']?.toString();
      }
    }
    if (code == 'invalid_grant') return true;
    final normalized = '${code ?? ''} ${message ?? ''}'.toLowerCase();
    if (!normalized.contains('refresh token')) return false;
    return normalized.contains('already been used') ||
        normalized.contains('invalid') ||
        normalized.contains('expired') ||
        normalized.contains('revoked');
  }

  /// When a refresh token is rejected, a fresher credential set may exist in
  /// the Codex CLI's auth file (the CLI refreshed independently). Re-import
  /// it once before forcing sign-in.
  Future<CodexCredentials?> _findReplacementForRejectedRefresh(
    CodexCredentials rejected,
  ) async {
    final stored = await _readStoredCredentials();
    if (stored != null && stored.refreshToken != rejected.refreshToken) {
      return stored;
    }
    if (await _importDisabled()) return null;
    final imported = await loadCodexHomeCredentials();
    if (imported != null && imported.refreshToken != rejected.refreshToken) {
      return imported;
    }
    return null;
  }

  Future<void> _clearCredentialsIfCurrent(CodexCredentials attempted) async {
    final current = await _readStoredCredentials();
    if (current != null && current.refreshToken != attempted.refreshToken) {
      return;
    }
    await _credentialStore.deleteApiKey(credentialsAccount);
  }

  // ── Loopback PKCE login ────────────────────────────────────────────────

  /// Starts a loopback OAuth login: binds a local HTTP server on
  /// [callbackPort], optionally opens the authorization URL in the browser,
  /// validates the callback, exchanges the code, and persists credentials.
  Future<CodexOAuthFlow> startLogin({bool openBrowser = true}) async {
    final verifier = generateCodeVerifier();
    final state = generateState();
    final codeChallenge = codeChallengeForVerifier(verifier);
    final authorizationUri = buildAuthorizationUri(
      codeChallenge: codeChallenge,
      state: state,
    );

    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      callbackPort,
    );
    final completer = Completer<CodexCredentials>();
    late final StreamSubscription<HttpRequest> subscription;

    Future<void> closeServer() async {
      await subscription.cancel();
      await server.close(force: true);
    }

    subscription = server.listen((request) async {
      if (request.uri.path != callbackPath) {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
        return;
      }

      final query = request.uri.queryParameters;
      final returnedState = query['state'];
      final code = query['code'];
      final error = query['error'] ?? query['error_description'];

      if (returnedState != state) {
        await _writeCallbackPage(
          request,
          HttpStatus.badRequest,
          'ChatGPT sign-in failed: invalid state.',
        );
        if (!completer.isCompleted) {
          completer.completeError(
            const CodexOAuthException('Invalid OAuth state.'),
          );
        }
        await closeServer();
        return;
      }

      if (error != null && error.isNotEmpty) {
        await _writeCallbackPage(
          request,
          HttpStatus.badRequest,
          'ChatGPT sign-in failed.',
        );
        if (!completer.isCompleted) {
          completer.completeError(CodexOAuthException(error));
        }
        await closeServer();
        return;
      }

      if (code == null || code.isEmpty) {
        await _writeCallbackPage(
          request,
          HttpStatus.badRequest,
          'ChatGPT sign-in failed: missing code.',
        );
        if (!completer.isCompleted) {
          completer.completeError(
            const CodexOAuthException('Missing OAuth code.'),
          );
        }
        await closeServer();
        return;
      }

      try {
        final credentials = await exchangeAuthorizationCode(
          code: code,
          codeVerifier: verifier,
          codeChallenge: codeChallenge,
        );
        await saveCredentials(credentials);
        await _writeCallbackPage(
          request,
          HttpStatus.ok,
          'ChatGPT sign-in complete. You can close this tab.',
        );
        if (!completer.isCompleted) completer.complete(credentials);
      } catch (error, stackTrace) {
        await _writeCallbackPage(
          request,
          HttpStatus.badGateway,
          'ChatGPT sign-in failed during token exchange.',
        );
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      } finally {
        await closeServer();
      }
    });

    if (openBrowser) {
      unawaited(_openAuthorizationUrl(authorizationUri.toString()));
    }

    return CodexOAuthFlow(
      authorizationUrl: authorizationUri.toString(),
      completion: completer.future,
      cancelAction: () async {
        if (!completer.isCompleted) {
          completer.completeError(
            const CodexOAuthException('ChatGPT sign-in cancelled.'),
          );
        }
        await closeServer();
      },
    );
  }

  /// Opens [authorizationUrl] in the user's default browser. Overridable via
  /// the constructor for tests; defaults to `url_launcher`.
  Future<void> _openAuthorizationUrl(String authorizationUrl) =>
      _openUrl(authorizationUrl);

  // ── Manual paste-the-redirect-URL login ────────────────────────────────

  /// Starts a login without binding a loopback server. The caller shows
  /// [CodexManualLoginSession.authorizationUrl]; after authorizing, the user
  /// pastes the redirect URL (or bare code) into [completeManualLogin].
  Future<CodexManualLoginSession> startManualLogin() async {
    final verifier = generateCodeVerifier();
    final state = generateState();
    final codeChallenge = codeChallengeForVerifier(verifier);
    final authorizationUri = buildAuthorizationUri(
      codeChallenge: codeChallenge,
      state: state,
    );
    return CodexManualLoginSession(
      authorizationUrl: authorizationUri.toString(),
      state: state,
      codeVerifier: verifier,
      codeChallenge: codeChallenge,
      createdAt: _now(),
    );
  }

  /// Completes a manual login. Accepts a full redirect URL (query or
  /// fragment), a `code#state` pair, or a bare authorization code.
  Future<CodexCredentials> completeManualLogin(
    CodexManualLoginSession session,
    String pastedInput,
  ) async {
    final parsed = _parseManualLoginInput(pastedInput);
    if (parsed.code.isEmpty) {
      throw const CodexOAuthException(
        'The pasted input did not contain an authorization code.',
      );
    }
    final returnedState = parsed.state;
    if (returnedState != null && returnedState != session.state) {
      throw StateError(
        'Codex OAuth state mismatch during manual sign-in: expected '
        '"${session.state}", received "$returnedState".',
      );
    }
    final credentials = await exchangeAuthorizationCode(
      code: parsed.code,
      codeVerifier: session.codeVerifier,
      codeChallenge: session.codeChallenge,
    );
    await saveCredentials(credentials);
    return credentials;
  }

  static ({String code, String? state}) _parseManualLoginInput(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return (code: '', state: null);

    final uri = Uri.tryParse(trimmed);
    if (uri != null) {
      final query = uri.queryParameters;
      final fragment = _parseQueryMap(uri.fragment);
      final code = _firstNonEmpty([query['code'], fragment['code']]);
      if (code != null) {
        return (
          code: code,
          state: _firstNonEmpty([query['state'], fragment['state']]),
        );
      }
    }

    // OpenClaw-style "code#state" (no key=value pairs anywhere).
    final hashIndex = trimmed.indexOf('#');
    if (hashIndex > 0 && !trimmed.contains('=')) {
      final left = trimmed.substring(0, hashIndex).trim();
      final right = trimmed.substring(hashIndex + 1).trim();
      if (left.isNotEmpty) {
        return (code: left, state: right.isEmpty ? null : right);
      }
    }

    return (code: trimmed, state: null);
  }

  static Map<String, String> _parseQueryMap(String value) {
    if (value.isEmpty) return const <String, String>{};
    return Uri.splitQueryString(value);
  }

  static String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  // ── Device-code login (codex login --device-auth) ──────────────────────

  /// Starts a bespoke Codex device-code login. `POST {client_id}` to the
  /// usercode endpoint; a `404` maps to [CodexDeviceLoginUnavailableException]
  /// so callers can fall back to loopback login.
  Future<CodexDeviceCodeSession> startDeviceCodeLogin() async {
    final response = await _client.post(
      Uri.parse(deviceAuthUsercodeEndpoint),
      headers: const <String, String>{
        HttpHeaders.contentTypeHeader: 'application/json',
        HttpHeaders.acceptHeader: 'application/json',
      },
      body: jsonEncode(const <String, String>{'client_id': clientId}),
    );
    if (response.statusCode == HttpStatus.notFound) {
      throw const CodexDeviceLoginUnavailableException();
    }
    if (response.statusCode < HttpStatus.ok ||
        response.statusCode >= HttpStatus.multipleChoices) {
      throw CodexOAuthException(
        'Codex device-code login request failed with HTTP '
        '${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }
    final decoded = _decodeJson(response.body);
    if (decoded is! Map) {
      throw const CodexOAuthException(
        'Codex device-code login response was not a JSON object.',
      );
    }
    final json = Map<String, dynamic>.from(decoded);
    final deviceAuthId =
        (json['device_auth_id'] ?? json['deviceAuthId'])?.toString() ?? '';
    final userCode =
        (json['user_code'] ?? json['usercode'] ?? json['userCode'])
            ?.toString() ??
        '';
    if (deviceAuthId.isEmpty || userCode.isEmpty) {
      throw const CodexOAuthException(
        'Codex device-code login response is missing required fields.',
      );
    }
    return CodexDeviceCodeSession(
      deviceAuthId: deviceAuthId,
      userCode: userCode,
      verificationUrl: deviceAuthVerificationUrl,
      pollInterval: Duration(seconds: _asIntSeconds(json['interval']) ?? 5),
      expiresAt: _now().add(deviceAuthSessionLifetime),
    );
  }

  /// Polls the token endpoint until the user authorizes the device session.
  ///
  /// `403`/`404` mean "not authorized yet" and polling continues. A success
  /// response carries the server-generated PKCE triplet, exchanged with the
  /// *returned* code verifier (never a locally generated one).
  Future<CodexCredentials> completeDeviceCodeLogin(
    CodexDeviceCodeSession session,
  ) async {
    while (_now().isBefore(session.expiresAt)) {
      final response = await _client.post(
        Uri.parse(deviceAuthTokenPollEndpoint),
        headers: const <String, String>{
          HttpHeaders.contentTypeHeader: 'application/json',
          HttpHeaders.acceptHeader: 'application/json',
        },
        body: jsonEncode(<String, String>{
          'device_auth_id': session.deviceAuthId,
          'user_code': session.userCode,
        }),
      );

      if (response.statusCode == HttpStatus.forbidden ||
          response.statusCode == HttpStatus.notFound) {
        await Future<void>.delayed(session.pollInterval);
        continue;
      }

      final is2xx =
          response.statusCode >= HttpStatus.ok &&
          response.statusCode < HttpStatus.multipleChoices;
      if (is2xx) {
        final decoded = _decodeJson(response.body);
        if (decoded is! Map) {
          throw const CodexOAuthException(
            'Codex device-code token response was not a JSON object.',
          );
        }
        final json = Map<String, dynamic>.from(decoded);
        final authorizationCode =
            (json['authorization_code'] ?? json['authorizationCode'])
                ?.toString() ??
            '';
        final codeVerifier =
            (json['code_verifier'] ?? json['codeVerifier'])?.toString() ?? '';
        if (authorizationCode.isEmpty || codeVerifier.isEmpty) {
          throw const CodexOAuthException(
            'Codex device-code login completed but the response was missing '
            'the authorization code or code verifier.',
          );
        }
        final codeChallenge = (json['code_challenge'] ?? json['codeChallenge'])
            ?.toString();
        final credentials = await exchangeAuthorizationCode(
          code: authorizationCode,
          codeVerifier: codeVerifier,
          codeChallenge: codeChallenge,
          redirectUriOverride: deviceAuthCallbackRedirectUri,
        );
        await saveCredentials(credentials);
        return credentials;
      }

      throw CodexOAuthException(
        'Codex device-code login failed with HTTP ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }
    throw TimeoutException(
      'Codex device-code login timed out before the user completed '
      'authentication.',
      session.expiresAt.difference(_now()),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  static dynamic _decodeJson(String body) {
    try {
      return jsonDecode(body);
    } catch (_) {
      return body;
    }
  }

  static int? _asIntSeconds(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString());
  }

  static Future<void> _writeCallbackPage(
    HttpRequest request,
    int statusCode,
    String message,
  ) async {
    request.response
      ..statusCode = statusCode
      ..headers.contentType = ContentType.html
      ..write(
        '<!doctype html><html><body><p>'
        '${const HtmlEscape().convert(message)}'
        '</p></body></html>',
      );
    await request.response.close();
  }
}

/// Internal carrier for non-2xx token-endpoint responses so the refresh path
/// can inspect the decoded error body (e.g. `invalid_grant`).
class _CodexTokenHttpError implements Exception {
  const _CodexTokenHttpError(this.statusCode, this.decoded);

  final int statusCode;
  final dynamic decoded;
}
