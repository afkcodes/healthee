/// Breathing patterns: the counts, the evidence behind them, and the timeline
/// the player will draw.
///
/// ## Evidence
///
/// Only two presets cite the knowledge base, and both cite the same note,
/// `slow_breathing_hrv_acute` (Established): breathing near six breaths a
/// minute raises HRV while you do it. The claim stops there. The note's own
/// honesty section says the effect is mostly within the session and that a
/// higher baseline over weeks is smaller and less certain, so no pattern here
/// promises one. Box and 4-7-8 are not in the knowledge base and carry no
/// citation and no health claim, which is what [BreathEvidence.notInOurBase]
/// means.
library;

import 'package:meta/meta.dart';

/// What the knowledge base says about a pattern.
@immutable
sealed class BreathEvidence {
  const BreathEvidence();

  /// The note id this pattern cites, or null when it cites nothing.
  String? get noteId;

  /// The note's evidence grade as the manifest spells it, or null.
  String? get grade;

  /// Whether the pattern has a citation.
  bool get isCited => noteId != null;
}

/// Backed by a real note, at that note's own grade.
final class EstablishedEvidence extends BreathEvidence {
  /// A citation of [noteId] graded [grade].
  const EstablishedEvidence({required this.noteId, required this.grade});

  @override
  final String noteId;

  @override
  final String grade;
}

/// Not in our research base: no citation, no health claim.
final class NotInOurBase extends BreathEvidence {
  /// The single uncited state.
  const NotInOurBase();

  @override
  String? get noteId => null;

  @override
  String? get grade => null;
}

/// The note the two slow-breathing presets cite.
const String kSlowBreathingNoteId = 'slow_breathing_hrv_acute';

/// Its grade in `packages/knowledge/manifest.json`.
const String kSlowBreathingGrade = 'Established';

const BreathEvidence _slowBreathing = EstablishedEvidence(
  noteId: kSlowBreathingNoteId,
  grade: kSlowBreathingGrade,
);

/// The footnote the plan screen shows under the pattern list.
const String kBreathingFootnote =
    'Slow breathing lifts HRV during the session. '
    "It doesn't promise a higher baseline over weeks.";

/// One of the four moments of a breath.
enum BreathPhaseKind {
  /// Breathing in.
  inhale('Breathe in', 'In'),

  /// Holding after the in-breath.
  holdFull('Hold', 'Hold'),

  /// Breathing out.
  exhale('Breathe out', 'Out'),

  /// Holding after the out-breath.
  holdEmpty('Hold', 'Hold');

  const BreathPhaseKind(this.prompt, this.shortLabel);

  /// The words the player shows in the circle.
  final String prompt;

  /// The words under the phase bar.
  final String shortLabel;
}

/// One phase of a cycle with where it starts.
@immutable
class BreathPhase {
  /// A phase of [seconds] starting [startSeconds] into the cycle.
  const BreathPhase({
    required this.kind,
    required this.startSeconds,
    required this.seconds,
  });

  /// Which phase.
  final BreathPhaseKind kind;

  /// Offset from the start of the cycle.
  final int startSeconds;

  /// Length, always at least one second.
  final int seconds;

  @override
  bool operator ==(Object other) =>
      other is BreathPhase &&
      other.kind == kind &&
      other.startSeconds == startSeconds &&
      other.seconds == seconds;

  @override
  int get hashCode => Object.hash(kind, startSeconds, seconds);

  @override
  String toString() => 'BreathPhase($kind, $startSeconds, $seconds)';
}

/// An immutable breathing pattern.
@immutable
class BreathPattern {
  /// A pattern. Prefer the presets and [BreathPattern.custom].
  const BreathPattern({
    required this.id,
    required this.name,
    required this.inSeconds,
    required this.hold1Seconds,
    required this.outSeconds,
    required this.hold2Seconds,
    required this.evidence,
    required this.blurb,
  });

  /// A pattern with the owner's own counts.
  ///
  /// In and out must be 1 to 12 seconds. Holds may be 0 to 12 (no hold is a
  /// real choice). Throws [FormatException] with the reason otherwise.
  factory BreathPattern.custom({
    required int inSeconds,
    required int hold1Seconds,
    required int outSeconds,
    required int hold2Seconds,
  }) {
    final problem = validateCustom(
      inSeconds: inSeconds,
      hold1Seconds: hold1Seconds,
      outSeconds: outSeconds,
      hold2Seconds: hold2Seconds,
    );
    if (problem != null) throw FormatException(problem);
    return BreathPattern(
      id: customId,
      name: 'Custom',
      inSeconds: inSeconds,
      hold1Seconds: hold1Seconds,
      outSeconds: outSeconds,
      hold2Seconds: hold2Seconds,
      evidence: const NotInOurBase(),
      blurb: 'Your own in, hold and out counts.',
    );
  }

  /// The reason these counts are refused, or null when they are fine.
  static String? validateCustom({
    required int inSeconds,
    required int hold1Seconds,
    required int outSeconds,
    required int hold2Seconds,
  }) {
    if (inSeconds < 1 || inSeconds > 12 || outSeconds < 1 || outSeconds > 12) {
      return 'Breathing in and out each take 1 to 12 seconds.';
    }
    if (hold1Seconds < 0 ||
        hold1Seconds > 12 ||
        hold2Seconds < 0 ||
        hold2Seconds > 12) {
      return 'Holds take 0 to 12 seconds.';
    }
    return null;
  }

