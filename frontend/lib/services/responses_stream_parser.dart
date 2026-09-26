import 'dart:async';
import 'dart:convert';

import 'cloud_transcription_client.dart';

/// Aggregates an OpenAI Responses API server-sent event stream into final
/// output text.
///
/// Shared by the providers that speak the Responses-over-SSE surface
/// (`ChatGPT Codex` at `chatgpt.com/backend-api/codex` and `xAI Grok` at
/// `api.x.ai/v1`): `response.output_text.delta` events are concatenated and
/// `response.completed` is used as a fallback when no deltas arrive.
/// `response.failed`/`error` events abort with the upstream message.
class ResponsesStreamParser {
  const ResponsesStreamParser({
    required this.providerLabel,
    required this.timeout,
  });

  /// Human-readable provider name used in error messages
  /// (`'ChatGPT Codex'`, `'xAI Grok'`).
  final String providerLabel;

  /// Maximum time to wait for the stream to finish.
  final Duration timeout;

  /// Consumes [byteStream] and returns the final response text.
  Future<String> collect(Stream<List<int>> byteStream) async {
    final buffer = StringBuffer();
    String? completedText;
    String? streamError;

    try {
      await utf8.decoder
          .bind(byteStream)
          .transform(const LineSplitter())
          .forEach((line) {
            if (!line.startsWith('data:')) return;
            final data = line.substring(5).trim();
            if (data.isEmpty || data == '[DONE]') return;
            final decoded = jsonDecode(data);
            if (decoded is! Map) return;
            final event = Map<String, dynamic>.from(decoded);
            final type = event['type']?.toString() ?? '';
            switch (type) {
              case 'response.output_text.delta':
                final delta = event['delta'];
                if (delta is String) buffer.write(delta);
              case 'response.completed':
                completedText = _textFromCompletedResponse(event['response']);
              case 'response.failed':
              case 'error':
                streamError = _errorMessageFromEvent(event);
            }
          })
          .timeout(timeout);
    } on TimeoutException {
      throw CloudTranscriptionException(
        '$providerLabel did not finish within ${timeout.inSeconds} '
        'seconds. Try again in a moment.',
      );
    }

    if (streamError != null) {
      throw CloudTranscriptionException(streamError!);
    }
    final text = buffer.isNotEmpty
        ? buffer.toString().trim()
        : (completedText ?? '').trim();
    if (text.isEmpty) {
      throw CloudTranscriptionException(
        '$providerLabel returned an empty response.',
      );
    }
    return text;
  }

  /// Extracts `output_text` content from a `response.completed` event's
  /// `response.output[].content[]` structure.
  String? _textFromCompletedResponse(Object? response) {
    if (response is! Map) return null;
    final output = response['output'];
    if (output is! List) return null;
    final buffer = StringBuffer();
    for (final item in output) {
      if (item is! Map || item['type'] != 'message') continue;
      final content = item['content'];
      if (content is! List) continue;
      for (final part in content) {
        if (part is Map &&
            part['type'] == 'output_text' &&
            part['text'] is String) {
          buffer.write(part['text'] as String);
        }
      }
    }
    final text = buffer.toString().trim();
    return text.isEmpty ? null : text;
  }

  String _errorMessageFromEvent(Map<String, dynamic> event) {
    final error = event['error'];
    final message = error is Map
        ? error['message']?.toString()
        : error?.toString();
    if (message != null && message.trim().isNotEmpty) {
      return '$providerLabel request failed: ${message.trim()}';
    }
    final response = event['response'];
    if (response is Map) {
      final responseError = response['error'];
      final responseMessage = responseError is Map
          ? responseError['message']?.toString()
          : null;
      if (responseMessage != null && responseMessage.trim().isNotEmpty) {
        return '$providerLabel request failed: ${responseMessage.trim()}';
      }
    }
    return '$providerLabel request failed.';
  }
}
