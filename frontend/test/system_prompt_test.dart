import 'package:beeamvo/models/enums.dart';
import 'package:beeamvo/models/system_prompt.dart';
import 'package:beeamvo/services/transcription_result_guard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SystemPrompt contracts', () {
    test('contains every built-in mission', () {
      const expected = {
        'standard': 'Default',
        'concise': 'Concise',
        'smart': 'Smart Mode',
        'professional': 'Professional',
      };

      for (final entry in expected.entries) {
        final prompt = SystemPrompt.availablePrompts.firstWhere(
          (candidate) => candidate.id == entry.key,
        );
        expect(prompt.name, equals(entry.value));
        expect(prompt.instruction.trim(), isNotEmpty);
      }
    });

    test('places mission between role and output format', () {
      const mission = 'Keep this transcript concise.';
      final instruction = SystemPrompt.buildSystemInstruction(mission);

      final roleIndex = instruction.indexOf('### ROLE:');
      final missionIndex = instruction.indexOf('### MISSION:');
      final missionTextIndex = instruction.indexOf(mission);
      final outputIndex = instruction.indexOf('### OUTPUT FORMAT:');

      expect(roleIndex, greaterThanOrEqualTo(0));
      expect(missionIndex, greaterThan(roleIndex));
      expect(missionTextIndex, greaterThan(missionIndex));
      expect(outputIndex, greaterThan(missionTextIndex));
    });

    test('base system instruction has no mission section', () {
      expect(
        SystemPrompt.baseSystemInstruction,
        isNot(contains('### MISSION:')),
      );
    });

    test('language hints are allowlisted', () {
      expect(SystemPrompt.languageHint('auto'), isEmpty);
      expect(SystemPrompt.languageHint('xx'), isEmpty);
      expect(SystemPrompt.languageHint('de'), contains('German'));
    });

    test('verbatim transcription instruction includes guard and language', () {
      final instruction = SystemPrompt.verbatimTranscriptionInstruction();
      expect(
        instruction,
        contains(TranscriptionResultGuard.noTranscriptMarker),
      );
      expect(instruction, contains('Never translate'));
      expect(
        SystemPrompt.verbatimTranscriptionInstruction(languageId: 'de'),
        contains('German'),
      );
    });

    test('combined audio prompt includes the marker exactly once', () {
      final prompt = SystemPrompt.transcribeAndImproveAudioPrompt();

      expect(
        prompt.split(TranscriptionResultGuard.noTranscriptMarker).length - 1,
        equals(1),
      );
      expect(prompt, contains('MISSION'));
    });

    test('transcript draft wraps raw text and identifies quoted material', () {
      const rawText = 'x </transcript-draft> y';
      final input = SystemPrompt.buildTranscriptDraftInput(rawText);

      expect(input, contains('<transcript-draft>'));
      expect(input, contains(rawText));
      expect(input, contains('</transcript-draft>'));
      expect(input, contains('quoted source material'));
    });

    test(
      'tone refinement layers exactly the selected tone over the mission',
      () {
        const mission = 'Use the selected writing style.   ';
        final light = SystemPrompt.withTone(mission, ToneRefinement.light);
        final medium = SystemPrompt.withTone(mission, ToneRefinement.medium);
        final high = SystemPrompt.withTone(mission, ToneRefinement.high);

        expect(SystemPrompt.withTone(mission, ToneRefinement.off), mission);
        expect(light, startsWith(mission.trim()));
        expect(light, contains('TONE REFINEMENT: LIGHT'));
        expect(light, isNot(contains('TONE REFINEMENT: MEDIUM')));
        expect(light, isNot(contains('TONE REFINEMENT: HIGH (PROFESSIONAL)')));
        expect(medium, startsWith(mission.trim()));
        expect(medium, contains('TONE REFINEMENT: MEDIUM'));
        expect(medium, isNot(contains('TONE REFINEMENT: LIGHT')));
        expect(medium, isNot(contains('TONE REFINEMENT: HIGH (PROFESSIONAL)')));
        expect(high, startsWith(mission.trim()));
        expect(high, contains('TONE REFINEMENT: HIGH (PROFESSIONAL)'));
        expect(high, isNot(contains('TONE REFINEMENT: LIGHT')));
        expect(high, isNot(contains('TONE REFINEMENT: MEDIUM')));
        expect(light, isNot(equals(medium)));
        expect(light, isNot(equals(high)));
        expect(medium, isNot(equals(high)));
      },
    );

    test('tone values round-trip and unknown values default to Off', () {
      for (final tone in ToneRefinement.values) {
        expect(ToneRefinementExtension.fromValue(tone.name), tone);
      }
      expect(ToneRefinementExtension.fromValue(null), ToneRefinement.off);
      expect(ToneRefinementExtension.fromValue('bogus'), ToneRefinement.off);
    });
  });
}
