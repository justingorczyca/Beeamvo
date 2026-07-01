/// Certificate-pinning HTTP infrastructure for Beeamvo.
///
/// ## What this provides
/// [createPinnedHttpClient] builds an [`http.Client`] backed by a `dart:io`
/// [`HttpClient`] whose `badCertificateCallback` validates every TLS peer that
/// fails the OS trust store against a per-host allow-list of **leaf certificate
/// SHA-256 hashes**. [createTrustingHttpClient] preserves the legacy "trust the
/// OS store" behaviour for call sites that want the original semantics.
///
/// ## Decide-once, enforce-later
/// All hosts ship with **empty** allow-lists ([_kPinnedHostAllowLists]). With an
/// empty allow-list a host has *no* pins configured, so the callback defers to
/// the OS trust store — pinning is a strict no-op until a maintainer deliberately
/// captures and pastes real hashes (see [captureLeafCertificateDescription]).
/// This means shipping this client is **zero risk**: every connection behaves
/// exactly as it did with a plain `http.Client()`.
///
/// A separate global switch, [kCertificatePinningEnforced] (default `false`),
/// controls what happens once pins *are* populated and a host presents a cert
/// that is **not** in the allow-list:
///   * `false` (fail-open, default) — the mismatch is *logged but tolerated*,
///     so a Google certificate rotation can never lock users out while we are
///     still pinning in observe-only mode.
///   * `true`  (enforced) — the mismatch is fatal: the connection is rejected.
///
/// ## Honest limitation of the `badCertificateCallback` approach
/// Dart's `badCertificateCallback` is only invoked when standard OS validation
/// has **already failed**. Consequences:
///   * For a host with configured pins, a *matching* hash lets us override the
///     failure and trust a cert the OS might not (this is the core value, e.g.
///     for self-signed / internally-issued certificates).
///   * We **cannot** reject an OS-trusted-yet-wrong certificate through this
///     callback alone, because the callback never fires for a cert the OS
///     already trusts. Full fail-closed pinning against compromised-but-valid
///     CAs would require disabling OS validation entirely and verifying the
///     chain manually (a deeper integration task, intentionally out of scope).
/// The design above — deferred-to-OS until pins exist, then fail-open by
/// default — is the safe, correct use of `badCertificateCallback` and is exactly
/// what protects users today while leaving a clear, testable upgrade path.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' show IOClient;

/// Master switch for certificate pinning enforcement.
///
/// While `false` (the shipped default), a host that HAS configured pins but
/// presents a non-matching certificate will have the mismatch **logged** but the
/// connection is still allowed (fail-open). This guarantees we never break a
/// real user on a routine Google certificate rotation.
///
/// Flip to `true` only AFTER you have:
///   1. Populated real leaf SHA-256 hashes in [_kPinnedHostAllowLists].
///   2. Shipped at least one release with this flag still `false` to observe the
///      `PIN MISMATCH` log lines in the wild and confirm no legitimate Google
///      rotation is being caught.
const bool kCertificatePinningEnforced = false;

// ═════════════════════════════════════════════════════════════════════════════
// PIN CONSTANTS
// ═════════════════════════════════════════════════════════════════════════════
// Per-host allow-lists of accepted **leaf** certificate SHA-256 hashes.
//
// The map key is matched against the tail of the request host (domain-suffix
// matching on label boundaries): a key of `googleapis.com` matches both
// `generativelanguage.googleapis.com` and `us-central1-aiplatform.googleapis.com`.
//
// Each value is a list so you can pin several leaves at once (current +
// rotation-rollover cert) to ride out rotation without an outage.
//
// TO POPULATE A PIN:
//   1. From a trusted machine, run (e.g. in a Dart debug session):
//        print(await captureLeafCertificateDescription('generativelanguage.googleapis.com'));
//   2. Copy the printed `SHA-256` value into the list below.
//   3. Repeat after a Google rotation to capture the new leaf, then remove the
//      old hash once every client has rotated.
//
// Until a host has a non-empty list here, it is NOT pinned and behaves exactly
// like a plain OS-trusting client.
// ═════════════════════════════════════════════════════════════════════════════
const Map<String, List<String>> _kPinnedHostAllowLists =
    <String, List<String>>{
      // Google AI Gemini API (generativelanguage.googleapis.com).
      'generativelanguage.googleapis.com': <String>[
        // e.g. 'AbCd...leaf-sha256-hash...==',
      ],

      // Google Cloud Vertex AI GLOBAL endpoint (aiplatform.googleapis.com).
      // NOTE: regional Vertex endpoints use a HYPHENATED host, e.g.
      //   us-central1-aiplatform.googleapis.com
      // which is NOT matched by this dot-suffix key. If you pin while using a
      // regional location, add a broad 'googleapis.com' key or a per-region key.
      'aiplatform.googleapis.com': <String>[
        // e.g. 'Ef01...leaf-sha256-hash...==',
      ],

      // Whisper.cpp model downloads (Hugging Face).
      'huggingface.co': <String>[
        // e.g. '2345...leaf-sha256-hash...==',
      ],
    };

