import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SecureCredentialStore {
  Future<String?> readApiKey(String account);
  Future<void> writeApiKey(String account, String value);
  Future<void> deleteApiKey(String account);

  Future<String?> readGeminiApiKey();
  Future<void> writeGeminiApiKey(String value);
  Future<void> deleteGeminiApiKey();
}

/// A consistent credential store implementation that uses native Keychain
/// storage on macOS.
class FlutterSecureCredentialStore implements SecureCredentialStore {
  const FlutterSecureCredentialStore();

  static const String _kGeminiApiKey = 'gemini_api_key';

  /// Platform channel for macOS native credential access
  static const _channel = MethodChannel('com.beamvo/keychain_credentials');

  /// Standard flutter_secure_storage for non-macOS platforms
  static const _fallbackStorage = FlutterSecureStorage();

  @override
  Future<String?> readApiKey(String account) async {
    try {
      if (Platform.isMacOS) {
        return await _channel.invokeMethod<String>('read', {
          'account': account,
        });
      } else {
        return await _fallbackStorage.read(key: account);
      }
    } catch (e) {
      debugPrint('[SecureCredentialStore] Error reading key: $e');
      return null;
    }
  }

  @override
  Future<void> writeApiKey(String account, String value) async {
    try {
      if (Platform.isMacOS) {
        final success = await _channel.invokeMethod<bool>('write', {
          'account': account,
          'value': value,
        });
        if (success != true) {
          throw Exception('Failed to write credentials');
        }
      } else {
        await _fallbackStorage.write(key: account, value: value);
      }
    } catch (e) {
      debugPrint('[SecureCredentialStore] Error writing key: $e');
      rethrow;
    }
  }

  @override
  Future<void> deleteApiKey(String account) async {
    try {
      if (Platform.isMacOS) {
        await _channel.invokeMethod<bool>('delete', {'account': account});
      } else {
        await _fallbackStorage.delete(key: account);
      }
    } catch (e) {
      debugPrint('[SecureCredentialStore] Error deleting key: $e');
    }
  }

  @override
  Future<String?> readGeminiApiKey() => readApiKey(_kGeminiApiKey);

  @override
  Future<void> writeGeminiApiKey(String value) =>
      writeApiKey(_kGeminiApiKey, value);

  @override
  Future<void> deleteGeminiApiKey() => deleteApiKey(_kGeminiApiKey);
}

class InMemorySecureCredentialStore implements SecureCredentialStore {
  final Map<String, String> _apiKeys = {};

  @override
  Future<String?> readApiKey(String account) async => _apiKeys[account];

  @override
  Future<void> writeApiKey(String account, String value) async {
    _apiKeys[account] = value;
  }

  @override
  Future<void> deleteApiKey(String account) async {
    _apiKeys.remove(account);
  }

  @override
  Future<String?> readGeminiApiKey() => readApiKey('gemini_api_key');

  @override
  Future<void> writeGeminiApiKey(String value) =>
      writeApiKey('gemini_api_key', value);

  @override
  Future<void> deleteGeminiApiKey() => deleteApiKey('gemini_api_key');
}

String openAiCompatibleApiKeyAccount(String providerId) {
  final normalized = providerId.trim();
  if (!RegExp(r'^[a-z0-9_-]+$').hasMatch(normalized)) {
    throw ArgumentError(
      'OpenAI-compatible provider IDs may contain only lowercase letters, '
      'digits, underscores, and hyphens.',
    );
  }
  return 'openai_compatible_api_key_$normalized';
}
