// Logic-only unit tests for the certificate-pinning infrastructure.
//
// These tests exercise the PURE decision/hash functions only — no sockets, no
// TLS handshake, no `dart:io` HttpClient. The only "certificate" used is a fake
// PEM blob wrapping the bytes of "hello", whose SHA-256 is a well-known vector,
// so we can assert correctness independently of any real cert machinery.

import 'package:beeamvo/services/pinned_http_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // "hello" (5 bytes) wrapped as a fake leaf certificate. Its well-known
  // SHA-256 lets us verify the hash computation independently of the rest of
  // the logic.
  const helloPem =
      '-----BEGIN CERTIFICATE-----\naGVsbG8=\n-----END CERTIFICATE-----';
  const helloSha256 =
      '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';

  group('computeLeafPinHash', () {
    test('derives SHA-256 over the PEM body (well-known vector)', () {
      expect(computeLeafPinHash(helloPem), equals(helloSha256));
    });

    test('ignores PEM armor, blank lines, and CRLF line endings', () {
      const armored =
          '-----BEGIN CERTIFICATE-----\r\n\r\naGVsbG8=\r\n-----END '
          'CERTIFICATE-----\r\n';
      expect(computeLeafPinHash(armored), equals(helloSha256));
    });

    test('throws when the certificate body is empty', () {
      expect(
        () => computeLeafPinHash(
          '-----BEGIN CERTIFICATE-----\n-----END CERTIFICATE-----',
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  group('evaluateCertificatePin', () {
    test('(a) host with NO configured pins defers to the OS trust store', () {
      const config = PinnedHostConfig.empty;
      expect(
        evaluateCertificatePin(
          host: 'generativelanguage.googleapis.com',
          certPem: helloPem,
          config: config,
        ),
        equals(PinDecision.deferToSystem),
      );
    });

    test('(b) host with a matching pin accepts the certificate', () {
      const config = PinnedHostConfig({
        'generativelanguage.googleapis.com': <String>[helloSha256],
      });
      expect(
        evaluateCertificatePin(
          host: 'generativelanguage.googleapis.com',
          certPem: helloPem,
          config: config,
        ),
        equals(PinDecision.acceptPin),
      );
    });

    test('(c) host with a non-matching pin rejects the certificate', () {
      const config = PinnedHostConfig({
        'generativelanguage.googleapis.com': <String>[
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        ],
      });
      expect(
        evaluateCertificatePin(
          host: 'generativelanguage.googleapis.com',
          certPem: helloPem,
          config: config,
        ),
        equals(PinDecision.rejectPin),
      );
    });

    test('rejectPin also becomes acceptPin once a real match is configured', () {
      // Same wrong-pin config as (c), but now the real hash is present.
      const config = PinnedHostConfig({
        'generativelanguage.googleapis.com': <String>[
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
          helloSha256,
        ],
      });
      expect(
        evaluateCertificatePin(
          host: 'generativelanguage.googleapis.com',
          certPem: helloPem,
          config: config,
        ),
        equals(PinDecision.acceptPin),
      );
    });

    test('allow-list keys match by domain suffix on label boundaries', () {
      // A `googleapis.com` key must cover regional Vertex hosts too…
      const config = PinnedHostConfig({
        'googleapis.com': <String>[helloSha256],
      });
      expect(
        evaluateCertificatePin(
          host: 'us-central1-aiplatform.googleapis.com',
          certPem: helloPem,
          config: config,
        ),
        equals(PinDecision.acceptPin),
      );
      // …but must NOT match a host that merely contains the key as a substring
      // without a label boundary.
      expect(
        evaluateCertificatePin(
          host: 'evilgoogleapis.com',
          certPem: helloPem,
          config: config,
        ),
        equals(PinDecision.deferToSystem),
      );
    });

    test('host matching is case-insensitive', () {
      const config = PinnedHostConfig({
        'HuggingFace.CO': <String>[helloSha256],
      });
      expect(
        evaluateCertificatePin(
          host: 'huggingface.co',
          certPem: helloPem,
          config: config,
        ),
        equals(PinDecision.acceptPin),
      );
    });
  });

  group('badCertificateCallbackResult', () {
    test('deferToSystem → false (standard OS validation runs)', () {
      expect(
        badCertificateCallbackResult(PinDecision.deferToSystem),
        isFalse,
      );
    });

    test('acceptPin → true (override the failure, trust the pinned cert)', () {
      expect(badCertificateCallbackResult(PinDecision.acceptPin), isTrue);
    });

    test('rejectPin + enforced → false (fatal: connection refused)', () {
      expect(
        badCertificateCallbackResult(PinDecision.rejectPin, enforced: true),
        isFalse,
      );
    });

    test(
      'rejectPin + fail-open → true (tolerated: rely on logging for visibility)',
      () {
        expect(
          badCertificateCallbackResult(PinDecision.rejectPin, enforced: false),
          isTrue,
        );
      },
    );

    test('rejectPin with no override reflects the shipped default', () {
      // kCertificatePinningEnforced ships false → fail-open.
      expect(
        badCertificateCallbackResult(PinDecision.rejectPin),
        equals(!kCertificatePinningEnforced),
      );
    });
  });

  group('shipped default state', () {
    test('kCertificatePinningEnforced ships false (observe-only / fail-open)', () {
      expect(kCertificatePinningEnforced, isFalse);
    });

    test('target hosts ship with EMPTY allow-lists (zero breakage)', () {
      const config = PinnedHostConfig.kDefault;
      // "Not pinned" = allowListForHost returns null (host unconfigured) OR an
      // empty list. Regional Vertex hosts are hyphenated and intentionally
      // unlisted today, so they resolve to null — both states mean "defer".
      void expectUnpinned(String host) {
        final pins = config.allowListForHost(host);
        expect(
          pins == null || pins.isEmpty,
          isTrue,
          reason: '$host must not be pinned in the shipped default',
        );
      }

      expectUnpinned('generativelanguage.googleapis.com');
      expectUnpinned('us-central1-aiplatform.googleapis.com');
      expectUnpinned('aiplatform.googleapis.com');
      expectUnpinned('huggingface.co');
    });

    test('with the default config, every supported host currently defers', () {
      const config = PinnedHostConfig.kDefault;
      for (final host in [
        'generativelanguage.googleapis.com',
        'us-central1-aiplatform.googleapis.com',
        'huggingface.co',
        'api.github.com', // update-check host: intentionally unlisted
      ]) {
        expect(
          evaluateCertificatePin(host: host, certPem: helloPem, config: config),
          equals(PinDecision.deferToSystem),
          reason: '$host must defer to the OS store while its allow-list is '
              'empty',
        );
      }
    });
  });
}
