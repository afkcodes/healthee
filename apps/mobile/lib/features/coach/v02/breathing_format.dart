/// Words and small shared pieces for the breathing card, plan and player.
///
/// Copy is sentence case. Nothing here makes a health claim: the only claim in
/// the feature is the one the evidence chip names, and it comes from the
/// pattern's own evidence record.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/dimensions.dart';
import 'package:healthee/core/theme/tokens.dart';
import 'package:healthee/core/theme/tone_scope.dart';
import 'package:healthee/core/theme/type_ladder.dart';
import 'package:healthee/data/basics/breathing/breathing_pattern.dart';
import 'package:healthee/data/basics/breathing/breathing_plan.dart';

/// "8:30" and "am" for a clock minute, the way the card sets them.
({String time, String meridiem}) clockParts(int minuteOfDay) {
  final hour = minuteOfDay ~/ 60;
  final hour12 = hour % 12 == 0 ? 12 : hour % 12;
  return (
    time: '$hour12:${(minuteOfDay % 60).toString().padLeft(2, '0')}',
    meridiem: hour < 12 ? 'am' : 'pm',
  );
}

/// "8:30 am".
String clockLabel(int minuteOfDay) {
  final parts = clockParts(minuteOfDay);
  return '${parts.time} ${parts.meridiem}';
}

/// "Steady · 5 in, 5 out" or "Box · 4, 4, 4, 4".
String patternLine(BreathPattern pattern) =>
    '${pattern.name} · ${pattern.counts}';

/// The words for a small count in a sentence.
String countWord(int count) {
  const words = <String>['no', 'one', 'two', 'three', 'four', 'five', 'six'];
  return count >= 0 && count < words.length ? words[count] : '$count';
}

/// The player's title for a plan item.
String playerTitle(BreathingItemKind kind) => switch (kind) {
  BreathingItemKind.morning => 'Morning breathing',
  BreathingItemKind.midday => 'Midday reset',
  BreathingItemKind.night => 'Night wind-down',
  BreathingItemKind.onDemand => 'If you wake',
};

/// The item's time and length: "10:15 pm · 10 min", "On demand · 5 min".
String itemWhen(BreathingItem item) {
  final minute = item.minuteOfDay;
  final when = minute == null ? 'On demand' : clockLabel(minute);
  return '$when · ${item.minutes} min';
}

/// The evidence chip's words: the grade and note id, or the plain absence.
String evidenceLabel(BreathEvidence evidence) {
  final grade = evidence.grade;
  final note = evidence.noteId;
  return grade == null || note == null ? 'Not in our base' : '$grade · $note';
}

/// A pill in the enclosing tone's soft fill: "Breathing".
class ToneChip extends StatelessWidget {
  /// A chip reading [label].
  const ToneChip(this.label, {super.key});

  /// The word.
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.familySoft,
      borderRadius: BorderRadius.circular(Radii.pill),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.md,
        vertical: Insets.xs,
      ),
      child: Text(
        label,
        style: TypeLadder.calloutStrong.copyWith(color: context.family),
      ),
    ),
  );
}

/// The quiet chip: a pattern's evidence, or that it has none.
class EvidenceChip extends StatelessWidget {
  /// A chip for [evidence].
  const EvidenceChip(this.evidence, {super.key});

  /// What the knowledge base says.
  final BreathEvidence evidence;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: context.colors.surface2,
      borderRadius: BorderRadius.circular(Radii.pill),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.md,
        vertical: Insets.xs,
      ),
      child: Text(
        evidenceLabel(evidence),
        style: TypeLadder.caption.copyWith(color: context.colors.ink2),
      ),
    ),
  );
}
