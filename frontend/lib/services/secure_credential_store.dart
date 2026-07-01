import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

abstract class SecureCredentialStore {
  Future<String?> readGeminiApiKey();
  Future<void> writeGeminiApiKey(String value);
  Future<void> deleteGeminiApiKey();
}

/// A consistent credential store implementation that uses native Keychain
/// storage on macOS.
class FlutterSecureCredentialStore implements SecureCredentialStore {
  const FlutterSecureCredentialStore();

  static const _kGeminiApiKey = 'gemini_api_key';

  /// Platform channel for macOS native credential access
  static const _channel = MethodChannel('com.beamvo/keychain_credentials');

  /// Standard flutter_secure_storage for non-macOS platforms
  static const _fallbackStorage = FlutterSecureStorage();

  @override
  Future<String?> readGeminiApiKey() async {
    try {
      if (Platform.isMacOS) {
        return await _channel.invokeMethod<String>('read', {
          'account': _kGeminiApiKey,
        });
      } else {
        return await _fallbackStorage.read(key: _kGeminiApiKey);
      }
    } catch (e) {
      debugPrint('[SecureCredentialStore] Error reading key: $e');
      return null;
    }
  }

  @override
  Future<void> writeGeminiApiKey(String value) async {
    try {
      if (Platform.isMacOS) {
        final success = await _channel.invokeMethod<bool>('write', {
          'account': _kGeminiApiKey,
          'value': value,
        });
        if (success != true) {
          throw Exception('Failed to write credentials');
        }
      } else {
        await _fallbackStorage.write(key: _kGeminiApiKey, value: value);
      }
    } catch (e) {
      debugPrint('[SecureCredentialStore] Error writing key: $e');
      rethrow;
    }
  }

  @override
  Future<void> deleteGeminiApiKey() async {
    try {
      if (Platform.isMacOS) {
        await _channel.invokeMethod<bool>('delete', {
          'account': _kGeminiApiKey,
        });
      } else {
        await _fallbackStorage.delete(key: _kGeminiApiKey);
      }
    } catch (e) {
      debugPrint('[SecureCredentialStore] Error deleting key: $e');
    }
  }
}

class InMemorySecureCredentialStore implements SecureCredentialStore {
  String? _geminiApiKey;

  @override
  Future<String?> readGeminiApiKey() async => _geminiApiKey;

  @override
  Future<void> writeGeminiApiKey(String value) async {
    _geminiApiKey = value;
  }

  @override
  Future<void> deleteGeminiApiKey() async {
    _geminiApiKey = null;
  }
}
