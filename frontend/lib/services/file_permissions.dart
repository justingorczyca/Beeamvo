import 'dart:io';

// Windows DACL handling is intentionally out of scope; the documented
// platform storage mechanisms provide the applicable protection there.
Future<void> setPosixPermissions(String filePath, String mode) async {
  if (!Platform.isMacOS && !Platform.isLinux) return;
  try {
    await Process.run('chmod', [mode, filePath]);
  } catch (_) {
    // Best effort: permissions must never prevent startup or persistence.
  }
}
