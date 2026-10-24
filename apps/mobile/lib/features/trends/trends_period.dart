/// The Trends screen's three periods, and how a dated series is cut into one.
///
/// `design/mobile-preview/proposal.js` (`#p-trends`): Week, Month, 6 months.
/// A week and a month draw one reading per day; six months draws one per
/// week, the mean of that week's days, because 182 dots on a phone are a
/// smear. Each period is read against the same length of time before it.
///
/// A day with no reading is a gap, never a zero, and a week with no day in it
/// is a gap too.
library;

import 'package:flutter/foundation.dart';
import 'package:healthee/data/models/trend_point.dart';
import 'package:healthee/features/sleep/sleep_format.dart';

/// One of the three.
enum TrendPeriod {
  week(7, 1, 'Week', 'days', 'the week before'),
  month(30, 1, 'Month', 'days', 'the month before'),
  halfYear(182, 7, '6 months', 'weeks', 'the 6 months before');

  const TrendPeriod(
    this.days,
    this.step,
    this.label,
    this.readings,
    this.before,
  );

  /// How many days the period covers.
  final int days;

  /// Days per drawn reading: 1 for a day, 7 for a week.
  final int step;

  /// The switch's word.
  final String label;

  /// What one drawn reading is.
  final String readings;

  /// What the change is against.
  final String before;

  /// How much history the period and the one before it need.
  int get fetchDays => days * 2;
}

/// A series cut to a period: what is drawn, and what it is read against.
@immutable
class PeriodSeries {
  const PeriodSeries({
    required this.values,
    required this.earlier,
    required this.captions,
  });

  /// One slot per day or week, oldest first; null is unmeasured.
  final List<double?> values;

  /// The period before, measured slots only.
  final List<double> earlier;

  /// The first and last date of the period.
  final List<String> captions;
}

/// Cuts [points] into [period], ending on [end] (`YYYY-MM-DD`, inclusive).
PeriodSeries cutPeriod(
  List<TrendPoint> points,
  String end,
  TrendPeriod period,
) {
  // UTC, so stepping back a day never lands on a daylight-saving hour.
  final last = DateTime.parse('${end}T00:00:00Z');
  final byDay = <String, double>{for (final p in points) p.date: p.value};
  String iso(DateTime d) => d.toIso8601String().substring(0, 10);
  double? slot(DateTime slotEnd) {
    final days = <double>[
      for (var i = 0; i < period.step; i++)
        ?byDay[iso(slotEnd.subtract(Duration(days: i)))],
    ];
    return days.isEmpty ? null : days.reduce((a, b) => a + b) / days.length;
  }

  final count = period.days ~/ period.step;
  List<double?> slots(int offsetDays) => <double?>[
    for (var i = count - 1; i >= 0; i--)
      slot(last.subtract(Duration(days: offsetDays + i * period.step))),
  ];
  final first = last.subtract(Duration(days: count * period.step - 1));
  return PeriodSeries(
    values: slots(0),
    earlier: <double>[for (final v in slots(count * period.step)) ?v],
    captions: <String>[shortDate(iso(first)), shortDate(end)],
  );
}
