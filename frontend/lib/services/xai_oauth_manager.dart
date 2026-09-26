import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import 'codex_oauth_manager.dart' show CodexOAuthManager;
import 'pinned_http_client.dart';
import 'secure_credential_store.dart';

/// Thrown when the user must (re-)sign-in with their xAI account before Grok
/// requests can run.
class XAiSignInRequiredException implements Exception {
  const XAiSignInRequiredException([this.message]);

  final String? message;

  @override
  String toString() =>
      message ?? 'xAI sign-in required. Sign in with xAI and try again.';
}

/// Generic xAI OAuth failure (discovery, token exchange, refresh, device
/// login).
class XAiOAuthException implements Exception {
  const XAiOAuthException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

/// OAuth credentials for the xAI Grok backend.
///
/// In addition to the standard OAuth fields this stores [tokenEndpoint]
/// (resolved via OIDC discovery on first sign-in) so future refreshes hit the
/// same realm even if discovery later changes.
class XAiCredentials {
  const XAiCredentials({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    this.idToken,
    this.tokenType = 'Bearer',
    this.accountId,
    this.tokenEndpoint,
    required this.createdAt,
    required this.updatedAt,
  });

  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final String? idToken;
  final String tokenType;
  final String? accountId;
  final String? tokenEndpoint;
  final DateTime createdAt;
  final DateTime updatedAt;

