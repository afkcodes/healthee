/// The Health signals screen's rows, built from the Today snapshot.
///
/// Presentation only: every figure is read from a field the snapshot already
/// carries, in this order, and the first that has one wins.
///
///   1. the metric's own `MetricCard` (value, unit, server median and spread);
///   2. the typed block that owns the metric (recovery, VO2max, cardio load,
///      sleep debt, sleep health, MVPA);
///   3. the newest point of the metric's fortnight sparkline.
///
/// A metric none of them covers is a row that says **No reading**; a card the
/// server *withheld* stays withheld and prints the server's sentence. Nothing
/// is estimated here, and no goal is invented: a goal exists only where the
/// snapshot carries one (`Mvpa.weekTarget`).
///
/// On a past day [signalGroups] is given a null snapshot and every row reads
/// "No reading", because `/api/today` is the latest reading and not the day
/// above it (`metric_explorer_screen.dart` carries the argument).
library;

import 'package:flutter/widgets.dart';
import 'package:healthee/core/theme/tone.dart';
import 'package:healthee/data/history/history_metric.dart';
import 'package:healthee/data/honesty/reading.dart';
import 'package:healthee/data/models/metric_card.dart';
import 'package:healthee/data/models/today_snapshot.dart';
import 'package:healthee/data/models/trend_point.dart';
import 'package:healthee/features/history/v02/signal_row.dart';
import 'package:healthee/features/history/v02/signal_special.dart';
import 'package:healthee/shared/format/duration.dart';
import 'package:healthee/shared/format/metric_names.dart';
import 'package:healthee/shared/format/number_labels.dart';
import 'package:healthee/shared/usual_range.dart';
import 'package:healthee/shared/v02/reading_state.dart';
import 'package:solar_icons/solar_icons.dart';

/// A domain: its label, family, glyph and rows.
@immutable
class SignalGroup {
  /// A group of [rows] under [label].
  const SignalGroup({
    required this.label,
    required this.tone,
    required this.icon,
    required this.rows,
  });

  /// "Heart", "Breathing & oxygen"…
  final String label;

  /// The family everything in the group resolves.
  final Tone tone;

  /// The 16 px glyph beside the label.
  final IconData icon;

  /// Rows, top to bottom.
  final List<SignalRow> rows;
}

/// The days of series a row's strip draws.
const int kSignalSparkDays = 14;

/// The groups in screen order. A null [snapshot] is a past day or an
/// unreachable server: every row is "No reading".
List<SignalGroup> signalGroups(TodaySnapshot? snapshot) {
  SignalGroup group(String label, Tone tone, IconData icon, List<String> ids) =>
      SignalGroup(
        label: label,
        tone: tone,
        icon: icon,
        rows: <SignalRow>[for (final id in ids) signalRow(id, tone, snapshot)],
      );
  final mvpa = snapshot?.mvpa.valueOrNull;
  return <SignalGroup>[
    group('Heart', Tone.heart, SolarIconsBold.heart, const <String>[
      'hrv_sleep_avg',
      'rhr_daily',
      'recovery_score',
      'vo2max_estimate',
      'cardio_load',
    ]),
    group('Breathing & oxygen', Tone.oxygen, SolarIconsBold.waterdrop, const [
      'spo2_overnight',
      'spo2_overnight_min',
      'respiratory_rate_sleep',
    ]),
    group('Sleep', Tone.sleep, SolarIconsBold.moonSleep, const <String>[
      'sleep_health_score_4dim',
      'sleep_regularity_index',
      'sleep_debt_min',
    ]),
    group('Activity', Tone.movement, SolarIconsBold.walking, <String>[
      'steps_total',
      'distance_m_daily',
      'active_calories',
      'total_calories',
      'mvpa_min',
      if (mvpa?.weekModerateMin != null) 'moderate_min',
      'vigorous_min',
    ]),
    group('Body', Tone.fitness, SolarIconsBold.user, const <String>[
      'weight_kg',
      'basal_calories',
    ]),
  ];
}

/// One row for [metric].
SignalRow signalRow(String metric, Tone groupTone, TodaySnapshot? snapshot) {
  final tone = metric == 'cardio_load' ? Tone.load : groupTone;
  final card = snapshot?.metric(metric);
  final title = card?.label ?? metricTitle(metric);
  final special = specialRow(metric, title, tone, snapshot);
  if (special != null) {
    return special;
  }
  final reading = card?.reading;
  final withheld = reading is Withheld<double> ? reading : null;
  final value = withheld != null
      ? null
      : weekValue(metric, snapshot) ??
            card?.reading.valueOrNull ??
            blockValue(metric, snapshot) ??
            _latest(snapshot, metric);
  final usual = card == null ? null : usualOfCard(card);
  final goal = weekGoal(metric, snapshot);
  final judgement = judge(
    value: value,
    usual: usual,
    polarity: polarityOf(metric),
    goal: goal,
  );
  final unit = unitFor(metric, card);
  final series = seriesFor(metric, snapshot);
  final progress = goal != null && value != null && goal > 0
      ? (value / goal).clamp(0.0, 1.0)
      : null;
  return SignalRow(
    metric: metric,
    title: title,
    tone: tone,
    caption:
        withheld?.disclosure.message ??
        captionFor(metric, usual, goal, known: snapshot != null),
    judgement: judgement,
    figure: value == null ? null : figureOf(metric, value, unit),
    graphic: progress == null ? SignalGraphic.spark : SignalGraphic.bar,
    values: series,
    usual: usual,
    progress: progress,
    spoken: value == null ? '' : spokenFigure(metric, value, unit),
    withheld: withheld,
  );
}

