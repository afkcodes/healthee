import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/basics/breathing/breathing_pattern.dart';

void main() {
  test('cycle seconds and breaths for the presets', () {
    expect(kSteady.cycleSeconds, 10);
    expect(kSteady.breathsPerMinute, 6);
    expect(kSteady.breathsIn(1), 6);
    expect(kLongExhale.cycleSeconds, 10);
    expect(kLongExhale.breathsIn(10), 60);
    expect(kBox.cycleSeconds, 16);
    expect(kBox.breathsIn(4), 15);
    expect(kFourSevenEight.cycleSeconds, 19);
    expect(kFourSevenEight.breathsIn(5), 15);
  });

  test('timeline offsets, leaving out zero-length holds', () {
    expect(kLongExhale.timeline, const [
      BreathPhase(kind: BreathPhaseKind.inhale, startSeconds: 0, seconds: 4),
      BreathPhase(kind: BreathPhaseKind.exhale, startSeconds: 4, seconds: 6),
    ]);
    expect([for (final p in kBox.timeline) p.startSeconds], [0, 4, 8, 12]);
    expect(kFourSevenEight.timeline.length, 3);
  });

  test('phaseAt wraps each cycle', () {
    expect(kLongExhale.phaseAt(3).kind, BreathPhaseKind.inhale);
    expect(kLongExhale.phaseAt(4).kind, BreathPhaseKind.exhale);
    expect(kLongExhale.phaseAt(10).kind, BreathPhaseKind.inhale);
    expect(kBox.phaseAt(13).kind, BreathPhaseKind.holdEmpty);
  });

  test('only the two slow presets cite the note, at its grade', () {
    expect(kSteady.evidence.noteId, 'slow_breathing_hrv_acute');
    expect(kSteady.evidence.grade, 'Established');
    expect(kLongExhale.evidence.noteId, 'slow_breathing_hrv_acute');
    expect(kBox.evidence.isCited, isFalse);
    expect(kFourSevenEight.evidence.isCited, isFalse);
    expect(kBox.evidence, isA<NotInOurBase>());
    final custom = BreathPattern.custom(
      inSeconds: 4,
      hold1Seconds: 0,
      outSeconds: 4,
      hold2Seconds: 0,
    );
    expect(custom.evidence.isCited, isFalse);
  });

  test('the cited note exists in the manifest with the stated grade', () {
    final text = File(
      '../../packages/knowledge/manifest.json',
    ).readAsStringSync();
    final entry = RegExp(
      '"grade": "(\\w+)",\\s*"id": "$kSlowBreathingNoteId"',
    ).firstMatch(text);
    expect(entry?.group(1), kSlowBreathingGrade);
  });

  test('custom counts are validated', () {
    BreathPattern make(int i, int h1, int o, int h2) => BreathPattern.custom(
      inSeconds: i,
      hold1Seconds: h1,
      outSeconds: o,
      hold2Seconds: h2,
    );
    expect(make(1, 0, 12, 12).cycleSeconds, 25);
    expect(() => make(0, 0, 4, 0), throwsFormatException);
    expect(() => make(13, 0, 4, 0), throwsFormatException);
    expect(() => make(4, 0, 0, 0), throwsFormatException);
    expect(() => make(4, -1, 4, 0), throwsFormatException);
    expect(() => make(4, 0, 4, 13), throwsFormatException);
  });

  test('presets are found by id and custom is not one', () {
    expect(presetById('box'), kBox);
    expect(presetById('custom'), isNull);
    expect(kBreathPresets.length, 4);
  });

  test('counts and dotted show only what is breathed', () {
    expect(kSteady.counts, '5 in, 5 out');
    expect(kSteady.dotted, '5·5');
    expect(kBox.counts, '4, 4, 4, 4');
    expect(kBox.dotted, '4·4·4·4');
    expect(kFourSevenEight.counts, '4, 7, 8');
    expect(kFourSevenEight.dotted, '4·7·8');
  });
}
