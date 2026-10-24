import 'package:flutter_test/flutter_test.dart';
import 'package:healthee/data/basics/breathing/breathing_pattern.dart';
import 'package:healthee/data/basics/breathing/breathing_progress.dart';

BreathProgress at(BreathPattern p, int minutes, double seconds) =>
    breathProgressAt(
      p,
      minutes,
      Duration(microseconds: (seconds * 1e6).round()),
    );

void main() {
  test('the start is breathing in, the full count, the first breath', () {
    final p = at(kLongExhale, 10, 0);
    expect(p.phase.kind, BreathPhaseKind.inhale);
    expect(p.countdown, 4);
    expect(p.breath, 1);
    expect(p.totalBreaths, 60);
    expect(p.leftLabel, '10:00');
    expect(p.scale, kBreathMinScale);
    expect(p.finished, isFalse);
  });

  test('phases change on the boundary and the countdown rounds up', () {
    expect(at(kLongExhale, 10, 3.2).countdown, 1);
    final out = at(kLongExhale, 10, 4);
    expect(out.phase.kind, BreathPhaseKind.exhale);
    expect(out.countdown, 6);
    expect(at(kLongExhale, 10, 8.5).countdown, 2);
    expect(at(kLongExhale, 10, 10).phase.kind, BreathPhaseKind.inhale);
  });

  test('breath count and time left follow the elapsed time', () {
    final p = at(kLongExhale, 10, 234);
    expect(p.breath, 24);
    expect(p.phase.kind, BreathPhaseKind.exhale);
    expect(p.leftLabel, '6:06');
    expect(p.fraction, closeTo(0.39, 1e-9));
  });

  test('the scale grows in, holds, shrinks out and holds', () {
    expect(at(kBox, 4, 2).scale, greaterThan(kBreathMinScale));
    expect(at(kBox, 4, 2).scale, lessThan(1));
    expect(at(kBox, 4, 5).scale, 1);
    expect(at(kBox, 4, 10).scale, lessThan(1));
    expect(at(kBox, 4, 13).scale, kBreathMinScale);
  });

  test('a session that does not divide evenly caps the breath count', () {
    final p = at(kFourSevenEight, 5, 299);
    expect(p.totalBreaths, 15);
    expect(p.breath, 15);
  });

  test('the end is finished with nothing left', () {
    final p = at(kSteady, 5, 400);
    expect(p.finished, isTrue);
    expect(p.remaining, Duration.zero);
    expect(p.leftLabel, '0:00');
    expect(p.fraction, 1);
  });
}