/// The figure and its unit as drawn.
SignalFigure figureOf(String metric, double value, String unit) =>
    isDuration(metric)
    ? SignalFigure(durationText(value))
    : SignalFigure(plain(metric, value), unit);

/// [value] without a unit, in the metric's own display form.
String plain(String metric, double value) => switch (metric) {
  'steps_total' ||
  'active_calories' ||
  'total_calories' ||
  'basal_calories' => groupedInt(value.round()),
  'distance_m_daily' => (value / 1000).toStringAsFixed(2),
  'sleep_debt_min' || 'sleep_need_min' => durationText(value),
  'mvpa_min' ||
  'vigorous_min' ||
  'moderate_min' ||
  'recovery_score' ||
  'sleep_regularity_index' ||
  'cardio_load' => value.round().toString(),
  _ => decimalLabel(value),
};

/// A range bound: [plain] without a trailing `.0`, so `44 to 57`, not
/// `44.0 to 57.0`.
String bound(String metric, double value) =>
    plain(metric, value).replaceFirst(RegExp(r'\.0$'), '');

/// Whether the figure is a duration, which carries its own units.
bool isDuration(String metric) =>
    metric == 'sleep_debt_min' || metric == 'sleep_need_min';

/// The display unit: the card's, else the history table's, shortened where the
/// screen's width needs it.
String unitFor(String metric, MetricCard? card) => switch (metric) {
  'distance_m_daily' => 'km',
  'respiratory_rate_sleep' => '/min',
  'recovery_score' => '%',
  'steps_total' ||
  'cardio_load' ||
  'sleep_regularity_index' ||
  'sleep_debt_min' => '',
  _ => card?.unit ?? _historyUnit(metric),
};

String _historyUnit(String metric) {
  for (final m in HistoryMetric.values) {
    if (m.id == metric) {
      return m.unit;
    }
  }
  return '';
}

/// The newest point of the fortnight sparkline.
double? _latest(TodaySnapshot? snapshot, String metric) {
  final series = snapshot?.sparklines[metric];
  return series == null || series.isEmpty ? null : series.last.value;
}

/// The strip's values, oldest first, at most [kSignalSparkDays].
List<double?> seriesFor(String metric, TodaySnapshot? snapshot) {
  if (snapshot == null) {
    return const <double?>[];
  }
  List<TrendPoint> points = snapshot.sparklines[metric] ?? const <TrendPoint>[];
  if (points.isEmpty && metric == 'cardio_load') {
    points = snapshot.cardioLoad.valueOrNull?.trend30d ?? const <TrendPoint>[];
  }
  if (points.isEmpty && metric == 'vo2max_estimate') {
    points = snapshot.vo2max.valueOrNull?.trend90d ?? const <TrendPoint>[];
  }
  final tail = points.length > kSignalSparkDays
      ? points.sublist(points.length - kSignalSparkDays)
      : points;
  return <double?>[for (final p in tail) p.value];
}

/// `higher is better · usual 44 to 57`, or a goal, or what is still unknown.
String captionFor(
  String metric,
  UsualRange? usual,
  double? goal, {
  required bool known,
}) {
  final polarity = polarityOf(metric);
  final words = switch (polarity) {
    Polarity.higherBetter => 'higher is better',
    Polarity.lowerBetter => 'lower is better',
    Polarity.insideRange => 'best inside range',
    Polarity.goal => goal == null ? 'against your usual' : 'this week',
    Polarity.neutral =>
      metric == 'vigorous_min' || metric == 'moderate_min' ? 'this week' : '',
  };
  final tail = goal != null
      ? 'goal ${goal.round()}'
      : usual != null
      ? 'usual ${bound(metric, usual.low)} to ${bound(metric, usual.high)}'
      : known && metric != 'vigorous_min' && metric != 'moderate_min'
      ? 'usual still being learned'
      : '';
  return <String>[words, tail].where((s) => s.isNotEmpty).join(' · ');
}

/// The figure with its unit, spoken.
String spokenFigure(String metric, double value, String unit) {
  if (isDuration(metric)) {
    return durationText(value);
  }
  final said = switch (unit) {
    'ms' => 'milliseconds',
    'bpm' => 'beats per minute',
    '%' => 'percent',
    'kcal' => 'kilocalories',
    'kg' => 'kilograms',
    'km' => 'kilometres',
    '/min' => 'breaths per minute',
    'min' => 'minutes',
    'ml/kg/min' => 'millilitres per kilogram per minute',
    _ => unit,
  };
  return said.isEmpty ? plain(metric, value) : '${plain(metric, value)} $said';
}
