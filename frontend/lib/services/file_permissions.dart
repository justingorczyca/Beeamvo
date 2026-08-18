import 'dart:io';

Future<void> setPosixPermissions(String filePath, String mode) async {
  if (!Platform.isMacOS && !Platform.isLinux) return;
  try {
    await Process.run('chmod', [mode, filePath]);
  } catch (_) {
    // Best effort: permissions must never prevent startup or persistence.
  }
}