  bool expiresWithin(Duration buffer, DateTime now) =>
      !expiresAt.isAfter(now.add(buffer));

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'expiresAt': expiresAt.toUtc().toIso8601String(),
      if (idToken != null && idToken!.isNotEmpty) 'idToken': idToken,
      'tokenType': tokenType,
      if (accountId != null && accountId!.isNotEmpty) 'accountId': accountId,
      if (tokenEndpoint != null && tokenEndpoint!.isNotEmpty)
        'tokenEndpoint': tokenEndpoint,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
    };
  }

  static XAiCredentials? fromJson(Map<String, dynamic> json) {
    final accessToken =
        json['accessToken']?.toString() ??
        json['access_token']?.toString() ??
        '';
    final refreshToken =
        json['refreshToken']?.toString() ??
        json['refresh_token']?.toString() ??
        '';
    if (accessToken.isEmpty || refreshToken.isEmpty) return null;

    final now = DateTime.now().toUtc();
    return XAiCredentials(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt:
          CodexOAuthManager.parseDateTime(json['expiresAt']) ??
          CodexOAuthManager.parseDateTime(json['expires_at']) ??
          XAiOAuthManager.expiresAtFromJwt(accessToken) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      idToken: json['idToken']?.toString() ?? json['id_token']?.toString(),
      tokenType:
          json['tokenType']?.toString() ??
          json['token_type']?.toString() ??
          'Bearer',
      accountId:
          json['accountId']?.toString() ??
          json['account_id']?.toString() ??
          XAiOAuthManager.accountIdFromClaims(
            XAiOAuthManager.decodeJwtClaims(accessToken),
          ),
      tokenEndpoint:
          json['tokenEndpoint']?.toString() ??
          json['token_endpoint']?.toString(),
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

/// Snapshot of the current xAI sign-in state.
class XAiAuthStatus {
  const XAiAuthStatus({
    required this.isSignedIn,
    this.accountId,
    this.expiresAt,
  });

  final bool isSignedIn;
  final String? accountId;
  final DateTime? expiresAt;
}

/// Handle for an in-progress loopback OAuth login.
class XAiOAuthFlow {
  const XAiOAuthFlow({
    required this.authorizationUrl,
    required this.completion,
    required Future<void> Function() cancelAction,
  }) : _cancel = cancelAction;

  /// The authorization URL the user's browser was sent to.
  final String authorizationUrl;

  /// Resolves once the loopback callback has been exchanged for credentials.
  final Future<XAiCredentials> completion;

  final Future<void> Function() _cancel;

  Future<void> cancel() => _cancel();
}

/// In-progress "paste the redirect URL" login for environments where a
/// loopback callback cannot be received.
class XAiManualLoginSession {
  const XAiManualLoginSession({
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

/// State for an in-progress xAI device-code login (RFC 8628). The user visits
/// [verificationUrl] and enters [userCode]; polling completes via
/// [XAiOAuthManager.completeDeviceCodeLogin].
class XAiDeviceCodeSession {
  const XAiDeviceCodeSession({
    required this.deviceCode,
    required this.userCode,
    required this.verificationUrl,
    this.verificationUrlComplete,
    required this.pollInterval,
    required this.expiresAt,
  });

  /// The opaque device code exchanged with the token endpoint on each poll.
  final String deviceCode;

  /// The user-facing code entered at the verification page.
  final String userCode;

  /// The verification URI the user must visit (`verification_uri`).
  final String verificationUrl;

  /// Optional verification URI that already embeds [userCode]
  /// (`verification_uri_complete`), when the server provides one.
  final String? verificationUrlComplete;

  /// Minimum time between token polls.
  final Duration pollInterval;

  /// Absolute time after which polling must stop.
  final DateTime expiresAt;
}

/// OAuth manager for xAI Grok.
///
/// Adapted from the codgine `XAiOAuthManager`:
///
/// * Endpoints are resolved via OIDC discovery at
///   `https://auth.x.ai/.well-known/openid-configuration`; discovered hosts
///   must be `x.ai`/`*.x.ai` over https.
/// * The authorization request adds `nonce`, `plan=generic`, and `referrer`
///   parameters specific to the X Premium / SuperGrok subscription tiers.
/// * Loopback redirect + PKCE on `http://127.0.0.1:56121/callback`.
/// * Token requests are form-urlencoded, and the `code_challenge` is re-sent
///   on the authorization-code exchange.
/// * The discovered token endpoint is pinned onto the stored credentials so
///   refreshes keep hitting the same realm.
/// * Credentials persist in the OS secure store via [SecureCredentialStore].
class XAiOAuthManager {
  XAiOAuthManager({
    SecureCredentialStore? credentialStore,
    http.Client? client,
    DateTime Function()? now,
    Future<void> Function(String url)? openUrl,
  }) : _credentialStore =
           credentialStore ?? const FlutterSecureCredentialStore(),
       _client = client ?? createSecureHttpClient(),
       _now = now ?? (() => DateTime.now().toUtc()),
       _openUrl = openUrl ?? _defaultOpenUrl;

  // ── Static configuration ───────────────────────────────────────────────

  static const String credentialsAccount = 'xai_oauth_credentials';
  static const String clientId = 'b1a00492-073a-47ea-816f-4c329264a828';
  static const String issuer = 'https://auth.x.ai';
  static const String discoveryUrl =
      'https://auth.x.ai/.well-known/openid-configuration';
  static const String redirectUri = 'http://127.0.0.1:56121/callback';
  static const String defaultScope =
      'openid profile email offline_access grok-cli:access api:access';
  static const int callbackPort = 56121;
  static const String callbackPath = '/callback';
  static const Duration refreshBuffer = Duration(minutes: 5);

  /// The OAuth 2.0 device authorization grant type (RFC 8628).
  static const String deviceCodeGrantType =
      'urn:ietf:params:oauth:grant-type:device_code';

  /// Fallback device-authorization endpoint used when OIDC discovery omits
  /// `device_authorization_endpoint`.
  static const String fallbackDeviceAuthorizationEndpoint =
      'https://auth.x.ai/oauth2/device/code';

  final SecureCredentialStore _credentialStore;
  final http.Client _client;
  final DateTime Function() _now;
  final Future<void> Function(String url) _openUrl;

  Future<XAiCredentials>? _refreshFuture;
  Future<({Uri authorizationEndpoint, Uri tokenEndpoint})>? _endpointsFuture;

  DateTime currentTime() => _now();

  static Future<void> _defaultOpenUrl(String url) async {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  }

  // ── PKCE / JWT helpers (delegate to the shared implementations) ────────

  static String generateCodeVerifier({int length = 64}) =>
      CodexOAuthManager.generateCodeVerifier(length: length);

  static String codeChallengeForVerifier(String verifier) =>
      CodexOAuthManager.codeChallengeForVerifier(verifier);

  static String generateState({int byteLength = 32}) =>
      CodexOAuthManager.generateState(byteLength: byteLength);

  /// xAI's authorization request additionally requires an OIDC `nonce`.
  static String generateNonce({int byteLength = 32}) =>
      CodexOAuthManager.generateState(byteLength: byteLength);

  static Map<String, dynamic>? decodeJwtClaims(String token) =>
      CodexOAuthManager.decodeJwtClaims(token);

  static DateTime? expiresAtFromJwt(String token) =>
      CodexOAuthManager.expiresAtFromJwt(token);

  /// Extracts an xAI account id from JWT claims (`email`, `sub`,
  /// `account_id`).
  static String? accountIdFromClaims(Map<String, dynamic>? claims) {
    if (claims == null) return null;
    for (final key in const <String>['email', 'sub', 'account_id']) {
      final value = claims[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  /// xAI only accepts endpoints on `x.ai` / `*.x.ai` over https.
  static void ensureTrustedEndpoint(Uri uri) {
    final host = uri.host.toLowerCase();
    final trusted =
        uri.scheme == 'https' && (host == 'x.ai' || host.endsWith('.x.ai'));
    if (!trusted) {
      throw XAiOAuthException('Refusing untrusted xAI OAuth endpoint: $uri');
    }
  }

  /// Builds an xAI authorization URL from a discovered
  /// [authorizationEndpoint].
  static Uri buildAuthorizationUri({
    required Uri authorizationEndpoint,
    required String codeChallenge,
    required String state,
    required String nonce,
    String redirectUri = redirectUri,
    String scope = defaultScope,
    String referrer = 'beeamvo',
  }) {
    ensureTrustedEndpoint(authorizationEndpoint);
    return authorizationEndpoint.replace(
      queryParameters: <String, String>{
        'response_type': 'code',
        'client_id': clientId,
        'redirect_uri': redirectUri,
        'scope': scope,
        'state': state,
        'nonce': nonce,
        'code_challenge': codeChallenge,
        'code_challenge_method': 'S256',
        'plan': 'generic',
        'referrer': referrer,
      },
    );
  }

  // ── OIDC discovery ─────────────────────────────────────────────────────

  /// Resolves the authorization/token endpoints. Single-flight and
  /// self-healing: a transient failure clears the cache so the next call
  /// retries instead of disabling xAI OAuth for the whole process.
  Future<({Uri authorizationEndpoint, Uri tokenEndpoint})> resolveEndpoints() {
    final existing = _endpointsFuture;
    if (existing != null) return existing;

    final pending = _fetchEndpoints()
        .then((endpoints) {
          _endpointsFuture = Future.value(endpoints);
          return endpoints;
        })
        .catchError((Object error) {
          _endpointsFuture = null;
          throw error;
        });
    _endpointsFuture = pending;
    return pending;
  }

  Future<({Uri authorizationEndpoint, Uri tokenEndpoint})>
  _fetchEndpoints() async {
    final response = await _client.get(Uri.parse(discoveryUrl));
    if (response.statusCode >= HttpStatus.badRequest) {
      throw XAiOAuthException(
        'Failed to discover xAI OAuth endpoints: HTTP ${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }
    final decoded = _decodeJson(response.body);
    if (decoded is! Map) {
      throw const XAiOAuthException('Invalid xAI OAuth discovery response.');
    }
    final json = Map<String, dynamic>.from(decoded);
    final authorizationEndpoint = Uri.parse(
      json['authorization_endpoint']?.toString() ?? '',
    );
    final tokenEndpoint = Uri.parse(json['token_endpoint']?.toString() ?? '');
    ensureTrustedEndpoint(authorizationEndpoint);
    ensureTrustedEndpoint(tokenEndpoint);
    return (
      authorizationEndpoint: authorizationEndpoint,
      tokenEndpoint: tokenEndpoint,
    );
  }

  /// The token endpoint pinned on [credentials], or the discovered one.
  Future<Uri> tokenEndpointFor(XAiCredentials? credentials) async {
    final pinned = credentials?.tokenEndpoint?.trim();
    if (pinned != null && pinned.isNotEmpty) {
      final uri = Uri.parse(pinned);
      ensureTrustedEndpoint(uri);
      return uri;
    }
    return (await resolveEndpoints()).tokenEndpoint;
  }

  // ── Persistence ────────────────────────────────────────────────────────

  /// Loads stored credentials. Unlike Codex there is no external CLI auth
  /// file to import — Beeamvo's own secure store is the only source.
  Future<XAiCredentials?> loadCredentials() async {
    final raw = await _credentialStore.readApiKey(credentialsAccount);
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return XAiCredentials.fromJson(decoded);
      }
      if (decoded is Map) {
        return XAiCredentials.fromJson(Map<String, dynamic>.from(decoded));
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> saveCredentials(XAiCredentials credentials) async {
    await _credentialStore.writeApiKey(
      credentialsAccount,
      jsonEncode(credentials.toJson()),
    );
  }

  /// Removes the stored credentials.
  Future<void> signOut() async {
    await _credentialStore.deleteApiKey(credentialsAccount);
  }

  /// Current sign-in status without triggering a refresh.
  Future<XAiAuthStatus> status() async {
    final credentials = await loadCredentials();
    return XAiAuthStatus(
      isSignedIn: credentials != null,
      accountId: credentials?.accountId,
      expiresAt: credentials?.expiresAt,
    );
  }

  // ── Token exchange & refresh ───────────────────────────────────────────

  XAiCredentials _credentialsFromTokenResponse(
    Map<String, dynamic> response, {
    XAiCredentials? previous,
    required Uri tokenEndpoint,
  }) {
    final accessToken = response['access_token']?.toString() ?? '';
    final refreshToken =
        response['refresh_token']?.toString() ?? previous?.refreshToken ?? '';
    if (accessToken.isEmpty || refreshToken.isEmpty) {
      throw const XAiOAuthException(
        'xAI OAuth response did not include tokens.',
      );
    }

    final now = _now();
    final expiresIn = response['expires_in'];
    final expiresAt = expiresIn is num
        ? now.add(Duration(seconds: expiresIn.toInt()))
        : expiresAtFromJwt(accessToken) ?? now.add(const Duration(hours: 1));
    final idToken = response['id_token']?.toString();
    return XAiCredentials(
      accessToken: accessToken,
      refreshToken: refreshToken,
      expiresAt: expiresAt,
      idToken: idToken ?? previous?.idToken,
      tokenType: response['token_type']?.toString() ?? 'Bearer',
      accountId:
          accountIdFromClaims(decodeJwtClaims(idToken ?? accessToken)) ??
          previous?.accountId,
      tokenEndpoint: tokenEndpoint.toString(),
      createdAt: previous?.createdAt ?? now,
      updatedAt: now,
    );
  }

  /// Token requests are form-urlencoded (xAI's realm does not accept JSON).
  Future<Map<String, dynamic>> _postTokenRequest(
    Uri endpoint,
    Map<String, String> form,
  ) async {
    ensureTrustedEndpoint(endpoint);
    final response = await _client.post(
      endpoint,
      headers: const <String, String>{
        HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded',
        HttpHeaders.acceptHeader: 'application/json',
      },
      body: form,
    );
    final decoded = _decodeJson(response.body);
    if (response.statusCode >= HttpStatus.badRequest) {
      throw _XAiTokenHttpError(response.statusCode, decoded);
    }
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    throw XAiOAuthException(
      'xAI token response was not a JSON object.',
      statusCode: response.statusCode,
    );
  }

  /// Exchanges an authorization [code] for credentials. xAI requires the
  /// `code_challenge` to be re-sent alongside the `code_verifier`.
  Future<XAiCredentials> exchangeAuthorizationCode({
    required String code,
    required String codeVerifier,
    String? codeChallenge,
    Uri? tokenEndpointOverride,
  }) async {
    final endpoint =
        tokenEndpointOverride ?? (await resolveEndpoints()).tokenEndpoint;
    final form = <String, String>{
      'grant_type': 'authorization_code',
      'code': code,
      'redirect_uri': redirectUri,
      'client_id': clientId,
      'code_verifier': codeVerifier,
    };
    if (codeChallenge != null && codeChallenge.isNotEmpty) {
      form['code_challenge'] = codeChallenge;
      form['code_challenge_method'] = 'S256';
    }
    final response = await _postTokenRequest(endpoint, form);
    return _credentialsFromTokenResponse(response, tokenEndpoint: endpoint);
  }

  /// Returns a valid access token, refreshing when expiry is within
  /// [refreshBuffer].
  Future<String> getAccessToken() async {
    final credentials = await loadCredentials();
    if (credentials == null) {
      throw const XAiSignInRequiredException();
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
      throw const XAiSignInRequiredException();
    }
    return (await refreshCredentials(credentials)).accessToken;
  }

  /// De-duplicated refresh: concurrent callers share one in-flight future.
  Future<XAiCredentials> refreshCredentials(XAiCredentials credentials) async {
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

  Future<XAiCredentials> _performRefresh(XAiCredentials credentials) async {
    if (credentials.refreshToken.isEmpty) {
      await signOut();
      throw const XAiSignInRequiredException();
    }
    final endpoint = await tokenEndpointFor(credentials);
    Map<String, dynamic> response;
    try {
      response = await _postTokenRequest(endpoint, <String, String>{
        'grant_type': 'refresh_token',
        'client_id': clientId,
        'refresh_token': credentials.refreshToken,
      });
    } on _XAiTokenHttpError catch (error) {
      if (_isRefreshTokenRejection(error)) {
        await _clearCredentialsIfCurrent(credentials);
        throw const XAiSignInRequiredException(
          'xAI session expired. Sign in again.',
        );
      }
      if (error.statusCode == HttpStatus.forbidden) {
        throw XAiOAuthException(
          'xAI OAuth token was rejected. Check that the account has an '
          'eligible X Premium or SuperGrok subscription.',
          statusCode: error.statusCode,
        );
      }
      throw XAiOAuthException(
        'xAI token refresh failed with HTTP ${error.statusCode}.',
        statusCode: error.statusCode,
      );
    }
    final refreshed = _credentialsFromTokenResponse(
      response,
      previous: credentials,
      tokenEndpoint: endpoint,
    );
    await saveCredentials(refreshed);
    return refreshed;
  }

  bool _isRefreshTokenRejection(_XAiTokenHttpError error) {
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

  Future<void> _clearCredentialsIfCurrent(XAiCredentials attempted) async {
    final current = await loadCredentials();
    if (current != null && current.refreshToken != attempted.refreshToken) {
      return;
    }
    await _credentialStore.deleteApiKey(credentialsAccount);
  }

  // ── Loopback PKCE login ────────────────────────────────────────────────

  /// Starts a loopback OAuth login: resolves endpoints via discovery, binds
  /// a local HTTP server on [callbackPort], optionally opens the
  /// authorization URL in the browser, validates the callback, exchanges the
  /// code, and persists credentials.
  Future<XAiOAuthFlow> startLogin({bool openBrowser = true}) async {
    final endpoints = await resolveEndpoints();
    final verifier = generateCodeVerifier();
    final state = generateState();
    final nonce = generateNonce();
    final codeChallenge = codeChallengeForVerifier(verifier);
    final authorizationUri = buildAuthorizationUri(
      authorizationEndpoint: endpoints.authorizationEndpoint,
      codeChallenge: codeChallenge,
      state: state,
      nonce: nonce,
    );

    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      callbackPort,
    );
    final completer = Completer<XAiCredentials>();
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
          'xAI sign-in failed: invalid state.',
        );
        if (!completer.isCompleted) {
          completer.completeError(
            const XAiOAuthException('Invalid OAuth state.'),
          );
        }
        await closeServer();
        return;
      }

      if (error != null && error.isNotEmpty) {
        await _writeCallbackPage(
          request,
          HttpStatus.badRequest,
          'xAI sign-in failed.',
        );
        if (!completer.isCompleted) {
          completer.completeError(XAiOAuthException(error));
        }
        await closeServer();
        return;
      }

      if (code == null || code.isEmpty) {
        await _writeCallbackPage(
          request,
          HttpStatus.badRequest,
          'xAI sign-in failed: missing code.',
        );
        if (!completer.isCompleted) {
          completer.completeError(
            const XAiOAuthException('Missing OAuth code.'),
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
          tokenEndpointOverride: endpoints.tokenEndpoint,
        );
        await saveCredentials(credentials);
        await _writeCallbackPage(
          request,
          HttpStatus.ok,
          'xAI sign-in complete. You can close this tab.',
        );
        if (!completer.isCompleted) completer.complete(credentials);
      } catch (error, stackTrace) {
        await _writeCallbackPage(
          request,
          HttpStatus.badGateway,
          'xAI sign-in failed during token exchange.',
        );
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      } finally {
        await closeServer();
      }
    });

    if (openBrowser) {
      unawaited(_openUrl(authorizationUri.toString()));
    }

    return XAiOAuthFlow(
      authorizationUrl: authorizationUri.toString(),
      completion: completer.future,
      cancelAction: () async {
        if (!completer.isCompleted) {
          completer.completeError(
            const XAiOAuthException('xAI sign-in cancelled.'),
          );
        }
        await closeServer();
      },
    );
  }

  // ── Manual paste-the-redirect-URL login ────────────────────────────────

  /// Starts a login without binding a loopback server. The caller shows
  /// [XAiManualLoginSession.authorizationUrl]; after authorizing, the user
  /// pastes the redirect URL (or bare code) into [completeManualLogin].
  Future<XAiManualLoginSession> startManualLogin() async {
    final endpoints = await resolveEndpoints();
    final verifier = generateCodeVerifier();
    final state = generateState();
    final nonce = generateNonce();
    final codeChallenge = codeChallengeForVerifier(verifier);
    final authorizationUri = buildAuthorizationUri(
      authorizationEndpoint: endpoints.authorizationEndpoint,
      codeChallenge: codeChallenge,
      state: state,
      nonce: nonce,
    );
    return XAiManualLoginSession(
      authorizationUrl: authorizationUri.toString(),
      state: state,
      codeVerifier: verifier,
      codeChallenge: codeChallenge,
      createdAt: _now(),
    );
  }

  /// Completes a manual login. Accepts a full redirect URL (query or
  /// fragment), a `code#state` pair, or a bare authorization code.
  Future<XAiCredentials> completeManualLogin(
    XAiManualLoginSession session,
    String pastedInput,
  ) async {
    final parsed = _parseManualLoginInput(pastedInput);
    if (parsed.code.isEmpty) {
      throw const XAiOAuthException(
        'The pasted input did not contain an authorization code.',
      );
    }
    final returnedState = parsed.state;
    if (returnedState != null && returnedState != session.state) {
      throw StateError(
        'xAI OAuth state mismatch during manual sign-in: expected '
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

  // ── RFC 8628 device-code login ─────────────────────────────────────────

  /// Starts an RFC 8628 device-code login. Resolves the device-authorization
  /// endpoint from the xAI OIDC discovery document (falling back to
  /// [fallbackDeviceAuthorizationEndpoint] when the field is absent).
  Future<XAiDeviceCodeSession> startDeviceCodeLogin() async {
    final deviceAuthEndpoint = await _resolveDeviceAuthorizationEndpoint();
    final response = await _client.post(
      deviceAuthEndpoint,
      headers: const <String, String>{
        HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded',
        HttpHeaders.acceptHeader: 'application/json',
      },
      body: <String, String>{'client_id': clientId, 'scope': defaultScope},
    );
    if (response.statusCode < HttpStatus.ok ||
        response.statusCode >= HttpStatus.multipleChoices) {
      throw XAiOAuthException(
        'xAI device-code login request failed with HTTP '
        '${response.statusCode}.',
        statusCode: response.statusCode,
      );
    }
    final body = _decodeJson(response.body);
    if (body is! Map) {
      throw const XAiOAuthException('Invalid xAI device-code response.');
    }
    final json = Map<String, dynamic>.from(body);
    final deviceCode = json['device_code']?.toString() ?? '';
    final userCode = json['user_code']?.toString() ?? '';
    final verificationUri = json['verification_uri']?.toString() ?? '';
    if (deviceCode.isEmpty || userCode.isEmpty || verificationUri.isEmpty) {
      throw const XAiOAuthException(
        'xAI device-code response is missing required fields.',
      );
    }
    return XAiDeviceCodeSession(
      deviceCode: deviceCode,
      userCode: userCode,
      verificationUrl: verificationUri,
      verificationUrlComplete: json['verification_uri_complete']?.toString(),
      pollInterval: Duration(seconds: _asIntSeconds(json['interval']) ?? 5),
      expiresAt: _now().add(
        Duration(seconds: _asIntSeconds(json['expires_in']) ?? 300),
      ),
    );
  }

  /// Completes an RFC 8628 device-code login by polling the discovered token
  /// endpoint until the user authorizes, denies, or the session expires.
  ///
  /// `authorization_pending` waits [XAiDeviceCodeSession.pollInterval],
  /// `slow_down` increases the interval by 5 seconds,
  /// `access_denied`/`expired_token` abort, and a successful response pins
  /// the discovered token endpoint onto the stored credentials.
  Future<XAiCredentials> completeDeviceCodeLogin(
    XAiDeviceCodeSession session,
  ) async {
    final tokenEndpoint = (await resolveEndpoints()).tokenEndpoint;
    var pollInterval = session.pollInterval;
    while (_now().isBefore(session.expiresAt)) {
      final response = await _client.post(
        tokenEndpoint,
        headers: const <String, String>{
          HttpHeaders.contentTypeHeader: 'application/x-www-form-urlencoded',
          HttpHeaders.acceptHeader: 'application/json',
        },
        body: <String, String>{
          'grant_type': deviceCodeGrantType,
          'device_code': session.deviceCode,
          'client_id': clientId,
        },
      );

      final body = _decodeJson(response.body);
      final json = body is Map ? Map<String, dynamic>.from(body) : null;
      final error = json?['error']?.toString();
      final hasError = error != null && error.isNotEmpty;

      final is2xx =
          response.statusCode >= HttpStatus.ok &&
          response.statusCode < HttpStatus.multipleChoices;

      if (is2xx && !hasError) {
        if (json == null) {
          throw const XAiOAuthException(
            'xAI device-code token response was not a JSON object.',
          );
        }
        final credentials = _credentialsFromTokenResponse(
          json,
          tokenEndpoint: tokenEndpoint,
        );
        await saveCredentials(credentials);
        return credentials;
      }

      switch (error) {
        case 'authorization_pending':
          await Future<void>.delayed(pollInterval);
        case 'slow_down':
          pollInterval += const Duration(seconds: 5);
          await Future<void>.delayed(pollInterval);
        case 'access_denied':
          throw XAiOAuthException(
            'xAI device-code login was denied by the user.',
            statusCode: response.statusCode,
          );
        case 'expired_token':
          throw XAiOAuthException(
            'The xAI device-code login session expired.',
            statusCode: response.statusCode,
          );
        default:
          throw XAiOAuthException(
            json?['error_description']?.toString() ??
                'xAI device-code login failed with HTTP '
                    '${response.statusCode}.',
            statusCode: response.statusCode,
          );
      }
    }
    throw TimeoutException(
      'xAI device-code login timed out before the user completed '
      'authentication.',
      session.expiresAt.difference(_now()),
    );
  }

  /// Resolves `device_authorization_endpoint` from discovery; falls back to
  /// the well-known constant when discovery fails or omits it.
  Future<Uri> _resolveDeviceAuthorizationEndpoint() async {
    try {
      final response = await _client.get(Uri.parse(discoveryUrl));
      if (response.statusCode >= HttpStatus.ok &&
          response.statusCode < HttpStatus.multipleChoices) {
        final body = _decodeJson(response.body);
        if (body is Map) {
          final raw = body['device_authorization_endpoint']?.toString();
          if (raw != null && raw.isNotEmpty) {
            final uri = Uri.parse(raw);
            ensureTrustedEndpoint(uri);
            return uri;
          }
        }
      }
    } catch (_) {
      // Fall back to the well-known constant below.
    }
    return Uri.parse(fallbackDeviceAuthorizationEndpoint);
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  Future<void> _writeCallbackPage(
    HttpRequest request,
    int statusCode,
    String message,
  ) async {
    request.response.statusCode = statusCode;
    request.response.headers.contentType = ContentType.html;
    request.response.write(
      '<!doctype html><html><body><p>$message</p></body></html>',
    );
    await request.response.close();
  }

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
}

/// HTTP error from an xAI token request; [decoded] is the raw response body
/// (decoded JSON when possible) so rejection detection can inspect it.
class _XAiTokenHttpError implements Exception {
  const _XAiTokenHttpError(this.statusCode, this.decoded);

  final int statusCode;
  final dynamic decoded;
}
