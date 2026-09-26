import 'dart:convert';
import 'dart:io';

import 'package:beeamvo/services/secure_credential_store.dart';
import 'package:beeamvo/services/xai_oauth_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _jwt(Map<String, dynamic> claims) {
  String segment(Object? value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${segment(const {'alg': 'none'})}.${segment(claims)}.sig';
}

const _authorizationEndpoint = 'https://auth.x.ai/oauth2/authorize';
const _tokenEndpoint = 'https://auth.x.ai/oauth2/token';
const _deviceEndpoint = 'https://auth.x.ai/oauth2/device/code';

Map<String, dynamic> _discoveryDoc() => {
  'authorization_endpoint': _authorizationEndpoint,
  'token_endpoint': _tokenEndpoint,
  'device_authorization_endpoint': _deviceEndpoint,
};

Map<String, dynamic> _tokenResponse({
  String accessToken = 'at-new',
  String refreshToken = 'rt-new',
}) {
  return {
    'access_token': accessToken,
    'refresh_token': refreshToken,
    'expires_in': 3600,
  };
}

XAiCredentials _credentials({
  String accessToken = 'at',
  String refreshToken = 'rt',
  DateTime? expiresAt,
  String? accountId,
  String? tokenEndpoint,
}) {
  final now = DateTime.now().toUtc();
  return XAiCredentials(
    accessToken: accessToken,
    refreshToken: refreshToken,
    expiresAt: expiresAt ?? now.add(const Duration(hours: 1)),
    accountId: accountId,
    tokenEndpoint: tokenEndpoint,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  XAiOAuthManager manager({SecureCredentialStore? store, http.Client? client}) {
    return XAiOAuthManager(
      credentialStore: store ?? InMemorySecureCredentialStore(),
      client:
          client ??
          MockClient((request) async {
            if (request.method == 'GET' &&
                request.url.toString() == XAiOAuthManager.discoveryUrl) {
              return http.Response(jsonEncode(_discoveryDoc()), 200);
            }
            return http.Response('{}', 500);
          }),
      openUrl: (_) async => fail('browser must not open in tests'),
    );
  }

  /// MockClient that serves discovery plus a token response.
  http.Client discoveryAndTokenClient({
    List<Map<String, String>>? tokenBodies,
    http.Response Function(http.Request request)? onToken,
  }) {
    return MockClient((request) async {
      final url = request.url.toString();
      if (request.method == 'GET' && url == XAiOAuthManager.discoveryUrl) {
        return http.Response(jsonEncode(_discoveryDoc()), 200);
      }
      if (url == _tokenEndpoint) {
        tokenBodies?.add(request.bodyFields);
        if (onToken != null) return onToken(request);
        return http.Response(jsonEncode(_tokenResponse()), 200);
      }
      return http.Response('{}', 500);
    });
  }

  group('discovery', () {
    test('resolveEndpoints returns the discovered endpoints', () async {
      final endpoints = await manager().resolveEndpoints();
      expect(
        endpoints.authorizationEndpoint.toString(),
        _authorizationEndpoint,
      );
      expect(endpoints.tokenEndpoint.toString(), _tokenEndpoint);
    });

    test('discovery response is cached — one network call', () async {
      var discoveryCalls = 0;
      final m = manager(
        client: MockClient((request) async {
          if (request.url.toString() == XAiOAuthManager.discoveryUrl) {
            discoveryCalls++;
            return http.Response(jsonEncode(_discoveryDoc()), 200);
          }
          return http.Response('{}', 500);
        }),
      );
      await m.resolveEndpoints();
      await m.resolveEndpoints();
      expect(discoveryCalls, 1);
    });

    test(
      'a failed discovery clears the cache so the next call retries',
      () async {
        var discoveryCalls = 0;
        final m = manager(
          client: MockClient((request) async {
            if (request.url.toString() == XAiOAuthManager.discoveryUrl) {
              discoveryCalls++;
              if (discoveryCalls == 1) return http.Response('{}', 503);
              return http.Response(jsonEncode(_discoveryDoc()), 200);
            }
            return http.Response('{}', 500);
          }),
        );
        await expectLater(
          m.resolveEndpoints(),
          throwsA(isA<XAiOAuthException>()),
        );
        final endpoints = await m.resolveEndpoints();
        expect(endpoints.tokenEndpoint.toString(), _tokenEndpoint);
        expect(discoveryCalls, 2);
      },
    );

    test('an untrusted discovered host is rejected', () async {
      final m = manager(
        client: MockClient((request) async {
          return http.Response(
            jsonEncode({
              'authorization_endpoint': 'https://evil.example.com/auth',
              'token_endpoint': _tokenEndpoint,
            }),
            200,
          );
        }),
      );
      await expectLater(
        m.resolveEndpoints(),
        throwsA(
          isA<XAiOAuthException>().having(
            (e) => e.message,
            'message',
            contains('untrusted'),
          ),
        ),
      );
    });
  });

  group('authorization URL', () {
    test('carries PKCE, nonce, plan, and referrer parameters', () {
      final uri = XAiOAuthManager.buildAuthorizationUri(
        authorizationEndpoint: Uri.parse(_authorizationEndpoint),
        codeChallenge: 'challenge',
        state: 'state-1',
        nonce: 'nonce-1',
      );
      expect(uri.host, 'auth.x.ai');
      final query = uri.queryParameters;
      expect(query['response_type'], 'code');
      expect(query['client_id'], XAiOAuthManager.clientId);
      expect(query['redirect_uri'], XAiOAuthManager.redirectUri);
      expect(query['scope'], contains('offline_access'));
      expect(query['scope'], contains('grok-cli:access'));
      expect(query['state'], 'state-1');
      expect(query['nonce'], 'nonce-1');
      expect(query['code_challenge'], 'challenge');
      expect(query['code_challenge_method'], 'S256');
      expect(query['plan'], 'generic');
      expect(query['referrer'], 'beeamvo');
    });

    test('rejects an authorization endpoint outside x.ai', () {
      expect(
        () => XAiOAuthManager.buildAuthorizationUri(
          authorizationEndpoint: Uri.parse('https://evil.example.com/auth'),
          codeChallenge: 'c',
          state: 's',
          nonce: 'n',
        ),
        throwsA(isA<XAiOAuthException>()),
      );
    });

    test('PKCE challenge matches the RFC 7636 appendix B test vector', () {
      expect(
        XAiOAuthManager.codeChallengeForVerifier(
          'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
        ),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });
  });

  group('XAiCredentials', () {
    test('fromJson round-trips including the pinned token endpoint', () {
      final credentials = XAiCredentials.fromJson(
        _credentials(
          accessToken: 'a1',
          refreshToken: 'r1',
          accountId: 'me',
          tokenEndpoint: _tokenEndpoint,
        ).toJson(),
      );
      expect(credentials!.accessToken, 'a1');
      expect(credentials.refreshToken, 'r1');
      expect(credentials.accountId, 'me');
      expect(credentials.tokenEndpoint, _tokenEndpoint);
    });

    test('fromJson derives the account id from JWT claims', () {
      final credentials = XAiCredentials.fromJson({
        'access_token': _jwt({'email': 'user@x.ai'}),
        'refresh_token': 'r1',
      });
      expect(credentials!.accountId, 'user@x.ai');
    });

    test('returns null without both tokens', () {
      expect(XAiCredentials.fromJson(const {}), isNull);
      expect(XAiCredentials.fromJson(const {'access_token': 'x'}), isNull);
    });
  });

  group('credential persistence', () {
    test('loadCredentials returns null when nothing exists', () async {
      expect(await manager().loadCredentials(), isNull);
      expect((await manager().status()).isSignedIn, isFalse);
    });

    test('stored credentials load and report signed in', () async {
      final store = InMemorySecureCredentialStore();
      final m = manager(store: store);
      await m.saveCredentials(
        _credentials(accessToken: 'a', refreshToken: 'r', accountId: 'me'),
      );
      final credentials = await m.loadCredentials();
      expect(credentials!.accessToken, 'a');
      final status = await m.status();
      expect(status.isSignedIn, isTrue);
      expect(status.accountId, 'me');
    });

    test('signOut deletes credentials', () async {
      final store = InMemorySecureCredentialStore();
      final m = manager(store: store);
      await m.saveCredentials(_credentials());
      await m.signOut();
      expect(
        await store.readApiKey(XAiOAuthManager.credentialsAccount),
        isNull,
      );
    });
  });

  group('token endpoint', () {
    test('exchangeAuthorizationCode posts a form-encoded grant re-sending the '
        'code challenge and pins the discovered endpoint', () async {
      final bodies = <Map<String, String>>[];
      final contentTypes = <String?>[];
      final m = manager(
        client: MockClient((request) async {
          if (request.method == 'GET') {
            return http.Response(jsonEncode(_discoveryDoc()), 200);
          }
          contentTypes.add(request.headers['content-type']);
          bodies.add(request.bodyFields);
          return http.Response(jsonEncode(_tokenResponse()), 200);
        }),
      );
      final credentials = await m.exchangeAuthorizationCode(
        code: 'the-code',
        codeVerifier: 'the-verifier',
        codeChallenge: 'the-challenge',
      );
      expect(credentials.accessToken, 'at-new');
      expect(credentials.tokenEndpoint, _tokenEndpoint);
      final body = bodies.single;
      expect(body['grant_type'], 'authorization_code');
      expect(body['code'], 'the-code');
      expect(body['code_verifier'], 'the-verifier');
      expect(body['code_challenge'], 'the-challenge');
      expect(body['code_challenge_method'], 'S256');
      expect(body['redirect_uri'], XAiOAuthManager.redirectUri);
      expect(body['client_id'], XAiOAuthManager.clientId);
      expect(
        contentTypes.single,
        contains('application/x-www-form-urlencoded'),
      );
    });

    test('getAccessToken returns fresh tokens without a refresh', () async {
      var tokenCalls = 0;
      final m = manager(
        client: discoveryAndTokenClient(
          onToken: (_) {
            tokenCalls++;
            return http.Response(jsonEncode(_tokenResponse()), 200);
          },
        ),
      );
      await m.saveCredentials(_credentials(accessToken: 'good'));
      expect(await m.getAccessToken(), 'good');
      expect(tokenCalls, 0);
    });

    test('getAccessToken refreshes credentials inside the buffer', () async {
      final bodies = <Map<String, String>>[];
      final m = manager(client: discoveryAndTokenClient(tokenBodies: bodies));
      await m.saveCredentials(
        _credentials(
          accessToken: 'stale',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 1)),
          tokenEndpoint: _tokenEndpoint,
        ),
      );
      expect(await m.getAccessToken(), 'at-new');
      expect(bodies.single['grant_type'], 'refresh_token');
      expect(bodies.single['refresh_token'], 'rt-1');
    });

    test('refresh keeps the pinned token endpoint', () async {
      final urls = <String>[];
      final m = manager(
        client: MockClient((request) async {
          urls.add(request.url.toString());
          return http.Response(jsonEncode(_tokenResponse()), 200);
        }),
      );
      await m.saveCredentials(
        _credentials(
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
          tokenEndpoint: 'https://auth.x.ai/oauth2/token',
        ),
      );
      expect(await m.getAccessToken(), 'at-new');
      // Pinned endpoint — no discovery fetch needed.
      expect(urls, [_tokenEndpoint]);
      final credentials = await m.loadCredentials();
      expect(credentials!.tokenEndpoint, _tokenEndpoint);
    });

    test('getAccessToken without credentials requires sign-in', () async {
      await expectLater(
        manager().getAccessToken(),
        throwsA(isA<XAiSignInRequiredException>()),
      );
    });

    test('concurrent refreshes share one token request', () async {
      var tokenCalls = 0;
      final m = manager(
        client: discoveryAndTokenClient(
          onToken: (_) {
            tokenCalls++;
            return http.Response(jsonEncode(_tokenResponse()), 200);
          },
        ),
      );
      final stale = _credentials(
        expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
        tokenEndpoint: _tokenEndpoint,
      );
      final results = await Future.wait([
        m.refreshCredentials(stale),
        m.refreshCredentials(stale),
      ]);
      expect(tokenCalls, 1);
      expect(results[0].accessToken, results[1].accessToken);
    });

    test(
      'a rejected refresh clears credentials and requires sign-in',
      () async {
        final store = InMemorySecureCredentialStore();
        final m = manager(
          store: store,
          client: MockClient((request) async {
            if (request.method == 'GET') {
              return http.Response(jsonEncode(_discoveryDoc()), 200);
            }
            return http.Response(jsonEncode({'error': 'invalid_grant'}), 400);
          }),
        );
        await m.saveCredentials(
          _credentials(
            refreshToken: 'rt-rejected',
            expiresAt: DateTime.now().toUtc().subtract(
              const Duration(hours: 1),
            ),
            tokenEndpoint: _tokenEndpoint,
          ),
        );
        await expectLater(
          m.getAccessToken(),
          throwsA(isA<XAiSignInRequiredException>()),
        );
        expect(
          await store.readApiKey(XAiOAuthManager.credentialsAccount),
          isNull,
        );
      },
    );

    test(
      'a 403 refresh failure hints at the subscription requirement',
      () async {
        final m = manager(
          client: MockClient((request) async {
            if (request.method == 'GET') {
              return http.Response(jsonEncode(_discoveryDoc()), 200);
            }
            return http.Response('{}', 403);
          }),
        );
        await m.saveCredentials(
          _credentials(
            refreshToken: 'rt-1',
            expiresAt: DateTime.now().toUtc().subtract(
              const Duration(hours: 1),
            ),
            tokenEndpoint: _tokenEndpoint,
          ),
        );
        await expectLater(
          m.getAccessToken(),
          throwsA(
            isA<XAiOAuthException>().having(
              (e) => e.message,
              'message',
              contains('subscription'),
            ),
          ),
        );
      },
    );
  });

  group('manual login', () {
    test('accepts a full redirect URL, code#state, or a bare code', () async {
      final bodies = <Map<String, String>>[];
      final m = manager(client: discoveryAndTokenClient(tokenBodies: bodies));
      final session = await m.startManualLogin();

      await m.completeManualLogin(
        session,
        '${XAiOAuthManager.redirectUri}?code=c1&state=${session.state}',
      );
      await m.completeManualLogin(session, 'c2#${session.state}');
      await m.completeManualLogin(session, 'c3');

      expect(bodies.map((b) => b['code']), ['c1', 'c2', 'c3']);
      for (final body in bodies) {
        expect(body['code_verifier'], session.codeVerifier);
        expect(body['code_challenge'], session.codeChallenge);
      }
    });

    test(
      'rejects a mismatched state before hitting the token endpoint',
      () async {
        var tokenCalls = 0;
        final m = manager(
          client: discoveryAndTokenClient(
            onToken: (_) {
              tokenCalls++;
              return http.Response(jsonEncode(_tokenResponse()), 200);
            },
          ),
        );
        final session = await m.startManualLogin();
        await expectLater(
          m.completeManualLogin(
            session,
            '${XAiOAuthManager.redirectUri}?code=c&state=wrong',
          ),
          throwsA(isA<StateError>()),
        );
        expect(tokenCalls, 0);
      },
    );

    test('rejects empty input', () async {
      final m = manager();
      final session = await m.startManualLogin();
      await expectLater(
        m.completeManualLogin(session, '   '),
        throwsA(isA<XAiOAuthException>()),
      );
    });
  });

  group('loopback login', () {
    test('callback completes the flow and persists credentials', () async {
      final bodies = <Map<String, String>>[];
      final store = InMemorySecureCredentialStore();
      final m = manager(
        store: store,
        client: discoveryAndTokenClient(tokenBodies: bodies),
      );
      final flow = await m.startLogin(openBrowser: false);
      final state = Uri.parse(flow.authorizationUrl).queryParameters['state']!;

      final response = await http.get(
        Uri.parse('${XAiOAuthManager.redirectUri}?code=loop-code&state=$state'),
      );
      expect(response.statusCode, HttpStatus.ok);

      final credentials = await flow.completion;
      expect(credentials.accessToken, 'at-new');
      expect(bodies.single['code'], 'loop-code');
      expect(
        await store.readApiKey(XAiOAuthManager.credentialsAccount),
        isNotNull,
      );
    });

    test('a state mismatch fails the flow', () async {
      final m = manager();
      final flow = await m.startLogin(openBrowser: false);
      final expectation = expectLater(
        flow.completion,
        throwsA(
          isA<XAiOAuthException>().having(
            (e) => e.message,
            'message',
            contains('state'),
          ),
        ),
      );
      final response = await http.get(
        Uri.parse('${XAiOAuthManager.redirectUri}?code=x&state=not-the-state'),
      );
      expect(response.statusCode, HttpStatus.badRequest);
      await expectation;
    });
  });

  group('device-code login', () {
    test('polls per RFC 8628 and pins the discovered token endpoint', () async {
      var polls = 0;
      final store = InMemorySecureCredentialStore();
      final m = manager(
        store: store,
        client: MockClient((request) async {
          final url = request.url.toString();
          if (request.method == 'GET' && url == XAiOAuthManager.discoveryUrl) {
            return http.Response(jsonEncode(_discoveryDoc()), 200);
          }
          if (url == _deviceEndpoint) {
            expect(request.bodyFields['client_id'], XAiOAuthManager.clientId);
            expect(request.bodyFields['scope'], XAiOAuthManager.defaultScope);
            return http.Response(
              jsonEncode({
                'device_code': 'dev-1',
                'user_code': 'CODE-1',
                'verification_uri': 'https://x.ai/device',
                'interval': 0,
                'expires_in': 300,
              }),
              200,
            );
          }
          if (url == _tokenEndpoint) {
            polls++;
            expect(
              request.bodyFields['grant_type'],
              XAiOAuthManager.deviceCodeGrantType,
            );
            expect(request.bodyFields['device_code'], 'dev-1');
            if (polls == 1) {
              return http.Response(
                jsonEncode({'error': 'authorization_pending'}),
                400,
              );
            }
            return http.Response(jsonEncode(_tokenResponse()), 200);
          }
          return http.Response('{}', 500);
        }),
      );

      final session = await m.startDeviceCodeLogin();
      expect(session.userCode, 'CODE-1');
      expect(session.verificationUrl, 'https://x.ai/device');

      final credentials = await m.completeDeviceCodeLogin(session);
      expect(credentials.accessToken, 'at-new');
      expect(credentials.tokenEndpoint, _tokenEndpoint);
      expect(polls, 2);
      expect(
        await store.readApiKey(XAiOAuthManager.credentialsAccount),
        isNotNull,
      );
    });

    test(
      'falls back to the well-known endpoint when discovery omits it',
      () async {
        final m = manager(
          client: MockClient((request) async {
            final url = request.url.toString();
            if (request.method == 'GET' &&
                url == XAiOAuthManager.discoveryUrl) {
              return http.Response(
                jsonEncode({
                  'authorization_endpoint': _authorizationEndpoint,
                  'token_endpoint': _tokenEndpoint,
                }),
                200,
              );
            }
            if (url == XAiOAuthManager.fallbackDeviceAuthorizationEndpoint) {
              return http.Response(
                jsonEncode({
                  'device_code': 'dev-2',
                  'user_code': 'CODE-2',
                  'verification_uri': 'https://x.ai/device',
                }),
                200,
              );
            }
            return http.Response('{}', 500);
          }),
        );
        final session = await m.startDeviceCodeLogin();
        expect(session.deviceCode, 'dev-2');
      },
    );

    test('access_denied aborts the poll', () async {
      final m = manager(
        client: MockClient((request) async {
          final url = request.url.toString();
          if (request.method == 'GET') {
            return http.Response(jsonEncode(_discoveryDoc()), 200);
          }
          if (url == _deviceEndpoint) {
            return http.Response(
              jsonEncode({
                'device_code': 'dev-1',
                'user_code': 'CODE-1',
                'verification_uri': 'https://x.ai/device',
                'expires_in': 60,
              }),
              200,
            );
          }
          return http.Response(jsonEncode({'error': 'access_denied'}), 400);
        }),
      );
      final session = await m.startDeviceCodeLogin();
      await expectLater(
        m.completeDeviceCodeLogin(session),
        throwsA(
          isA<XAiOAuthException>().having(
            (e) => e.message,
            'message',
            contains('denied'),
          ),
        ),
      );
    });
  });
}
