import 'package:beeamvo/config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GeminiModelConfig', () {
    test('thinkingConfig returns budget for Gemini 2.5 models', () {
      const flashModel = GeminiModelConfig(
        id: 'test-flash',
        name: 'Test Flash',
        modelName: 'gemini-2.5-flash',
        thinkingBudget: 0,
      );

      expect(flashModel.thinkingConfig, isNotNull);
      expect(flashModel.thinkingConfig!['thinkingBudget'], equals(0));
    });

    test(
      'thinkingConfigWithLevel returns named thinking levels for preview models',
      () {
        const previewModel = GeminiModelConfig(
          id: 'test-preview',
          name: 'Preview',
          modelName: 'gemini-3-flash-preview',
          isPreview: true,
          thinkingLevel: GeminiThinkingLevel.low,
          supportedThinkingLevels: [
            GeminiThinkingLevel.minimal,
            GeminiThinkingLevel.low,
            GeminiThinkingLevel.medium,
          ],
        );

        expect(
          previewModel.thinkingConfigWithLevel(GeminiThinkingLevel.medium),
          equals({'thinkingLevel': 'MEDIUM'}),
        );
        expect(previewModel.displayName, equals('Preview (Preview)'));
      },
    );
  });

  group('AppConfig defaults', () {
    test('default model is Gemini 3.1 Flash Lite', () {
      expect(AppConfig.defaultModelId, equals('gemini-3.1-flash-lite'));

      final defaultModel = AppConfig.getModelById(AppConfig.defaultModelId);
      expect(defaultModel.modelName, equals('gemini-3.1-flash-lite'));
      expect(defaultModel.isPreview, isFalse);
      expect(defaultModel.vertexLocation, equals('global'));
    });

    group('resolveModelId', () {
      test('falls back to the default when no id was ever saved', () {
        expect(
          AppConfig.resolveModelId(null),
          equals(AppConfig.defaultModelId),
        );
      });

      test('returns the default for an id that is no longer offered', () {
        expect(
          AppConfig.resolveModelId('retired-stable-diffusion-pro'),
          equals(AppConfig.defaultModelId),
        );
      });

      test('keeps a valid, currently-offered model id untouched', () {
        final kept = AppConfig.resolveModelId('gemini-2.5-flash');
        expect(kept, equals('gemini-2.5-flash'));
        expect(kept, isNot(equals(AppConfig.defaultModelId)));
      });
    });

    group('isOfferedModelId', () {
      test('returns false for null', () {
        expect(AppConfig.isOfferedModelId(null), isFalse);
      });

      test('returns false for a retired / unknown id', () {
        expect(AppConfig.isOfferedModelId('gemini-2.0-flash'), isFalse);
        expect(AppConfig.isOfferedModelId('does-not-exist'), isFalse);
      });

      test('returns true for every currently-offered id', () {
        for (final model in AppConfig.availableModels) {
          expect(AppConfig.isOfferedModelId(model.id), isTrue);
        }
      });
    });

    test('Gemini 3 Flash preview defaults to minimal thinking in the app', () {
      final previewModel = AppConfig.availableModels.firstWhere(
        (model) => model.id == 'gemini-3-flash',
      );

      expect(previewModel.isPreview, isTrue);
      expect(previewModel.supportedThinkingLevels, isNotEmpty);
      expect(previewModel.thinkingLevel, equals(GeminiThinkingLevel.minimal));
    });

    test('Gemini 3.5 Flash is available as the current stable Flash model', () {
      final model = AppConfig.getModelById('gemini-3.5-flash');

      expect(model.modelName, equals('gemini-3.5-flash'));
      expect(model.isPreview, isFalse);
      expect(model.displayName, equals('Gemini 3.5 Flash'));
      expect(model.thinkingLevel, equals(GeminiThinkingLevel.minimal));
      expect(model.supportedThinkingLevels, contains(GeminiThinkingLevel.high));
    });

    test('model list excludes deprecated Gemini 2.0 variants', () {
      expect(
        AppConfig.availableModels.map((model) => model.id),
        isNot(containsAll(['gemini-2.0-flash', 'gemini-2.0-flash-lite'])),
      );
    });

    test('Gemini 3.1 Flash-Lite uses the stable model id', () {
      final model = AppConfig.getModelById('gemini-3.1-flash-lite');

      expect(model.modelName, equals('gemini-3.1-flash-lite'));
      expect(model.isPreview, isFalse);
      expect(model.displayName, equals('Gemini 3.1 Flash Lite'));
      expect(model.supportedThinkingLevels, contains(GeminiThinkingLevel.high));
    });
  });
}
