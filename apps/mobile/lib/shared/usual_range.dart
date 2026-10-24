/// The owner's usual range: the middle half of their own last 14 days.
///
/// **The one definition.** Every "your usual" band on a screen, and every
/// "Below your usual" beside a reading, is this function's answer and nobody
/// else's (CLAUDE.md: one canonical definition per metric). It is a display
/// band, not a score and not a judgement of health.
///
///   * **The window** is the [kUsualWindowDays] calendar days BEFORE the day
///     being read. The day itself is left out: a band that contained today
///     could never say today was unusual.
///   * **The band** is the 25th to the 75th percentile of the readings in that
///     window, linearly interpolated. The middle half, so one odd night or one
///     long hike does not stretch it, and a person reads it as "half of my days
///     fell in here".
///   * **No band below [kUsualMinDays] readings.** Six numbers do not have a
///     middle half worth drawing; the bar says it is still learning instead.
///     Days without a reading are absent, never zero.
library;

import 'package:flutter/foundation.dart';
import 'package:healthee/data/models/trend_point.dart';

/// How far back the usual range looks, in calendar days.
const int kUsualWindowDays = 14;

/// The fewest readings in the window that make a band.
const int kUsualMinDays = 7;

/// The middle half of the owner's recent readings.
@immutable
class UsualRange {
  /// [low] ≤ [high]; [days] is how many readings the band was made from.
  const UsualRange({required this.low, required this.high, required this.days});

  /// The 25th percentile.
  final double low;

  /// The 75th percentile.
  final double high;

  /// How many readings it was made from.
  final int days;

  /// Where [value] sits against the band. The edges count as inside.
  UsualSide sideOf(double value) => value < low
      ? UsualSide.below
      : value > high
      ? UsualSide.above
      : UsualSide.within;

  @override
  bool operator ==(Object other) =>
      other is UsualRange &&
      other.low == low &&
      other.high == high &&
      other.days == days;

  @override
  int get hashCode => Object.hash(low, high, days);

  @override
  String toString() => 'UsualRange($low–$high, $days days)';
}

/// Where a reading sits against the owner's usual range.
enum UsualSide {
  /// Under the 25th percentile.
  below('Below your usual'),

  /// Inside the middle half, edges included.
  within('In your usual range'),

  /// Over the 75th percentile.
  above('Above your usual');

  const UsualSide(this.words);

  /// The verdict as the owner reads it.
  final String words;
}

/// The usual range of [values], or null when there are fewer than
/// [kUsualMinDays] of them.
UsualRange? usualRangeOf(Iterable<double> values) {
  final sorted = values.where((v) => v.isFinite).toList()..sort();
  if (sorted.length < kUsualMinDays) {
    return null;
  }
  return UsualRange(
    low: _quantile(sorted, 0.25),
    high: _quantile(sorted, 0.75),
    days: sorted.length,
  );
}

/// The readings of [points] in the [kUsualWindowDays] days before [day]
/// (`YYYY-MM-DD`), the day itself excluded.
Iterable<double> windowBefore(Iterable<TrendPoint> points, String day) {
  final end = DateTime.parse(day);
  final start = end.subtract(const Duration(days: kUsualWindowDays));
  return <double>[
    for (final point in points)
      if (_inWindow(DateTime.tryParse(point.date), start, end)) point.value,
  ];
}

bool _inWindow(DateTime? date, DateTime start, DateTime end) =>
    date != null && !date.isBefore(start) && date.isBefore(end);

/// Linear interpolation between closest ranks (the common "type 7" quantile).
double _quantile(List<double> sorted, double q) {
  final at = (sorted.length - 1) * q;
  final below = at.floor();
  final above = at.ceil();
  return sorted[below] + (sorted[above] - sorted[below]) * (at - below);
}
