import 'package:beeamvo/services/recording_start_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'release during startup processes immediately when startup completes',
    () {
      final gate = RecordingStartGate()..begin();
      expect(gate.requestProcessing(), isTrue);
      expect(gate.finish(canProcess: true), isTrue);
      expect(gate.isStarting, isFalse);
      expect(gate.finish(canProcess: true), isFalse);
    },
  );

  test('repeated stop requests coalesce into one processing action', () {
    final gate = RecordingStartGate()..begin();
    gate.requestProcessing();
    gate.requestProcessing();
    expect(gate.finish(canProcess: true), isTrue);
    expect(gate.finish(canProcess: true), isFalse);
  });

  test('failed or cancelled starts never process or leak pending requests', () {
    final gate = RecordingStartGate()..begin();
    gate.requestProcessing();
    expect(gate.finish(canProcess: false), isFalse);
    gate.begin();
    expect(gate.finish(canProcess: true), isFalse);
  });

  test('stop after startup is not delayed by the gate', () {
    final gate = RecordingStartGate();
    expect(gate.requestProcessing(), isFalse);
    gate.begin();
    expect(gate.finish(canProcess: true), isFalse);
    expect(gate.requestProcessing(), isFalse);
  });
}
