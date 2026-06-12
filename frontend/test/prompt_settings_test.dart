import 'package:beeamvo/config.dart';
import 'package:beeamvo/models/prompt_settings.dart';
import 'package:beeamvo/models/system_prompt.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PromptSettings', () {
    test(
      'serializes all prompt-level override fields including thinking levels',
      () {
        const settings = PromptSettings(
          modelId: 'gemini-3-flash',
          transcriptionBackend: 'whisper',
          cloudProvider: 'vertexAi',
          whisperModelId: 'ggml-large-v3-turbo.bin',
          whisperLanguage: 'de',
          twoPassTranscriptionEnabled: true,
          twoPassTranscriptionModelId: 'gemini-3.1-flash-lite',
          twoPassRefinementModelId: 'gemini-3-flash',
          rephraseLevel: RephraseLevel.high,
          thinkingLevel: GeminiThinkingLevel.low,
          twoPassRefinementThinkingLevel: GeminiThinkingLevel.high,
        );

        final map = settings.toMap();
        final restored = PromptSettings.fromMap(map);

        expect(map['modelId'], equals('gemini-3-flash'));
        expect(map['transcriptionBackend'], equals('whisper'));
        expect(map['cloudProvider'], equals('vertexAi'));
        expect(
          map['twoPassTranscriptionModelId'],
          equals('gemini-3.1-flash-lite'),
        );
        expect(map['thinkingLevel'], equals('LOW'));
        expect(map['twoPassRefinementThinkingLevel'], equals('HIGH'));
        expect(restored.modelId, equals(settings.modelId));
        expect(
          restored.transcriptionBackend,
          equals(settings.transcriptionBackend),
        );
        expect(restored.cloudProvider, equals(settings.cloudProvider));
        expect(restored.whisperModelId, equals(settings.whisperModelId));
        expect(restored.whisperLanguage, equals(settings.whisperLanguage));
        expect(
          restored.twoPassTranscriptionEnabled,
          equals(settings.twoPassTranscriptionEnabled),
        );
        expect(
          restored.twoPassTranscriptionModelId,
          equals(settings.twoPassTranscriptionModelId),
        );
        expect(
          restored.twoPassRefinementModelId,
          equals(settings.twoPassRefinementModelId),
        );
        expect(restored.rephraseLevel, equals(settings.rephraseLevel));
        expect(restored.thinkingLevel, equals(settings.thinkingLevel));
        expect(
          restored.twoPassRefinementThinkingLevel,
          equals(settings.twoPassRefinementThinkingLevel),
        );
        expect(restored.overrideCount, equals(11));
        expect(restored.hasAnyOverride, isTrue);
      },
    );
  });
}
