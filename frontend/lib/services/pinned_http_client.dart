/// HTTPS transport for Beeamvo, plus (un-wired) pinning scaffolding.
///
/// ## TLS posture — READ THIS (it is intentionally plain)
/// The shipped [createSecureHttpClient] performs **standard platform TLS
/// validation only**. It trusts the operating system's root certificate store
/// and rejects any peer that fails that validation — exactly like a plain
/// `http.Client()`.
///
/// **No certificate pinning is active, enforced, or wired into outbound
/// traffic.** Every HTTPS request from this app (Gemini, Vertex via
/// `googleapis_auth`, the Hugging Face model mirror, the GitHub update check)
/// is validated solely by the OS trust store. Keep the operating system and its
/// trusted roots current.
///
/// ## Why the pinning machinery below is NOT connected
/// The remainder of this file (`PinnedHostConfig`, [evaluateCertificatePin],
/// [computeLeafPinHash], [PinDecision], [badCertificateCallbackResult],
/// [captureLeafCertificateDescription]) is a small, **pure, unit-tested**
/// representation of the pinning design space. It is deliberately **not**
/// referenced by [createSecureHttpClient]. It is retained so a future
/// maintainer can implement pinning *correctly* — but reconnecting it through
/// Dart's `HttpClient.badCertificateCallback` would be **unsafe**, because that
/// callback is only invoked after standard OS validation has **already failed**.
///
/// Concrete consequences of that limitation:
///   * The callback can only *override* an OS-trust failure (the only real value
///     is trusting a self-signed / internally-issued leaf). It can **never**
///     reject an OS-trusted-but-impersonating certificate, because the callback
///     simply never fires for a cert the OS already trusts.
///   * Worse: the pure helper [badCertificateCallbackResult] defines a fail-open
///     branch (`rejectPin` while enforcement is disabled → return `true`, i.e.
///     **accept a certificate that already failed OS validation**). Wiring that
///     into a live client with populated pins would make HTTPS *weaker* than
///     standard TLS. That branch is intentionally never used in production.
///
/// Sound, fail-closed pinning would require disabling OS validation entirely and
/// verifying the chain in native code (e.g. a TLS intercept/proxy or a custom
/// `SecurityContext` per platform). That is a larger, platform-specific
/// integration task and is intentionally out of scope for this release.
library;

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart' show IOClient;

/// Builds the [http.Client] used for all outbound HTTPS traffic.
///
/// The client is a `dart:io` [HttpClient] wrapped in [IOClient] and trusts the
/// operating-system certificate store. It deliberately installs **no**
/// `badCertificateCallback`, so there is no code path that can weaken standard
/// platform TLS validation. Certificate pinning is intentionally not
/// implemented — see the library-level docs for why a Dart
/// `badCertificateCallback` cannot soundly enforce it.
///
/// Callers that already own an [http.Client] (e.g. tests) may inject one; this
/// factory is only the default.
http.Client createSecureHttpClient() {
  return IOClient(HttpClient());
}

// ═════════════════════════════════════════════════════════════════════════════
// PIN-EVALUATION SCAFFOLDING — pure, unit-tested, AND INTENTIONALLY UNUSED.
//
// These symbols model how pin matching *would* work. They are kept so the logic
// stays documented and covered by tests, but [createSecureHttpClient] does NOT
// reference them. See the library-level docs before reconnecting anything here.
// ═════════════════════════════════════════════════════════════════════════════

/// Sentinel enforcement flag referenced by [badCertificateCallbackResult].
///
/// Kept at the shipped default of `false` purely so the pure helper below has a
/// stable, testable contract. It is NOT consumed by any live TLS path in the
/// app, because wiring pinning through `badCertificateCallback` is unsafe (see
/// the library-level docs). Do not flip this to `true` expecting pinning to take
/// effect: nothing reads it from the network layer today.
const bool kCertificatePinningEnforced = false;

