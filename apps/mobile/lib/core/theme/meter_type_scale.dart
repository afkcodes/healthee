/// The two meters v02 draws against a baseline, named after `charts.css`.
///
/// These belong with [TypeScale] and are only in a second file because that one
/// sat at the standards' 400-line ceiling when they were written. All three are
/// chart text — a meter's key, its reading, a comparison row's labels — so all
/// three are `type_ladder.dart`'s micro step, the one size kept for charts.
///
/// `.signal-row`'s own label is [TypeScale.factorRow] — the same rule on the
/// same kind of row — rather than a fourth entry here saying the same thing.
library;

import 'package:flutter/material.dart';
import 'package:healthee/core/theme/type_ladder.dart';

/// The type the baseline meters are set in.
abstract final class MeterType {
  /// `.signal-chart-key` — `Lower · Your baseline · Higher`.
  static final TextStyle signalKey = TypeLadder.micro;

  /// `.signal-row b` — the reading at the end of a signal row.
  static final TextStyle signalReading = TypeLadder.micro;

  /// `.comparison-row` — both of a comparison row's labels.
  static final TextStyle comparisonRow = TypeLadder.micro;
}
