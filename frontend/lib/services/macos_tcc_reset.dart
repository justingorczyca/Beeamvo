/// Absolute path to the macOS TCC (`tccutil`) helper.
///
/// Using the absolute path — instead of relying on `PATH` lookup — matches the
/// native scoped reset (`com.beeamvo.app` `resetAccessibilityEntry`) and
/// removes a PATH-hijack foothold from the troubleshooting UI.
const String tccutilExecutable = '/usr/bin/tccutil';

/// Builds the scoped `tccutil` argument list that resets [service] for [bundleId]
/// ONLY.
///
/// `service` is a macOS TCC privacy domain such as `'Accessibility'` or
/// `'AppleEvents'`. Scoping to the running app's own bundle id keeps the reset
/// from revoking privacy permission for *other* applications.
///
/// Returns `null` when [bundleId] is empty/blank so the caller can **fail safe**
/// (skip the reset and inform the user) rather than invoke an unscoped
/// `tccutil reset <service>`, which would clear that privacy entry for every app
/// on the machine.
List<String>? scopedTccutilArgs({
  required String service,
  required String bundleId,
}) {
  final id = bundleId.trim();
  if (id.isEmpty) return null;
  return ['reset', service, id];
}
