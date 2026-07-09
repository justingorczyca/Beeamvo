import 'package:beeamvo/services/pinned_http_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // A fake PEM wrapper around the bytes for "hello". These tests use only the
  // pure pin-decision functions; they never open a socket or alter TLS trust.
  const certPem =
      '-----BEGIN CERTIFICATE-----\naGVsbG8=\n-----END CERTIFICATE-----';
  const certHash =
      '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';

  group('shipped pinning behavior', () {
    test('uses OS trust decisions by default; pin enforcement is disabled', () {
      expect(kCertificatePinningEnforced, isFalse);

      for (final host in <String>[
        'generativelanguage.googleapis.com',
        'aiplatform.googleapis.com',
        'us-central1-aiplatform.googleapis.com',
        'huggingface.co',
        'api.github.com',
      ]) {
        expect(
          evaluateCertificatePin(host: host, certPem: certPem),
          PinDecision.deferToSystem,
          reason: '$host must use the operating-system trust store by default',
        );
      }
    });

    test('host rules match exact names and dot-delimited subdomains only', () {
      const config = PinnedHostConfig({
        'googleapis.com': <String>[certHash],
      });

      expect(
        evaluateCertificatePin(
          host: 'googleapis.com',
          certPem: certPem,
          config: config,
        ),
        PinDecision.acceptPin,
      );
      expect(
        evaluateCertificatePin(
          host: 'us-central1-aiplatform.googleapis.com',
          certPem: certPem,
          config: config,
        ),
        PinDecision.acceptPin,
      );
      expect(
        evaluateCertificatePin(
          host: 'evilgoogleapis.com',
          certPem: certPem,
          config: config,
        ),
        PinDecision.deferToSystem,
      );
    });

    test('an empty host rule remains an OS-trust decision', () {
      const config = PinnedHostConfig({
        'generativelanguage.googleapis.com': <String>[],
      });

      expect(
        evaluateCertificatePin(
          host: 'generativelanguage.googleapis.com',
          certPem: certPem,
          config: config,
        ),
        PinDecision.deferToSystem,
      );
    });
  });
}