  /// Stable id used in settings.
  final String id;

  /// The name shown to the owner.
  final String name;

  /// Seconds breathing in.
  final int inSeconds;

  /// Seconds held after the in-breath.
  final int hold1Seconds;

  /// Seconds breathing out.
  final int outSeconds;

  /// Seconds held after the out-breath.
  final int hold2Seconds;

  /// What the knowledge base says.
  final BreathEvidence evidence;

  /// One line for the pattern list.
  final String blurb;

  /// The id of the custom pattern.
  static const String customId = 'custom';

  /// Seconds in one full breath.
  int get cycleSeconds => inSeconds + hold1Seconds + outSeconds + hold2Seconds;

  /// Whole breaths that fit in [minutes] minutes.
  int breathsIn(int minutes) => minutes * 60 ~/ cycleSeconds;

  /// Breaths per minute, as a number to compare with the note's six.
  double get breathsPerMinute => 60 / cycleSeconds;

  /// The phases of one cycle in order; a zero-length hold is left out.
  List<BreathPhase> get timeline {
    final phases = <BreathPhase>[];
    var at = 0;
    void add(BreathPhaseKind kind, int seconds) {
      if (seconds <= 0) return;
      phases.add(BreathPhase(kind: kind, startSeconds: at, seconds: seconds));
      at += seconds;
    }

    add(BreathPhaseKind.inhale, inSeconds);
    add(BreathPhaseKind.holdFull, hold1Seconds);
    add(BreathPhaseKind.exhale, outSeconds);
    add(BreathPhaseKind.holdEmpty, hold2Seconds);
    return phases;
  }

  /// The phase running [secondsIn] seconds into a session, wrapping each cycle.
  BreathPhase phaseAt(int secondsIn) {
    final inCycle = secondsIn % cycleSeconds;
    return timeline.lastWhere((phase) => phase.startSeconds <= inCycle);
  }

  /// The counts to show: in and out alone with no holds, in, hold and out when
  /// only the second hold is zero (4-7-8), else all four.
  List<int> get _shown {
    if (hold1Seconds == 0 && hold2Seconds == 0) {
      return [inSeconds, outSeconds];
    }
    return hold2Seconds == 0
        ? [inSeconds, hold1Seconds, outSeconds]
        : [inSeconds, hold1Seconds, outSeconds, hold2Seconds];
  }

  /// "5 in, 5 out" or "4, 4, 4, 4" style counts for a subtitle.
  String get counts => hold1Seconds == 0 && hold2Seconds == 0
      ? '$inSeconds in, $outSeconds out'
      : _shown.join(', ');

  /// The counts as shown on a pattern row, joined with a middle dot.
  String get dotted => _shown.join('·');

  @override
  bool operator ==(Object other) =>
      other is BreathPattern &&
      other.id == id &&
      other.inSeconds == inSeconds &&
      other.hold1Seconds == hold1Seconds &&
      other.outSeconds == outSeconds &&
      other.hold2Seconds == hold2Seconds;

  @override
  int get hashCode =>
      Object.hash(id, inSeconds, hold1Seconds, outSeconds, hold2Seconds);

  @override
  String toString() => 'BreathPattern($id, $dotted)';
}

/// Five in, five out: six breaths a minute.
const BreathPattern kSteady = BreathPattern(
  id: 'steady',
  name: 'Steady',
  inSeconds: 5,
  hold1Seconds: 0,
  outSeconds: 5,
  hold2Seconds: 0,
  evidence: _slowBreathing,
  blurb: 'Six breaths a minute. Raises HRV while you do it.',
);

/// Four in, six out: the same ten-second pace with a longer out-breath.
const BreathPattern kLongExhale = BreathPattern(
  id: 'long_exhale',
  name: 'Long exhale',
  inSeconds: 4,
  hold1Seconds: 0,
  outSeconds: 6,
  hold2Seconds: 0,
  evidence: _slowBreathing,
  blurb: 'Same pace, longer out-breath. For winding down.',
);

/// Four, four, four, four.
const BreathPattern kBox = BreathPattern(
  id: 'box',
  name: 'Box',
  inSeconds: 4,
  hold1Seconds: 4,
  outSeconds: 4,
  hold2Seconds: 4,
  evidence: NotInOurBase(),
  blurb: 'In, hold, out, hold. Reset between tasks.',
);

/// Four in, seven held, eight out.
const BreathPattern kFourSevenEight = BreathPattern(
  id: 'four_seven_eight',
  name: '4-7-8',
  inSeconds: 4,
  hold1Seconds: 7,
  outSeconds: 8,
  hold2Seconds: 0,
  evidence: NotInOurBase(),
  blurb: 'Popular for falling asleep. Short sessions only.',
);

/// The four fixed presets in display order. Custom is built from settings.
const List<BreathPattern> kBreathPresets = [
  kSteady,
  kLongExhale,
  kBox,
  kFourSevenEight,
];

/// The preset with [id], or null (custom is not a preset).
BreathPattern? presetById(String id) {
  for (final pattern in kBreathPresets) {
    if (pattern.id == id) return pattern;
  }
  return null;
}
