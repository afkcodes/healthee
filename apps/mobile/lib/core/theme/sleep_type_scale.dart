/// The Sleep screen's own v02 roles, each an alias of a `type_ladder.dart` step.
///
/// These belong with [TypeScale] and are only in a second file because that one
/// sat at the standards' 400-line ceiling when they were written. Every entry
/// names the `richer.css` rule it came from, the same way `TypeScale`'s do, and
/// a call site uses whichever of the two files has the role it needs.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/type_ladder.dart';

/// The Sleep screen's type, on the ladder.
abstract final class SleepType {
  /// `.sleep-reading .big-duration` — the night's headline figure.
  static final TextStyle duration = TypeLadder.display;

  /// The same figure under the prototype's 359 px breakpoint. The prototype
  /// dropped to 54 px there; 54 snaps to the same display step, so the two are
  /// one size now and the name is kept for the call site that chooses.
  static final TextStyle durationNarrow = TypeLadder.display;

  /// The `h` and the `min` beside the headline figure: a unit is 13 px, set in
  /// ink3 by the caller (the brief; the prototype set them at 22 in the family).
  static final TextStyle durationUnit = TypeLadder.callout;

  /// `.sleep-device strong` — the strap's own score.
  static final TextStyle deviceScore = TypeLadder.title1;

  /// `.sleep-device span` — the two lines naming that instrument.
  static final TextStyle deviceCaption = TypeLadder.caption;

  /// `.sleep-check h3` — one check's name.
  static final TextStyle checkName = TypeLadder.calloutStrong;

  /// `.sleep-check strong` — its reading.
  static final TextStyle checkValue = TypeLadder.calloutStrong;

  /// `.check-target` — the published range it was read against.
  static final TextStyle checkTarget = TypeLadder.caption;

  /// `.check-detail` — how far outside it, in words.
  static final TextStyle checkDetail = TypeLadder.caption;

  /// `.data-table th` and `td`.
  static final TextStyle tableCell = TypeLadder.caption;

  /// The stage duration on a share row — the number the reader came for, so it
  /// is the largest thing on its line rather than one cell of a table.
  static final TextStyle shareDuration = TypeLadder.headline;

  /// `.vital-row .vital-label`.
  static final TextStyle vitalLabel = TypeLadder.caption;

  /// `.vital-row strong`.
  static final TextStyle vitalValue = TypeLadder.calloutStrong;

  /// `.vital-row strong small`.
  static final TextStyle vitalUnit = TypeLadder.caption;

  /// Below this width the prototype dropped the duration to 54 px.
  static const double narrowWidth = 360;
}