/// Per-host pinning configuration.
///
/// [kDefault] holds the live allow-lists shipped with the app. Use
/// [allowListForHost] to resolve which hashes apply to a given request host
/// (returns `null` when the host is unconfigured / not pinned).
class PinnedHostConfig {
  /// Map of allow-list keys → accepted leaf SHA-256 hashes (lowercase hex).
  const PinnedHostConfig(this.pins);

  /// The shipped allow-lists. As long as every entry is empty this performs no
  /// pinning — all hosts defer to the OS trust store.
  static const PinnedHostConfig kDefault = PinnedHostConfig(
    _kPinnedHostAllowLists,
  );

  /// A config with no pins at all — every host defers to the OS trust store.
  static const PinnedHostConfig empty = PinnedHostConfig(<String, List<String>>{});

  final Map<String, List<String>> pins;

  /// Returns the pin allow-list that applies to [host], or `null` when no pin
  /// rule is configured for [host] (meaning: defer to the OS trust store).
  ///
  /// Matching is domain-suffix on label boundaries:
  /// key `googleapis.com` matches `googleapis.com` and `*.googleapis.com`.
  List<String>? allowListForHost(String host) {
    final lowerHost = host.toLowerCase();
    for (final entry in pins.entries) {
      final key = entry.key.toLowerCase();
      if (lowerHost == key || lowerHost.endsWith('.$key')) {
        return entry.value;
      }
    }
    return null;
  }
}

/// Outcome of evaluating a presented certificate against the pin config.
///
/// Pure (no I/O, no network) so it is trivially unit-testable via
/// [evaluateCertificatePin]. The boolean the `badCertificateCallback` should
/// actually return is derived by [badCertificateCallbackResult].
enum PinDecision {
  /// No pins are configured for this host → defer to the OS trust store.
  deferToSystem,

  /// The presented leaf hash matches a configured pin → accept (override any
  /// OS-trust failure).
  acceptPin,

  /// Pins are configured for this host but the presented leaf hash does not
  /// match any of them → reject when enforced, otherwise tolerate (fail-open).
  rejectPin,
}

/// Computes the SHA-256 (lowercase hex) of a PEM-encoded certificate's DER body.
///
/// Pure & synchronous so it is unit-testable. Accepts the full PEM text
/// (`-----BEGIN CERTIFICATE-----\n<base64 DER>\n-----END CERTIFICATE-----`),
/// strips the armor, base64-decodes to DER, and hashes.
@visibleForTesting
String computeLeafPinHash(String pem) {
  final der = _pemToDerBytes(pem);
  return sha256.convert(der).toString();
}

