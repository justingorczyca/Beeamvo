import 'package:beeamvo/config.dart';
import 'package:beeamvo/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GeminiModelConfig', () {
    test('thinkingConfig returns budget for Gemini 2.x style models', () {
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

    test(
      'resolveThinkingLevel clamps unsupported overrides to the default',
      () {
        const model = GeminiModelConfig(
          id: 'test-3-7',
          name: 'Test 3.7',
          modelName: 'gemini-3.7-flash',
          thinkingLevel: GeminiThinkingLevel.medium,
          supportedThinkingLevels: [
            GeminiThinkingLevel.low,
            GeminiThinkingLevel.medium,
            GeminiThinkingLevel.high,
          ],
        );

        expect(
          model.resolveThinkingLevel(
            levelOverride: GeminiThinkingLevel.minimal,
          ),
          equals(GeminiThinkingLevel.medium),
        );
        expect(
          model.resolveThinkingLevel(levelOverride: GeminiThinkingLevel.high),
          equals(GeminiThinkingLevel.high),
        );
      },
    );

    test('resolveThinkingLevel falls back to the lowest supported level when '
        'forceMinimal is true and minimal is unavailable', () {
      const model = GeminiModelConfig(
        id: 'test-3-7',
        name: 'Test 3.7',
        modelName: 'gemini-3.7-flash',
        thinkingLevel: GeminiThinkingLevel.medium,
        supportedThinkingLevels: [
          GeminiThinkingLevel.low,
          GeminiThinkingLevel.medium,
          GeminiThinkingLevel.high,
        ],
      );

      expect(
        model.resolveThinkingLevel(forceMinimal: true),
        equals(GeminiThinkingLevel.low),
      );
    });
  });

  group('AppConfig defaults', () {
    test('default model is Gemini 3.5 Flash Lite', () {
      expect(AppConfig.defaultModelId, equals('gemini-3.5-flash-lite'));

      final defaultModel = AppConfig.getModelById(AppConfig.defaultModelId);
      expect(defaultModel.modelName, equals('gemini-3.5-flash-lite'));
      expect(defaultModel.isPreview, isFalse);
      expect(defaultModel.vertexLocation, equals('global'));
    });

    group('resolveRefinementModelId', () {
      test('falls back to the default when no id was ever saved', () {
        expect(
          AppConfig.resolveRefinementModelId(null),
          equals(AppConfig.defaultModelId),
        );
      });

      test('falls back to the default for a transcription-only model', () {
        expect(
          AppConfig.resolveRefinementModelId('gemini-3.5-transcribe'),
          equals(AppConfig.defaultModelId),
        );
      });

      test('keeps a valid prompt-capable model id untouched', () {
        final kept = AppConfig.resolveRefinementModelId('gemini-3.6-flash');
        expect(kept, equals('gemini-3.6-flash'));
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

    test('Gemini 3 Flash preview defaults to minimal thinking', () {
      final previewModel = AppConfig.availableModels.firstWhere(
        (model) => model.id == 'gemini-3-flash',
      );

      expect(previewModel.isPreview, isTrue);
      expect(previewModel.supportedThinkingLevels, isNotEmpty);
      expect(previewModel.thinkingLevel, equals(GeminiThinkingLevel.minimal));
    });

    test('Gemini 3.5 Flash is available as a stable Flash model', () {
      final model = AppConfig.getModelById('gemini-3.5-flash');

      expect(model.modelName, equals('gemini-3.5-flash'));
      expect(model.isPreview, isFalse);
      expect(model.displayName, equals('Gemini 3.5 Flash'));
      expect(model.thinkingLevel, equals(GeminiThinkingLevel.minimal));
      expect(model.supportedThinkingLevels, contains(GeminiThinkingLevel.high));
    });

    test('Gemini 3.6 Flash is available as the recommended replacement '
        'for Gemini 2.5 Flash', () {
      final model = AppConfig.getModelById('gemini-3.6-flash');

      expect(model.modelName, equals('gemini-3.6-flash'));
      expect(model.isPreview, isFalse);
      expect(model.displayName, equals('Gemini 3.6 Flash'));
      expect(model.thinkingLevel, equals(GeminiThinkingLevel.minimal));
      expect(
        model.supportedThinkingLevels,
        contains(GeminiThinkingLevel.minimal),
      );
    });

    test(
      'Gemini 3.7 Flash defaults to low thinking and does not support minimal',
      () {
        final model = AppConfig.getModelById('gemini-3.7-flash');

        expect(model.modelName, equals('gemini-3.7-flash'));
        expect(model.isPreview, isFalse);
        expect(model.vertexLocation, equals('global'));
        expect(model.thinkingLevel, equals(GeminiThinkingLevel.low));
        expect(
          model.supportedThinkingLevels,
          equals([
            GeminiThinkingLevel.low,
            GeminiThinkingLevel.medium,
            GeminiThinkingLevel.high,
          ]),
        );
      },
    );

    test(
      'model list retains live stable models but excludes shut-down variants',
      () {
        final ids = AppConfig.availableModels.map((model) => model.id);
        expect(
          ids,
          containsAll([
            'gemini-2.5-flash',
            'gemini-2.5-flash-lite',
            'gemini-3.1-flash-lite',
            'gemini-3.5-transcribe',
          ]),
        );
        for (final retired in [
          'gemini-2.0-flash',
          'gemini-2.0-flash-lite',
          'gemini-3.1-flash-lite-preview',
        ]) {
          expect(ids, isNot(contains(retired)));
        }
      },
    );

    test(
      'Gemini 3.5 Flash Lite is the default and supports all thinking levels',
      () {
        final model = AppConfig.getModelById('gemini-3.5-flash-lite');

        expect(model.modelName, equals('gemini-3.5-flash-lite'));
        expect(model.isPreview, isFalse);
        expect(model.displayName, equals('Gemini 3.5 Flash Lite'));
        expect(model.thinkingLevel, equals(GeminiThinkingLevel.minimal));
        expect(
          model.supportedThinkingLevels,
          contains(GeminiThinkingLevel.high),
        );
      },
    );
  });

  group('OpenAI and Codex catalogs', () {
    test('none thinking level parses but is not offered by Gemini models', () {
      expect(
        GeminiThinkingLevelExtension.fromString('NONE'),
        equals(GeminiThinkingLevel.none),
      );
      for (final model in AppConfig.availableModels) {
        expect(
          model.supportedThinkingLevels,
          isNot(contains(GeminiThinkingLevel.none)),
        );
      }
    });

    test('OpenAI and Codex catalogs use shared family ids, not codex ids', () {
      for (final model in [
        ...AppConfig.openAiModels,
        ...AppConfig.codexModels,
      ]) {
        expect(model.id.contains('codex'), isFalse);
      }
      expect(
        AppConfig.codexModels.map((model) => model.id).toList(),
        equals([
          'gpt-6-astra',
          'gpt-6-sol',
          'gpt-6-luna',
          'gpt-5.6-sol',
          'gpt-5.6-terra',
          'gpt-5.6-luna',
          'gpt-5-6-thinking',
          'gpt-5.5',
          'gpt-5.4',
          'chat-latest',
        ]),
      );
    });

    test('GPT-6 Sol and Luna are polish models for OpenAI and ChatGPT', () {
      for (final provider in const [
        CloudProvider.openaiApiKey,
        CloudProvider.codexOAuth,
      ]) {
        final ids = AppConfig.promptCapableModelsForProvider(
          provider,
        ).map((m) => m.id);
        expect(ids, containsAll(['gpt-6-sol', 'gpt-6-luna']));
        expect(AppConfig.audioModelsForProvider(provider), isEmpty);
      }
      final sol = AppConfig.getModelById('gpt-6-sol');
      final luna = AppConfig.getModelById('gpt-6-luna');
      expect(sol.displayName, 'GPT-6 Sol');
      expect(luna.displayName, 'GPT-6 Luna');
      for (final model in [sol, luna]) {
        expect(model.supportsAudio, isFalse);
        expect(model.supportedThinkingLevels, [
          GeminiThinkingLevel.none,
          GeminiThinkingLevel.low,
          GeminiThinkingLevel.medium,
          GeminiThinkingLevel.high,
          GeminiThinkingLevel.xhigh,
          GeminiThinkingLevel.max,
        ]);
      }
      expect(sol.resolveThinkingLevel(), GeminiThinkingLevel.low);
      expect(luna.resolveThinkingLevel(), GeminiThinkingLevel.none);
      expect(
        sol.resolveThinkingLevel(levelOverride: GeminiThinkingLevel.max),
        GeminiThinkingLevel.max,
      );
    });

    test('xhigh and max persist by name and follow the codgine catalog', () {
      expect(GeminiThinkingLevel.xhigh.apiValue, 'XHIGH');
      expect(GeminiThinkingLevel.max.apiValue, 'MAX');
      expect(
        GeminiThinkingLevelExtension.fromString('xhigh'),
        GeminiThinkingLevel.xhigh,
      );
      expect(
        GeminiThinkingLevelExtension.fromString('MAX'),
        GeminiThinkingLevel.max,
      );
      final withExtended = {
        for (final model in [
          ...AppConfig.availableModels,
          ...AppConfig.openAiModels,
          ...AppConfig.codexModels,
          ...AppConfig.grokModels,
        ])
          if (model.supportedThinkingLevels.any(
            (l) =>
                l == GeminiThinkingLevel.xhigh || l == GeminiThinkingLevel.max,
          ))
            model.id,
      };
      expect(withExtended, {
        'gpt-6-astra',
        'gpt-6-sol',
        'gpt-6-luna',
        'gpt-5.6-sol',
        'gpt-5.6-terra',
        'gpt-5.6-luna',
      });
      for (final id in const [
        'gpt-6-sol',
        'gpt-6-luna',
        'gpt-5.6-sol',
        'gpt-5.6-terra',
        'gpt-5.6-luna',
      ]) {
        expect(AppConfig.getModelById(id).supportedThinkingLevels, [
          GeminiThinkingLevel.none,
          GeminiThinkingLevel.low,
          GeminiThinkingLevel.medium,
          GeminiThinkingLevel.high,
          GeminiThinkingLevel.xhigh,
          GeminiThinkingLevel.max,
        ], reason: id);
      }
      // Astra cannot switch reasoning off.
      expect(AppConfig.getModelById('gpt-6-astra').supportedThinkingLevels, [
        GeminiThinkingLevel.low,
        GeminiThinkingLevel.medium,
        GeminiThinkingLevel.high,
        GeminiThinkingLevel.xhigh,
        GeminiThinkingLevel.max,
      ]);
    });
  });
}
