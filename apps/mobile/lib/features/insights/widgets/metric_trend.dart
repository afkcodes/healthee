/// One metric's window, and how its pattern tile is named and drawn.
///
/// A value type, so the arithmetic (mean, change, verdict) is checked without a
/// widget. [MetricTrend.delta] compares the window's newest third with its
/// oldest; see `trends_section.dart` for what the 14-day window can and cannot
/// say.
library;

import 'package:flutter/foundation.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/models/trend_point.dart';
import 'package:healthee/shared/format/metric_polarity.dart';

/// How one tracked metric is named and drawn on a pattern tile.
@immutable
class PatternSpec {
  /// A tile for [metric], labelled [label], in [tone]'s colour.
  const PatternSpec({
    required this.metric,
    required this.label,
    required this.tone,
    required this.decimals,
    this.unit,
  });

  /// The canonical metric id, the key of `sparklines`.
  final String metric;

  /// The tile's label.
  final String label;

  /// The domain colour of the label and the line.
  final Tone tone;

  /// Decimal places in the figure and in the change.
  final int decimals;

  /// The figure's unit, or null for a bare number.
  final String? unit;
}

/// The six tiles, in the order the screen draws them. Every metric is in
/// [kTrendMetrics], so each has a polarity behind its chip.
const List<PatternSpec> kPatternSpecs = <PatternSpec>[
  PatternSpec(
    metric: 'hrv_sleep_avg',
    label: 'Overnight HRV',
    tone: Tone.heart,
    decimals: 1,
    unit: 'ms',
  ),
  PatternSpec(
    metric: 'rhr_daily',
    label: 'Resting HR',
    tone: Tone.heart,
    decimals: 1,
    unit: 'bpm',
  ),
  PatternSpec(
    metric: 'sleep_regularity_index',
    label: 'Sleep regularity',
    tone: Tone.sleep,
    decimals: 0,
    unit: 'SRI',
  ),
  PatternSpec(
    metric: 'sleep_health_score_4dim',
    label: 'Sleep health',
    tone: Tone.sleep,
    decimals: 1,
    unit: '/ 4',
  ),
  PatternSpec(
    metric: 'total_calories',
    label: 'Total energy',
    tone: Tone.activity,
    decimals: 0,
    unit: 'kcal',
  ),
  PatternSpec(
    metric: 'steps_total',
    label: 'Steps',
    tone: Tone.activity,
    decimals: 0,
  ),
];

/// One metric's window: where it is now, and which way it has been going.
///
/// A value type rather than four positional arguments, so the arithmetic can be
/// checked without a widget. [delta] is legacy's `vals.last - vals.first`.
@immutable
class MetricTrend {
  /// Builds a trend from an already-windowed series.
  const MetricTrend({
    required this.metric,
    required this.series,
    required this.latest,
    required this.delta,
  });

  /// The series for [metric], or null when the payload carried fewer than two
  /// points — one point is a reading, not a trend, and a delta over it would be
  /// zero for a reason that has nothing to do with the owner.
  static MetricTrend? from(String metric, List<TrendPoint> series) {
    if (series.length < 2) {
      return null;
    }
    return MetricTrend(
      metric: metric,
      series: series,
      latest: series.last.value,
      delta: _robustDelta(series),
    );
  }

  /// The change across the window: the newest third's mean against the oldest
  /// third's.
  ///
  /// **It was `last − first`, and that is two arbitrary days.** On a smooth
  /// series — resting heart rate, sleep regularity — the endpoints are a fair
  /// proxy and the old arithmetic read fine. On a high-variance daily count it
  /// is noise wearing a verdict: the owner's steps swing between 1.2k and 8k,
  /// so a fortnight's "change" was whichever way those two particular days
  /// happened to fall, printed in verdict green.
  ///
  /// Thirds rather than halves so the middle of the window is excluded from
  /// both ends — a point next to the boundary should not pull the number both
  /// ways. [_edge] is at least one, so a two-point series still reduces to
  /// exactly the old subtraction and the shortest windows are unchanged.
  static double _robustDelta(List<TrendPoint> series) {
    final n = _edge(series.length);
    var newest = 0.0;
    var oldest = 0.0;
    for (var i = 0; i < n; i++) {
      newest += series[series.length - 1 - i].value;
      oldest += series[i].value;
    }
    return (newest - oldest) / n;
  }

  /// How many points each end contributes. `2 * _edge(n) <= n` for every
  /// `n >= 2`, so the two ends never overlap and never read the same point
  /// twice.
  static int _edge(int length) => length < 3 ? 1 : (length + 2) ~/ 3;

  /// The canonical metric id.
  final String metric;

  /// The window, oldest first.
  final List<TrendPoint> series;

  /// The newest value in the window.
  final double latest;

  /// The change across the window — see [_robustDelta].
  ///
  /// **No longer legacy's `last − first`.** Legacy compared two single days and
  /// coloured the result; this compares the window's newest third with its
  /// oldest, which is the same claim made out of enough measurement to support
  /// it.
  final double delta;

  /// What that change means, if anything. Never inferred from the sign alone.
  TrendVerdict get verdict => verdictFor(metric, delta);

  /// How many days the window covers.
  int get days => series.length;

  /// The mean of the window: the tile's big figure.
  double get mean =>
      series.fold<double>(0, (sum, point) => sum + point.value) / series.length;
}
