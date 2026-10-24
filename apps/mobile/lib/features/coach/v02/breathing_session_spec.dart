/// What a player session is: its title, its time line, its pattern and length.
library;

import 'package:flutter/foundation.dart';
import 'package:healthee/data/basics/breathing/breathing_pattern.dart';
import 'package:healthee/data/basics/breathing/breathing_plan.dart';
import 'package:healthee/data/basics/breathing/breathing_settings.dart';
import 'package:healthee/features/coach/v02/breathing_format.dart';

/// Minutes in a session started from the pattern list.
const int kAdHocMinutes = 5;

/// One session to run.
@immutable
class BreathingSessionSpec {
  /// A session. Prefer [resolveBreathingSession].
  const BreathingSessionSpec({
    required this.title,
    required this.subtitle,
    required this.pattern,
    required this.minutes,
    this.kind,
  });

  /// The header's name.
  final String title;

  /// Under the title: time and length.
  final String subtitle;

  /// The pattern it opens with.
  final BreathPattern pattern;

  /// Planned minutes.
  final int minutes;

  /// The plan item it belongs to, or null for an ad hoc session.
  final BreathingItemKind? kind;
}

/// The session for a plan item named [item] (a `BreathingItemKind` name) or a
/// pattern with id [patternId]; null when neither is known.
///
/// [plan] may be null (still loading or failed): the item's time is then left
/// out of the subtitle rather than guessed.
BreathingSessionSpec? resolveBreathingSession({
  required BreathingSettings settings,
  BreathingPlan? plan,
  String? item,
  String? patternId,
}) {
  if (item != null) {
    for (final kind in BreathingItemKind.values) {
      if (kind.name != item) continue;
      final planned = plan?.item(kind);
      return BreathingSessionSpec(
        title: playerTitle(kind),
        subtitle: planned == null ? '${kind.minutes} min' : itemWhen(planned),
        pattern: settings.patternFor(kind),
        minutes: kind.minutes,
        kind: kind,
      );
    }
    return null;
  }
  final pattern = patternId == BreathPattern.customId
      ? settings.custom
      : patternId == null
      ? null
      : presetById(patternId);
  if (pattern == null) return null;
  return BreathingSessionSpec(
    title: pattern.name,
    subtitle: '$kAdHocMinutes min session',
    pattern: pattern,
    minutes: kAdHocMinutes,
  );
}
