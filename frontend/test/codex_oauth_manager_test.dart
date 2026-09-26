import 'dart:convert';
import 'dart:io';

import 'package:beeamvo/services/codex_oauth_manager.dart';
import 'package:beeamvo/services/secure_credential_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

String _jwt(Map<String, dynamic> claims) {
  String segment(Object? value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${segment(const {'alg': 'none'})}.${segment(claims)}.sig';
}

int _expSeconds(int fromNowSeconds) =>
    DateTime.now().toUtc().millisecondsSinceEpoch ~/ 1000 + fromNowSeconds;

CodexCredentials _credentials({
  String accessToken = 'at',
  String refreshToken = 'rt',
  DateTime? expiresAt,
  String? accountId,
  DateTime? updatedAt,
}) {
  final now = DateTime.now().toUtc();
  return CodexCredentials(
    accessToken: accessToken,
    refreshToken: refreshToken,
    expiresAt: expiresAt ?? now.add(const Duration(hours: 1)),
    accountId: accountId,
    createdAt: now,
    updatedAt: updatedAt ?? now,
  );
}

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

void main() {
  late Directory codexDir;
  setUp(() async {
    codexDir = await Directory.systemTemp.createTemp('beeamvo-codex-');
  });
  tearDown(() async {
    if (codexDir.existsSync()) await codexDir.delete(recursive: true);
  });

  CodexOAuthManager manager({
    SecureCredentialStore? store,
    http.Client? client,
    bool cliImportDisabled = false,
  }) {
    return CodexOAuthManager(
      credentialStore: store ?? InMemorySecureCredentialStore(),
      client: client ?? MockClient((_) async => http.Response('{}', 500)),
      codexDirOverride: codexDir.path,
      isCliImportDisabled: () => cliImportDisabled,
      openUrl: (_) async => fail('browser must not open in tests'),
    );
  }

  Future<void> writeCliAuth(Map<String, dynamic> json) async {
    await File(
      '${codexDir.path}${Platform.pathSeparator}auth.json',
    ).writeAsString(jsonEncode(json));
  }

  group('PKCE helpers', () {
    test('verifier uses the RFC 7636 alphabet at the requested length', () {
      final verifier = CodexOAuthManager.generateCodeVerifier();
      expect(verifier.length, 64);
      expect(verifier, matches(RegExp(r'^[A-Za-z0-9\-._~]+$')));
      expect(CodexOAuthManager.generateCodeVerifier(), isNot(equals(verifier)));
    });

    test('challenge matches the RFC 7636 appendix B test vector', () {
      expect(
        CodexOAuthManager.codeChallengeForVerifier(
          'dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk',
        ),
        'E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM',
      );
    });

    test('authorization URI carries the Codex OAuth parameters', () {
      final uri = CodexOAuthManager.buildAuthorizationUri(
        codeChallenge: 'challenge',
        state: 'state-1',
      );
      expect(uri.host, 'auth.openai.com');
      expect(uri.path, '/oauth/authorize');
      final query = uri.queryParameters;
      expect(query['response_type'], 'code');
      expect(query['client_id'], CodexOAuthManager.clientId);
      expect(query['redirect_uri'], CodexOAuthManager.redirectUri);
      expect(query['code_challenge'], 'challenge');
      expect(query['code_challenge_method'], 'S256');
      expect(query['state'], 'state-1');
      expect(query['scope'], contains('offline_access'));
    });
  });

  group('JWT helpers', () {
    test('decodeJwtClaims round-trips claims and rejects garbage', () {
      final token = _jwt({'sub': 'u1', 'exp': _expSeconds(60)});
      expect(CodexOAuthManager.decodeJwtClaims(token)!['sub'], 'u1');
      expect(CodexOAuthManager.decodeJwtClaims('not.a.jwt'), isNull);
      expect(CodexOAuthManager.decodeJwtClaims('single'), isNull);
    });

    test('expiresAtFromJwt reads the exp claim', () {
      final exp = _expSeconds(120);
      final token = _jwt({'exp': exp});
      expect(
        CodexOAuthManager.expiresAtFromJwt(token),
        DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true),
      );
      expect(CodexOAuthManager.expiresAtFromJwt(_jwt({})), isNull);
    });

    test('extractAccountIdFromClaims covers direct and nested shapes', () {
      expect(
        CodexOAuthManager.extractAccountIdFromClaims({'account_id': 'a'}),
        'a',
      );
      expect(
        CodexOAuthManager.extractAccountIdFromClaims({
          'https://api.openai.com/auth': {'chatgpt_account_id': 'nested'},
        }),
        'nested',
      );
      expect(
        CodexOAuthManager.extractAccountIdFromClaims({
          'accounts': [
            {'id': 'acc-1'},
          ],
        }),
        'acc-1',
      );
      expect(CodexOAuthManager.extractAccountIdFromClaims(const {}), isNull);
    });

    test('parseDateTime accepts ISO strings, seconds, and millis', () {
      expect(
        CodexOAuthManager.parseDateTime('2025-01-01T00:00:00Z'),
        DateTime.utc(2025),
      );
      expect(CodexOAuthManager.parseDateTime(1735689600), DateTime.utc(2025));
      expect(
        CodexOAuthManager.parseDateTime(1735689600000),
        DateTime.utc(2025),
      );
      expect(CodexOAuthManager.parseDateTime('bogus'), isNull);
      expect(CodexOAuthManager.parseDateTime(null), isNull);
    });
  });

  group('CodexCredentials.fromJson', () {
    test('parses the native shape', () {
      final credentials = CodexCredentials.fromJson(
        _credentials(accessToken: 'a1', refreshToken: 'r1').toJson(),
      );
      expect(credentials!.accessToken, 'a1');
      expect(credentials.refreshToken, 'r1');
    });

    test('parses the Codex CLI nested auth.json shape', () {
      final credentials = CodexCredentials.fromJson({
        'tokens': {
          'access_token': _jwt({
            'exp': _expSeconds(3600),
            'https://api.openai.com/auth': {'chatgpt_account_id': 'acct-9'},
          }),
          'refresh_token': 'cli-rt',
        },
        'last_refresh': '2025-06-01T00:00:00Z',
      });
      expect(credentials, isNotNull);
      expect(credentials!.refreshToken, 'cli-rt');
      expect(credentials.accountId, 'acct-9');
      expect(credentials.expiresAt.isAfter(DateTime.now().toUtc()), isTrue);
    });

    test('returns null without both tokens', () {
      expect(CodexCredentials.fromJson(const {}), isNull);
      expect(CodexCredentials.fromJson(const {'access_token': 'x'}), isNull);
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

    test(
      'a CLI auth.json is imported and persisted when none stored',
      () async {
        await writeCliAuth({
          'tokens': {
            'access_token': _jwt({'exp': _expSeconds(3600)}),
            'refresh_token': 'cli-rt',
          },
          'last_refresh': '2025-06-01T00:00:00Z',
        });
        final store = InMemorySecureCredentialStore();
        final m = manager(store: store);
        final credentials = await m.loadCredentials();
        expect(credentials!.refreshToken, 'cli-rt');
        // The import is persisted so later reads don't depend on the CLI file.
        expect(
          await store.readApiKey(CodexOAuthManager.credentialsAccount),
          isNotNull,
        );
      },
    );

    test('import-disabled flag keeps the CLI file ignored', () async {
      await writeCliAuth({
        'tokens': {
          'access_token': _jwt({'exp': _expSeconds(3600)}),
          'refresh_token': 'cli-rt',
        },
      });
      final m = manager(cliImportDisabled: true);
      expect(await m.loadCredentials(), isNull);
    });

    test(
      'a strictly newer CLI credential set replaces a stale stored one',
      () async {
        await writeCliAuth({
          'tokens': {
            'access_token': _jwt({'exp': _expSeconds(3600)}),
            'refresh_token': 'cli-newer',
          },
          'last_refresh': DateTime.now()
              .toUtc()
              .add(const Duration(minutes: 10))
              .toIso8601String(),
        });
        final store = InMemorySecureCredentialStore();
        final m = manager(store: store);
        await m.saveCredentials(
          _credentials(accessToken: 'old-at', refreshToken: 'old-rt'),
        );
        final credentials = await m.loadCredentials();
        expect(credentials!.refreshToken, 'cli-newer');
      },
    );

    test('signOut deletes credentials and disables future imports', () async {
      var disabled = false;
      final store = InMemorySecureCredentialStore();
      final m = CodexOAuthManager(
        credentialStore: store,
        client: MockClient((_) async => http.Response('{}', 500)),
        codexDirOverride: codexDir.path,
        isCliImportDisabled: () => disabled,
        setCliImportDisabled: (value) async {
          disabled = value;
        },
      );
      await m.saveCredentials(_credentials());
      await m.signOut();
      expect(
        await store.readApiKey(CodexOAuthManager.credentialsAccount),
        isNull,
      );
      expect(disabled, isTrue);

      await writeCliAuth({
        'tokens': {
          'access_token': _jwt({'exp': _expSeconds(3600)}),
          'refresh_token': 'cli-rt',
        },
      });
      expect(await m.loadCredentials(), isNull);
    });
  });

  group('token endpoint', () {
    test(
      'exchangeAuthorizationCode sends a JSON authorization_code grant',
      () async {
        final bodies = <Map<String, dynamic>>[];
        final m = manager(
          client: MockClient((request) async {
            expect(request.url.toString(), CodexOAuthManager.tokenEndpoint);
            bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response(jsonEncode(_tokenResponse()), 200);
          }),
        );
        final credentials = await m.exchangeAuthorizationCode(
          code: 'the-code',
          codeVerifier: 'the-verifier',
          codeChallenge: 'the-challenge',
        );
        expect(credentials.accessToken, 'at-new');
        final body = bodies.single;
        expect(body['grant_type'], 'authorization_code');
        expect(body['code'], 'the-code');
        expect(body['code_verifier'], 'the-verifier');
        expect(body['code_challenge'], 'the-challenge');
        expect(body['redirect_uri'], CodexOAuthManager.redirectUri);
        expect(body['client_id'], CodexOAuthManager.clientId);
      },
    );

    test('getAccessToken returns fresh tokens without a refresh', () async {
      var tokenCalls = 0;
      final m = manager(
        client: MockClient((_) async {
          tokenCalls++;
          return http.Response(jsonEncode(_tokenResponse()), 200);
        }),
      );
      await m.saveCredentials(_credentials(accessToken: 'good'));
      expect(await m.getAccessToken(), 'good');
      expect(tokenCalls, 0);
    });

    test('getAccessToken refreshes credentials inside the buffer', () async {
      final bodies = <Map<String, dynamic>>[];
      final m = manager(
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(jsonEncode(_tokenResponse()), 200);
        }),
      );
      await m.saveCredentials(
        _credentials(
          accessToken: 'stale',
          refreshToken: 'rt-1',
          expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 1)),
        ),
      );
      expect(await m.getAccessToken(), 'at-new');
      expect(bodies.single['grant_type'], 'refresh_token');
      expect(bodies.single['refresh_token'], 'rt-1');
    });

    test('getAccessToken without credentials requires sign-in', () async {
      await expectLater(
        manager().getAccessToken(),
        throwsA(isA<CodexSignInRequiredException>()),
      );
    });

    test('concurrent refreshes share one token request', () async {
      var tokenCalls = 0;
      final m = manager(
        client: MockClient((_) async {
          tokenCalls++;
          return http.Response(jsonEncode(_tokenResponse()), 200);
        }),
      );
      final stale = _credentials(
        expiresAt: DateTime.now().toUtc().subtract(const Duration(hours: 1)),
      );
      final results = await Future.wait([
        m.refreshCredentials(stale),
        m.refreshCredentials(stale),
      ]);
      expect(tokenCalls, 1);
      expect(results[0].accessToken, results[1].accessToken);
    });

    test(
      'a rejected refresh re-imports fresher CLI credentials once',
      () async {
        final store = InMemorySecureCredentialStore();
        final stale = _credentials(refreshToken: 'rt-rejected');
        await store.writeApiKey(
          CodexOAuthManager.credentialsAccount,
          jsonEncode(stale.toJson()),
        );
        await writeCliAuth({
          'tokens': {
            'access_token': _jwt({
              'exp': _expSeconds(3600),
              'https://api.openai.com/auth': {'chatgpt_account_id': 'acct-cli'},
            }),
            'refresh_token': 'rt-rotated',
          },
          'last_refresh': DateTime.now().toUtc().toIso8601String(),
        });
        final m = manager(
          store: store,
          client: MockClient(
            (_) async =>
                http.Response(jsonEncode({'error': 'invalid_grant'}), 400),
          ),
        );
        final refreshed = await m.refreshCredentials(stale);
        expect(refreshed.refreshToken, 'rt-rotated');
        expect(refreshed.accountId, 'acct-cli');
      },
    );

    test(
      'a rejected refresh without a fresher import requires sign-in',
      () async {
        final store = InMemorySecureCredentialStore();
        final stale = _credentials(refreshToken: 'rt-rejected');
        await store.writeApiKey(
          CodexOAuthManager.credentialsAccount,
          jsonEncode(stale.toJson()),
        );
        final m = manager(
          store: store,
          client: MockClient(
            (_) async =>
                http.Response(jsonEncode({'error': 'invalid_grant'}), 400),
          ),
        );
        await expectLater(
          m.refreshCredentials(stale),
          throwsA(isA<CodexSignInRequiredException>()),
        );
        expect(
          await store.readApiKey(CodexOAuthManager.credentialsAccount),
          isNull,
        );
      },
    );
  });

  group('manual login', () {
    test('accepts a full redirect URL, code#state, or a bare code', () async {
      final bodies = <Map<String, dynamic>>[];
      final m = manager(
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(jsonEncode(_tokenResponse()), 200);
        }),
      );
      final session = await m.startManualLogin();

      await m.completeManualLogin(
        session,
        'http://localhost:1455/auth/callback?code=c1&state=${session.state}',
      );
      await m.completeManualLogin(session, 'c2#${session.state}');
      await m.completeManualLogin(session, 'c3');

      expect(bodies.map((b) => b['code']), ['c1', 'c2', 'c3']);
      for (final body in bodies) {
        expect(body['code_verifier'], session.codeVerifier);
      }
    });

    test(
      'rejects a mismatched state before hitting the token endpoint',
      () async {
        var tokenCalls = 0;
        final m = manager(
          client: MockClient((_) async {
            tokenCalls++;
            return http.Response(jsonEncode(_tokenResponse()), 200);
          }),
        );
        final session = await m.startManualLogin();
        await expectLater(
          m.completeManualLogin(
            session,
            'http://localhost:1455/auth/callback?code=c&state=wrong',
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
        throwsA(isA<CodexOAuthException>()),
      );
    });
  });

  group('loopback login', () {
    test('callback completes the flow and persists credentials', () async {
      final bodies = <Map<String, dynamic>>[];
      final store = InMemorySecureCredentialStore();
      final m = manager(
        store: store,
        client: MockClient((request) async {
          bodies.add(jsonDecode(request.body) as Map<String, dynamic>);
          return http.Response(jsonEncode(_tokenResponse()), 200);
        }),
      );
      final flow = await m.startLogin(openBrowser: false);
      final state = Uri.parse(flow.authorizationUrl).queryParameters['state']!;

      final response = await http.get(
        Uri.parse(
          '${CodexOAuthManager.redirectUri}?code=loop-code&state=$state',
        ),
      );
      expect(response.statusCode, HttpStatus.ok);

      final credentials = await flow.completion;
      expect(credentials.accessToken, 'at-new');
      expect(bodies.single['code'], 'loop-code');
      expect(
        await store.readApiKey(CodexOAuthManager.credentialsAccount),
        isNotNull,
      );
    });

    test('a state mismatch fails the flow', () async {
      final m = manager();
      final flow = await m.startLogin(openBrowser: false);
      final expectation = expectLater(
        flow.completion,
        throwsA(
          isA<CodexOAuthException>().having(
            (e) => e.message,
            'message',
            contains('state'),
          ),
        ),
      );
      final response = await http.get(
        Uri.parse(
          '${CodexOAuthManager.redirectUri}?code=x&state=not-the-state',
        ),
      );
      expect(response.statusCode, HttpStatus.badRequest);
      await expectation;
    });
  });

  group('device-code login', () {
    test('404 maps to CodexDeviceLoginUnavailableException', () async {
      final m = manager(
        client: MockClient((_) async => http.Response('{}', 404)),
      );
      await expectLater(
        m.startDeviceCodeLogin(),
        throwsA(isA<CodexDeviceLoginUnavailableException>()),
      );
    });

    test(
      'polls until authorized, then exchanges the server verifier',
      () async {
        var polls = 0;
        final tokenBodies = <Map<String, dynamic>>[];
        final m = manager(
          client: MockClient((request) async {
            final url = request.url.toString();
            if (url == CodexOAuthManager.deviceAuthUsercodeEndpoint) {
              return http.Response(
                jsonEncode({
                  'device_auth_id': 'dev-1',
                  'user_code': 'CODE-1',
                  'interval': 0,
                }),
                200,
              );
            }
            if (url == CodexOAuthManager.deviceAuthTokenPollEndpoint) {
              polls++;
              if (polls == 1) return http.Response('{}', 403);
              return http.Response(
                jsonEncode({
                  'authorization_code': 'dev-code',
                  'code_verifier': 'server-verifier',
                }),
                200,
              );
            }
            tokenBodies.add(jsonDecode(request.body) as Map<String, dynamic>);
            return http.Response(jsonEncode(_tokenResponse()), 200);
          }),
        );

        final session = await m.startDeviceCodeLogin();
        expect(session.userCode, 'CODE-1');
        expect(session.deviceAuthId, 'dev-1');

        final credentials = await m.completeDeviceCodeLogin(session);
        expect(credentials.accessToken, 'at-new');
        expect(polls, 2);
        // The exchange uses the server-issued verifier and the device callback
        // redirect URI — never a locally generated PKCE pair.
        expect(tokenBodies.single['code_verifier'], 'server-verifier');
        expect(
          tokenBodies.single['redirect_uri'],
          CodexOAuthManager.deviceAuthCallbackRedirectUri,
        );
      },
    );
  });
}
