/// Where a breathing session is, as a pure function of the elapsed time.
///
/// The player keeps no counters of its own: it asks this for the phase, the
/// countdown, the breath count and the sphere's scale at the time the clock
/// shows. That is what makes the timeline testable with fake time and keeps a
/// paused session exactly where it stopped.
library;

import 'dart:math' as math;

import 'package:healthee/data/basics/breathing/breathing_pattern.dart';
import 'package:meta/meta.dart';

/// The sphere's scale with the lungs empty; full is 1.
const double kBreathMinScale = 0.72;

const int _micros = Duration.microsecondsPerSecond;

/// One moment of a session.
@immutable
class BreathProgress {
  /// A moment. Built by [breathProgressAt].
  const BreathProgress({
    required this.phase,
    required this.phaseIndex,
    required this.countdown,
    required this.phaseFraction,
    required this.breath,
    required this.totalBreaths,
    required this.remaining,
    required this.fraction,
    required this.scale,
    required this.finished,
  });

  /// The phase running now.
  final BreathPhase phase;

  /// Its place in the pattern's timeline.
  final int phaseIndex;

  /// Whole seconds left in the phase, counting down to 1.
  final int countdown;

  /// How far through the phase, 0 to 1.
  final double phaseFraction;

  /// The breath under way, from 1.
  final int breath;

  /// Whole breaths in the session.
  final int totalBreaths;

  /// Time left in the session.
  final Duration remaining;

  /// How far through the session, 0 to 1.
  final double fraction;

  /// The sphere's scale: it grows in, holds, shrinks out and holds.
  final double scale;

  /// Whether the planned time is used up.
  final bool finished;

  /// The time left as the player writes it, rounded up: `6:10`.
  String get leftLabel {
    final seconds = (remaining.inMicroseconds + _micros - 1) ~/ _micros;
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }
}

double _ease(double t) => 0.5 - 0.5 * math.cos(math.pi * t);

/// The session of [plannedMinutes] with [pattern], [elapsed] in.
BreathProgress breathProgressAt(
  BreathPattern pattern,
  int plannedMinutes,
  Duration elapsed,
) {
  final plannedUs = plannedMinutes * 60 * _micros;
  final us = elapsed.inMicroseconds.clamp(0, plannedUs);
  final cycleUs = pattern.cycleSeconds * _micros;
  final inCycle = us % cycleUs;
  final timeline = pattern.timeline;
  var index = 0;
  for (var i = 0; i < timeline.length; i++) {
    if (timeline[i].startSeconds * _micros <= inCycle) index = i;
  }
  final phase = timeline[index];
  final intoPhase = inCycle - phase.startSeconds * _micros;
  final phaseUs = phase.seconds * _micros;
  final fraction = intoPhase / phaseUs;
  final scale = switch (phase.kind) {
    BreathPhaseKind.inhale =>
      kBreathMinScale + (1 - kBreathMinScale) * _ease(fraction),
    BreathPhaseKind.exhale => 1 - (1 - kBreathMinScale) * _ease(fraction),
    BreathPhaseKind.holdFull => 1.0,
    BreathPhaseKind.holdEmpty => kBreathMinScale,
  };
  final total = math.max(1, pattern.breathsIn(plannedMinutes));
  return BreathProgress(
    phase: phase,
    phaseIndex: index,
    countdown: ((phaseUs - intoPhase + _micros - 1) ~/ _micros).clamp(
      1,
      phase.seconds,
    ),
    phaseFraction: fraction,
    breath: math.min(total, us ~/ cycleUs + 1),
    totalBreaths: total,
    remaining: Duration(microseconds: plannedUs - us),
    fraction: us / plannedUs,
    scale: scale,
    finished: us >= plannedUs,
  );
}
