/// The numbers above the Effort and stress chart, and the window it covers.
///
/// Pure functions over the payload's hourly series, so every figure on the card
/// is asserted without a widget. Nothing is interpolated: an hour the strap did
/// not measure is not in the series, and so is not in these numbers.
library;

import 'dart:math' as math;

import 'package:healthee/data/models/today_series.dart';
import 'package:healthee/shared/format/time_labels.dart';

/// The day's heart-rate range, peak-hour stress and average stress.
class EffortStressStats {
  /// Reads [heartRate] and [stress].
  EffortStressStats(List<HourPoint> heartRate, List<HourPoint> stress)
    : heartRange = _range(heartRate),
      peakStress = stress.isEmpty
          ? null
          : stress.map((p) => p.average).reduce(math.max),
      averageStress = stress.isEmpty
          ? null
          : stress.map((p) => p.average).reduce((a, b) => a + b) /
                stress.length;

  /// The lowest and highest heart rate of the day, or null with no samples.
  final ({double low, double high})? heartRange;

  /// The highest hourly stress average.
  final double? peakStress;

  /// The mean of the hourly stress averages.
  final double? averageStress;

  static ({double low, double high})? _range(List<HourPoint> hours) {
    if (hours.isEmpty) {
      return null;
    }
    return (
      low: hours.map((p) => p.minimum ?? p.average).reduce(math.min),
      high: hours.map((p) => p.maximum ?? p.average).reduce(math.max),
    );
  }

  /// `55–90`, an en dash between whole numbers.
  String? get heartRangeLabel => heartRange == null
      ? null
      : '${heartRange!.low.round()}–${heartRange!.high.round()}';
}

/// `00:00 to 08:03`: from the first hour in the series to the sync that ended
/// it. Without a sync inside the last hour it ends at that hour's own start,
/// which says no more than the series knows.
String syncedWindow(List<HourPoint> hours, {DateTime? lastSync}) {
  if (hours.isEmpty) {
    return '';
  }
  String hourLabel(int hour) => '${(hour % 24).toString().padLeft(2, '0')}:00';
  final last = hours.last.hour;
  final end = lastSync != null && lastSync.hour == last % 24
      ? clockLabel(lastSync)
      : hourLabel(last);
  return '${hourLabel(hours.first.hour)} to $end';
}
