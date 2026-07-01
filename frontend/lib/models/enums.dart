/// Which transcription backend to use.
enum TranscriptionBackend {
  /// Cloud-based transcription with a selectable provider.
  cloud,

  /// Local offline transcription via whisper.cpp (ggml-tiny.bin, ~75 MB).
  whisper,
}

extension TranscriptionBackendExtension on TranscriptionBackend {
  /// Serialized string value used in JSON persistence and prompt overrides.
  String get value => name;

  /// Human-readable label shown in the UI.
  String get displayName {
    switch (this) {
      case TranscriptionBackend.cloud:
        return 'Cloud';
      case TranscriptionBackend.whisper:
        return 'Offline (Whisper)';
    }
  }

  /// Resolve a stored [value] string back to an enum member, defaulting
  /// to [cloud] when the value is unrecognised.
  static TranscriptionBackend fromValue(String? value) {
    if (value == TranscriptionBackend.whisper.name) {
      return TranscriptionBackend.whisper;
    }
    return TranscriptionBackend.cloud;
  }
}

/// Which cloud provider to use for transcription.
enum CloudProvider { geminiApiKey, vertexAi }

extension CloudProviderExtension on CloudProvider {
  /// Serialized string value used in JSON persistence and prompt overrides.
  String get value => name;

  /// Human-readable label shown in the UI.
  String get displayName {
    switch (this) {
      case CloudProvider.geminiApiKey:
        return 'Gemini API Key';
      case CloudProvider.vertexAi:
        return 'Vertex AI';
    }
  }

  /// Human-readable description shown in the UI.
  String get description {
    switch (this) {
      case CloudProvider.geminiApiKey:
        return 'Use your own Gemini API key stored locally on this device.';
      case CloudProvider.vertexAi:
        return 'Use direct Vertex AI REST with your own Google Cloud project credentials.';
    }
  }

  /// Resolve a stored [value] string back to an enum member, defaulting
  /// to [geminiApiKey] when the value is unrecognised.
  static CloudProvider fromValue(String? value) {
    if (value == CloudProvider.vertexAi.name) {
      return CloudProvider.vertexAi;
    }
    return CloudProvider.geminiApiKey;
  }
}
