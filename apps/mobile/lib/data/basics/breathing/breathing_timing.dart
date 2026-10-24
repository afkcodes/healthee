/// Clock arithmetic for the plan, as pure functions over local clock minutes.
///
/// Wake times are minutes since local midnight. Clock times wrap, so the
/// median and the range are taken on a circular axis cut where nobody is
/// usually at the edge: noon for wake-ups, 18:00 for lights-out.
library;

import 'package:meta/meta.dart';

/// The fewest nights with a wake time that make a morning time.
const int kMinWakeNights = 5;

/// The fewest nights with a lights-out time that make a range.
const int kMinOnsetNights = 3;

/// Minutes after the median wake time the reminder waits.
const int kMorningLeadMinutes = 15;

const int _day = 1440;

int _toAxis(int minute, int anchor) => (minute - anchor) % _day;
int _fromAxis(int value, int anchor) => (value + anchor) % _day;

/// The median of [wakeMinutes] (local clock minutes), or null with fewer than
/// [kMinWakeNights]. An even count averages the middle two, rounded half up.
int? medianWakeMinute(List<int> wakeMinutes) {
  if (wakeMinutes.length < kMinWakeNights) return null;
  final axis = [for (final m in wakeMinutes) _toAxis(m, 720)]..sort();
  final mid = axis.length ~/ 2;
  final median = axis.length.isOdd
      ? axis[mid]
      : (axis[mid - 1] + axis[mid] + 1) ~/ 2;
  return _fromAxis(median, 720);
}

/// The first quarter-hour at or after [median] plus [kMorningLeadMinutes].
///
/// 8:00 gives 8:15, 8:15 gives 8:30, 8:16 gives 8:45. Wraps past midnight.
int firstQuarterHourAfter(int median) {
  final earliest = median + kMorningLeadMinutes;
  return ((earliest + 14) ~/ 15 * 15) % _day;
}

/// The earliest and latest lights-out over some nights.
@immutable
class LightsOutRange {
  /// A range over [nights] nights.
  const LightsOutRange({
    required this.earliest,
    required this.latest,
    required this.nights,
  });

  /// The earliest lights-out, local clock minutes.
  final int earliest;

  /// The latest lights-out, local clock minutes.
  final int latest;

  /// How many nights it spans.
  final int nights;
}

/// The earliest and latest of [onsetMinutes] with times after 18:00 and before
/// 06:00 on one axis, or null with fewer than [kMinOnsetNights].
LightsOutRange? lightsOutRange(List<int> onsetMinutes) {
  if (onsetMinutes.length < kMinOnsetNights) return null;
  final axis = [for (final m in onsetMinutes) _toAxis(m, 1080)]..sort();
  return LightsOutRange(
    earliest: _fromAxis(axis.first, 1080),
    latest: _fromAxis(axis.last, 1080),
    nights: axis.length,
  );
}

/// "8:14" without [meridiem], "9:43 pm" with it.
String formatClock(int minute, {bool meridiem = true}) {
  final h = minute ~/ 60;
  final m = (minute % 60).toString().padLeft(2, '0');
  if (!meridiem) return '$h:$m';
  final hour12 = h % 12 == 0 ? 12 : h % 12;
  return '$hour12:$m ${h < 12 ? 'am' : 'pm'}';
}
