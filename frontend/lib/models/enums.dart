/// Which transcription backend to use.
enum TranscriptionBackend {
  /// Cloud-based transcription with a selectable provider.
  cloud,

  /// Local offline transcription via whisper.cpp (ggml-tiny.bin, ~75 MB).
  whisper,
}

extension TranscriptionBackendExtension on TranscriptionBackend {
  /// Human-readable label shown in the UI.
  String get displayName {
    switch (this) {
      case TranscriptionBackend.cloud:
        return 'Cloud';
      case TranscriptionBackend.whisper:
        return 'Offline';
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
enum CloudProvider {
  geminiApiKey,
  vertexAi,
  openaiApiKey,
  codexOAuth,
  grokOAuth,
}

extension CloudProviderExtension on CloudProvider {
  /// Human-readable label shown in the UI.
  String get displayName {
    switch (this) {
      case CloudProvider.geminiApiKey:
        return 'Gemini';
      case CloudProvider.vertexAi:
        return 'Vertex AI';
      case CloudProvider.openaiApiKey:
        return 'OpenAI';
      case CloudProvider.codexOAuth:
        return 'ChatGPT';
      case CloudProvider.grokOAuth:
        return 'Grok';
    }
  }

  /// One-sentence description used as the provider row description.
  String get description {
    switch (this) {
      case CloudProvider.geminiApiKey:
        return 'Your own Gemini API key, stored locally on this device.';
      case CloudProvider.vertexAi:
        return 'Your Google Cloud project via Vertex AI and local ADC '
            'credentials.';
      case CloudProvider.openaiApiKey:
        return 'An OpenAI API key, or any OpenAI-compatible endpoint.';
      case CloudProvider.codexOAuth:
        return 'Sign in with your ChatGPT account. GPT-5.6 and GPT-6 models, '
            'no API key.';
      case CloudProvider.grokOAuth:
        return 'Sign in with your xAI account. Grok models, no API key.';
    }
  }

  /// Short label for the credential the provider needs ('API key',
  /// 'Project ID', or 'Sign-in').
  String get credentialLabel {
    switch (this) {
      case CloudProvider.geminiApiKey:
      case CloudProvider.openaiApiKey:
        return 'API key';
      case CloudProvider.vertexAi:
        return 'Project ID';
      case CloudProvider.codexOAuth:
      case CloudProvider.grokOAuth:
        return 'Sign-in';
    }
  }

  /// Resolve a stored [value] string back to an enum member, defaulting
  /// to [geminiApiKey] when the value is unrecognised.
  static CloudProvider fromValue(String? value) {
    for (final provider in CloudProvider.values) {
      if (provider.name == value) return provider;
    }
    return CloudProvider.geminiApiKey;
  }
}