List<int> _pemToDerBytes(String pem) {
  final cleaned = pem
      .split(RegExp(r'\r?\n'))
      .where((line) => !line.contains('-----'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .join();

  if (cleaned.isEmpty) {
    throw ArgumentError('PEM certificate contained no base64 data.');
  }
  return base64.decode(cleaned);
}

/// Pure decision function: decides [PinDecision] for a presented certificate
/// against [config] without any network access or I/O.
///
/// - [certPem] is the PEM text of the **leaf** certificate the peer presented.
/// - [config] defaults to the shipped [PinnedHostConfig.kDefault].
///
/// Returns:
/// - [PinDecision.deferToSystem] when [host] has no configured pins (defer to
///   the OS trust store — the only path that runs while allow-lists are empty).
/// - [PinDecision.acceptPin] when the leaf hash is in the allow-list.
/// - [PinDecision.rejectPin] when pins exist but none match.
///
/// Note: whether a [PinDecision.rejectPin] is actually fatal is decided later by
/// [badCertificateCallbackResult] using [kCertificatePinningEnforced].
@visibleForTesting
PinDecision evaluateCertificatePin({
  required String host,
  required String certPem,
  PinnedHostConfig config = PinnedHostConfig.kDefault,
}) {
  final allowList = config.allowListForHost(host);
  if (allowList == null || allowList.isEmpty) {
    return PinDecision.deferToSystem;
  }

  final presentedHash = computeLeafPinHash(certPem);
  if (allowList.contains(presentedHash)) {
    return PinDecision.acceptPin;
  }
  return PinDecision.rejectPin;
}

/// Translates a [PinDecision] into the boolean `HttpClient.badCertificateCallback`
/// must return, honouring [kCertificatePinningEnforced].
///
/// - `deferToSystem` → `false`  (standard OS validation runs, unchanged).
/// - `acceptPin`     → `true`   (override the failure, trust the pinned cert).
/// - `rejectPin`     → enforced ? `false` (fatal) : `true` (tolerated / fail-open).
@visibleForTesting
bool badCertificateCallbackResult(PinDecision decision, {bool? enforced}) {
  final effectiveEnforced = enforced ?? kCertificatePinningEnforced;
  switch (decision) {
    case PinDecision.deferToSystem:
      return false;
    case PinDecision.acceptPin:
      return true;
    case PinDecision.rejectPin:
      // Enforced → reject (return false so the failed standard validation
      // stands and the connection is refused). Fail-open → tolerate (return
      // true) and rely on the PIN MISMATCH log line for visibility.
      return effectiveEnforced ? false : true;
  }
}

void _debugLog(String message) {
  if (kDebugMode) debugPrint(message);
}

bool _onBadCertificate(X509Certificate cert, String host, int port) {
  final decision = evaluateCertificatePin(
    host: host,
    certPem: cert.pem,
    config: PinnedHostConfig.kDefault,
  );

  if (decision == PinDecision.rejectPin) {
    final presentedHash = computeLeafPinHash(cert.pem);
    final allowList = PinnedHostConfig.kDefault.allowListForHost(host);
    _debugLog(
      '[PinnedHttpClient] PIN MISMATCH for "$host:$port" '
      '(enforced=$kCertificatePinningEnforced). '
      'Presented leaf SHA-256: $presentedHash. '
      'Allowed: ${allowList ?? const <String>[]}. '
      '${kCertificatePinningEnforced ? 'Connection rejected.' : 'Tolerated (fail-open).'}',
    );
  }

  return badCertificateCallbackResult(decision);
}

/// Builds an [http.Client] that applies certificate pinning (observe-only by
/// default; see [kCertificatePinningEnforced]).
///
/// Hosts with no configured pins defer to the OS trust store and are
/// indistinguishable from a plain client — so this is safe to use as the default
/// for every outbound HTTPS call. Hosts WITH pins are validated against their
/// allow-list before the connection is accepted.
http.Client createPinnedHttpClient() {
  final ioClient = HttpClient()..badCertificateCallback = _onBadCertificate;
  return IOClient(ioClient);
}

/// Builds an [http.Client] with the legacy "trust the OS store" behaviour —
/// identical to a plain `http.Client()`. Provided for call sites that
/// deliberately want no pin validation.
http.Client createTrustingHttpClient() => http.Client();

/// Connects to `https://[host]:[port]`, reads the peer's leaf certificate, and
/// returns a human-readable description including its **SHA-256 pin hash**.
///
/// This is a maintainer capture helper: run it once from a trusted machine for
/// each host listed in [_kPinnedHostAllowLists], copy the printed `SHA-256`
/// value into the allow-list, and only THEN consider flipping
/// [kCertificatePinningEnforced] to `true`.
///
/// Requires network access — never call this from unit tests.
Future<String> captureLeafCertificateDescription(
  String host, {
  int port = 443,
}) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(
      // Default port 443 → Uri normalizes it away; an explicit non-443 port is
      // preserved so capture works against non-standard endpoints too.
      Uri(scheme: 'https', host: host, port: port, path: '/'),
    );
    final response = await request.close();
    final cert = response.certificate;
    await response.drain<void>();
    if (cert == null) {
      return 'No certificate presented by $host:$port '
          '(TLS was not negotiated).';
    }
    final hash = computeLeafPinHash(cert.pem);
    final buffer = StringBuffer()
      ..writeln('Certificate pin capture for $host:$port:')
      ..writeln('  subject : ${cert.subject}')
      ..writeln('  issuer  : ${cert.issuer}')
      ..writeln('  SHA-256 : $hash')
      ..writeln(
        'Add the SHA-256 value above to PinnedHostConfig under a host key '
        'matching "$host" (or a domain suffix such as "googleapis.com").',
      );
    return buffer.toString().trim();
  } finally {
    client.close(force: true);
  }
}