// ─────────────────────────────────────────────────────────────────────────────
// Per-host allow-lists of accepted **leaf** certificate SHA-256 hashes.
//
// These are SCAFFOLDING ONLY: with no live pinning wiring (see
// [createSecureHttpClient]) they have zero runtime effect. They are retained so
// a future maintainer who implements native fail-closed pinning has a tested
// matching layer and a capture workflow ready.
//
// The map key is matched against the tail of the request host (domain-suffix
// matching on label boundaries): a key of `googleapis.com` matches both
// `generativelanguage.googleapis.com` and `us-central1-aiplatform.googleapis.com`.
//
// Each value is a list so you can pin several leaves at once (current +
// rotation-rollover cert) to ride out rotation without an outage.
// ─────────────────────────────────────────────────────────────────────────────
const Map<String, List<String>> _kPinnedHostAllowLists = <String, List<String>>{
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

/// Per-host pinning configuration (scaffolding).
///
/// [kDefault] holds the allow-lists above. As long as this layer is not wired
/// into the live client (it is not — see [createSecureHttpClient]) it performs
/// no TLS validation of any kind. [allowListForHost] returns the hashes that
/// *would* apply to a given request host (`null` when none are configured).
class PinnedHostConfig {
  /// Map of allow-list keys → accepted leaf SHA-256 hashes (lowercase hex).
  const PinnedHostConfig(this.pins);

  /// The shipped allow-lists. These exist for documentation and for a future
  /// maintainer; they have no runtime effect until a sound pinning layer is
  /// built on top of them.
  static const PinnedHostConfig kDefault = PinnedHostConfig(
    _kPinnedHostAllowLists,
  );

  /// A config with no pins at all.
  static const PinnedHostConfig empty = PinnedHostConfig(
    <String, List<String>>{},
  );

  final Map<String, List<String>> pins;

  /// Returns the pin allow-list that *would* apply to [host], or `null` when no
  /// pin rule is configured for [host].
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

/// Pure outcome of evaluating a presented certificate against a pin config.
///
/// Pure (no I/O, no network) so it is unit-testable via
/// [evaluateCertificatePin]. NOTE: this type is part of the un-wired scaffolding;
/// no live TLS path consumes it. See the library-level docs.
enum PinDecision {
  /// No pins are configured for this host → defer to the OS trust store.
  deferToSystem,

  /// The presented leaf hash matches a configured pin → accept (override any
  /// OS-trust failure). Only meaningful if pinning were wired in.
  acceptPin,

  /// Pins are configured for this host but the presented leaf hash does not
  /// match any of them → reject when enforced, otherwise tolerate (fail-open).
  ///
  /// The fail-open branch is deliberately never wired into production because
  /// accepting an OS-trust failure is strictly weaker than standard TLS.
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
/// - [config] defaults to [PinnedHostConfig.kDefault] (the un-wired scaffolding
///   allow-lists; they have no runtime effect today).
///
/// Returns:
/// - [PinDecision.deferToSystem] when [host] has no configured pins.
/// - [PinDecision.acceptPin] when the leaf hash is in the allow-list.
/// - [PinDecision.rejectPin] when pins exist but none match.
///
/// NOTE: this function is part of the un-wired scaffolding. It does not gate any
/// real connection in the shipped app. See the library-level docs.
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

/// Translates a [PinDecision] into the boolean a `HttpClient.badCertificateCallback`
/// *would* have to return, honouring [kCertificatePinningEnforced].
///
/// - `deferToSystem` → `false`  (standard OS validation runs, unchanged).
/// - `acceptPin`     → `true`   (override the failure, trust the pinned cert).
/// - `rejectPin`     → enforced ? `false` (fatal) : `true` (tolerated / fail-open).
///
/// **This helper is kept for documentation/testing only and is deliberately NOT
/// referenced by [createSecureHttpClient].** The `rejectPin`/fail-open branch
/// (`true`) would ACCEPT a certificate that already failed OS validation — which
/// is strictly weaker than standard TLS. Wiring it in is unsafe; see the
/// library-level docs.
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
      // true). Documented here precisely to make the danger visible; not wired.
      return effectiveEnforced ? false : true;
  }
}

/// Connects to `https://[host]:[port]`, reads the peer's leaf certificate, and
/// returns a human-readable description including its **SHA-256 pin hash**.
///
/// **Maintainer capture helper only.** It uses a plain, OS-trusting connection
/// to inspect a certificate. It is useful ONLY if a future maintainer implements
/// sound fail-closed pinning in native code and needs to capture real leaf
/// hashes — it has no effect on the shipped app's TLS behaviour and is never
/// called from production paths. Requires network access; never call from tests.
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
    // Every outbound network operation is bounded by an explicit timeout so a
    // dead/unreachable host fails fast instead of waiting up to the platform's
    // multi-minute default socket timeout. Any TimeoutException propagates to
    // the caller after the `finally` block below closes the client.
    final response = await request.close().timeout(const Duration(seconds: 10));
    final cert = response.certificate;
    await response.drain<void>().timeout(const Duration(seconds: 10));
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
        'This capture is only meaningful if you later implement SOUND, '
        'fail-closed pinning in native code (a Dart `badCertificateCallback` '
        'cannot enforce it — see pinned_http_client.dart). Add the SHA-256 '
        'value above to PinnedHostConfig under a host key matching "$host" '
        '(or a domain suffix such as "googleapis.com").',
      );
    return buffer.toString().trim();
  } finally {
    client.close(force: true);
  }
}
